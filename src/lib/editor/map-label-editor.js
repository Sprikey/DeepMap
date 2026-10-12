const MAP_LABEL_SELECT = `
    id,
    game_id,
    game_uuid,
    map_layer,
    layer_uuid,
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

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** @typedef {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameUuid: string, gameMapUuid: string }} LabelContext */
/** @typedef {{ id: string, legacyGameId: string, gameUuid: string, gameMapUuid: string, layerUuid: string, label: { en: string, pt: string }, sortOrder: number, isActive: boolean }} EditorLayer */

/** @param {unknown} value */
function requireUuid(value) {
    if (typeof value !== 'string' || !UUID_PATTERN.test(value)) throw new Error('LABEL_UUID_CONTEXT_REQUIRED');
}

/** @param {unknown} value */
function isLegacyKey(value) {
    return typeof value === 'string' && value.trim().length > 0;
}

/** @param {unknown} value */
function labelIdKey(value) {
    if (typeof value === 'number' ? !Number.isSafeInteger(value)
        : typeof value !== 'string' || !/^-?[0-9]+$/.test(value)) {
        throw new Error('LABEL_BIGINT_ID_REQUIRED');
    }
    const id = BigInt(String(value));
    if (id < -9223372036854775808n || id > 9223372036854775807n) throw new Error('LABEL_BIGINT_ID_REQUIRED');
    return id.toString();
}

/** @param {LabelContext} context @returns {Promise<EditorLayer[]>} */
async function loadEditorLayers({ supabase, gameUuid, gameMapUuid }) {
    requireUuid(gameUuid);
    requireUuid(gameMapUuid);
    const { data, error } = await supabase
        .from('map_layers')
        .select('id, game_id, game_uuid, game_map_id, layer_uuid, name_en, name_pt, sort_order, is_active')
        .eq('game_uuid', gameUuid)
        .eq('game_map_id', gameMapUuid)
        .order('sort_order', { ascending: true })
        .order('id', { ascending: true });
    if (error) throw error;
    if (!Array.isArray(data)) throw new Error('LABEL_LAYERS_UNAVAILABLE');
    const uuids = new Set();
    const keys = new Set();
    for (const row of data) {
        if (!row || row.game_uuid !== gameUuid || row.game_map_id !== gameMapUuid
            || !isLegacyKey(row.id) || !isLegacyKey(row.game_id)) throw new Error('LABEL_LAYER_CONTEXT_CONFLICT');
        requireUuid(row.layer_uuid);
        if (uuids.has(row.layer_uuid) || keys.has(row.id)) throw new Error('LABEL_LAYER_IDENTITY_CONFLICT');
        uuids.add(row.layer_uuid);
        keys.add(row.id);
    }
    return data.map((row) => ({
        id: row.id, legacyGameId: row.game_id, gameUuid: row.game_uuid,
        gameMapUuid: row.game_map_id, layerUuid: row.layer_uuid,
        label: { en: row.name_en, pt: row.name_pt },
        sortOrder: row.sort_order, isActive: row.is_active !== false
    }));
}

/** @param {any[]} rows @param {string} gameUuid @param {EditorLayer[]} layers */
function validateLabelRows(rows, gameUuid, layers) {
    if (!Array.isArray(rows)) throw new Error('LABEL_EDITOR_DATA_UNAVAILABLE');
    const byUuid = new Map(layers.map((layer) => [layer.layerUuid, layer]));
    const ids = new Set();
    for (const row of rows) {
        const key = labelIdKey(row?.id);
        requireUuid(row.layer_uuid);
        const layer = byUuid.get(row.layer_uuid);
        if (ids.has(key) || row.game_uuid !== gameUuid || !isLegacyKey(row.game_id)
            || !layer || row.map_layer !== layer.id) throw new Error('LABEL_EDITOR_IDENTITY_CONFLICT');
        if (!isLegacyKey(row.slug) || typeof row.text_en !== 'string' || !row.text_en.trim()
            || (row.text_pt !== null && typeof row.text_pt !== 'string')
            || !Number.isFinite(row.coordinate_x) || !Number.isFinite(row.coordinate_y)) {
            throw new Error('LABEL_EDITOR_FIELDS_INVALID');
        }
        ids.add(key);
    }
}

/** @param {EditorLayer[]} layers @param {string} selectedLayerUuid @param {string} legacyGameId @param {any} label */
function resolveWriteLayer(layers, selectedLayerUuid, legacyGameId, label) {
    requireUuid(selectedLayerUuid);
    const layer = layers.find((item) => item.layerUuid === selectedLayerUuid);
    if (!layer || !isLegacyKey(legacyGameId) || layer.legacyGameId !== legacyGameId
        || label.mapLayer !== layer.id) throw new Error('LABEL_LAYER_ADAPTER_CONFLICT');
    return layer;
}

/** @param {unknown} value */
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

/** @param {any} row */
export function normaliseMapLabel(row) {
    return {
        id: row.id,
        legacyGameId: row.game_id,
        gameUuid: row.game_uuid,
        mapLayer: row.map_layer,
        layerUuid: row.layer_uuid,
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

/** @param {string} legacyGameId @param {any} label @param {EditorLayer} layer */
function payload(legacyGameId, label, layer) {
    if (!isLegacyKey(label.slug) || typeof label.textEn !== 'string' || !label.textEn.trim()
        || typeof label.textPt !== 'string' || !label.textPt.trim()
        || !Number.isFinite(Number(label.coordinateX)) || !Number.isFinite(Number(label.coordinateY))) {
        throw new Error('LABEL_EDITOR_FIELDS_INVALID');
    }
    return {
        game_id: legacyGameId,
        map_layer: layer.id,
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

/** @param {LabelContext} context */
export async function loadEditorMapLabels({ supabase, gameUuid, gameMapUuid }) {
    const layers = await loadEditorLayers({ supabase, gameUuid, gameMapUuid });
    if (!layers.length) return { layers, labels: [] };
    const { data, error } = await supabase
        .from('map_labels')
        .select(MAP_LABEL_SELECT)
        .eq('game_uuid', gameUuid)
        .in('layer_uuid', layers.map((layer) => layer.layerUuid))
        .order('updated_at', { ascending: false })
        .order('id', { ascending: false });

    if (error) throw error;
    validateLabelRows(data, gameUuid, layers);
    return { layers, labels: data.map(normaliseMapLabel) };
}

/** @param {LabelContext & { legacyGameId: string, selectedLayerUuid: string, label: any }} options */
export async function createEditorMapLabel({ supabase, gameUuid, gameMapUuid, legacyGameId, selectedLayerUuid, label }) {
    requireUuid(selectedLayerUuid);
    const layers = await loadEditorLayers({ supabase, gameUuid, gameMapUuid });
    const layer = resolveWriteLayer(layers, selectedLayerUuid, legacyGameId, label);
    const { data, error } = await supabase
        .from('map_labels')
        .insert(payload(legacyGameId, label, layer))
        .select(MAP_LABEL_SELECT)
        .single();

    if (error) throw error;
    validateLabelRows([data], gameUuid, layers);
    if (data.layer_uuid !== selectedLayerUuid) throw new Error('LABEL_LAYER_ADAPTER_CONFLICT');
    return normaliseMapLabel(data);
}

/** @param {LabelContext & { labelId: string | number, selectedLayerUuid: string, label: any }} options */
export async function updateEditorMapLabel({ supabase, gameUuid, gameMapUuid, labelId, selectedLayerUuid, label }) {
    const expectedId = labelIdKey(labelId);
    requireUuid(selectedLayerUuid);
    const layers = await loadEditorLayers({ supabase, gameUuid, gameMapUuid });
    const layerUuids = layers.map((layer) => layer.layerUuid);
    if (!layerUuids.length) throw new Error('LABEL_LAYERS_UNAVAILABLE');
    // Preserve the target's own legacy alias in the compatibility payload;
    // the permanent target and its map membership are independently UUID-scoped.
    const { data: existing, error: readError } = await supabase
        .from('map_labels')
        .select(MAP_LABEL_SELECT)
        .eq('id', labelId)
        .eq('game_uuid', gameUuid)
        .in('layer_uuid', layerUuids)
        .single();
    if (readError) throw readError;
    validateLabelRows([existing], gameUuid, layers);
    if (labelIdKey(existing.id) !== expectedId) throw new Error('LABEL_EDITOR_IDENTITY_CONFLICT');
    const layer = resolveWriteLayer(layers, selectedLayerUuid, existing.game_id, label);
    const { data, error } = await supabase
        .from('map_labels')
        .update(payload(existing.game_id, label, layer))
        .eq('id', labelId)
        .eq('game_uuid', gameUuid)
        .in('layer_uuid', layerUuids)
        .select(MAP_LABEL_SELECT)
        .single();

    if (error) throw error;
    validateLabelRows([data], gameUuid, layers);
    if (labelIdKey(data.id) !== expectedId || data.layer_uuid !== selectedLayerUuid) {
        throw new Error('LABEL_EDITOR_IDENTITY_CONFLICT');
    }
    return normaliseMapLabel(data);
}

/** @param {LabelContext & { labelId: string | number }} options */
export async function deleteEditorMapLabel({ supabase, gameUuid, gameMapUuid, labelId }) {
    const expectedId = labelIdKey(labelId);
    const layers = await loadEditorLayers({ supabase, gameUuid, gameMapUuid });
    if (!layers.length) throw new Error('LABEL_LAYERS_UNAVAILABLE');
    const { data, error } = await supabase
        .from('map_labels')
        .delete()
        .eq('id', labelId)
        .eq('game_uuid', gameUuid)
        .in('layer_uuid', layers.map((layer) => layer.layerUuid))
        .select(MAP_LABEL_SELECT)
        .single();

    if (error) throw error;
    validateLabelRows([data], gameUuid, layers);
    if (labelIdKey(data.id) !== expectedId) throw new Error('LABEL_EDITOR_IDENTITY_CONFLICT');
}
