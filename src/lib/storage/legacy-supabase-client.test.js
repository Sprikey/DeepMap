// @ts-expect-error Node-only test: no Node ambient types in this repo.
import test from 'node:test';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import assert from 'node:assert/strict';
import { uploadLegacyAvatar, deleteLegacyAvatar } from './legacy-supabase-client.js';

/** @param {any} result */
function fixture(result = { data: null, error: null }) {
    const calls = /** @type {any[]} */ ([]);
    const response = Promise.resolve(result);
    const client = /** @type {any} */ ({ storage: { from(/** @type {string} */ bucket) {
        return {
            upload(/** @type {string} */ path, /** @type {File} */ file, /** @type {any} */ options) {
                calls.push({ operation: 'upload', bucket, path, file, options }); return response;
            },
            remove(/** @type {string[]} */ paths) {
                calls.push({ operation: 'remove', bucket, paths }); return response;
            }
        };
    } } });
    return { client, calls, response };
}

test('upload preserves bucket, exact key/file, options and SDK response', async () => {
    const sdk = fixture({ data: { path: 'unchanged' }, error: null });
    const file = new File(['bytes'], 'avatar.webp', { type: 'image/webp' });
    const path = 'owner/avatar-uuid.webp';
    const response = uploadLegacyAvatar(sdk.client, path, file);
    assert.equal(response, sdk.response);
    assert.deepEqual(sdk.calls, [{ operation: 'upload', bucket: 'avatars', path, file,
        options: { contentType: 'image/webp', cacheControl: '3600', upsert: false } }]);
    assert.equal(await response, await sdk.response);
});

test('delete sends only the exact captured key as a single-object array', async () => {
    const sdk = fixture();
    const path = 'captured-owner/avatar-uuid.webp';
    assert.equal(deleteLegacyAvatar(sdk.client, path), sdk.response);
    assert.deepEqual(sdk.calls, [{ operation: 'remove', bucket: 'avatars', paths: [path] }]);
});

test('each operation uses its injected client, without global session or configuration', async () => {
    const first = fixture(), second = fixture();
    const file = new File(['bytes'], 'avatar.webp');
    await Promise.all([uploadLegacyAvatar(first.client, 'first/new.webp', file),
        uploadLegacyAvatar(second.client, 'second/new.webp', file)]);
    await deleteLegacyAvatar(first.client, 'first/old.webp');
    assert.deepEqual(first.calls.map(call => call.path ?? call.paths[0]), ['first/new.webp', 'first/old.webp']);
    assert.deepEqual(second.calls.map(call => call.path), ['second/new.webp']);
});

test('adapter preserves returned SDK errors and thrown failures for caller cleanup handling', async () => {
    const error = new Error('storage-error');
    const sdk = fixture({ data: null, error });
    assert.equal((await deleteLegacyAvatar(sdk.client, 'owner/key.webp')).error, error);
    const throwing = /** @type {any} */ ({ storage: { from() { throw error; } } });
    assert.throws(() => uploadLegacyAvatar(throwing, 'owner/key.webp', new File([], 'avatar.webp')), error);
});
