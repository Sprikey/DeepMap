// @ts-expect-error Node-only test: no Node ambient types in this repo.
import assert from 'node:assert/strict';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import test from 'node:test';
import { safeInternalPath } from './internal-path.js';

const origin = 'https://deepmap.example';

test('ordinary paths, queries and fragments remain internal', () => {
    for (const path of ['/', '/profile', '/games/elden-ring/map',
        '/games/elden-ring/map?marker=123', '/notifications?page=2',
        '/profile?tab=activity#latest', '/search?q=hello%20world', '/search?q=100%25']) {
        assert.equal(safeInternalPath(path, origin), path);
    }
    assert.equal(safeInternalPath('/games/../profile', origin), '/profile');
});

test('external, malformed, control and encoded normalization attacks fall back', () => {
    const invalid = [null, undefined, false, 42, {}, '', ' /profile', 'profile',
        'https://evil.example/', 'http://evil.example/', 'https://deepmap.example/profile',
        '//evil.example', '///evil.example', '\\\\evil.example', '/\\evil.example',
        '/\t/attacker.invalid', '/\n/attacker.invalid', '/\r/attacker.invalid',
        '/profile\u0000', '/profile\u007f', '/profile\u0085',
        '/%09/attacker.invalid', '/%0a/attacker.invalid', '/%0d/attacker.invalid',
        '/%2509/attacker.invalid', '/%25250a/attacker.invalid',
        '/%2f/attacker.invalid', '/%252f/attacker.invalid', '/%5cevil.example',
        '/.%2f/attacker.invalid', '/safe/..//attacker.invalid',
        '/%00', '/%7f', '/%zz', '/%', '/%E0%A4',
        'javascript:alert(1)', 'data:text/html,hello'];
    for (const path of invalid) {
        assert.equal(safeInternalPath(path, origin, '/profile'), '/profile', String(path));
    }
    // The audit's exact raw-control class really does change WHATWG URL origin.
    assert.equal(new URL('/\t/attacker.invalid', origin).origin, 'https://attacker.invalid');
    const encodedAttack = '/%09/attacker.invalid';
    assert.equal(new URL(decodeURIComponent(encodedAttack), origin).origin, 'https://attacker.invalid');
});

test('fallbacks are validated independently and never escape the origin', () => {
    assert.equal(safeInternalPath(null, origin), '/');
    assert.equal(safeInternalPath(null, origin, '/games/../profile?tab=1#bio'), '/profile?tab=1#bio');
    for (const fallback of ['//evil.example', '/\t/evil.example', '/%2fevil.example', 'https://evil.example', null]) {
        assert.equal(safeInternalPath(null, origin, fallback), '/');
    }
    assert.equal(safeInternalPath('/profile', 'not an origin', '//evil.example'), '/');
    assert.equal(safeInternalPath('/profile', 'javascript:alert(1)'), '/');
    assert.equal(safeInternalPath('/profile', origin, '//evil.example'), '/profile');
});

test('nested encoding and URL serialization cannot return an external location', () => {
    let attack = '/%2fevil.example';
    for (let depth = 0; depth < 12; depth += 1) {
        const result = safeInternalPath(attack, origin, '/profile');
        assert.equal(result, '/profile');
        assert.equal(new URL(result, origin).origin, origin);
        attack = attack.replaceAll('%', '%25');
    }
});
