// @ts-expect-error Node-only test: the repo does not include Node ambient types.
import assert from 'node:assert/strict';
// @ts-expect-error Node-only test: the repo does not include Node ambient types.
import test from 'node:test';
// @ts-expect-error Node-only test: the repo does not include Node ambient types.
import { readFileSync } from 'node:fs';
// @ts-expect-error Node-only test: the repo does not include Node ambient types.
import { runInNewContext } from 'node:vm';
import { normaliseAdminAuditRow, loadAdminAuditWithRecovery } from './admin-audit.js';

const uuid = 'd90a98a1-1234-4567-9876-abcdef012345';
/** @param {any} overrides */
function row(overrides = {}) {
    return { event_id: 'submission-7-approved', action: 'submission_approved', actor_username: 'reviewer',
        target_username: 'author', game_id: 'historical-alias', submission_id: '9007199254740993',
        marker_id: '9007199254740995', detail: 'Reviewed', created_at: '2026-10-16T10:00:00Z',
        total_count: '1', route_game_uuid: uuid, route_game_slug: 'current-db-slug', route_game_name: 'Current DB name', ...overrides };
}
/** @param {any[]} responses */
function mock(responses) {
    const calls = /** @type {any[]} */ ([]);
    const client = { async rpc(/** @type {string} */ name, /** @type {any} */ args) {
        calls.push({ name, args });
        if (name !== 'get_admin_audit_log_by_game_uuid') throw new Error('Unexpected RPC');
        const next = responses.shift();
        if (next instanceof Error) return { data: null, error: next };
        return { data: next, error: null };
    }};
    return { supabase: /** @type {import('@supabase/supabase-js').SupabaseClient} */ (/** @type {unknown} */ (client)), calls };
}
const current = () => true;

test('explicit row contract preserves BIGINT strings and DB identity, with separate legacy metadata', () => {
    const item = normaliseAdminAuditRow(row());
    assert.deepEqual(item, { eventId: 'submission-7-approved', action: 'submission_approved', actorUsername: 'reviewer',
        targetUsername: 'author', legacyGameId: 'historical-alias', submissionId: '9007199254740993', markerId: '9007199254740995',
        detail: 'Reviewed', createdAt: '2026-10-16T10:00:00Z', totalCount: 1, routeGameUuid: uuid,
        routeGameSlug: 'current-db-slug', routeGameName: 'Current DB name' });
    assert.equal('gameId' in item, false);
});

for (const action of ['moderator_granted', 'moderator_revoked', 'user_banned', 'user_unbanned']) {
    test(action + ' global context remains null without a legacy fallback', () => {
        const item = normaliseAdminAuditRow(row({ action, submission_id: null, marker_id: null,
            route_game_uuid: null, route_game_slug: null, route_game_name: null }));
        assert.equal(item.routeGameUuid, null); assert.equal(item.routeGameSlug, null); assert.equal(item.routeGameName, null);
        assert.equal(item.submissionId, null); assert.equal(item.markerId, null);
    });
}

test('missing/malformed context fails closed; alias never supplies a slug/name', () => {
    for (const route_game_uuid of [null, undefined, '', 'not-a-uuid']) {
        const item = normaliseAdminAuditRow(row({ route_game_uuid }));
        assert.equal(item.routeGameUuid, null); assert.equal(item.routeGameSlug, null); assert.equal(item.routeGameName, null);
    }
    const item = normaliseAdminAuditRow(row({ route_game_slug: undefined, route_game_name: undefined }));
    assert.equal(item.routeGameSlug, null); assert.equal(item.routeGameName, null);
    assert.equal(normaliseAdminAuditRow(row({ route_game_slug: '../alias' })).routeGameSlug, null);
});

for (const key of ['submission_id', 'marker_id']) {
    test(key + ' rejects malformed, rounded, nonpositive and overflowing identities', () => {
        for (const value of [9007199254740992, 1.5, NaN, Infinity, 0, -1, '', '1e4', '1.5', '-1', ' 7 ', '9223372036854775808', {}, true]) {
            assert.throws(() => normaliseAdminAuditRow(row({ [key]: value })));
        }
        assert.equal(normaliseAdminAuditRow(row({ [key]: '0007' }))[key === 'submission_id' ? 'submissionId' : 'markerId'], '7');
    });
}

for (const limit of [10, 20, 50]) {
    test('all-games UUID RPC at page size ' + limit + ' preserves total/offset', async () => {
        const { supabase, calls } = mock([[row({ total_count: '123' })]]);
        const result = await loadAdminAuditWithRecovery({ supabase, limit, page: 2, isCurrent: current });
        assert.equal(result?.total, 123); assert.equal(result?.page, 2);
        assert.deepEqual(calls, [{ name: 'get_admin_audit_log_by_game_uuid', args: { p_game_uuid: null, p_limit: limit, p_offset: limit } }]);
    });
}

test('empty later page recovers first, clamps and reads corrected page using same RPC', async () => {
    const { supabase, calls } = mock([[], [row({ total_count: 23 })], [row({ total_count: 23 })]]);
    const result = await loadAdminAuditWithRecovery({ supabase, limit: 10, page: 8, isCurrent: current });
    assert.equal(result?.page, 3); assert.equal(result?.total, 23);
    assert.deepEqual(calls.map(c => c.args.p_offset), [70, 0, 20]);
    assert.ok(calls.every(c => c.name === 'get_admin_audit_log_by_game_uuid' && c.args.p_game_uuid === null));
});

test('second concurrent deletion reuses first snapshot without retry loop', async () => {
    const { supabase, calls } = mock([[], [row({ total_count: 23 })], []]);
    const result = await loadAdminAuditWithRecovery({ supabase, limit: 10, page: 8, isCurrent: current });
    assert.equal(result?.page, 1); assert.equal(result?.total, 23); assert.equal(calls.length, 3);
});

test('empty first/recovery page returns zero without retry loops', async () => {
    for (const page of [1, 5]) {
        const { supabase, calls } = mock([[], []]);
        const result = await loadAdminAuditWithRecovery({ supabase, limit: 10, page, isCurrent: current });
        assert.equal(result?.page, 1); assert.equal(result?.total, 0); assert.equal(calls.length, page === 1 ? 1 : 2);
    }
});

test('errors/malformed counts/rows never trigger legacy fallback; unsafe paging rejected', async () => {
    for (const response of [new Error('Denied'), null, [row({ total_count: '9007199254740993' })], [row({ total_count: -1 })]]) {
        const { supabase, calls } = mock([response]);
        await assert.rejects(loadAdminAuditWithRecovery({ supabase, limit: 10, page: 1, isCurrent: current }));
        assert.equal(calls.length, 1); assert.equal(calls[0].name, 'get_admin_audit_log_by_game_uuid');
    }
    const { supabase, calls } = mock([]);
    await assert.rejects(loadAdminAuditWithRecovery({ supabase, limit: 25, page: 1, isCurrent: current }));
    assert.equal(calls.length, 0);
});

test('stale recovery stops before subsequent requests', async () => {
    const { supabase, calls } = mock([[]]); let checks = 0;
    assert.equal(await loadAdminAuditWithRecovery({ supabase, limit: 10, page: 3, isCurrent: () => ++checks === 1 }), null);
    assert.equal(calls.length, 1);
});

const panel = readFileSync(new URL('./AdminAuditPanel.svelte', import.meta.url), 'utf8');
/** Actual panel script with mocked lifecycle/runes/client. No browser or network.
 * @param {any} client
 */
function panelHarness(client) {
    let mount = /** @type {() => () => void} */ (() => () => {});
    const effects = /** @type {Array<() => void>} */ ([]);
    const timers = new Map(); let timerId = 0;
    const context = { getSupabaseBrowserClient: () => client, loadAdminAuditWithRecovery,
        onMount: (/** @type {() => () => void} */ fn) => { mount = fn; }, tick: async () => {}, untrack: (/** @type {any} */ fn) => fn(),
        $props: () => ({}), $state: (/** @type {any} */ value) => value, $derived: (/** @type {any} */ value) => value,
        $effect: (/** @type {() => void} */ fn) => effects.push(fn),
        setTimeout: (/** @type {any} */ fn) => { timers.set(++timerId, fn); return timerId; }, clearTimeout: (/** @type {number} */ id) => timers.delete(id),
        console: { error() {}, warn() {} } };
    const script = panel.split('<script>')[1].split('</script>')[0].replace(/^    import .*;\r?\n/gm, '');
    const api = runInNewContext(script + `\n({ load, refresh, toggleDetails, sessionChanged,
        setPage: (value) => { page=value; }, setActive: (value) => { active=value; },
        snapshot: () => ({items, total, page, pageSize, expandedId, detailCache, loading, errorMessage, refreshFeedback}) })`, context);
    const cleanup = mount(); api.sessionChanged('user-a');
    return { api, cleanup, effects, timers };
}

function deferred() {
    let resolve = /** @type {(value: any) => void} */ (() => {});
    const promise = new Promise(r => { resolve = r; });
    return { promise, resolve };
}
/** @param {any} rpc @returns {any} */
function panelClient(rpc) {
    let authChange = /** @type {any} */ (null);
    return { rpc, auth: { getUser: () => new Promise(() => {}),
        onAuthStateChange: (/** @type {any} */ fn) => { authChange=fn; return { data: { subscription: { unsubscribe() {} } } }; } },
        authChange: (/** @type {string | null} */ user) => authChange('SIGNED_IN', user ? { user: { id: user } } : null) };
}

test('logout/account/session replacement clears rows and discards old response', async () => {
    for (const user of [null, 'user-b', 'user-a']) {
        const pending=deferred(); const client=panelClient(() => pending.promise);
        const {api,cleanup}=panelHarness(client); const request=api.load(); client.authChange(user);
        pending.resolve({data:[row()],error:null}); await request;
        assert.equal(api.snapshot().items.length,0); assert.equal(api.snapshot().total,0); cleanup();
    }
});

test('unmount/section deactivation discard pending responses', async () => {
    for (const unmount of [true,false]) {
        const pending=deferred(); const {api,cleanup,effects}=panelHarness(panelClient(() => pending.promise));
        const request=api.load();
        if(unmount) cleanup(); else { api.setActive(false); effects.forEach(fn => fn()); }
        pending.resolve({data:[row()],error:null}); await request;
        assert.equal(api.snapshot().items.length,0); if(!unmount) cleanup();
    }
});

test('out-of-order list completion cannot replace newer page/loading state', async () => {
    const first=deferred(),second=deferred();let count=0;
    const {api,cleanup}=panelHarness(panelClient(() => (++count===1?first:second).promise));
    const old=api.load();api.setPage(2);const latest=api.load();
    second.resolve({data:[row({event_id:'submission-8-approved',total_count:20})],error:null});await latest;
    first.resolve({data:[row({total_count:20})],error:null});await old;
    assert.equal(api.snapshot().items[0].eventId,'submission-8-approved'); assert.equal(api.snapshot().page,2);
    assert.equal(api.snapshot().loading,false);cleanup();
});

test('failed refresh clears existing rows/detail cache', async () => {
    let count=0;const {api,cleanup}=panelHarness(panelClient(async () => ++count===1?{data:[row()],error:null}:{data:null,error:new Error('denied')}));
    await api.load();assert.equal(api.snapshot().items.length,1);await api.refresh();
    assert.equal(api.snapshot().items.length,0);assert.equal(Object.keys(api.snapshot().detailCache).length,0);
    assert.ok(api.snapshot().errorMessage);cleanup();
});

test('submission/revisions retain exact BIGINT and projection; stale selected-row details ignored', async () => {
    const submission=deferred(),revisions=deferred();const calls=/** @type {any[]} */ ([]);
    const client=panelClient((/** @type {string} */ name,/** @type {any} */ args)=>{
        calls.push({name,args});return name==='get_marker_submission_revisions'?revisions.promise:Promise.resolve({data:[row()],error:null});
    });
    client.from=(/** @type {string} */ table)=>({select(/** @type {string} */ columns){calls.push({table,columns});return this;},eq(/** @type {string} */ key,/** @type {any} */ value){calls.push({key,value});return this;},maybeSingle(){return submission.promise;}});
    const {api,cleanup}=panelHarness(client);await api.load();const item=api.snapshot().items[0];
    const pending=api.toggleDetails(item);
    assert.equal(calls.find(c=>c.name==='get_marker_submission_revisions').args.p_submission_id,'9007199254740993');
    assert.equal(calls.find(c=>c.key==='id').value,'9007199254740993');
    assert.equal(calls.find(c=>c.table).columns,'id, game_id, marker_id, submission_type, correction_kind, status, payload, note, review_note, created_at, reviewed_at, updated_at');
    await api.toggleDetails(item);
    submission.resolve({data:{note:'private detail'},error:null});revisions.resolve({data:[{revision_no:1}],error:null});await pending;
    assert.equal(Object.keys(api.snapshot().detailCache).length,0);
    await api.toggleDetails(item);
    assert.equal(api.snapshot().detailCache[item.eventId].submission.note,'private detail');
    assert.equal(api.snapshot().detailCache[item.eventId].revisions.length,1);cleanup();
});

test('panel keeps UI sizes/current DB display without static authority, legacy calls or invented links', () => {
    assert.doesNotMatch(panel,/get_deepmap_admin_audit|deepMapGames|getDeepMapGameName|game_legacy_identifiers|elden-ring/);
    assert.doesNotMatch(panel,/item\.game_id|item\.gameId|href=/);
    assert.match(panel,/item\.routeGameName \?\? item\.routeGameSlug/);
    assert.match(panel,/let pageSize = \$state\(10\)/);
    for(const size of [10,20,50])assert.ok(panel.includes('<option value={'+size+'}>'));
});
