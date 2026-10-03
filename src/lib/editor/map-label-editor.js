const MAP_LABEL_SELECT = `
    id,
    game_id,
    map_layer,
    slug,
    text_en,
    text_pt,
    coordinate_x,
    coordinate_y,
    font_size,
    font_weight,
    color,
    opacity,
    uppercase,
    is_published,
    created_at,
    updated_at
`;

export function slugifyMapLabel(value) {
    return String(value ?? '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .trim()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '')
        .slice(0, 80);
}

export function normaliseMapLabel(row) {
    return {
        id: row.id,
        gameId: row.game_id,
        mapLayer: row.map_layer,
        slug: row.slug,
        textEn: row.text_en ?? '',
        textPt: row.text_pt ?? '',
        coordinateX: row.coordinate_x,
        coordinateY: row.coordinate_y,
        fontSize: row.font_size ?? 34,
        fontWeight: row.font_weight ?? 700,
        color: row.color ?? '#E8D7A4',
        opacity: row.opacity ?? 0.82,
        uppercase: row.uppercase !== false,
        isPublished: row.is_published === true,
        createdAt: row.created_at,
        updatedAt: row.updated_at
    };
}

function payload(gameId, label) {
    return {
        game_id: gameId,
        map_layer: label.mapLayer,
        slug: label.slug,
        text_en: label.textEn.trim(),
        text_pt: label.textPt.trim(),
        coordinate_x: Number(label.coordinateX),
        coordinate_y: Number(label.coordinateY),
        font_size: Number(label.fontSize),
        font_weight: Number(label.fontWeight),
        color: label.color,
        opacity: Number(label.opacity),
        uppercase: label.uppercase === true,
        is_published: label.isPublished === true
    };
}

export async function loadEditorMapLabels({ supabase, gameId }) {
    const { data, error } = await supabase
        .from('map_labels')
        .select(MAP_LABEL_SELECT)
        .eq('game_id', gameId)
        .order('updated_at', { ascending: false })
        .order('id', { ascending: false });

    if (error) throw error;
    return (data ?? []).map(normaliseMapLabel);
}

export async function createEditorMapLabel({ supabase, gameId, label }) {
    const { data, error } = await supabase
        .from('map_labels')
        .insert(payload(gameId, label))
        .select(MAP_LABEL_SELECT)
        .single();

    if (error) throw error;
    return normaliseMapLabel(data);
}

export async function updateEditorMapLabel({ supabase, gameId, labelId, label }) {
    const { data, error } = await supabase
        .from('map_labels')
        .update(payload(gameId, label))
        .eq('id', labelId)
        .eq('game_id', gameId)
        .select(MAP_LABEL_SELECT)
        .single();

    if (error) throw error;
    return normaliseMapLabel(data);
}

export async function deleteEditorMapLabel({ supabase, gameId, labelId }) {
    const { error } = await supabase
        .from('map_labels')
        .delete()
        .eq('id', labelId)
        .eq('game_id', gameId);

    if (error) throw error;
}
