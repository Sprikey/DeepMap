export function slugifyCategoryId(value) {
    return String(value ?? '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .trim()
        .replace(/[^a-z0-9]+/g, '_')
        .replace(/^_+|_+$/g, '');
}

function nullablePositiveInt(value) {
    if (value === '' || value === null || value === undefined) return null;
    const parsed = Number(value);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function normaliseCategoryPayload(category) {
    const iconSource = category.iconSource || 'none';
    const iconRef = iconSource === 'none' ? null : (category.iconRef?.trim() || null);

    return {
        group_id: category.groupId || null,
        name_en: category.nameEn.trim(),
        name_pt: category.namePt.trim(),
        icon_source: iconSource,
        icon_ref: iconRef,
        color: category.color || '#777777',
        marker_width: nullablePositiveInt(category.markerWidth),
        marker_height: nullablePositiveInt(category.markerHeight),
        symbol_size: nullablePositiveInt(category.symbolSize),
        sort_order: Number.isFinite(Number(category.sortOrder)) ? Number(category.sortOrder) : 0,
        is_active: category.isActive !== false
    };
}

export async function createEditorCategory({ supabase, gameId, category }) {
    const payload = {
        game_id: gameId,
        id: category.id,
        ...normaliseCategoryPayload(category)
    };

    const { data, error } = await supabase
        .from('marker_categories')
        .insert(payload)
        .select('*')
        .single();

    if (error) throw error;
    return data;
}

export async function updateEditorCategory({ supabase, gameId, categoryId, category }) {
    const payload = normaliseCategoryPayload(category);

    const { data, error } = await supabase
        .from('marker_categories')
        .update(payload)
        .eq('game_id', gameId)
        .eq('id', categoryId)
        .select('*')
        .single();

    if (error) throw error;
    return data;
}


function normaliseEditorCategory(row) {
    return {
        id: row.id,
        group: row.group_id,
        label: {
            en: row.name_en,
            pt: row.name_pt
        },
        iconSource: row.icon_source,
        iconRef: row.icon_ref,
        icon: row.icon_ref,
        color: row.color,
        markerWidth: row.marker_width ?? undefined,
        markerHeight: row.marker_height ?? undefined,
        symbolSize: row.symbol_size ?? undefined,
        sortOrder: row.sort_order,
        isActive: row.is_active !== false
    };
}

export async function loadEditorCategories({ supabase, gameId }) {
    const { data, error } = await supabase
        .from('marker_categories')
        .select(`
            id,
            group_id,
            name_en,
            name_pt,
            icon_source,
            icon_ref,
            color,
            marker_width,
            marker_height,
            symbol_size,
            sort_order,
            is_active
        `)
        .eq('game_id', gameId)
        .order('sort_order', { ascending: true })
        .order('id', { ascending: true });

    if (error) throw error;
    return (data ?? []).map(normaliseEditorCategory);
}

export async function deleteEditorCategory({ supabase, gameId, categoryId }) {
    const { count, error: countError } = await supabase
        .from('marcadores')
        .select('id', { count: 'exact', head: true })
        .eq('game_id', gameId)
        .eq('category_id', categoryId);

    if (countError) throw countError;

    if ((count ?? 0) > 0) {
        const error = new Error('CATEGORY_IN_USE');
        error.code = 'CATEGORY_IN_USE';
        error.markerCount = count;
        throw error;
    }

    const { error } = await supabase
        .from('marker_categories')
        .delete()
        .eq('game_id', gameId)
        .eq('id', categoryId);

    if (error) throw error;
}
