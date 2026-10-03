export const QUICK_CONTENT_EDITOR_KEY = 'quick-content-v1';

export const MARKER_CONTENT_TYPES = [
    { id: 'npc', en: 'NPC', pt: 'NPC' },
    { id: 'item', en: 'Item', pt: 'Item' },
    { id: 'reward', en: 'Reward', pt: 'Recompensa' },
    { id: 'requirement', en: 'Requirement', pt: 'Requisito' },
    { id: 'note', en: 'Note', pt: 'Nota' }
];

export function contentTypeLabel(type, language = 'en') {
    const definition = MARKER_CONTENT_TYPES.find((item) => item.id === type);
    return definition?.[language] ?? definition?.en ?? type;
}

export function normaliseMarkerContentItems(items = []) {
    return (Array.isArray(items) ? items : [])
        .map((item) => ({
            type: MARKER_CONTENT_TYPES.some((type) => type.id === item?.type) ? item.type : 'note',
            textEn: String(item?.textEn ?? item?.text_en ?? '').trim(),
            textPt: String(item?.textPt ?? item?.text_pt ?? '').trim()
        }))
        .filter((item) => item.textEn || item.textPt);
}

export function serialiseMarkerContentItems(items = []) {
    return normaliseMarkerContentItems(items).map((item) => ({
        type: item.type,
        text_en: item.textEn,
        text_pt: item.textPt
    }));
}

export async function loadEditorMarkerContent({ supabase, markerId }) {
    if (markerId == null) return [];

    const { data: sections, error: sectionsError } = await supabase
        .from('marker_sections')
        .select('id, section_type, sort_order, metadata')
        .eq('marker_id', markerId)
        .order('sort_order', { ascending: true })
        .order('id', { ascending: true });

    if (sectionsError) throw sectionsError;

    const quickSections = (sections ?? []).filter(
        (section) => section?.metadata?.editor === QUICK_CONTENT_EDITOR_KEY
    );

    if (!quickSections.length) return [];

    const sectionIds = quickSections.map((section) => section.id);
    const { data: rows, error: rowsError } = await supabase
        .from('marker_section_rows')
        .select('id, section_id, text_en, text_pt, sort_order')
        .in('section_id', sectionIds)
        .order('sort_order', { ascending: true })
        .order('id', { ascending: true });

    if (rowsError) throw rowsError;

    const sectionById = new Map(quickSections.map((section) => [Number(section.id), section]));

    return (rows ?? []).map((row) => {
        const section = sectionById.get(Number(row.section_id));
        return {
            type: section?.section_type ?? 'note',
            textEn: row.text_en ?? '',
            textPt: row.text_pt ?? ''
        };
    });
}

export async function replaceEditorMarkerContent({ supabase, markerId, items = [] }) {
    const normalised = normaliseMarkerContentItems(items);

    const { data: existingSections, error: existingError } = await supabase
        .from('marker_sections')
        .select('id, metadata')
        .eq('marker_id', markerId);

    if (existingError) throw existingError;

    const quickSectionIds = (existingSections ?? [])
        .filter((section) => section?.metadata?.editor === QUICK_CONTENT_EDITOR_KEY)
        .map((section) => section.id);

    if (quickSectionIds.length) {
        const { error: deleteError } = await supabase
            .from('marker_sections')
            .delete()
            .in('id', quickSectionIds);

        if (deleteError) throw deleteError;
    }

    if (!normalised.length) return;

    for (let index = 0; index < normalised.length; index += 1) {
        const item = normalised[index];
        const definition = MARKER_CONTENT_TYPES.find((type) => type.id === item.type);

        const { data: section, error: sectionError } = await supabase
            .from('marker_sections')
            .insert({
                marker_id: markerId,
                section_type: item.type,
                title_en: definition?.en ?? null,
                title_pt: definition?.pt ?? null,
                sort_order: (index + 1) * 10,
                is_collapsible: true,
                metadata: { editor: QUICK_CONTENT_EDITOR_KEY }
            })
            .select('id')
            .single();

        if (sectionError) throw sectionError;

        const { error: rowError } = await supabase
            .from('marker_section_rows')
            .insert({
                section_id: section.id,
                row_type: 'text',
                text_en: item.textEn || null,
                text_pt: item.textPt || null,
                sort_order: 10,
                metadata: { editor: QUICK_CONTENT_EDITOR_KEY }
            });

        if (rowError) throw rowError;
    }
}
