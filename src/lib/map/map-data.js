/* DeepMap map data: UUID-scoped database loader shared by game renderers.
 * Static renderer data is not merged into database-owned collections.
 */

import { markerIdKey as bigintIdKey } from '../editor/marker-editor.js';
import { normalizeFileReference } from '../storage/references.js';
import { resolveFileUrl } from '../storage/resolve.js';

function keyedObject(rows, transform) {
    return Object.fromEntries(rows.map((row) => {
        const value = transform(row);
        return [value.id, value];
    }));
}

function resolveAsset(source, ref) {
    return resolveFileUrl(normalizeFileReference(source, ref));
}

function normaliseLayer(row) {
    return {
        id: row.id,
        layerUuid: row.layer_uuid,
        gameUuid: row.game_uuid,
        gameMapUuid: row.game_map_id,
        label: { en: row.name_en, pt: row.name_pt },
        image: resolveAsset(row.image_source, row.image_ref),
        imageSource: row.image_source,
        imageRef: row.image_ref,
        width: row.width,
        height: row.height,
        sortOrder: row.sort_order
    };
}

function normaliseGroup(row) {
    return {
        id: row.id,
        gameUuid: row.game_uuid,
        groupUuid: row.group_uuid,
        label: { en: row.name_en, pt: row.name_pt },
        sortOrder: row.sort_order
    };
}

function normaliseCategory(row) {
    return {
        id: row.id,
        gameUuid: row.game_uuid,
        categoryUuid: row.category_uuid,
        group: row.group_id,
        groupUuid: row.group_uuid,
        label: { en: row.name_en, pt: row.name_pt },
        icon: resolveAsset(row.icon_source, row.icon_ref),
        iconSource: row.icon_source,
        iconRef: row.icon_ref,
        color: row.color,
        markerWidth: row.marker_width ?? undefined,
        markerHeight: row.marker_height ?? undefined,
        symbolSize: row.symbol_size ?? undefined,
        sortOrder: row.sort_order
    };
}

function normaliseMarker(row) {
    return {
        databaseId: row.id,
        gameUuid: row.game_uuid,
        layerUuid: row.layer_uuid,
        categoryUuid: row.category_uuid,
        id: row.slug,
        slug: row.slug,
        mapLayer: row.map_layer,
        categoryId: row.category_id,
        regionId: row.region_id,
        regionKey: row.region_id,
        title: { en: row.title_en, pt: row.title_pt },
        description: { en: row.description_en, pt: row.description_pt },
        coordinates: [row.coordinate_y, row.coordinate_x],
        videoUrl: row.video_url,
        isPublished: row.is_published,
        publishedByUsername: null,
        modifiedByUsername: null,
        approvedByUsername: null,
        colorOverride: row.color_override,
        icon: resolveAsset(row.icon_source_override, row.icon_ref_override),
        iconSourceOverride: row.icon_source_override,
        iconRefOverride: row.icon_ref_override,
        markerWidthOverride: row.marker_width_override,
        markerHeightOverride: row.marker_height_override,
        symbolSizeOverride: row.symbol_size_override,
        image: null,
        images: [],
        contentItems: [],
        npcs: [],
        items: [],
        quests: [],
        notesKey: null
    };
}

function normaliseMarkerImage(row) {
    return {
        id: row.id,
        markerId: row.marker_id,
        source: row.source,
        imageRef: row.image_ref,
        url: resolveAsset(row.source, row.image_ref),
        alt: { en: row.alt_en ?? '', pt: row.alt_pt ?? '' },
        caption: { en: row.caption_en ?? '', pt: row.caption_pt ?? '' },
        sortOrder: row.sort_order ?? 0,
        isCover: row.is_cover === true
    };
}

function normaliseMapLabel(row) {
    return {
        databaseId: row.id,
        gameUuid: row.game_uuid,
        layerUuid: row.layer_uuid,
        id: row.slug,
        slug: row.slug,
        mapLayer: row.map_layer,
        text: { en: row.text_en, pt: row.text_pt },
        coordinates: [row.coordinate_y, row.coordinate_x],
        fontSize: row.font_size ?? 34,
        fontWeight: row.font_weight ?? 700,
        color: row.color ?? '#E8D7A4',
        opacity: row.opacity ?? 0.82,
        uppercase: row.uppercase !== false,
        isPublished: row.is_published === true
    };
}

/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string, locations: any[] }} options */
function loadUuidPublicMarkerAttribution({ supabase, gameUuid, locations }) {
    return attachPublicMarkerAttribution({
        query: () => supabase.rpc('get_public_marker_attribution_by_game_uuid', { p_game_uuid: gameUuid }),
        locations
    });
}

/** @param {{ query: () => PromiseLike<{ data: any[] | null, error: unknown }>, locations: any[] }} options */
async function attachPublicMarkerAttribution({ query, locations }) {
    try {
        const { data, error } = await query();

        if (error) throw error;

        const attributionByMarker = new Map(
            (data ?? []).map((row) => [String(row.marker_id), row])
        );

        return locations.map((location) => {
            const attribution = location.databaseId
                ? attributionByMarker.get(String(location.databaseId)) ?? null
                : null;

            return {
                ...location,
                publishedByUsername: attribution?.published_username ?? location.publishedByUsername ?? null,
                modifiedByUsername: attribution?.modified_username ?? location.modifiedByUsername ?? null,
                approvedByUsername: attribution?.approved_username ?? location.approvedByUsername ?? null
            };
        });
    } catch (error) {
        console.warn('DeepMap map data (public marker attribution):', error?.message ?? error);
        return locations;
    }
}

async function attachMarkerImages({ supabase, locations }) {
    const databaseIds = locations
        .map((location) => location.databaseId)
        .filter((id) => id != null)
        .map(bigintIdKey);

    if (!databaseIds.length) return locations;

    try {
        const { data, error } = await supabase
            .from('marker_images')
            .select('id, marker_id, source, image_ref, alt_en, alt_pt, caption_en, caption_pt, sort_order, is_cover')
            .in('marker_id', databaseIds)
            .order('sort_order', { ascending: true })
            .order('id', { ascending: true });

        if (error) throw error;

        const byMarker = new Map();
        const requested = new Set(databaseIds);
        for (const row of data ?? []) {
            const markerId = bigintIdKey(row.marker_id);
            if (!requested.has(markerId)) throw new Error('MARKER_IMAGE_SCOPE_CONFLICT');
            const image = normaliseMarkerImage(row);
            if (!byMarker.has(markerId)) byMarker.set(markerId, []);
            byMarker.get(markerId).push(image);
        }

        return locations.map((location) => {
            if (!location.databaseId) {
                return {
                    ...location,
                    images: location.images?.length
                        ? location.images
                        : location.image
                            ? [{ id: `legacy-${location.id}`, url: location.image, isCover: true, sortOrder: 0 }]
                            : []
                };
            }

            const images = byMarker.get(bigintIdKey(location.databaseId)) ?? [];
            const cover = images.find((image) => image.isCover && image.url) ?? images.find((image) => image.url) ?? null;

            return {
                ...location,
                images,
                image: cover?.url ?? location.image ?? null
            };
        });
    } catch (error) {
        console.warn('DeepMap map data (marker images):', error?.message ?? error);
        return locations;
    }
}


async function attachMarkerContent({ supabase, locations }) {
    const databaseIds = locations
        .map((location) => location.databaseId)
        .filter((id) => id != null)
        .map(bigintIdKey);

    if (!databaseIds.length) return locations;

    try {
        const { data: sections, error: sectionsError } = await supabase
            .from('marker_sections')
            .select('id, marker_id, section_type, title_en, title_pt, sort_order, metadata')
            .in('marker_id', databaseIds)
            .order('sort_order', { ascending: true })
            .order('id', { ascending: true });

        if (sectionsError) throw sectionsError;
        if (!sections?.length) return locations;

        const requested = new Set(databaseIds);
        const sectionById = new Map();
        for (const section of sections) {
            const id = bigintIdKey(section.id);
            if (!requested.has(bigintIdKey(section.marker_id)) || sectionById.has(id)) {
                throw new Error('MARKER_CONTENT_SCOPE_CONFLICT');
            }
            sectionById.set(id, section);
        }
        const sectionIds = [...sectionById.keys()];
        const { data: rows, error: rowsError } = await supabase
            .from('marker_section_rows')
            .select('id, section_id, text_en, text_pt, sort_order')
            .in('section_id', sectionIds)
            .order('sort_order', { ascending: true })
            .order('id', { ascending: true });

        if (rowsError) throw rowsError;

        const byMarker = new Map();

        for (const row of rows ?? []) {
            const section = sectionById.get(bigintIdKey(row.section_id));
            if (!section) throw new Error('MARKER_CONTENT_SECTION_CONFLICT');

            const markerId = bigintIdKey(section.marker_id);
            if (!byMarker.has(markerId)) byMarker.set(markerId, []);

            byMarker.get(markerId).push({
                id: row.id,
                type: section.section_type ?? 'note',
                title: { en: section.title_en ?? '', pt: section.title_pt ?? '' },
                text: { en: row.text_en ?? '', pt: row.text_pt ?? '' },
                sortOrder: section.sort_order ?? row.sort_order ?? 0
            });
        }

        return locations.map((location) => ({
            ...location,
            contentItems: location.databaseId
                ? byMarker.get(bigintIdKey(location.databaseId)) ?? []
                : location.contentItems ?? []
        }));
    } catch (error) {
        console.warn('DeepMap map data (marker content):', error?.message ?? error);
        return locations;
    }
}

const LAYER_UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** @param {unknown} value */
function isLayerUuid(value) {
    return typeof value === 'string' && LAYER_UUID_PATTERN.test(value);
}

/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string, gameMapUuid: string }} options */
async function loadUuidLayers({ supabase, gameUuid, gameMapUuid }) {
    if (!isLayerUuid(gameUuid) || !isLayerUuid(gameMapUuid)) {
        throw new Error('LAYER_UUID_CONTEXT_REQUIRED');
    }
    const { data, error } = await supabase
        .from('map_layers')
        .select('id, game_id, game_uuid, game_map_id, layer_uuid, name_en, name_pt, image_source, image_ref, width, height, sort_order')
        .eq('game_uuid', gameUuid)
        .eq('game_map_id', gameMapUuid)
        .eq('is_active', true)
        .order('sort_order', { ascending: true })
        .order('id', { ascending: true });

    if (error) throw new Error('LAYER_QUERY_UNAVAILABLE');
    if (!Array.isArray(data) || !data.length) throw new Error('LAYER_DATA_UNAVAILABLE');

    const keys = new Set();
    const uuids = new Set();
    for (const row of data) {
        if (!row || typeof row.id !== 'string' || !row.id
            || row.game_uuid !== gameUuid || row.game_map_id !== gameMapUuid
            || !isLayerUuid(row.layer_uuid) || keys.has(row.id) || uuids.has(row.layer_uuid)) {
            throw new Error('LAYER_IDENTITY_CONTEXT_INVALID');
        }
        keys.add(row.id);
        uuids.add(row.layer_uuid);
    }
    // This collection is DB-owned: never merge static rows without UUID identity.
    return { value: keyedObject(data, normaliseLayer), source: 'supabase' };
}

/**
 * @param {unknown} data
 * @param {string} gameUuid
 * @param {'group_uuid' | 'category_uuid'} uuidField
 */
function validateUuidTaxonomyRows(data, gameUuid, uuidField) {
    if (!Array.isArray(data)) throw new Error('TAXONOMY_DATA_UNAVAILABLE');
    const keys = new Set();
    const uuids = new Set();
    for (const row of data) {
        if (!row || typeof row.id !== 'string' || !row.id.trim()
            || row.game_uuid !== gameUuid || !isLayerUuid(row[uuidField])
            || keys.has(row.id) || uuids.has(row[uuidField])) {
            throw new Error('TAXONOMY_IDENTITY_CONTEXT_INVALID');
        }
        if (uuidField === 'category_uuid') {
            if (row.group_id === null ? row.group_uuid !== null
                : typeof row.group_id !== 'string' || !row.group_id.trim() || !isLayerUuid(row.group_uuid)) {
                throw new Error('CATEGORY_GROUP_UUID_PAIR_INVALID');
            }
        }
        keys.add(row.id);
        uuids.add(row[uuidField]);
    }
    return data;
}

/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string }} options */
async function loadUuidCategoryGroups({ supabase, gameUuid }) {
    if (!isLayerUuid(gameUuid)) throw new Error('TAXONOMY_GAME_UUID_REQUIRED');
    const { data, error } = await supabase
        .from('marker_category_groups')
        .select('id, game_id, game_uuid, group_uuid, name_en, name_pt, sort_order')
        .eq('game_uuid', gameUuid)
        .eq('is_active', true)
        .order('sort_order', { ascending: true })
        .order('id', { ascending: true });
    if (error) throw new Error('CATEGORY_GROUP_QUERY_UNAVAILABLE');
    const rows = validateUuidTaxonomyRows(data, gameUuid, 'group_uuid');
    return { value: rows.map(normaliseGroup), source: 'supabase' };
}

/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string }} options */
async function loadUuidCategories({ supabase, gameUuid }) {
    if (!isLayerUuid(gameUuid)) throw new Error('TAXONOMY_GAME_UUID_REQUIRED');
    const { data, error } = await supabase
        .from('marker_categories')
        .select('id, game_id, game_uuid, category_uuid, group_id, group_uuid, name_en, name_pt, icon_source, icon_ref, color, marker_width, marker_height, symbol_size, sort_order')
        .eq('game_uuid', gameUuid)
        .eq('is_active', true)
        .order('sort_order', { ascending: true })
        .order('id', { ascending: true });
    if (error) throw new Error('CATEGORY_QUERY_UNAVAILABLE');
    const rows = validateUuidTaxonomyRows(data, gameUuid, 'category_uuid');
    // A referenced group need not appear in the public active-group collection.
    return { value: keyedObject(rows, normaliseCategory), source: 'supabase' };
}

/** @param {unknown} value */
function isDatabaseBigintId(value) {
    if (typeof value === 'number') return Number.isSafeInteger(value);
    if (typeof value !== 'string' || !/^-?[0-9]+$/.test(value)) return false;
    const id = BigInt(value);
    return id >= -9223372036854775808n && id <= 9223372036854775807n;
}

/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string, layersPromise: Promise<{ value: any, source: string }>, categoriesPromise: Promise<{ value: any, source: string }> }} options */
async function loadUuidMarkers({ supabase, gameUuid, layersPromise, categoriesPromise }) {
    if (!isLayerUuid(gameUuid)) throw new Error('MARKER_GAME_UUID_REQUIRED');
    const layers = await layersPromise;
    const layerByUuid = new Map(Object.values(layers.value).map((layer) => [layer.layerUuid, layer]));
    const layerUuids = [...layerByUuid.keys()];
    if (!layerUuids.length || !layerUuids.every(isLayerUuid)) {
        throw new Error('MARKER_LAYER_SCOPE_INVALID');
    }
    const { data, error } = await supabase
        .from('marcadores')
        .select('id, game_id, game_uuid, map_layer, layer_uuid, slug, category_id, category_uuid, region_id, title_en, title_pt, coordinate_x, coordinate_y, description_en, description_pt, video_url, color_override, icon_source_override, icon_ref_override, marker_width_override, marker_height_override, symbol_size_override, is_published')
        .eq('game_uuid', gameUuid)
        .eq('is_published', true)
        .in('layer_uuid', layerUuids)
        .order('id', { ascending: true });
    if (error) throw new Error('MARKER_QUERY_UNAVAILABLE');
    if (!Array.isArray(data)) throw new Error('MARKER_DATA_UNAVAILABLE');
    const categories = await categoriesPromise;
    for (const row of data) {
        if (!row || !isDatabaseBigintId(row.id) || row.game_uuid !== gameUuid
            || !isLayerUuid(row.layer_uuid) || !layerByUuid.has(row.layer_uuid)
            || !isLayerUuid(row.category_uuid)
            || typeof row.map_layer !== 'string' || !row.map_layer.trim()
            || typeof row.category_id !== 'string' || !row.category_id.trim()) {
            throw new Error('MARKER_IDENTITY_CONTEXT_INVALID');
        }
        if (layerByUuid.get(row.layer_uuid).id !== row.map_layer) {
            throw new Error('MARKER_LAYER_KEY_MISMATCH');
        }
        const category = Object.hasOwn(categories.value, row.category_id)
            ? categories.value[row.category_id] : undefined;
        // Inactive/non-visible parent categories need not appear in public taxonomy.
        if (category && (category.categoryUuid !== row.category_uuid || category.gameUuid !== row.game_uuid)) {
            throw new Error('MARKER_CATEGORY_CONTEXT_INVALID');
        }
    }
    return { value: data.map(normaliseMarker), source: 'supabase' };
}

/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string, layersPromise: Promise<{ value: any, source: string }> }} options */
async function loadUuidMapLabels({ supabase, gameUuid, layersPromise }) {
    if (!isLayerUuid(gameUuid)) throw new Error('LABEL_GAME_UUID_REQUIRED');
    const layers = await layersPromise;
    const layerByUuid = new Map(Object.values(layers.value).map((layer) => [layer.layerUuid, layer]));
    const layerUuids = [...layerByUuid.keys()];
    if (!layerUuids.length || !layerUuids.every(isLayerUuid)) {
        throw new Error('LABEL_LAYER_SCOPE_INVALID');
    }
    const { data, error } = await supabase
        .from('map_labels')
        .select('id, game_id, game_uuid, map_layer, layer_uuid, slug, text_en, text_pt, coordinate_x, coordinate_y, font_size, font_weight, color, opacity, uppercase, is_published')
        .eq('game_uuid', gameUuid)
        .eq('is_published', true)
        .in('layer_uuid', layerUuids)
        .order('id', { ascending: true });
    if (error) throw new Error('LABEL_QUERY_UNAVAILABLE');
    if (!Array.isArray(data)) throw new Error('LABEL_DATA_UNAVAILABLE');
    for (const row of data) {
        if (!row || !isDatabaseBigintId(row.id) || row.game_uuid !== gameUuid
            || !isLayerUuid(row.layer_uuid) || !layerByUuid.has(row.layer_uuid)
            || typeof row.map_layer !== 'string' || !row.map_layer.trim()
            || typeof row.slug !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(row.slug)
            || row.is_published !== true) {
            throw new Error('LABEL_IDENTITY_CONTEXT_INVALID');
        }
        if (layerByUuid.get(row.layer_uuid).id !== row.map_layer) {
            throw new Error('LABEL_LAYER_KEY_MISMATCH');
        }
    }
    return { value: data.map(normaliseMapLabel), source: 'supabase' };
}

// Public path: UUID layers/taxonomy/markers/labels/attribution.
// legacyGameId remains an unused compatibility argument for existing callers.
/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string, gameMapUuid: string, legacyGameId: string, fallback: any }} options */
export async function loadDeepMapGameDataWithUuidLayers({ supabase, gameUuid, gameMapUuid }) {
    const layersPromise = loadUuidLayers({ supabase, gameUuid, gameMapUuid });
    const categoriesPromise = loadUuidCategories({ supabase, gameUuid });
    return loadGameData({
        supabase,
        attachAttribution: (locations) => loadUuidPublicMarkerAttribution({ supabase, gameUuid, locations }),
        layersPromise,
        groupsPromise: loadUuidCategoryGroups({ supabase, gameUuid }),
        categoriesPromise,
        markersPromise: loadUuidMarkers({ supabase, gameUuid, layersPromise, categoriesPromise }),
        labelsPromise: loadUuidMapLabels({ supabase, gameUuid, layersPromise })
    });
}

/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, attachAttribution: (locations: any[]) => Promise<any[]>, layersPromise: Promise<{ value: any, source: string }>, groupsPromise: Promise<{ value: any, source: string }>, categoriesPromise: Promise<{ value: any, source: string }>, markersPromise: Promise<{ value: any, source: string }>, labelsPromise: Promise<{ value: any, source: string }> }} options */
async function loadGameData({ supabase, attachAttribution, layersPromise, groupsPromise, categoriesPromise, markersPromise, labelsPromise }) {
    const [layers, groups, categories, markers, labels] = await Promise.all([
        layersPromise,
        groupsPromise,
        categoriesPromise,
        markersPromise,
        labelsPromise
    ]);

    const locationsWithImages = await attachMarkerImages({
        supabase,
        locations: markers.value
    });

    const locationsWithContent = await attachMarkerContent({
        supabase,
        locations: locationsWithImages
    });

    const locations = await attachAttribution(locationsWithContent);

    return {
        mapDefinitions: layers.value,
        categoryGroups: groups.value,
        categories: categories.value,
        locations,
        mapLabels: labels.value,
        sources: {
            layers: layers.source,
            groups: groups.source,
            categories: categories.source,
            markers: markers.source,
            labels: labels.source
        }
    };
}
