import { loadEditorCategories, loadEditorCategoryGroups } from './category-editor.js';

const MARKER_SELECT = `
    id,
    game_id,
    game_uuid,
    map_layer,
    layer_uuid,
    slug,
    category_id,
    category_uuid,
    region_id,
    title_en,
    title_pt,
    coordinate_x,
    coordinate_y,
    description_en,
    description_pt,
    video_url,
    color_override,
    icon_source_override,
    icon_ref_override,
    marker_width_override,
    marker_height_override,
    symbol_size_override,
    is_published,
    created_at,
    updated_at
`;

/** @param {any} row @param {any} audit */
export function normaliseEditorMarker(row, audit = null) {
    return {
        id: markerIdKey(row.id),
        legacyGameId: row.game_id,
        gameUuid: row.game_uuid,
        mapLayer: row.map_layer,
        layerUuid: row.layer_uuid,
        slug: row.slug,
        categoryId: row.category_id,
        categoryUuid: row.category_uuid,
        regionId: row.region_id ?? '',
        titleEn: row.title_en ?? '',
        titlePt: row.title_pt ?? '',
        coordinateX: row.coordinate_x,
        coordinateY: row.coordinate_y,
        descriptionEn: row.description_en ?? '',
        descriptionPt: row.description_pt ?? '',
        videoUrl: row.video_url ?? '',
        isPublished: row.is_published === true,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        createdBy: audit?.created_by ?? null,
        createdByUsername: audit?.created_username ?? null,
        auditCreatedAt: audit?.created_at ?? null,
        updatedBy: audit?.updated_by ?? null,
        updatedByUsername: audit?.updated_username ?? null,
        auditUpdatedAt: audit?.updated_at ?? null,
        publishedBy: audit?.published_by ?? null,
        publishedByUsername: audit?.published_username ?? null,
        publishedAt: audit?.published_at ?? null,
        approvedBy: audit?.approved_by ?? null,
        approvedByUsername: audit?.approved_username ?? null,
        approvedAt: audit?.approved_at ?? null
    };
}

/** @param {unknown} value */
export function slugifyMarkerTitle(value) {
    return String(value ?? '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .trim()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '')
        .slice(0, 80);
}

/** @param {string} legacyGameId @param {any} marker @param {any} layer @param {any} category */
function markerPayload(legacyGameId, marker, layer, category) {
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(marker.slug)
        || typeof marker.titleEn !== 'string' || !marker.titleEn.trim()
        || String(marker.coordinateX ?? '').trim() === '' || String(marker.coordinateY ?? '').trim() === ''
        || !Number.isFinite(Number(marker.coordinateX)) || !Number.isFinite(Number(marker.coordinateY))) {
        throw new Error('MARKER_EDITOR_FIELDS_INVALID');
    }
    return {
        game_id: legacyGameId,
        map_layer: layer.id,
        slug: marker.slug,
        category_id: category.id,
        region_id: marker.regionId?.trim() || null,
        title_en: marker.titleEn.trim(),
        title_pt: marker.titlePt?.trim() || null,
        coordinate_x: Number(marker.coordinateX),
        coordinate_y: Number(marker.coordinateY),
        description_en: marker.descriptionEn?.trim() || null,
        description_pt: marker.descriptionPt?.trim() || null,
        video_url: marker.videoUrl?.trim() || null,
        is_published: marker.isPublished === true
    };
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** @typedef {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string, gameMapUuid: string, isCurrent?: () => boolean }} MarkerContext */
/** @typedef {{ id: string, legacyGameId: string, gameUuid: string, gameMapUuid: string, layerUuid: string, label: {en: string, pt: string}, sortOrder: number, isActive: boolean }} EditorLayer */
/** @typedef {Awaited<ReturnType<typeof loadEditorCategories>>[number]} EditorCategory */
/** @typedef {MarkerContext & { legacyGameId: string, selectedLayerUuid: string, selectedCategoryUuid: string, marker: any }} MarkerWrite */

/** @param {unknown} value */
function requireUuid(value) {
    if (typeof value !== 'string' || !UUID_PATTERN.test(value)) throw new Error('MARKER_UUID_CONTEXT_REQUIRED');
}

/** @param {unknown} value */
function isLegacyKey(value) {
    return typeof value === 'string' && value.trim().length > 0;
}

/** @param {unknown} value */
export function markerIdKey(value) {
    if (typeof value === 'number' ? !Number.isSafeInteger(value)
        : typeof value !== 'string' || !/^-?[0-9]+$/.test(value)) throw new Error('MARKER_BIGINT_ID_REQUIRED');
    const id = BigInt(String(value));
    if (id < -9223372036854775808n || id > 9223372036854775807n) throw new Error('MARKER_BIGINT_ID_REQUIRED');
    return id.toString();
}

/** @param {unknown} left @param {unknown} right */
export function sameMarkerId(left, right) {
    try { return markerIdKey(left) === markerIdKey(right); }
    catch { return false; }
}

/** @param {MarkerContext} context */
function assertCurrent(context) {
    if (context.isCurrent && !context.isCurrent()) throw new Error('MARKER_STALE_CONTEXT');
}

/** @param {MarkerContext} context */
async function loadEditorAuthority(context) {
    const { supabase, gameUuid, gameMapUuid } = context;
    requireUuid(gameUuid);
    requireUuid(gameMapUuid);
    assertCurrent(context);
    const [layerResult, categories, groups] = await Promise.all([
        supabase.from('map_layers')
            .select('id, game_id, game_uuid, game_map_id, layer_uuid, name_en, name_pt, sort_order, is_active')
            .eq('game_uuid', gameUuid).eq('game_map_id', gameMapUuid)
            .order('sort_order', { ascending: true }).order('id', { ascending: true }),
        loadEditorCategories({ supabase, gameUuid }),
        loadEditorCategoryGroups({ supabase, gameUuid })
    ]);
    assertCurrent(context);
    if (layerResult.error) throw layerResult.error;
    if (!Array.isArray(layerResult.data)) throw new Error('MARKER_LAYERS_UNAVAILABLE');
    const layerUuids = new Set();
    const layerKeys = new Set();
    for (const row of layerResult.data) {
        requireUuid(row?.layer_uuid);
        if (row.game_uuid !== gameUuid || row.game_map_id !== gameMapUuid
            || !isLegacyKey(row.id) || !isLegacyKey(row.game_id)
            || layerUuids.has(row.layer_uuid) || layerKeys.has(row.id)) throw new Error('MARKER_LAYER_IDENTITY_CONFLICT');
        layerUuids.add(row.layer_uuid);
        layerKeys.add(row.id);
    }
    const categoryKeys = new Set();
    for (const category of categories) {
        const key = JSON.stringify([category.legacyGameId, category.id]);
        if (categoryKeys.has(key)) throw new Error('MARKER_CATEGORY_ADAPTER_CONFLICT');
        categoryKeys.add(key);
        if (category.groupUuid !== null) {
            const group = groups.find((item) => item.groupUuid === category.groupUuid);
            if (!group || group.id !== category.group || group.legacyGameId !== category.legacyGameId) {
                throw new Error('MARKER_CATEGORY_GROUP_CONFLICT');
            }
        }
    }
    /** @type {EditorLayer[]} */
    const layers = layerResult.data.map((row) => ({
        id: row.id, legacyGameId: row.game_id, gameUuid: row.game_uuid,
        gameMapUuid: row.game_map_id, layerUuid: row.layer_uuid,
        label: { en: row.name_en, pt: row.name_pt }, sortOrder: row.sort_order,
        isActive: row.is_active !== false
    }));
    return { layers, categories, groups };
}

/** @param {any[]} rows @param {string} gameUuid @param {Awaited<ReturnType<typeof loadEditorAuthority>>} authority */
function validateMarkerRows(rows, gameUuid, { layers, categories }) {
    if (!Array.isArray(rows)) throw new Error('MARKER_EDITOR_DATA_UNAVAILABLE');
    const ids = new Set();
    for (const row of rows) {
        const key = markerIdKey(row?.id);
        const layer = layers.find((item) => item.layerUuid === row.layer_uuid);
        const category = categories.find((item) => item.categoryUuid === row.category_uuid);
        if (ids.has(key) || row.game_uuid !== gameUuid || !isLegacyKey(row.game_id)
            || !layer || layer.id !== row.map_layer || layer.legacyGameId !== row.game_id
            || !category || category.id !== row.category_id || category.legacyGameId !== row.game_id) {
            throw new Error('MARKER_EDITOR_IDENTITY_CONFLICT');
        }
        if (!isLegacyKey(row.slug) || typeof row.title_en !== 'string' || !row.title_en.trim()
            || !Number.isFinite(row.coordinate_x) || !Number.isFinite(row.coordinate_y)) {
            throw new Error('MARKER_EDITOR_FIELDS_INVALID');
        }
        ids.add(key);
    }
}

/** @param {MarkerContext} context */
export async function loadEditorMarkers(context) {
    const { supabase, gameUuid } = context;
    const authority = await loadEditorAuthority(context);
    if (!authority.layers.length) return { ...authority, markers: [] };
    const [markersResult, auditResult] = await Promise.all([
        supabase
            .from('marcadores')
            .select(MARKER_SELECT)
            .eq('game_uuid', gameUuid)
            .in('layer_uuid', authority.layers.map((layer) => layer.layerUuid))
            .order('updated_at', { ascending: false })
            .order('id', { ascending: false }),
        supabase.rpc('get_marker_editor_audit_by_game_uuid', { p_game_uuid: gameUuid })
    ]);
    assertCurrent(context);
    if (markersResult.error) throw markersResult.error;
    validateMarkerRows(markersResult.data, gameUuid, authority);
    // Preserve optional attribution on RPC errors; never call the legacy RPC.
    if (auditResult.error) {
        console.warn('DeepMap marker audit:', auditResult.error.message);
    }
    const markerKeys = new Set(markersResult.data.map((row) => markerIdKey(row.id)));
    const auditByMarker = new Map();
    const auditRows = auditResult.error ? [] : auditResult.data;
    if (!Array.isArray(auditRows)) throw new Error('MARKER_AUDIT_DATA_UNAVAILABLE');
    const auditFields = ['marker_id', 'created_by', 'created_username', 'created_at', 'updated_by',
        'updated_username', 'updated_at', 'published_by', 'published_username', 'published_at',
        'approved_by', 'approved_username', 'approved_at'];
    for (const row of auditRows) {
        const key = markerIdKey(row?.marker_id);
        if (auditByMarker.has(key) || auditFields.some((field) => !(field in row))) {
            throw new Error('MARKER_AUDIT_IDENTITY_CONFLICT');
        }
        auditByMarker.set(key, row);
    }
    // The RPC is game-wide; audit rows for other maps must also belong to this
    // game, but are never attached to the current map's marker dataset.
    const otherIds = [...auditByMarker.keys()].filter((key) => !markerKeys.has(key));
    if (otherIds.length) {
        const { data, error } = await supabase.from('marcadores').select('id, game_uuid, layer_uuid')
            .eq('game_uuid', gameUuid).in('id', otherIds);
        assertCurrent(context);
        if (error) throw error;
        const found = new Set((data ?? []).map((row) => {
            if (row.game_uuid !== gameUuid || authority.layers.some((layer) => layer.layerUuid === row.layer_uuid)) {
                throw new Error('MARKER_AUDIT_SCOPE_CONFLICT');
            }
            return markerIdKey(row.id);
        }));
        if (otherIds.some((id) => !found.has(id))) throw new Error('MARKER_AUDIT_SCOPE_CONFLICT');
    }
    return { ...authority, markers: markersResult.data.map((row) =>
        normaliseEditorMarker(row, auditByMarker.get(markerIdKey(row.id)) ?? null)) };
}

/** @param {MarkerWrite} context @param {Awaited<ReturnType<typeof loadEditorAuthority>>} authority */
function resolveWriteParents(context, authority) {
    requireUuid(context.selectedLayerUuid);
    requireUuid(context.selectedCategoryUuid);
    const layer = authority.layers.find((item) => item.layerUuid === context.selectedLayerUuid);
    const category = authority.categories.find((item) => item.categoryUuid === context.selectedCategoryUuid);
    if (!isLegacyKey(context.legacyGameId) || !layer || !category
        || layer.legacyGameId !== context.legacyGameId || category.legacyGameId !== context.legacyGameId) {
        throw new Error('MARKER_WRITE_PARENT_CONFLICT');
    }
    return { layer, category };
}

/** @param {any} data @param {MarkerWrite} context @param {Awaited<ReturnType<typeof loadEditorAuthority>>} authority @param {unknown} [expectedId] */
function validateSavedMarker(data, context, authority, expectedId) {
    validateMarkerRows([data], context.gameUuid, authority);
    if (data.layer_uuid !== context.selectedLayerUuid || data.category_uuid !== context.selectedCategoryUuid
        || data.game_id !== context.legacyGameId
        || (expectedId !== undefined && !sameMarkerId(data.id, expectedId))) throw new Error('MARKER_WRITE_RESULT_CONFLICT');
    return normaliseEditorMarker(data);
}

/** @param {MarkerWrite} context */
export async function createEditorMarker(context) {
    const { supabase, marker } = context;
    const authority = await loadEditorAuthority(context);
    const { layer, category } = resolveWriteParents(context, authority);
    assertCurrent(context);
    const { data, error } = await supabase
        .from('marcadores')
        .insert(markerPayload(context.legacyGameId, marker, layer, category))
        .select(MARKER_SELECT)
        .single();

    assertCurrent(context);
    if (error) throw error;
    return validateSavedMarker(data, context, authority);
}

/** @param {MarkerContext & {markerId: unknown}} context @param {Awaited<ReturnType<typeof loadEditorAuthority>>} authority */
async function readMutationTarget(context, authority) {
    const id = markerIdKey(context.markerId);
    if (!authority.layers.length) throw new Error('MARKER_EDITOR_TARGET_UNAVAILABLE');
    const { data, error } = await context.supabase.from('marcadores').select(MARKER_SELECT)
        .eq('id', id).eq('game_uuid', context.gameUuid)
        .in('layer_uuid', authority.layers.map((layer) => layer.layerUuid)).single();
    assertCurrent(context);
    if (error) throw error;
    validateMarkerRows([data], context.gameUuid, authority);
    if (!sameMarkerId(data.id, id)) throw new Error('MARKER_EDITOR_TARGET_CONFLICT');
    return data;
}

/** @param {MarkerWrite & {markerId: unknown}} context */
export async function updateEditorMarker(context) {
    const { supabase, marker } = context;
    markerIdKey(context.markerId);
    const authority = await loadEditorAuthority(context);
    const { layer, category } = resolveWriteParents(context, authority);
    const current = await readMutationTarget(context, authority);
    if (current.game_id !== context.legacyGameId) throw new Error('MARKER_WRITE_ALIAS_CONFLICT');
    assertCurrent(context);
    const { data, error } = await supabase
        .from('marcadores')
        .update(markerPayload(context.legacyGameId, marker, layer, category))
        .eq('id', markerIdKey(context.markerId))
        .eq('game_uuid', context.gameUuid)
        .in('layer_uuid', authority.layers.map((item) => item.layerUuid))
        .select(MARKER_SELECT)
        .single();

    assertCurrent(context);
    if (error) throw error;
    return validateSavedMarker(data, context, authority, context.markerId);
}

/** @param {MarkerContext & {markerId: unknown}} context */
export async function deleteEditorMarker(context) {
    markerIdKey(context.markerId);
    const authority = await loadEditorAuthority(context);
    await readMutationTarget(context, authority);
    assertCurrent(context);
    const { data, error } = await context.supabase
        .from('marcadores')
        .delete()
        .eq('id', markerIdKey(context.markerId))
        .eq('game_uuid', context.gameUuid)
        .in('layer_uuid', authority.layers.map((layer) => layer.layerUuid))
        .select(MARKER_SELECT).single();
    assertCurrent(context);
    if (error) throw error;
    validateMarkerRows([data], context.gameUuid, authority);
    if (!sameMarkerId(data.id, context.markerId)) throw new Error('MARKER_DELETE_RESULT_CONFLICT');
}
