const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** @param {unknown} value */
function requireUuid(value) {
    if (typeof value !== 'string' || !UUID_PATTERN.test(value)) {
        throw new Error('CATEGORY_UUID_CONTEXT_REQUIRED');
    }
}

/** @param {unknown} value */
function isLegacyKey(value) {
    return typeof value === 'string' && value.trim().length > 0;
}

/** @param {unknown} value */
export function slugifyCategoryId(value) {
    return String(value ?? '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .trim()
        .replace(/[^a-z0-9]+/g, '_')
        .replace(/^_+|_+$/g, '');
}

/** @param {any} value */
function nullablePositiveInt(value) {
    if (value === '' || value === null || value === undefined) return null;
    const parsed = Number(value);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

/** @param {any} category @param {string | null} groupId */
function normaliseCategoryPayload(category, groupId) {
    const iconSource = category.iconSource || 'none';
    const iconRef = iconSource === 'none' ? null : (category.iconRef?.trim() || null);

    return {
        group_id: groupId,
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

/** @param {any[]} rows @param {string} gameUuid @param {'category_uuid' | 'group_uuid'} uuidField */
function validateEditorRows(rows, gameUuid, uuidField) {
    if (!Array.isArray(rows)) throw new Error('CATEGORY_EDITOR_DATA_UNAVAILABLE');
    const uuids = new Set();
    for (const row of rows) {
        if (!row || row.game_uuid !== gameUuid || !isLegacyKey(row.id) || !isLegacyKey(row.game_id)) {
            throw new Error('CATEGORY_EDITOR_IDENTITY_CONFLICT');
        }
        requireUuid(row[uuidField]);
        if (uuids.has(row[uuidField])) throw new Error('CATEGORY_EDITOR_DUPLICATE_UUID');
        uuids.add(row[uuidField]);
        if (uuidField === 'category_uuid') {
            if (row.group_id === null) {
                if (row.group_uuid !== null) throw new Error('CATEGORY_GROUP_IDENTITY_CONFLICT');
            } else {
                if (!isLegacyKey(row.group_id)) throw new Error('CATEGORY_GROUP_IDENTITY_CONFLICT');
                requireUuid(row.group_uuid);
            }
        }
    }
}

/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string, groupUuid: string | null }} options */
async function resolveLegacyGroupId({ supabase, gameUuid, groupUuid }) {
    if (groupUuid === null) return null;
    requireUuid(groupUuid);
    const { data, error } = await supabase
        .from('marker_category_groups')
        .select('id, game_id, game_uuid, group_uuid')
        .eq('game_uuid', gameUuid)
        .eq('group_uuid', groupUuid)
        .single();
    if (error) throw error;
    validateEditorRows([data], gameUuid, 'group_uuid');
    if (data.group_uuid !== groupUuid) throw new Error('CATEGORY_GROUP_IDENTITY_CONFLICT');
    return data.id;
}

/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string, legacyGameId: string, category: any, isCurrent?: () => boolean }} options */
export async function createEditorCategory({ supabase, isCurrent = () => true, gameUuid, legacyGameId, category }) {
    requireUuid(gameUuid);
    if (!isLegacyKey(legacyGameId) || !isLegacyKey(category.id)) throw new Error('CATEGORY_LEGACY_PAYLOAD_REQUIRED');
    const groupId = await resolveLegacyGroupId({ supabase, gameUuid, groupUuid: category.groupUuid });
    const payload = {
        game_id: legacyGameId,
        // Let the DB bridge reject an alias for another game before insertion.
        game_uuid: gameUuid,
        id: category.id,
        ...normaliseCategoryPayload(category, groupId)
    };

    if (!isCurrent()) throw new Error('EDITOR_STALE_SESSION');

    const { data, error } = await supabase
        .from('marker_categories')
        .insert(payload)
        .select('*')
        .single();

    if (error) throw error;
    validateEditorRows([data], gameUuid, 'category_uuid');
    return data;
}

/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string, categoryUuid: string, category: any, isCurrent?: () => boolean }} options */
export async function updateEditorCategory({ supabase, isCurrent = () => true, gameUuid, categoryUuid, category }) {
    requireUuid(gameUuid);
    requireUuid(categoryUuid);
    const groupId = await resolveLegacyGroupId({ supabase, gameUuid, groupUuid: category.groupUuid });
    const payload = normaliseCategoryPayload(category, groupId);

    if (!isCurrent()) throw new Error('EDITOR_STALE_SESSION');

    const { data, error } = await supabase
        .from('marker_categories')
        .update(payload)
        .eq('game_uuid', gameUuid)
        .eq('category_uuid', categoryUuid)
        .select('*')
        .single();

    if (error) throw error;
    validateEditorRows([data], gameUuid, 'category_uuid');
    if (data.category_uuid !== categoryUuid) throw new Error('CATEGORY_EDITOR_IDENTITY_CONFLICT');
    return data;
}


/** @param {any} row */
function normaliseEditorCategory(row) {
    return {
        id: row.id,
        legacyGameId: row.game_id,
        gameUuid: row.game_uuid,
        categoryUuid: row.category_uuid,
        group: row.group_id,
        groupUuid: row.group_uuid,
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

/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string }} options */
export async function loadEditorCategories({ supabase, gameUuid }) {
    requireUuid(gameUuid);
    const { data, error } = await supabase
        .from('marker_categories')
        .select(`
            id,
            game_id,
            game_uuid,
            category_uuid,
            group_id,
            group_uuid,
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
        .eq('game_uuid', gameUuid)
        .order('sort_order', { ascending: true })
        .order('id', { ascending: true });

    if (error) throw error;
    validateEditorRows(data, gameUuid, 'category_uuid');
    return data.map(normaliseEditorCategory);
}

/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string }} options */
export async function loadEditorCategoryGroups({ supabase, gameUuid }) {
    requireUuid(gameUuid);
    const { data, error } = await supabase
        .from('marker_category_groups')
        .select('id, game_id, game_uuid, group_uuid, name_en, name_pt, sort_order, is_active')
        .eq('game_uuid', gameUuid)
        .order('sort_order', { ascending: true })
        .order('id', { ascending: true });
    if (error) throw error;
    validateEditorRows(data, gameUuid, 'group_uuid');
    return data.map((row) => ({
        id: row.id,
        legacyGameId: row.game_id,
        gameUuid: row.game_uuid,
        groupUuid: row.group_uuid,
        label: { en: row.name_en, pt: row.name_pt },
        sortOrder: row.sort_order,
        isActive: row.is_active !== false
    }));
}

/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string, categoryUuid: string, isCurrent?: () => boolean }} options */
export async function deleteEditorCategory({ supabase, isCurrent = () => true, gameUuid, categoryUuid }) {
    requireUuid(gameUuid);
    requireUuid(categoryUuid);
    if (!isCurrent()) throw new Error('EDITOR_STALE_SESSION');
    const { count, error: countError } = await supabase
        .from('marcadores')
        .select('id', { count: 'exact', head: true })
        .eq('game_uuid', gameUuid)
        .eq('category_uuid', categoryUuid);

    if (countError) throw countError;

    if (count === null || !Number.isSafeInteger(count) || count < 0) throw new Error('CATEGORY_USAGE_UNAVAILABLE');
    if (count > 0) {
        throw Object.assign(new Error('CATEGORY_IN_USE'), { code: 'CATEGORY_IN_USE', markerCount: count });
    }

    if (!isCurrent()) throw new Error('EDITOR_STALE_SESSION');

    const { data, error } = await supabase
        .from('marker_categories')
        .delete()
        .eq('game_uuid', gameUuid)
        .eq('category_uuid', categoryUuid)
        .select('game_uuid, category_uuid')
        .single();

    if (error) throw error;
    if (!data || data.game_uuid !== gameUuid || data.category_uuid !== categoryUuid) {
        throw new Error('CATEGORY_EDITOR_IDENTITY_CONFLICT');
    }
}
