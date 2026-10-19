// @ts-expect-error Node-only test: no Node ambient types in this repo.
import assert from 'node:assert/strict';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import test from 'node:test';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import { readFileSync, existsSync } from 'node:fs';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import { runInNewContext } from 'node:vm';
import { getGameRendererBySlug, requireRendererLegacyGameId } from './registry.js';
import { GameContextError, resolvePublicGameContext } from './game-context.js';
import { categories, categoryGroups, defaultCategoryVisibility } from './elden-ring/categories.js';
import { locations } from './elden-ring/locations.js';
import { mapDefinitions } from './elden-ring/maps.js';
import { translations } from './elden-ring/translations.js';
import { notificationIdKey } from '../notifications/notification-data.js';

/** @param {string} path */
const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8').replace(/\r/g, '');
const server = read('../../routes/games/[game]/map/+page.server.js');
const route = read('../../routes/games/[game]/map/+page.svelte');
const component = read('../map/GameMapPage.svelte');
const layout = read('../../routes/+layout.svelte');
const moderation = read('../admin/GlobalModerationPanel.svelte');

test('exact renderer preserves Elden Ring public URL and complete config/assets', () => {
    const renderer = getGameRendererBySlug('elden-ring');
    if (!renderer) throw new Error('Expected Elden Ring renderer');
    assert.equal(renderer.mapHref, '/games/elden-ring/map');
    assert.equal(renderer.editorHref, '/games/elden-ring/map?editor=1');
    assert.equal(renderer.legacyGameId, 'elden-ring');
    assert.equal(renderer.defaultLayerKey, 'surface');
    assert.deepEqual(renderer.fallback, { categories, categoryGroups, locations, mapDefinitions, mapLabels: [] });
    assert.deepEqual(renderer.defaultCategoryVisibility, defaultCategoryVisibility);
    assert.equal(renderer.translations, translations);
});

test('unknown/current renamed slug never selects first renderer, alias, or Elden Ring data', () => {
    for (const slug of ['other-game', 'elden-ring-renamed', 'ELDEN-RING', '', 'surface']) {
        assert.equal(getGameRendererBySlug(slug), null);
    }
    assert.match(route, /getGameRendererBySlug\(data\.gameContext\.slug\)/);
    assert.match(route, /\{:else\}[\s\S]*role="status">Map temporarily unavailable\./);
    assert.match(route, /renderer && renderer\.legacyGameId\?\.trim\(\)/);
    assert.doesNotMatch(route, /elden-ring|legacy_identifier|\.find\(|\[0\]/);
});

test('legacy writer adapter is explicit and independent of current DB slug', () => {
    const renamedRenderer = { gameSlug: 'current-db-slug', legacyGameId: 'historical-writer-id' };
    assert.equal(requireRendererLegacyGameId(renamedRenderer), 'historical-writer-id');
    for (const renderer of [null, {}, { legacyGameId: '' }, { legacyGameId: '   ' }]) {
        assert.throws(() => requireRendererLegacyGameId(renderer), /MAP_RENDERER_LEGACY_GAME_ID_REQUIRED/);
    }
    assert.match(component, /const legacyGameId = requireRendererLegacyGameId\(config\)/);
    assert.equal((component.match(/legacyGameId=\{legacyGameId\}/g) ?? []).length, 4);
    assert.doesNotMatch(component, /legacyGameId\s*=\s*gameContext\.slug|GAME_ID|elden-ring|Elden Ring/);
});

test('UUID/map UUID flow only from DB context; layer key is renderer config', () => {
    assert.match(component, /gameUuid: gameContext\.gameUuid/);
    assert.match(component, /gameMapUuid: gameContext\.gameMapUuid/);
    assert.match(component, /identity\.gameMapUuid !== gameContext\.gameMapUuid/);
    assert.match(component, /let activeMapLayer = \$state\(defaultLayerKey\)/);
    assert.match(component, /data\.mapDefinitions\[defaultLayerKey\]/);
    assert.match(component, /game-title">\{gameContext\.name\}/);
    assert.doesNotMatch(component, /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i);
    assert.match(route, /#key JSON\.stringify\(\[data\.gameContext\.gameUuid, data\.gameContext\.gameMapUuid, data\.gameContext\.slug\]\)/);
    assert.match(component, /mapDisposed = true;\s*if \(map\) map\.remove\(\)/);
    assert.equal((component.match(/if \(mapDisposed\) return;/g) ?? []).length, 2);
});

test('thin dynamic route replaces both static route implementations', () => {
    for (const file of ['+page.server.js', '+page.svelte']) {
        assert.equal(existsSync(new URL('../../routes/games/elden-ring/map/' + file, import.meta.url)), false);
    }
    assert.match(server, /load\(\{ locals, params \}\)/);
    assert.match(server, /gameSlug: params\.game/);
    assert.doesNotMatch(server, /url|pathname|registry|legacy|redirect/);
    assert.match(server, /return \{ gameContext \}/);
    assert.match(route, /<GameMapPage gameContext=\{data\.gameContext\} \{renderer\}/);
    assert.doesNotMatch(route, /elden-ring\/(categories|locations|maps)|leaflet/);
});

/** Execute the actual server load with a mocked DB resolver/error boundary.
 * @param {any} resolver
 */
function serverLoad(resolver) {
    const body = server.replace(/import[\s\S]*?from '[^']+';\n/g, '').replace('export async function load', 'async function load');
    return runInNewContext(body + '\nload;', { GameContextError, resolvePublicGameContext: resolver,
        error: (/** @type {number} */ status, /** @type {string} */ message) => { throw Object.assign(new Error(message), { status }); } });
}

test('server passes params directly to resolver, returns serializable DB context only', async () => {
    const db = {}; const calls = /** @type {any[]} */ ([]);
    const context = { slug: 'different-current-slug', gameUuid: 'db-game-uuid', gameMapUuid: 'db-map-uuid', name: 'DB name' };
    const load = serverLoad(async (/** @type {any} */ args) => { calls.push(args); return context; });
    const result = await load({ params: { game: context.slug }, locals: { supabase: db }, url: new URL('https://example.test/games/ignored/map') });
    assert.equal(calls[0].gameSlug, context.slug); assert.equal(calls[0].supabase, db);
    assert.deepEqual(JSON.parse(JSON.stringify(result)), { gameContext: context });
});

for (const code of ['NOT_FOUND', 'CONFIGURATION_UNAVAILABLE', 'UPSTREAM_ERROR']) {
    test('public server retains ' + code + ' status and hides upstream details', async () => {
        const load = serverLoad(async () => { throw new GameContextError(/** @type {any} */ (code)); });
        await assert.rejects(load({ params: { game: 'any-game' }, locals: { supabase: {} } }),
            (/** @type {any} */ cause) => cause.status === (code === 'NOT_FOUND' ? 404 : 503)
                && cause.message === (code === 'NOT_FOUND' ? 'Map not found.' : 'Map temporarily unavailable.'));
    });
}

test('unknown renderer does not prevent published DB context resolving on generic server', async () => {
    const game = { id: '10000000-0000-0000-0000-000000000001', slug: 'another-game', name: 'Another game', status: 'published' };
    const map = { id: '20000000-0000-0000-0000-000000000002', game_id: game.id, slug: 'world', name: 'World', status: 'published', is_default: true };
    const client = { from(/** @type {string} */ table) {
        const data = table === 'games' ? game : table === 'game_maps' ? [map] : { game_id: game.id, module_key: 'map', enabled: true };
        return { select() { return this; }, eq() { return this; }, maybeSingle() { return Promise.resolve({ data, error: null }); }, limit() { return Promise.resolve({ data, error: null }); } };
    } };
    const result = await serverLoad(resolvePublicGameContext)({ params: { game: game.slug }, locals: { supabase: client } });
    assert.equal(result.gameContext.gameUuid, game.id); assert.equal(result.gameContext.gameMapUuid, map.id);
    assert.equal(result.gameContext.mapSlug, 'world'); assert.equal(getGameRendererBySlug(result.gameContext.slug), null);
});

test('global layout recognizes only exact generic map path shapes', () => {
    const expression = layout.match(/let isMapRoute = \$derived\(([^\n]+)\);/)?.[1];
    assert.ok(expression);
    for (const pathname of ['/games/elden-ring/map', '/games/new-game/map', '/games/new-game/map/']) {
        assert.equal(runInNewContext(expression, { page: { url: { pathname } } }), true);
    }
    for (const pathname of ['/games/new-game', '/games/new-game/items', '/games/new-game/maps', '/games/new-game/map/editor', '/games/Bad/map', '/games/a--b/map', '/games//map', '/profile']) {
        assert.equal(runInNewContext(expression, { page: { url: { pathname } } }), false);
    }
    assert.match(layout, /<SiteHeader \/>/); assert.match(layout, /#if !isMapRoute/);
});

test('marker/contribution/review/layer/category query semantics survive extraction', () => {
    const start = component.indexOf('    function getMapDeepLinkParams()');
    const end = component.indexOf('    function openMarkerDeepLink(', start);
    const parse = runInNewContext(component.slice(start, end) + '\ngetMapDeepLinkParams;', {
        window: { location: { search: '?marker=9007199254740993&contribution=9007199254740995&reviewX=120&reviewY=240&layer=underground&category=dungeon&editor=1' } },
        URLSearchParams, markerIdKey: notificationIdKey
    });
    assert.deepEqual(JSON.parse(JSON.stringify(parse())), { markerId: '9007199254740993', contributionId: '9007199254740995', reviewX: 120, reviewY: 240, reviewLayer: 'underground', reviewCategory: 'dungeon' });
    assert.match(component, /params\.get\('editor'\) === '1'\) editorMode = true/);
    assert.match(component, /PREVIEW_MARKER_COLOR = '#2f8fff'/);
});

/** B7f2 map-link regression against the actual current function.
 * @param {any} overrides
 */
function moderationHref(overrides = {}) {
    const item = { gameUuid: 'game-uuid', id: '9007199254740993', markerId: '9007199254740995', type: 'correction', payload: {} };
    const layer = { id: 'surface', gameMapUuid: 'map-uuid', isActive: true };
    const context = { selected: item, reviewContext: { gameUuid: item.gameUuid, submissionId: item.id, gameSlug: 'elden-ring', target: { isPublished: true }, submitted: { layer, category: { id: 'dungeon' } }, current: { layer } },
        gameCatalog: [{ gameUuid: item.gameUuid, publicGameMapUuid: 'map-uuid' }], mapDefinitions: { surface: layer }, categories: { dungeon: { id: 'dungeon' } },
        reviewLayerKey: 'surface', reviewCategoryKey: 'dungeon', reviewCoordinateX: null, reviewCoordinateY: null,
        getGameRendererBySlug, hasCoordinateValue: (/** @type {any} */ value) => value != null && value !== '', URLSearchParams, ...overrides };
    const start = moderation.indexOf('    function mapHref('), end = moderation.indexOf('    async function load(', start);
    return runInNewContext(moderation.slice(start, end) + '\nmapHref();', context);
}

test('B7f2 narrow regression: public target link still uses current slug and canonical marker ID', () => {
    assert.equal(moderationHref(), '/games/elden-ring/map?marker=9007199254740995');
    assert.doesNotMatch(moderation, /deepMapGames/);
});

test('B7f2 narrow regression: invalid renderer, parent identity or missing public map fail closed', () => {
    assert.equal(moderationHref({ gameCatalog: [] }), null);
    for (const [gameUuid, submissionId, gameSlug] of [['wrong', '9007199254740993', 'elden-ring'], ['game-uuid', 'wrong', 'elden-ring'], ['game-uuid', '9007199254740993', 'other-game']]) {
        assert.equal(moderationHref({ reviewContext: { gameUuid, submissionId, gameSlug } }), null);
    }
});

test('B7f2 narrow regression: submitted coordinates/layer/category retain preview query semantics', () => {
    const href = moderationHref({ selected: { gameUuid: 'game-uuid', id: '9007199254740993', markerId: '9007199254740995', type: 'create', payload: { coordinate_x: 123, coordinate_y: 456, map_layer: 'surface', category_id: 'dungeon' } } });
    const url = new URL(href, 'https://example.test');
    assert.equal(url.pathname, '/games/elden-ring/map');
    assert.deepEqual(Object.fromEntries(url.searchParams), { reviewX: '123', reviewY: '456', layer: 'surface', category: 'dungeon', marker: '9007199254740995', submission: '9007199254740993' });
    assert.doesNotMatch(href, /game-uuid|map-uuid/);
});
