import { notificationIdKey } from '../notifications/notification-data.js';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

/** @param {unknown} value */
function auditCount(value) {
    if (typeof value === 'number' && Number.isSafeInteger(value) && value >= 0) return value;
    if (typeof value === 'string' && /^[0-9]+$/.test(value) && BigInt(value) <= BigInt(Number.MAX_SAFE_INTEGER)) return Number(value);
    throw new Error('ADMIN_AUDIT_COUNT_INVALID');
}

/** The legacy alias is metadata only, never a source for current game context.
 * @param {any} row
 */
export function normaliseAdminAuditRow(row) {
    if (!row || typeof row.event_id !== 'string' || !row.event_id.length
        || typeof row.action !== 'string') throw new Error('ADMIN_AUDIT_ROW_INVALID');
    const routeGameUuid = typeof row.route_game_uuid === 'string' && UUID.test(row.route_game_uuid) ? row.route_game_uuid : null;
    return {
        eventId: row.event_id,
        action: row.action,
        actorUsername: typeof row.actor_username === 'string' ? row.actor_username : null,
        targetUsername: typeof row.target_username === 'string' ? row.target_username : null,
        legacyGameId: typeof row.game_id === 'string' ? row.game_id : null,
        submissionId: row.submission_id == null ? null : notificationIdKey(row.submission_id),
        markerId: row.marker_id == null ? null : notificationIdKey(row.marker_id),
        detail: typeof row.detail === 'string' ? row.detail : '',
        createdAt: row.created_at,
        totalCount: auditCount(row.total_count),
        routeGameUuid,
        routeGameSlug: routeGameUuid && typeof row.route_game_slug === 'string' && SLUG.test(row.route_game_slug) ? row.route_game_slug : null,
        routeGameName: routeGameUuid && typeof row.route_game_name === 'string' && row.route_game_name.trim() ? row.route_game_name : null
    };
}

/** @typedef {ReturnType<typeof normaliseAdminAuditRow>} AdminAuditRow */
/** @typedef {{supabase: import('@supabase/supabase-js').SupabaseClient, limit: number, page: number, isCurrent: () => boolean}} AuditRead */

/** All-games audit, with bounded recovery using only the UUID RPC.
 * A second concurrent deletion falls back to the already-read first page.
 * @param {AuditRead} options
 */
export async function loadAdminAuditWithRecovery({ supabase, limit, page, isCurrent }) {
    if (![10, 20, 50].includes(limit) || !Number.isSafeInteger(page) || page < 1
        || !Number.isSafeInteger((page - 1) * limit)) throw new Error('ADMIN_AUDIT_PAGE_INVALID');
    /** @param {number} requestedPage */
    async function read(requestedPage) {
        const { data, error } = await supabase.rpc('get_admin_audit_log_by_game_uuid', {
            p_game_uuid: null, p_limit: limit, p_offset: (requestedPage - 1) * limit
        });
        if (error) throw error;
        if (!Array.isArray(data)) throw new Error('ADMIN_AUDIT_ROWS_INVALID');
        const items = /** @type {AdminAuditRow[]} */ (data.map(normaliseAdminAuditRow));
        const total = items[0]?.totalCount ?? 0;
        if (new Set(items.map((row) => row.eventId)).size !== items.length
            || items.some((row) => row.totalCount !== total) || total < items.length) throw new Error('ADMIN_AUDIT_ROWS_INVALID');
        return { items, total, page: requestedPage };
    }
    if (!isCurrent()) return null;
    let result = await read(page);
    if (!isCurrent()) return null;
    if (result.items.length || page === 1) return result;
    const first = await read(1);
    if (!isCurrent()) return null;
    if (!first.items.length) return first;
    const correctedPage = Math.min(page, Math.max(1, Math.ceil(first.total / limit)));
    if (correctedPage === 1) return first;
    result = await read(correctedPage);
    if (!isCurrent()) return null;
    return result.items.length ? result : first;
}
