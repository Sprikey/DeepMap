// @ts-expect-error Node-only test: no Node ambient types in this repo.
import test from 'node:test';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import assert from 'node:assert/strict';
import { analyticsPath, redactAnalyticsEvent } from './redact.js';

test('dynamic identifiers and unknown paths never pass through Analytics', () => {
    const cases = [
        ['/u/rafa', '/u/[username]'], ['/u/a%40example.com/', '/u/[username]'],
        ['/p/550e8400-e29b-41d4-a716-446655440000', '/p/[id]'],
        ['/games/elden-ring/map', '/games/[game]/map'],
        ['/games/550e8400-e29b-41d4-a716-446655440000/map', '/games/[game]/map'],
        ['/future/email@example.com', '/[unmatched]'], ['/u/name/extra', '/[unmatched]'],
        ['/profile/', '/profile'], ['/', '/'], ['/auth/callback', '/auth/callback']
    ];
    for (const [input, output] of cases) assert.equal(analyticsPath(input), output);
});

test('beforeSend preserves event type and strips queries, fragments and credentials', () => {
    for (const type of /** @type {const} */ (['pageview', 'event'])) {
        const result = redactAnalyticsEvent({ type, url: 'https://name:password@deepmap.cc/u/rafa?email=private&code=secret#uuid' });
        assert.deepEqual(result, { type, url: 'https://deepmap.cc/u/[username]' });
    }
    assert.equal(redactAnalyticsEvent({ type: 'pageview', url: 'invalid' }), null);
});
