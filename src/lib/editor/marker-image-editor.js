const IMAGE_SELECT = `
    id,
    marker_id,
    source,
    image_ref,
    alt_en,
    alt_pt,
    caption_en,
    caption_pt,
    sort_order,
    is_cover,
    created_at,
    updated_at
`;

export function resolveMarkerImageUrl(image) {
    if (!image?.imageRef) return null;
    if (image.source === 'r2') return null;
    return image.imageRef;
}

function normaliseImage(row) {
    return {
        id: row.id,
        markerId: row.marker_id,
        source: row.source,
        imageRef: row.image_ref,
        altEn: row.alt_en ?? '',
        altPt: row.alt_pt ?? '',
        captionEn: row.caption_en ?? '',
        captionPt: row.caption_pt ?? '',
        sortOrder: row.sort_order ?? 0,
        isCover: row.is_cover === true,
        createdAt: row.created_at,
        updatedAt: row.updated_at
    };
}

export async function loadMarkerImages({ supabase, markerId }) {
    const { data, error } = await supabase
        .from('marker_images')
        .select(IMAGE_SELECT)
        .eq('marker_id', markerId)
        .order('sort_order', { ascending: true })
        .order('id', { ascending: true });

    if (error) throw error;
    return (data ?? []).map(normaliseImage);
}

export async function createMarkerImage({ supabase, markerId, image }) {
    const { data, error } = await supabase
        .from('marker_images')
        .insert({
            marker_id: markerId,
            source: image.source,
            image_ref: image.imageRef.trim(),
            alt_en: null,
            alt_pt: null,
            caption_en: null,
            caption_pt: null,
            sort_order: Number(image.sortOrder) || 0,
            is_cover: image.isCover === true
        })
        .select(IMAGE_SELECT)
        .single();

    if (error) throw error;
    return normaliseImage(data);
}

export async function deleteMarkerImage({ supabase, imageId }) {
    const { error } = await supabase
        .from('marker_images')
        .delete()
        .eq('id', imageId);

    if (error) throw error;
}

export async function setMarkerImageCover({ supabase, markerId, imageId }) {
    const { error: clearError } = await supabase
        .from('marker_images')
        .update({ is_cover: false })
        .eq('marker_id', markerId)
        .eq('is_cover', true);

    if (clearError) throw clearError;

    const { error } = await supabase
        .from('marker_images')
        .update({ is_cover: true })
        .eq('marker_id', markerId)
        .eq('id', imageId);

    if (error) throw error;
}

export async function moveMarkerImage({ supabase, images, imageId, direction }) {
    const ordered = [...images].sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0));
    const index = ordered.findIndex((image) => image.id === imageId);
    if (index < 0) return;

    const targetIndex = direction === 'up' ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= ordered.length) return;

    const current = ordered[index];
    const target = ordered[targetIndex];
    const currentOrder = Number(current.sortOrder ?? index * 10 + 10);
    const targetOrder = Number(target.sortOrder ?? targetIndex * 10 + 10);

    const { error: firstError } = await supabase
        .from('marker_images')
        .update({ sort_order: targetOrder })
        .eq('id', current.id);

    if (firstError) throw firstError;

    const { error: secondError } = await supabase
        .from('marker_images')
        .update({ sort_order: currentOrder })
        .eq('id', target.id);

    if (secondError) throw secondError;
}
