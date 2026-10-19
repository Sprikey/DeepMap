// @ts-expect-error Node-only test: no Node ambient types in this repo.
import test from 'node:test';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import assert from 'node:assert/strict';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import { readFileSync } from 'node:fs';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import { runInNewContext } from 'node:vm';
import { normaliseHttpUrl, getVideoEmbedUrl } from './media.js';

const source = readFileSync(new URL('./GameMapPage.svelte', import.meta.url), 'utf8');
const build = source.slice(source.indexOf('    function getLocationMedia('), source.indexOf('    function buildLocationPopup('));
const setup = source.slice(source.indexOf('    function setupPopupMedia('), source.indexOf('    function setupPopupActions('));

test('YouTube/Vimeo URLs discard tracking and autoplay parameters', () => {
    for (const url of ['https://youtu.be/abc?autoplay=1', 'https://www.youtube.com/watch?v=abc&autoplay=1', 'https://youtube.com/shorts/abc']) {
        assert.equal(getVideoEmbedUrl(url), 'https://www.youtube-nocookie.com/embed/abc');
    }
    assert.equal(getVideoEmbedUrl('https://vimeo.com/123?autoplay=1'), 'https://player.vimeo.com/video/123?dnt=1');
    for (const url of ['javascript:alert(1)', 'https://youtube.com.evil.example/watch?v=abc']) assert.equal(getVideoEmbedUrl(url), null);
});

test('popup HTML has no iframe or external thumbnail; gallery arrows survive', () => {
    const { buildLocationMediaHtml } = runInNewContext(build + '\n({buildLocationMediaHtml})', {
        currentLanguage: 'en', normaliseHttpUrl, getVideoEmbedUrl, URL,
        getLocationTitle: () => 'Fixture', escapeHtml: (/** @type {unknown} */ s) => String(s).replaceAll('"', '&quot;')
    });
    for (const videoUrl of ['https://youtu.be/abc', 'https://vimeo.com/123']) {
        const html = buildLocationMediaHtml({ videoUrl });
        assert.doesNotMatch(html, /<iframe|<img|autoplay/);
        assert.match(html, /data-load-video=/);
        assert.match(html, /Watch video/);
        const gallery = buildLocationMediaHtml({ videoUrl, image: '/fixture.webp' });
        assert.match(gallery, /data-media-prev/); assert.match(gallery, /data-media-next/);
        assert.doesNotMatch(gallery, /<iframe/);
    }
});

test('YouTube and Vimeo create a compatible iframe only on click, including after reopening', () => {
    for (const embed of ['https://www.youtube-nocookie.com/embed/abc', 'https://player.vimeo.com/video/123?dnt=1']) {
    for (let reopen = 0; reopen < 2; reopen++) {
        const nodes = /** @type {any[]} */ ([]);
        let handler = /** @type {any} */ (null), replacement = /** @type {any} */ (null);
        const button = { addEventListener: (/** @type {string} */ type, /** @type {any} */ callback) => { assert.equal(type, 'click'); handler = callback; },
            getAttribute: (/** @type {string} */ key) => key === 'data-load-video' ? embed : 'Video',
            replaceWith: (/** @type {any} */ node) => replacement = node };
        const root = { dataset: {}, querySelectorAll: (/** @type {string} */ selector) => selector === '[data-load-video]' ? [button] : [{}] };
        const { setupPopupMedia } = runInNewContext(setup + '\n({setupPopupMedia})', {
            document: { createElement: (/** @type {string} */ name) => { assert.equal(name, 'iframe'); const node = {}; nodes.push(node); return node; } },
            popupEvents: new AbortController(), ensurePopupInsideMap() {}
        });
        setupPopupMedia({ getPopup: () => ({ getElement: () => ({ querySelector: () => root }) }) });
        assert.equal(nodes.length, 0);
        handler({ preventDefault() {}, stopPropagation() {} });
        assert.equal(nodes.length, 1);
        assert.equal(replacement.src, embed);
        assert.equal(replacement.referrerPolicy, 'strict-origin-when-cross-origin');
        assert.doesNotMatch(replacement.allow, /autoplay/);
    }
    }
});
