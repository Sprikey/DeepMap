const MARKER_SELECT = `
    id,
    game_id,
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
    is_published,
    created_at,
    updated_at
`;

export function normaliseEditorMarker(row, audit = null) {
    return {
        id: row.id,
        gameId: row.game_id,
        mapLayer: row.map_layer,
        slug: row.slug,
        categoryId: row.category_id,
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

function markerPayload(gameId, marker) {
    return {
        game_id: gameId,
        map_layer: marker.mapLayer,
        slug: marker.slug,
        category_id: marker.categoryId,
        region_id: marker.regionId?.trim() || null,
        title_en: marker.titleEn.trim(),
        title_pt: marker.titlePt.trim(),
        coordinate_x: Number(marker.coordinateX),
        coordinate_y: Number(marker.coordinateY),
        description_en: marker.descriptionEn?.trim() || null,
        description_pt: marker.descriptionPt?.trim() || null,
        video_url: marker.videoUrl?.trim() || null,
        is_published: marker.isPublished === true
    };
}

export async function loadEditorMarkers({ supabase, gameId }) {
    const [markersResult, auditResult] = await Promise.all([
        supabase
            .from('marcadores')
            .select(MARKER_SELECT)
            .eq('game_id', gameId)
            .order('updated_at', { ascending: false })
            .order('id', { ascending: false }),
        supabase.rpc('get_marker_editor_audit', { p_game_id: gameId })
    ]);

    if (markersResult.error) throw markersResult.error;

    // The editor remains usable if the audit migration has not yet been applied.
    // Attribution simply stays empty until the RPC exists.
    if (auditResult.error) {
        console.warn('DeepMap marker audit:', auditResult.error.message);
    }

    const auditByMarker = new Map(
        (auditResult.data ?? []).map((row) => [Number(row.marker_id), row])
    );

    return (markersResult.data ?? []).map((row) =>
        normaliseEditorMarker(row, auditByMarker.get(Number(row.id)) ?? null)
    );
}

export async function createEditorMarker({ supabase, gameId, marker }) {
    const { data, error } = await supabase
        .from('marcadores')
        .insert(markerPayload(gameId, marker))
        .select(MARKER_SELECT)
        .single();

    if (error) throw error;

    return normaliseEditorMarker(data);
}

export async function updateEditorMarker({ supabase, gameId, markerId, marker }) {
    const { data, error } = await supabase
        .from('marcadores')
        .update(markerPayload(gameId, marker))
        .eq('id', markerId)
        .eq('game_id', gameId)
        .select(MARKER_SELECT)
        .single();

    if (error) throw error;

    return normaliseEditorMarker(data);
}

export async function deleteEditorMarker({ supabase, gameId, markerId }) {
    const { error } = await supabase
        .from('marcadores')
        .delete()
        .eq('id', markerId)
        .eq('game_id', gameId);

    if (error) throw error;
}
