// @ts-expect-error Node-only test: no Node ambient types in this repo.
import test from 'node:test';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import assert from 'node:assert/strict';
import { normalizeFileReference } from './references.js';
import { resolveFileUrl } from './resolve.js';
import { resolveMarkerImageUrl } from '../editor/marker-image-editor.js';
import { loadEditorCategories } from '../editor/category-editor.js';

test('static, external and Google references preserve exact strings without configuration', () => {
    for (const [source, value] of [
        ['static', '/games/example/a%20b.webp'],
        ['external', 'http://example.test/a%2Fb.png?q=1#image'],
        ['google', 'https://lh3.googleusercontent.com/a=s96-c']
    ]) {
        const reference = normalizeFileReference(source, value);
        assert.deepEqual(reference, { kind: source, value });
        assert.equal(resolveFileUrl(reference), value);
    }
});

test('normalization is not a new allowlist or URL canonicalizer for legacy consumers', () => {
    for (const source of ['external', 'none', 'old-source', undefined, null]) {
        assert.equal(resolveFileUrl(normalizeFileReference(source, ' legacy text ')), ' legacy text ');
    }
});

test('missing and non-text references are unavailable, and unknown normalized kinds fail closed', () => {
    for (const value of [null, undefined, '', 12, {}, []]) {
        assert.equal(normalizeFileReference('static', value), null);
        assert.equal(resolveFileUrl(normalizeFileReference('static', value)), null);
    }
    assert.equal(resolveFileUrl(null), null);
    assert.equal(resolveFileUrl(undefined), null);
    assert.equal(resolveFileUrl(/** @type {any} */ ({ kind: 'unrecognized', value: '/a' })), null);
});

test('legacy avatar URL uses only the injected public base and existing segment encoding', () => {
    const path = 'owner/avatar-123.webp';
    const reference = normalizeFileReference('legacy-supabase-avatar', path);
    assert.equal(resolveFileUrl(reference), null);
    assert.equal(resolveFileUrl(reference, { supabaseUrl: 'https://storage.example.test' }),
        'https://storage.example.test/storage/v1/object/public/avatars/' + path);
    assert.equal(resolveFileUrl(reference, { supabaseUrl: 'https://other.example.test/' }),
        'https://other.example.test//storage/v1/object/public/avatars/' + path);
    assert.equal(resolveFileUrl(normalizeFileReference('legacy-supabase-avatar', 'a b/image%20.webp'),
        { supabaseUrl: 'https://storage.example.test' }),
        'https://storage.example.test/storage/v1/object/public/avatars/a%20b/image%2520.webp');
});

test('R2 remains unsupported, including when a reference happens to contain a complete URL', () => {
    for (const value of ['future/key.webp', 'https://assets.example.test/key.webp']) {
        assert.equal(resolveFileUrl(normalizeFileReference('r2', value)), null);
        assert.equal(resolveMarkerImageUrl({ source: 'r2', imageRef: value }), null);
    }
});

test('marker editor preserves text references and missing-source compatibility', () => {
    for (const source of ['static', 'external', 'none', undefined]) {
        assert.equal(resolveMarkerImageUrl({ source, imageRef: '/same%20path.webp' }), '/same%20path.webp');
    }
    assert.equal(resolveMarkerImageUrl(null), null);
    assert.equal(resolveMarkerImageUrl({ source: 'external', imageRef: '' }), null);
});

test('category editor retains raw icon_ref even for none, R2 and empty values', async () => {
    const gameUuid = '10000000-0000-0000-0000-000000000001';
    const rows = ['static', 'external', 'r2', 'none'].map((source, index) => ({
        id: 'category-' + index, game_id: 'legacy-game', game_uuid: gameUuid, group_id: null,
        category_uuid: `20000000-0000-0000-0000-00000000000${index}`,
        group_uuid: null, icon_source: source, icon_ref: index === 3 ? '' : '/raw-' + source
    }));
    rows.push({ ...rows[0], id: 'null-icon', category_uuid: '20000000-0000-0000-0000-000000000004',
        icon_ref: /** @type {any} */ (null) });
    const supabase = /** @type {any} */ ({ from(/** @type {string} */ table) {
        assert.equal(table, 'marker_categories');
        return { select() { return this; }, eq() { return this; }, order() { return this; },
            then(/** @type {any} */ resolve) { return Promise.resolve({ data: rows, error: null }).then(resolve); } };
    } });
    const result = await loadEditorCategories({ supabase, gameUuid });
    assert.deepEqual(result.map(row => row.icon), rows.map(row => row.icon_ref));
});
