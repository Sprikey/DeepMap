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

export function normaliseSubmission(row) {
    return {
        id: Number(row.id),
        gameId: row.game_id,
        markerId: row.marker_id == null ? null : Number(row.marker_id),
        ...submissionDetails(row)
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

export async function loadMarkerSubmissions({ supabase, gameId, scope = 'mine' }) {
    const { data, error } = await supabase.rpc('get_marker_submissions', {
        p_game_id: gameId,
        p_scope: scope
    });

    if (error) throw error;
    return (data ?? []).map(normaliseSubmission);
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

export async function loadMarkerSubmissionsPage({
    supabase,
    gameId,
    status = 'pending',
    limit = 10,
    offset = 0
}) {
    const { data, error } = await supabase.rpc('get_marker_submissions_page', {
        p_game_id: gameId,
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
        p_submission_id: submissionId,
        p_decision: decision,
        p_review_note: reviewNote?.trim() || null,
        p_payload_override: payloadOverride
    });

    if (error) throw error;
    return data == null ? null : Number(data);
}
