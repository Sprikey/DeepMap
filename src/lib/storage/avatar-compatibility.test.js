// @ts-expect-error Node-only test: no Node ambient types in this repo.
import test from 'node:test';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import assert from 'node:assert/strict';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import { readFileSync } from 'node:fs';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import { runInNewContext } from 'node:vm';
import { normalizeFileReference } from './references.js';
import { resolveFileUrl } from './resolve.js';
import { uploadLegacyAvatar, deleteLegacyAvatar } from './legacy-supabase-client.js';

/** @param {string} path */
const read = path => readFileSync(new URL(path, import.meta.url), 'utf8').replace(/\r/g, '');
const publicBase = 'https://storage.example.test';
// Follow the repo's VM test convention to inject public config without SvelteKit's env module.
const avatarSource = read('../avatar/avatars.js').replace(/^import .*;$/gm, '').replace(/export /g, '');
const avatars = runInNewContext(avatarSource + '\n({getCustomAvatarUrl,getGoogleAvatarUrl,getAvatarPresentation,AVATAR_PRESETS})', {
    PUBLIC_SUPABASE_URL: publicBase, normalizeFileReference, resolveFileUrl
});
const publicSource = read('../../routes/u/[username]/+page.server.js');
const publicAvatar = runInNewContext(publicSource.slice(publicSource.indexOf('const USERNAME_PATTERN'),
    publicSource.indexOf('/** @type')) + '\navatarFromSafeFields', {
    PUBLIC_SUPABASE_URL: publicBase, AVATAR_PRESETS: avatars.AVATAR_PRESETS, normalizeFileReference, resolveFileUrl
});
const owner = '10000000-0000-0000-0000-000000000001';
const path = owner + '/avatar-20000000-0000-0000-0000-000000000002.webp';

test('account and public/private-profile readers share the exact legacy avatar URL', () => {
    const user = { id: owner, user_metadata: { avatar_choice: 'custom', avatar_custom_path: path } };
    const row = { public_avatar_choice: 'custom', public_avatar_path: path };
    const expected = publicBase + '/storage/v1/object/public/avatars/' + path;
    assert.equal(avatars.getCustomAvatarUrl(user), expected);
    assert.equal(avatars.getAvatarPresentation(user).image, expected);
    assert.equal(publicAvatar(row, owner), expected);
    assert.equal(publicAvatar(row), expected); // RPC-validated private identity path.
    assert.equal(avatars.getCustomAvatarUrl({ ...user, id: 'other' }), null);
    assert.equal(publicAvatar(row, 'other'), null);
    assert.equal(publicAvatar({ ...row, public_avatar_path: '/bad-path' }), null);
});

test('presets, initial and the existing different Google allowlists stay unchanged', () => {
    const google = 'https://lh3.googleusercontent.com/a=s96-c';
    const external = 'https://other.example.test/photo';
    for (const url of [google, external]) {
        assert.equal(avatars.getGoogleAvatarUrl({ user_metadata: { avatar_url: url } }), url);
    }
    assert.equal(publicAvatar({ public_avatar_choice: 'google', public_google_avatar_url: external }), null);
    assert.equal(publicAvatar({ public_avatar_choice: 'google', public_google_avatar_url: google }), google);
    const preset = avatars.AVATAR_PRESETS[0];
    assert.equal(avatars.getAvatarPresentation({ user_metadata: { avatar_choice: preset.id } }).image, preset.image);
    assert.equal(publicAvatar({ public_avatar_choice: preset.id }), preset.image);
    assert.equal(avatars.getAvatarPresentation({ user_metadata: { avatar_choice: 'initial', avatar_url: google } }).image, null);
    assert.equal(avatars.getCustomAvatarUrl(null), null);
    assert.equal(avatars.getGoogleAvatarUrl({ user_metadata: { avatar_url: 'http://example.test/a' } }), null);
});

const profileSource = read('../../routes/profile/+page.svelte');
const saveSource = profileSource.slice(profileSource.indexOf('    async function saveAvatar()'),
    profileSource.indexOf('    async function logout()'));

/** @param {{ staleUpload?: boolean, failMetadata?: boolean, choice?: string }} [options] */
function saveFixture(options = {}) {
    let current = true;
    const events = /** @type {any[]} */ ([]);
    const oldPath = 'owner/avatar-old.webp', newPath = 'owner/avatar-new.webp';
    const sdk = { storage: { from(/** @type {string} */ bucket) {
        assert.equal(bucket, 'avatars');
        return {
            async upload(/** @type {string} */ key) {
                events.push(['upload', key]);
                if (options.staleUpload) current = false;
                return { error: null };
            },
            async remove(/** @type {string[]} */ keys) { events.push(['remove', ...keys]); return { error: null }; }
        };
    } } };
    const context = {
        working: false, privacySaving: false, processingFile: false, canSaveAvatar: true,
        user: { id: 'owner', path: oldPath }, pendingAvatarChoice: options.choice ?? 'custom',
        pendingAvatarFile: new File(['bytes'], 'avatar.webp'), customAvatarUrl: '/old', googleAvatarUrl: '/google',
        AVATAR_PRESETS: [{ id: 'preset' }], avatarChoice: 'initial',
        beginMutation: () => ({ actor: 'owner' }), ownsMutation: () => current,
        avatarOperationGeneration: 0, fileSelectionVersion: 1, avatarMutation: null,
        getCustomAvatarPath: (/** @type {any} */ user) => user.path,
        createAvatarId: () => 'new', getSupabaseBrowserClient: () => sdk,
        uploadLegacyAvatar, deleteLegacyAvatar, t: { avatar_save_error: 'save error', avatar_saved: 'saved' },
        async updateOwnedMetadata(/** @type {any} */ operation, /** @type {any} */ metadata) {
            assert.equal(operation.actor, 'owner'); events.push(['metadata', metadata]);
            return { data: { user: options.failMetadata ? null : { id: 'owner', path: metadata.avatar_custom_path ?? oldPath } },
                error: options.failMetadata ? new Error('save failed') : null };
        },
        avatarDialog: { close() { events.push(['close']); } }, resetAvatarModal() {},
        console: { warn() {}, error() {} }
    };
    return { events, oldPath, newPath, save: runInNewContext(saveSource + '\nsaveAvatar', context) };
}

test('profile replacement still confirms metadata before deleting the captured old avatar', async () => {
    const flow = saveFixture(); await flow.save();
    assert.deepEqual(flow.events.map(event => event[0]), ['upload', 'metadata', 'remove', 'close']);
    assert.equal(flow.events[0][1], flow.newPath);
    assert.equal(flow.events[1][1].avatar_custom_path, flow.newPath);
    assert.equal(flow.events[2][1], flow.oldPath);
});

test('profile metadata failure cleans only the newly uploaded object', async () => {
    const flow = saveFixture({ failMetadata: true }); await flow.save();
    assert.deepEqual(flow.events.map(event => event[0]), ['upload', 'metadata', 'remove']);
    assert.equal(flow.events[2][1], flow.newPath);
});

test('profile stale upload cannot mutate metadata or trigger cleanup after session change', async () => {
    const flow = saveFixture({ staleUpload: true }); await flow.save();
    assert.deepEqual(flow.events, [['upload', flow.newPath]]);
});

test('profile preset and Google selection still avoid upload/delete and retain custom storage', async () => {
    for (const choice of ['preset', 'google']) {
        const flow = saveFixture({ choice }); await flow.save();
        assert.deepEqual(flow.events.map(event => event[0]), ['metadata', 'close']);
        assert.equal(flow.events[0][1].avatar_choice, choice);
        assert.equal('avatar_custom_path' in flow.events[0][1], false);
    }
});
