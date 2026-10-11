// @ts-expect-error Node-only test: the repo does not include Node ambient types.
import assert from 'node:assert/strict';
// @ts-expect-error Node-only test: the repo does not include Node ambient types.
import { randomUUID } from 'node:crypto';
// @ts-expect-error Node-only test: the repo does not include Node ambient types.
import test from 'node:test';
import {
    GameContextError,
    gameSlugFromMapPathname,
    resolvePublicGameContext
} from './game-context.js';

function fixture() {
    const game = { id: randomUUID(), slug: 'elden-ring-remastered', name: 'Game', status: 'published' };
    const module = { game_id: game.id, module_key: 'map', enabled: true };
    const map = {
        id: randomUUID(), game_id: game.id, slug: 'realm', name: 'Realm',
        status: 'published', is_default: true
    };
    return { game, module, map };
}

/** @param {Record<string, { data: unknown, error: unknown }>} responses */
function mockSupabase(responses) {
    /** @type {Array<{ table: string, columns: string, filters: Array<[string, unknown]>, limit?: number }>} */
    const calls = [];
    const client = {
        /** @param {string} table */
        from(table) {
            assert.ok(Object.hasOwn(responses, table), `Unexpected relation: ${table}`);
            const call = { table, columns: '', filters: /** @type {Array<[string, unknown]>} */ ([]), limit: 0 };
            calls.push(call);
            return {
                /** @param {string} columns */
                select(columns) { call.columns = columns; return this; },
                /** @param {string} column @param {unknown} value */
                eq(column, value) { call.filters.push([column, value]); return this; },
                maybeSingle() { return Promise.resolve(responses[table]); },
                /** @param {number} count */
                limit(count) { call.limit = count; return Promise.resolve(responses[table]); }
            };
        }
    };
    return {
        supabase: /** @type {import('@supabase/supabase-js').SupabaseClient} */ (/** @type {unknown} */ (client)),
        calls
    };
}

/** @param {ReturnType<typeof fixture>} f */
function responsesFor(f) {
    return {
        games: { data: f.game, error: null },
        game_modules: { data: f.module, error: null },
        game_maps: { data: [f.map], error: null }
    };
}

/** @param {unknown} cause @param {string} code */
function hasCode(cause, code) {
    if (!(cause instanceof GameContextError)) throw new Error('Expected GameContextError');
    assert.equal(cause.code, code);
    assert.equal(cause.message, code);
    return true;
}

test('published game resolves DB UUIDs and a published default map, independently of a legacy alias', async () => {
    const f = fixture();
    const { supabase, calls } = mockSupabase(responsesFor(f));
    const context = await resolvePublicGameContext({ supabase, gameSlug: f.game.slug });
    assert.deepEqual(context, {
        slug: f.game.slug, gameUuid: f.game.id, name: f.game.name, status: 'published',
        gameMapUuid: f.map.id, mapSlug: f.map.slug, mapName: f.map.name
    });
    assert.deepEqual(JSON.parse(JSON.stringify(context)), context);
    assert.deepEqual(calls.map((call) => call.table), ['games', 'game_modules', 'game_maps']);
    assert.deepEqual(calls[0].filters, [['slug', 'elden-ring-remastered'], ['status', 'published']]);
    assert.deepEqual(calls[1].filters, [['game_id', f.game.id], ['module_key', 'map'], ['enabled', true]]);
    assert.deepEqual(calls[2].filters, [['game_id', f.game.id], ['status', 'published'], ['is_default', true]]);
    assert.equal('legacyGameId' in context, false);
});

test('UUIDs follow each DB response instead of a game or map constant', async () => {
    const first = fixture();
    const second = fixture();
    const resolve = (/** @type {ReturnType<typeof fixture>} */ f) => resolvePublicGameContext({
        supabase: mockSupabase(responsesFor(f)).supabase, gameSlug: f.game.slug
    });
    const a = await resolve(first);
    const b = await resolve(second);
    assert.equal(b.gameUuid, second.game.id);
    assert.equal(b.gameMapUuid, second.map.id);
    assert.notEqual(a.gameUuid, b.gameUuid);
    assert.notEqual(a.gameMapUuid, b.gameMapUuid);
});

for (const status of ['draft', 'coming_soon']) {
    test(`${status} remains not found even if an Admin-visible response supplies it`, async () => {
        const f = fixture();
        f.game.status = status;
        const { supabase, calls } = mockSupabase(responsesFor(f));
        await assert.rejects(resolvePublicGameContext({ supabase, gameSlug: f.game.slug }), (/** @type {unknown} */ cause) => hasCode(cause, 'NOT_FOUND'));
        assert.equal(calls.length, 1);
    });
}

for (const relation of ['games', 'game_modules']) {
    test(`${relation} missing is not found`, async () => {
        const f = fixture();
        const responses = /** @type {Record<string, { data: unknown, error: unknown }>} */ (responsesFor(f));
        responses[relation] = { data: null, error: null };
        await assert.rejects(resolvePublicGameContext({
            supabase: mockSupabase(responses).supabase, gameSlug: f.game.slug
        }), (/** @type {unknown} */ cause) => hasCode(cause, 'NOT_FOUND'));
    });
}

test('disabled map module is not found even with a returned row', async () => {
    const f = fixture();
    f.module.enabled = false;
    const { supabase, calls } = mockSupabase(responsesFor(f));
    await assert.rejects(resolvePublicGameContext({ supabase, gameSlug: f.game.slug }), (/** @type {unknown} */ cause) => hasCode(cause, 'NOT_FOUND'));
    assert.equal(calls.length, 2);
});

for (const relation of ['games', 'game_modules', 'game_maps']) {
    test(`${relation} query error is upstream failure, never not found`, async () => {
        const f = fixture();
        const responses = /** @type {Record<string, { data: unknown, error: unknown }>} */ (responsesFor(f));
        responses[relation] = { data: null, error: { message: 'Sensitive upstream details' } };
        await assert.rejects(resolvePublicGameContext({
            supabase: mockSupabase(responses).supabase, gameSlug: f.game.slug
        }), (/** @type {unknown} */ cause) => hasCode(cause, 'UPSTREAM_ERROR'));
    });
}

test('thrown network failure is classified without exposing its message', async () => {
    const supabase = /** @type {import('@supabase/supabase-js').SupabaseClient} */ (/** @type {unknown} */ ({
        from() { throw new Error('Sensitive network details'); }
    }));
    await assert.rejects(resolvePublicGameContext({ supabase, gameSlug: fixture().game.slug }), (/** @type {unknown} */ cause) => hasCode(cause, 'UPSTREAM_ERROR'));
});

for (const kind of ['missing', 'multiple', 'wrong-game', 'draft', 'not-default', 'invalid-uuid', 'malformed']) {
    test(`default map ${kind} is a configuration failure`, async () => {
        const f = fixture();
        const responses = /** @type {Record<string, { data: unknown, error: unknown }>} */ (responsesFor(f));
        if (kind === 'missing') responses.game_maps.data = [];
        if (kind === 'multiple') responses.game_maps.data = [f.map, { ...f.map, id: randomUUID() }];
        if (kind === 'wrong-game') f.map.game_id = randomUUID();
        if (kind === 'draft') f.map.status = 'draft';
        if (kind === 'not-default') f.map.is_default = false;
        if (kind === 'invalid-uuid') f.map.id = 'not-a-uuid';
        if (kind === 'malformed') responses.game_maps.data = null;
        await assert.rejects(resolvePublicGameContext({
            supabase: mockSupabase(responses).supabase, gameSlug: f.game.slug
        }), (/** @type {unknown} */ cause) => hasCode(cause, 'CONFIGURATION_UNAVAILABLE'));
    });
}

test('malformed game response is unavailable rather than not found', async () => {
    const f = fixture();
    f.game.id = 'invalid';
    await assert.rejects(resolvePublicGameContext({
        supabase: mockSupabase(responsesFor(f)).supabase, gameSlug: f.game.slug
    }), (/** @type {unknown} */ cause) => hasCode(cause, 'CONFIGURATION_UNAVAILABLE'));
});

test('module response from another game is a configuration failure', async () => {
    const f = fixture();
    f.module.game_id = randomUUID();
    await assert.rejects(resolvePublicGameContext({
        supabase: mockSupabase(responsesFor(f)).supabase, gameSlug: f.game.slug
    }), (/** @type {unknown} */ cause) => hasCode(cause, 'CONFIGURATION_UNAVAILABLE'));
});

test('map pathname extracts a routing slug without knowing a legacy alias', () => {
    assert.equal(gameSlugFromMapPathname('/games/elden-ring-remastered/map'), 'elden-ring-remastered');
    assert.equal(gameSlugFromMapPathname('/games/elden-ring/map/'), 'elden-ring');
    for (const pathname of ['/games/game', '/games/game/map/extra', '/games//map', '/other/game/map', '/games/Game/map']) {
        assert.throws(() => gameSlugFromMapPathname(pathname), (/** @type {unknown} */ cause) => hasCode(cause, 'NOT_FOUND'));
    }
});
