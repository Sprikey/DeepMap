
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




export async function loadMyMarkerSubmissionsPage({
    supabase,
    gameId,
    limit = 20,
    offset = 0
}) {
    const { data, error } = await supabase.rpc('get_my_marker_submissions_page', {
        p_game_id: gameId,
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

export async function findPendingMarkerCorrection({ supabase, gameId, userId, markerId }) {
    if (!userId || markerId == null) return null;

    const { data, error } = await supabase
        .from('marker_submissions')
        .select('id')
        .eq('game_id', gameId)
        .eq('submitted_by', userId)
        .eq('marker_id', markerId)
        .eq('submission_type', 'correction')
        .eq('status', 'pending')
        .order('updated_at', { ascending: false })
        .limit(1)
        .maybeSingle();

    if (error) throw error;
    return data?.id == null ? null : Number(data.id);
}

export async function createMarkerSubmission({
    supabase,
    gameId,
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
            game_id: gameId,
            marker_id: markerId,
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
    return Number(data.id);
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
