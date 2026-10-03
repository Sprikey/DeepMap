/* ==========================================
   DEEPMAP — MAP DATA SOURCE
   ==========================================

   Loader genérico para qualquer jogo/mapa.

   A página fornece apenas:
   - gameId (ex.: "elden-ring")
   - cliente Supabase
   - dados legacy de fallback durante a migração

   O objetivo é o Editor/Mapa não depender de ficheiros específicos
   de um jogo. Quando a migração para a BD estiver concluída, o fallback
   pode ser desligado/removido sem alterar o formato consumido pelo mapa.
*/

function keyedObject(rows, transform) {
    return Object.fromEntries(rows.map((row) => {
        const value = transform(row);
        return [value.id, value];
    }));
}

function resolveAsset(source, ref) {
    if (!ref) return null;

    // R2 será resolvido numa fase própria quando ligarmos uploads/CDN.
    if (source === 'r2') return null;

    return ref;
}

function normaliseLayer(row) {
    return {
        id: row.id,
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
        label: { en: row.name_en, pt: row.name_pt },
        sortOrder: row.sort_order
    };
}

function normaliseCategory(row) {
    return {
        id: row.id,
        group: row.group_id,
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

function mergeKeyedObjects(fallbackValue, databaseValue) {
    return { ...(fallbackValue ?? {}), ...(databaseValue ?? {}) };
}

function mergeArraysById(fallbackValue, databaseValue) {
    const merged = new Map();
    for (const item of fallbackValue ?? []) merged.set(item.id, item);
    for (const item of databaseValue ?? []) merged.set(item.id, item);
    return [...merged.values()].sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0));
}

async function queryWithMigrationFallback({ query, fallbackValue, transform, merge, label }) {
    try {
        const { data, error } = await query;
        if (error) throw error;

        if (!data?.length) {
            return { value: fallbackValue, source: 'fallback-empty' };
        }

        const databaseValue = transform(data);
        return {
            value: merge(fallbackValue, databaseValue),
            source: 'supabase+fallback'
        };
    } catch (error) {
        console.warn(`DeepMap map data (${label}):`, error?.message ?? error);
        return { value: fallbackValue, source: 'fallback-error' };
    }
}

async function attachPublicMarkerAttribution({ supabase, gameId, locations }) {
    try {
        const { data, error } = await supabase.rpc('get_public_marker_attribution', {
            p_game_id: gameId
        });

        if (error) throw error;

        const attributionByMarker = new Map(
            (data ?? []).map((row) => [Number(row.marker_id), row])
        );

        return locations.map((location) => {
            const attribution = location.databaseId
                ? attributionByMarker.get(Number(location.databaseId)) ?? null
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
        .filter((id) => Number.isFinite(Number(id)))
        .map(Number);

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
        for (const row of data ?? []) {
            const image = normaliseMarkerImage(row);
            if (!byMarker.has(image.markerId)) byMarker.set(image.markerId, []);
            byMarker.get(image.markerId).push(image);
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

            const images = byMarker.get(location.databaseId) ?? [];
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
        .filter((id) => Number.isFinite(Number(id)))
        .map(Number);

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

        const sectionIds = sections.map((section) => section.id);
        const { data: rows, error: rowsError } = await supabase
            .from('marker_section_rows')
            .select('id, section_id, text_en, text_pt, sort_order')
            .in('section_id', sectionIds)
            .order('sort_order', { ascending: true })
            .order('id', { ascending: true });

        if (rowsError) throw rowsError;

        const sectionById = new Map(sections.map((section) => [Number(section.id), section]));
        const byMarker = new Map();

        for (const row of rows ?? []) {
            const section = sectionById.get(Number(row.section_id));
            if (!section) continue;

            const markerId = Number(section.marker_id);
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
                ? byMarker.get(Number(location.databaseId)) ?? []
                : location.contentItems ?? []
        }));
    } catch (error) {
        console.warn('DeepMap map data (marker content):', error?.message ?? error);
        return locations;
    }
}

export async function loadDeepMapGameData({ supabase, gameId, fallback }) {
    const layersPromise = queryWithMigrationFallback({
        query: supabase
            .from('map_layers')
            .select('id, name_en, name_pt, image_source, image_ref, width, height, sort_order')
            .eq('game_id', gameId)
            .eq('is_active', true)
            .order('sort_order', { ascending: true }),
        fallbackValue: fallback.mapDefinitions,
        transform: (rows) => keyedObject(rows, normaliseLayer),
        merge: mergeKeyedObjects,
        label: 'layers'
    });

    const groupsPromise = queryWithMigrationFallback({
        query: supabase
            .from('marker_category_groups')
            .select('id, name_en, name_pt, sort_order')
            .eq('game_id', gameId)
            .eq('is_active', true)
            .order('sort_order', { ascending: true }),
        fallbackValue: fallback.categoryGroups,
        transform: (rows) => rows.map(normaliseGroup),
        merge: mergeArraysById,
        label: 'category groups'
    });

    const categoriesPromise = queryWithMigrationFallback({
        query: supabase
            .from('marker_categories')
            .select('id, group_id, name_en, name_pt, icon_source, icon_ref, color, marker_width, marker_height, symbol_size, sort_order')
            .eq('game_id', gameId)
            .eq('is_active', true)
            .order('sort_order', { ascending: true }),
        fallbackValue: fallback.categories,
        transform: (rows) => keyedObject(rows, normaliseCategory),
        merge: mergeKeyedObjects,
        label: 'categories'
    });

    const markersPromise = queryWithMigrationFallback({
        query: supabase
            .from('marcadores')
            .select(`
                id,
                map_layer,
                slug,
                category_id,
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
                is_published
            `)
            .eq('game_id', gameId)
            .eq('is_published', true)
            .order('id', { ascending: true }),
        fallbackValue: fallback.locations,
        transform: (rows) => rows.map(normaliseMarker),
        merge: mergeArraysById,
        label: 'markers'
    });

    const labelsPromise = queryWithMigrationFallback({
        query: supabase
            .from('map_labels')
            .select('id, map_layer, slug, text_en, text_pt, coordinate_x, coordinate_y, font_size, font_weight, color, opacity, uppercase, is_published')
            .eq('game_id', gameId)
            .eq('is_published', true)
            .order('id', { ascending: true }),
        fallbackValue: fallback.mapLabels ?? [],
        transform: (rows) => rows.map(normaliseMapLabel),
        merge: mergeArraysById,
        label: 'map labels'
    });

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

    const locations = await attachPublicMarkerAttribution({
        supabase,
        gameId,
        locations: locationsWithContent
    });

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
