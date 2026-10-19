import { markerIdKey } from '../editor/marker-editor.js';

/** @param {unknown} value */
export function isCommunityGameUuid(value) {
    return typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

/** Community keeps canonical BIGINT strings; staff compatibility remains unchanged. @param {any} row */
export function normaliseCommunitySubmission(row) {
    return {
        ...submissionDetails(row),
        id: markerIdKey(row.id),
        markerId: row.marker_id == null ? null : markerIdKey(row.marker_id),
        gameUuid: row.game_uuid ?? null,
        gameSlug: row.game_slug ?? null,
        legacyGameId: row.game_id
    };
}

export async function ensureContributorProfile({ supabase }) {
    const { data, error } = await supabase.rpc('ensure_deepmap_profile');
    if (error) throw error;
    if (!data || !String(data).trim()) throw new Error('USERNAME_REQUIRED');
    return String(data).trim();
}

/** @param {any} row */
export function normaliseSubmission(row) {
    return {
        ...normaliseCommunitySubmission(row),
        gameName: row.game_name ?? null
    };
}

/** Shared display fields, without converting identities. @param {any} row */
function submissionDetails(row) {
    return {
        type: row.submission_type,
        correctionKind: row.correction_kind ?? null,
        status: row.status,
        submittedBy: row.submitted_by,
        submittedUsername: row.submitted_username ?? null,
        payload: row.payload ?? {},
        note: row.note ?? '',
        reviewedBy: row.reviewed_by ?? null,
        reviewedUsername: row.reviewed_username ?? null,
        reviewedAt: row.reviewed_at ?? null,
        reviewNote: row.review_note ?? '',
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        revisionCount: Number(row.revision_count ?? 0),
        totalCount: Number(row.total_count ?? 0)
    };
}

/** @param {{supabase: any, gameUuid: string, limit?: number, offset?: number}} options */
export async function loadMyMarkerSubmissionsPage({
    supabase,
    gameUuid,
    limit = 20,
    offset = 0
}) {
    if (!isCommunityGameUuid(gameUuid)) throw new Error('COMMUNITY_GAME_UUID_REQUIRED');
    const { data, error } = await supabase.rpc('get_my_marker_submissions_page_by_game_uuid', {
        p_game_uuid: gameUuid,
        p_limit: limit,
        p_offset: offset
    });

    if (error) throw error;
    const rows = data ?? [];
    return {
        items: rows.map(normaliseCommunitySubmission),
        total: rows.length ? Number(rows[0].total_count ?? 0) : 0
    };
}

/** @param {{supabase: any, gameUuid?: string | null, status?: string, limit?: number, offset?: number}} options */
export async function loadMarkerSubmissionsPage({
    supabase,
    gameUuid = null,
    status = 'pending',
    limit = 10,
    offset = 0
}) {
    if (gameUuid !== null && !isCommunityGameUuid(gameUuid)) throw new Error('MODERATION_GAME_UUID_REQUIRED');
    if (!['pending', 'approved', 'rejected'].includes(status)) throw new Error('INVALID_STATUS');
    const { data, error } = await supabase.rpc('get_marker_submissions_page_by_game_uuid', {
        p_game_uuid: gameUuid,
        p_status: status,
        p_limit: limit,
        p_offset: offset
    });

    if (error) throw error;

    const rows = data ?? [];
    return {
        items: rows.map(normaliseSubmission),
        total: rows.length ? Number(rows[0].total_count ?? 0) : 0
    };
}

/** @param {any} row @param {'current' | 'submitted'} scope @param {'layer' | 'category' | 'group'} kind */
function reviewParent(row, scope, kind) {
    const prefix = `${scope}_${kind}`;
    if (row[`${prefix}_uuid`] == null) return null;
    return {
        uuid: row[`${prefix}_uuid`],
        id: row[`${prefix}_id`],
        gameMapUuid: kind === 'layer' ? row[`${scope}_game_map_uuid`] : null,
        label: { en: row[`${prefix}_name_en`], pt: row[`${prefix}_name_pt`] },
        isActive: row[`${prefix}_is_active`]
    };
}

/** B7e2's complete raw row is retained; unresolved submitted parents stay null. @param {any} row */
export function normaliseMarkerReviewContext(row) {
    const markerId = row.marker_id == null ? null : markerIdKey(row.marker_id);
    const targetId = row.target_id == null ? null : markerIdKey(row.target_id);
    if (!isCommunityGameUuid(row.game_uuid) || (markerId !== null
        && (targetId !== markerId || row.target_game_uuid !== row.game_uuid))
        || (targetId !== null && markerId === null)
        || (row.submission_type === 'correction' && targetId === null)) {
        throw new Error('REVIEW_CONTEXT_TARGET_NOT_FOUND');
    }
    return {
        raw: row,
        submissionId: markerIdKey(row.submission_id),
        gameUuid: row.game_uuid,
        gameSlug: row.game_slug,
        gameName: row.game_name,
        legacyGameId: row.game_id,
        markerId,
        payload: row.payload,
        status: row.status,
        target: targetId === null ? null : {
            databaseId: targetId, gameUuid: row.target_game_uuid,
            title: { en: row.target_title_en, pt: row.target_title_pt },
            regionId: row.target_region_id,
            description: { en: row.target_description_en, pt: row.target_description_pt },
            videoUrl: row.target_video_url,
            coordinates: [row.target_coordinate_y, row.target_coordinate_x],
            isPublished: row.target_is_published,
            contentItems: row.target_content_items ?? [],
            imageCount: Number(row.target_image_count ?? 0),
            mapLayer: row.current_layer_id,
            categoryId: row.current_category_id
        },
        current: { layer: reviewParent(row, 'current', 'layer'), category: reviewParent(row, 'current', 'category'), group: reviewParent(row, 'current', 'group') },
        submitted: { layer: reviewParent(row, 'submitted', 'layer'), category: reviewParent(row, 'submitted', 'category'), group: reviewParent(row, 'submitted', 'group') }
    };
}

/** @param {{supabase: any, gameUuid: string, submissionId: unknown}} options */
export async function loadMarkerReviewContext({ supabase, gameUuid, submissionId }) {
    if (!isCommunityGameUuid(gameUuid)) throw new Error('MODERATION_GAME_UUID_REQUIRED');
    const id = markerIdKey(submissionId);
    const { data, error } = await supabase.rpc('get_marker_review_context_by_game_uuid', {
        p_game_uuid: gameUuid, p_submission_id: id
    });
    if (error) throw error;
    if (!Array.isArray(data) || data.length !== 1) throw new Error('REVIEW_CONTEXT_NOT_FOUND');
    const context = normaliseMarkerReviewContext(data[0]);
    if (context.gameUuid !== gameUuid || context.submissionId !== id) throw new Error('REVIEW_CONTEXT_NOT_FOUND');
    return context;
}

/** @param {{supabase: any, gameUuid: string, userId: string, markerId: unknown}} options */
export async function findPendingMarkerCorrection({ supabase, gameUuid, userId, markerId }) {
    if (!userId || markerId == null) return null;
    if (!isCommunityGameUuid(gameUuid)) throw new Error('COMMUNITY_GAME_UUID_REQUIRED');

    const { data, error } = await supabase
        .from('marker_submissions')
        .select('id')
        .eq('game_uuid', gameUuid)
        .eq('submitted_by', userId)
        .eq('marker_id', markerIdKey(markerId))
        .eq('submission_type', 'correction')
        .eq('status', 'pending')
        .order('updated_at', { ascending: false })
        .limit(1)
        .maybeSingle();

    if (error) throw error;
    return data?.id == null ? null : markerIdKey(data.id);
}

/** @param {{supabase: any, legacyGameId: string, userId: string, type: string, markerId?: unknown, correctionKind?: string | null, payload: any, note?: string}} options */
export async function createMarkerSubmission({
    supabase,
    legacyGameId,
    userId,
    type,
    markerId = null,
    correctionKind = null,
    payload,
    note = ''
}) {
    const { data, error } = await supabase
        .from('marker_submissions')
        .insert({
            game_id: legacyGameId,
            marker_id: markerId == null ? null : markerIdKey(markerId),
            submission_type: type,
            correction_kind: correctionKind,
            status: 'pending',
            submitted_by: userId,
            payload,
            note: note?.trim() || null
        })
        .select('id')
        .single();

    if (error) throw error;
    return markerIdKey(data.id);
}

export async function updateMarkerSubmission({
    supabase,
    submissionId,
    correctionKind = null,
    payload,
    note = ''
}) {
    const { data, error } = await supabase
        .from('marker_submissions')
        .update({
            correction_kind: correctionKind,
            payload,
            note: note?.trim() || null
        })
        .eq('id', submissionId)
        .eq('status', 'pending')
        .select('id')
        .maybeSingle();

    if (error) throw error;
    if (!data) throw new Error('SUBMISSION_NOT_PENDING');
}

export async function cancelMarkerSubmission({ supabase, submissionId }) {
    const { error } = await supabase.rpc('cancel_marker_submission', {
        p_submission_id: submissionId
    });

    if (error) throw error;
}

export async function reviewMarkerSubmission({
    supabase,
    submissionId,
    decision,
    reviewNote = '',
    payloadOverride = null
}) {
    const { data, error } = await supabase.rpc('review_marker_submission_v2', {
        p_submission_id: markerIdKey(submissionId),
        p_decision: decision,
        p_review_note: reviewNote?.trim() || null,
        p_payload_override: payloadOverride
    });

    if (error) throw error;
    return data == null ? null : markerIdKey(data);
}
