export const NOTIFICATIONS_PAGE_SIZE = 20;

export const NOTIFICATION_TEXT = {
    en: {
        title: 'Notifications', markAll: 'Mark all read', loading: 'Loading…', empty: 'No notifications yet.', approved: 'Approved', rejected: 'Rejected',
        markerApproved: 'Your marker was approved.', suggestionApproved: 'Your suggestion was approved.', markerRejected: 'Your marker was rejected.', suggestionRejected: 'Your suggestion was rejected.',
        moderatorNote: 'Moderator note', moderatorGranted: 'You are now a DeepMap moderator.', moderatorRevoked: 'Your moderator access was removed.',
        moderatorGrantedTitle: 'Moderator access', moderatorRevokedTitle: 'Moderator access changed', accountSuspendedTitle: 'Account suspended', accountSuspended: 'Your DeepMap account was suspended.', accountReinstatedTitle: 'Account restored', accountReinstated: 'Your DeepMap account access was restored.',
        adminSubmissionTitle: 'New community submission', adminMarkerSubmitted: 'A new marker is waiting for moderation.', adminSuggestionSubmitted: 'A new marker suggestion is waiting for moderation.',
        adminModerationTitle: 'Moderation activity', adminMarkerApproved: 'A moderator approved a marker.', adminMarkerRejected: 'A moderator rejected a marker.', adminSuggestionApproved: 'A moderator approved a suggestion.', adminSuggestionRejected: 'A moderator rejected a suggestion.',
        viewAll: 'View all notifications', page: 'Page', previous: 'Previous', next: 'Next', perPage: 'Per page'
    },
    pt: {
        title: 'Notificações', markAll: 'Marcar tudo como lido', loading: 'A carregar…', empty: 'Ainda não tens notificações.', approved: 'Aprovado', rejected: 'Reprovado',
        markerApproved: 'O teu marcador foi aprovado.', suggestionApproved: 'A tua sugestão foi aprovada.', markerRejected: 'O teu marcador foi reprovado.', suggestionRejected: 'A tua sugestão foi reprovada.',
        moderatorNote: 'Nota da moderação', moderatorGranted: 'Agora és moderador do DeepMap.', moderatorRevoked: 'O teu acesso de moderador foi removido.',
        moderatorGrantedTitle: 'Acesso de moderador', moderatorRevokedTitle: 'Acesso de moderador alterado', accountSuspendedTitle: 'Conta suspensa', accountSuspended: 'A tua conta DeepMap foi suspensa.', accountReinstatedTitle: 'Conta reativada', accountReinstated: 'O acesso à tua conta DeepMap foi reativado.',
        adminSubmissionTitle: 'Nova submissão da comunidade', adminMarkerSubmitted: 'Há um novo marcador à espera de moderação.', adminSuggestionSubmitted: 'Há uma nova sugestão de marcador à espera de moderação.',
        adminModerationTitle: 'Atividade de moderação', adminMarkerApproved: 'Um moderador aprovou um marcador.', adminMarkerRejected: 'Um moderador rejeitou um marcador.', adminSuggestionApproved: 'Um moderador aprovou uma sugestão.', adminSuggestionRejected: 'Um moderador rejeitou uma sugestão.',
        viewAll: 'Ver todas as notificações', page: 'Página', previous: 'Anterior', next: 'Seguinte', perPage: 'Por página'
    }
};

export function normaliseNotificationLanguage(language) {
    return String(language ?? '').toLowerCase().startsWith('pt') ? 'pt' : 'en';
}

export function getNotificationText(language) {
    return NOTIFICATION_TEXT[normaliseNotificationLanguage(language)];
}

/** Canonical positive PostgreSQL BIGINT identity, matching map deep links.
 * @param {unknown} value
 */
export function notificationIdKey(value) {
    if (typeof value === 'number' ? !Number.isSafeInteger(value)
        : typeof value !== 'string' || !/^[0-9]+$/.test(value)) throw new Error('NOTIFICATION_BIGINT_ID_REQUIRED');
    const id = BigInt(String(value));
    if (id <= 0n || id > 9223372036854775807n) throw new Error('NOTIFICATION_BIGINT_ID_REQUIRED');
    return id.toString();
}

/** @param {unknown} value */
function notificationCount(value) {
    if (typeof value === 'number' && Number.isSafeInteger(value) && value >= 0) return value;
    if (typeof value === 'string' && /^[0-9]+$/.test(value) && BigInt(value) <= BigInt(Number.MAX_SAFE_INTEGER)) return Number(value);
    throw new Error('NOTIFICATION_COUNT_INVALID');
}

/** @param {any} row */
export function normaliseNotification(row) {
    return {
        id: notificationIdKey(row.id),
        kind: row.kind ?? 'submission_review',
        legacyGameId: row.game_id ?? null,
        routeGameUuid: typeof row.route_game_uuid === 'string' ? row.route_game_uuid : null,
        routeGameSlug: typeof row.route_game_slug === 'string' && row.route_game_slug.length ? row.route_game_slug : null,
        routeMarkerIsPublished: typeof row.route_marker_is_published === 'boolean' ? row.route_marker_is_published : null,
        submissionId: row.submission_id == null ? null : notificationIdKey(row.submission_id),
        markerId: row.marker_id == null ? null : notificationIdKey(row.marker_id),
        submissionType: row.submission_type ?? null,
        decision: row.decision ?? null,
        reviewNote: row.review_note ?? '',
        metadata: row.metadata ?? {},
        isRead: row.is_read === true,
        createdAt: row.created_at
    };
}

/** @typedef {ReturnType<typeof normaliseNotification>} Notification */
/** @typedef {{ supabase: import('@supabase/supabase-js').SupabaseClient, userId: string | null }} NotificationRead */

/** @param {NotificationRead & { limit?: number, offset?: number }} options */
export async function loadNotificationsPage({ supabase, userId, limit = NOTIFICATIONS_PAGE_SIZE, offset = 0 }) {
    if (!userId) return { items: /** @type {Notification[]} */ ([]), total: 0 };
    const { data, error } = await supabase.rpc('get_my_notifications_with_route_context', {
        p_limit: limit,
        p_offset: offset
    });
    if (error) throw error;
    return { items: /** @type {Notification[]} */ ((data ?? []).map(normaliseNotification)), total: data?.length ? notificationCount(data[0].total_count) : 0 };
}

/** Bounded same-RPC recovery; a second concurrent deletion reuses page one's
 * snapshot instead of recursively retrying or inventing another count API.
 * @param {NotificationRead & { limit: number, page: number, isCurrent: () => boolean }} options
 */
export async function loadNotificationsWithRecovery({ supabase, userId, limit, page, isCurrent }) {
    let result = await loadNotificationsPage({ supabase, userId, limit, offset: (page - 1) * limit });
    if (!isCurrent()) return null;
    if (result.items.length || page === 1) return { ...result, page };
    const first = await loadNotificationsPage({ supabase, userId, limit, offset: 0 });
    if (!isCurrent()) return null;
    if (!first.items.length) return { ...first, total: 0, page: 1 };
    const correctedPage = Math.min(page, Math.max(1, Math.ceil(first.total / limit)));
    if (correctedPage === 1) return { ...first, page: 1 };
    result = await loadNotificationsPage({ supabase, userId, limit, offset: (correctedPage - 1) * limit });
    if (!isCurrent()) return null;
    return result.items.length ? { ...result, page: correctedPage } : { ...first, page: 1 };
}

/** @param {NotificationRead} options */
export async function loadUnreadNotificationCount({ supabase, userId }) {
    if (!userId) return 0;

    const { error, count } = await supabase
        .from('user_notifications')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', userId)
        .eq('is_read', false);

    if (error) throw error;
    return notificationCount(count ?? 0);
}

/** @param {NotificationRead & { notificationId: unknown }} options */
export async function markNotificationRead({ supabase, userId, notificationId }) {
    if (!userId || notificationId == null) return;
    const { error } = await supabase
        .from('user_notifications')
        .update({ is_read: true })
        .eq('id', notificationIdKey(notificationId))
        .eq('user_id', userId)
        .eq('is_read', false);
    if (error) throw error;
}

/** @param {NotificationRead} options */
export async function markAllNotificationsRead({ supabase, userId }) {
    if (!userId) return;
    const { error } = await supabase
        .from('user_notifications')
        .update({ is_read: true })
        .eq('user_id', userId)
        .eq('is_read', false);
    if (error) throw error;
}

export function notificationTitle(item, text) {
    if (item.kind === 'moderator_granted') return text.moderatorGrantedTitle;
    if (item.kind === 'moderator_revoked') return text.moderatorRevokedTitle;
    if (item.kind === 'account_suspended') return text.accountSuspendedTitle;
    if (item.kind === 'account_reinstated') return text.accountReinstatedTitle;
    if (item.kind === 'admin_submission_received') return text.adminSubmissionTitle;
    if (item.kind === 'admin_moderation_decision') return text.adminModerationTitle;
    return item.decision === 'approved' ? text.approved : text.rejected;
}

export function notificationBody(item, text) {
    if (item.kind === 'moderator_granted') return text.moderatorGranted;
    if (item.kind === 'moderator_revoked') return text.moderatorRevoked;
    if (item.kind === 'account_suspended') return text.accountSuspended;
    if (item.kind === 'account_reinstated') return text.accountReinstated;
    if (item.kind === 'admin_submission_received') {
        const base = item.submissionType === 'create' ? text.adminMarkerSubmitted : text.adminSuggestionSubmitted;
        return item.metadata?.submitted_username ? `${base} @${item.metadata.submitted_username}` : base;
    }
    if (item.kind === 'admin_moderation_decision') {
        let base;
        if (item.submissionType === 'create') base = item.decision === 'approved' ? text.adminMarkerApproved : text.adminMarkerRejected;
        else base = item.decision === 'approved' ? text.adminSuggestionApproved : text.adminSuggestionRejected;
        return item.metadata?.reviewed_username ? `${base} @${item.metadata.reviewed_username}` : base;
    }
    if (item.decision === 'approved') return item.submissionType === 'create' ? text.markerApproved : text.suggestionApproved;
    return item.submissionType === 'create' ? text.markerRejected : text.suggestionRejected;
}

export function notificationHref(item) {
    if (item.kind === 'moderator_granted') return '/moderation';
    if (item.kind === 'moderator_revoked') return '/profile';
    if (item.kind === 'account_suspended') return '/suspended';
    if (item.kind === 'account_reinstated') return '/profile';
    if (item.kind === 'admin_submission_received' || item.kind === 'admin_moderation_decision') return '/admin?section=moderation';
    if (!item.routeGameSlug) return '/profile';
    try {
        if (item.decision === 'approved' && item.markerId && item.routeMarkerIsPublished === true) {
            return `/games/${encodeURIComponent(item.routeGameSlug)}/map?marker=${notificationIdKey(item.markerId)}`;
        }
        if (item.submissionId) return `/games/${encodeURIComponent(item.routeGameSlug)}/map?contribution=${notificationIdKey(item.submissionId)}`;
    } catch { /* Invalid or already-rounded identities cannot target a public row. */ }
    return '/profile';
}

export function formatNotificationDate(value, language) {
    if (!value) return '';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    return new Intl.DateTimeFormat(normaliseNotificationLanguage(language) === 'pt' ? 'pt-PT' : 'en-GB', {
        dateStyle: 'short', timeStyle: 'short'
    }).format(date);
}
