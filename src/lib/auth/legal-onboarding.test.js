// @ts-expect-error Node-only test: no Node ambient types in this repo.
import test from 'node:test';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import assert from 'node:assert/strict';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import { readFileSync } from 'node:fs';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import { runInNewContext } from 'node:vm';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import { createHash } from 'node:crypto';
import { TERMS_VERSION, PRIVACY_VERSION } from './legal.js';
import { safeAccountPath } from './account-path.js';
import { authenticatedAccountPath } from '../server/legal-onboarding.js';

/** @param {string} path */
const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const hooks = read('../../hooks.server.js').replace(/^import[\s\S]*?;/gm, '').replace('export const handle', 'const handle');
const server = read('../../routes/onboarding/+page.server.js').replace(/import[^;]*;/g, '').replaceAll('export const', 'const');

// Lexical regression check only, not a replacement for a PostgreSQL parser.
// Inspect bodies recursively so nested tagged quotes in DO blocks are checked.
/** @param {string} sql */
function validateDollarQuotes(sql) {
    for (let i = 0; i < sql.length;) {
        if (sql.startsWith('--', i)) {
            const end = sql.indexOf('\n', i);
            i = end < 0 ? sql.length : end + 1;
        } else if (sql[i] === "'") {
            let closed = false;
            for (i++; i < sql.length; i++) {
                if (sql[i] !== "'") continue;
                if (sql[i + 1] === "'") { i++; continue; }
                i++; closed = true; break;
            }
            assert.ok(closed, 'Unclosed single-quoted string');
        } else if (sql[i] === '$') {
            const delimiter = sql.slice(i).match(/^\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/)?.[0];
            if (!delimiter) throw Error('Malformed dollar-quote delimiter');
            const end = sql.indexOf(delimiter, i + delimiter.length);
            assert.ok(end >= 0, `Unclosed dollar-quote: ${delimiter}`);
            validateDollarQuotes(sql.slice(i + delimiter.length, end));
            i = end + delimiter.length;
        } else i++;
    }
}

test('migration B dollar quotes are valid and balanced, including nested cohort guard', () => {
    const sql = read('../../../supabase/migrations/20261019123000_legal_acceptance_enforcement.sql');
    validateDollarQuotes(sql);
    assert.equal((sql.match(/^DO \$\$$/gm) ?? []).length, 4);
    assert.throws(() => validateDollarQuotes(sql.replace('DO $$', 'DO $')), /Malformed dollar-quote/);
    assert.throws(() => validateDollarQuotes(sql.replace('$cohort_guard$,', '$cohort_guard,')), /Unclosed dollar-quote/);
});
/** @param {number} status @param {string} location */
function redirect(status, location) { throw { status, location }; }

test('new email and OAuth users are gated; existing and accepted users retain access', async () => {
    for (const required of [true, false]) {
        const supabase = { auth: { getUser: async () => ({ data: { user: { id: 'fixture' } } }) },
            rpc: async () => ({ data: required, error: null }) };
        const { handle } = runInNewContext(hooks + '\n({handle})', {
            safeAccountPath, createServerClient: () => supabase, PUBLIC_SUPABASE_URL: '', PUBLIC_SUPABASE_PUBLISHABLE_KEY: '', redirect,
            error: (/** @type {number} */ status) => { throw { status }; }
        });
        const event = { locals: {}, route: { id: '/profile' }, url: new URL('https://deepmap.cc/profile'), cookies: {} };
        if (required) await assert.rejects(handle({ event, resolve: () => 'ok' }), { status: 303, location: '/onboarding?next=%2Fprofile' });
        else assert.equal(await handle({ event, resolve: () => 'ok' }), 'ok');
    }
});

test('legal, recovery and auth callbacks remain reachable; schema errors fail closed', async () => {
    let calls = 0;
    const supabase = { auth: { getUser: async () => ({ data: { user: { id: 'fixture' } } }) },
        rpc: async () => { calls++; return { data: null, error: {} }; } };
    const { handle } = runInNewContext(hooks + '\n({handle})', {
        safeAccountPath, createServerClient: () => supabase, PUBLIC_SUPABASE_URL: '', PUBLIC_SUPABASE_PUBLISHABLE_KEY: '', redirect,
        error: (/** @type {number} */ status) => { throw { status }; }
    });
    for (const path of ['/onboarding', '/terms', '/privacy', '/auth/callback', '/auth/confirm', '/reset-password', '/login', '/suspended']) {
        assert.equal(await handle({ event: { locals: {}, route: { id: path }, url: new URL('https://deepmap.cc' + path), cookies: {} }, resolve: () => 'ok' }), 'ok');
    }
    assert.equal(calls, 0);
    await assert.rejects(handle({ event: { locals: {}, route: { id: '/profile' }, url: new URL('https://deepmap.cc/profile'), cookies: {} }, resolve: () => 'ok' }), { status: 503 });
});

test('acceptance requires explicit checkbox, displayed versions and authenticated UUID', async () => {
    const calls = /** @type {unknown[]} */ ([]);
    const { actions } = runInNewContext(server + '\n({actions})', {
        TERMS_VERSION, PRIVACY_VERSION, safeAccountPath, authenticatedAccountPath, redirect,
        fail: (/** @type {number} */ status, /** @type {unknown} */ data) => ({ status, data })
    });
    const locals = { supabase: { auth: { getUser: async () => ({ data: { user: { id: 'fixture' } } }) },
        rpc: async (/** @type {string} */ name, /** @type {unknown} */ args) => {
            if (name === 'requires_legal_acceptance') return { data: true, error: null };
            calls.push({ name, args }); return { error: null };
        } } };
    const form = new FormData();
    const event = { locals, url: new URL('https://deepmap.cc/onboarding?next=//evil.example'), request: { formData: async () => form } };
    assert.equal((await actions.default(event)).status, 400);
    form.set('accepted', 'yes'); form.set('terms_version', 'stale'); form.set('privacy_version', PRIVACY_VERSION);
    assert.equal((await actions.default(event)).status, 409);
    assert.equal(calls.length, 0);
    form.set('terms_version', TERMS_VERSION);
    await assert.rejects(actions.default(event), { status: 303, location: '/profile' });
    assert.equal(calls.length, 1);
    assert.deepEqual(JSON.parse(JSON.stringify(calls[0])), {
        name: 'accept_legal_documents', args: { p_terms_version: TERMS_VERSION, p_privacy_version: PRIVACY_VERSION }
    });
    locals.supabase.auth.getUser = async () => ({ data: { user: /** @type {any} */ (null) } });
    await assert.rejects(actions.default(event), { status: 303, location: '/login' });
    assert.equal(calls.length, 1);
});

test('rollout A contains preparation only; B owns all new DB enforcement', () => {
    const preparation = read('../../../supabase/migrations/20261019120000_legal_acceptance_onboarding.sql');
    const enforcement = read('../../../supabase/migrations/20261019123000_legal_acceptance_enforcement.sql');
    // Security boundary regression test: A must remain safe with the old app.
    assert.doesNotMatch(preparation, /can_deepmap_interact|CREATE POLICY|AS RESTRICTIVE/i);
    for (const object of ['CREATE TABLE private.legal_onboarding', 'CREATE TRIGGER deepmap_require_legal_onboarding',
        'CREATE FUNCTION private.require_legal_onboarding()', 'CREATE FUNCTION public.requires_legal_acceptance()',
        'CREATE FUNCTION public.accept_legal_documents(']) {
        assert.ok(preparation.includes(object), object);
        assert.ok(!enforcement.includes(object), object);
    }
    assert.match(enforcement, /LEGAL_ACCEPTANCE_PREPARATION_REQUIRED/);
    assert.match(enforcement, /LEGAL_ACCEPTANCE_DEPENDENCY_DRIFT/);
    assert.match(enforcement, /CREATE OR REPLACE FUNCTION public\.can_deepmap_interact\(\)/);
    assert.match(enforcement, /CREATE POLICY profiles_legal_insert[\s\S]*?AS RESTRICTIVE/);
    assert.match(enforcement, /CREATE POLICY profiles_legal_update[\s\S]*?AS RESTRICTIVE/);
});

test('A-only onboarding: legacy account loads; new account accepts and then loads without B', async () => {
    // Stateful RPC fixture for the A contract; this is not a PostgreSQL test.
    let pending = false;
    const supabase = {
        auth: { getUser: async () => ({ data: { user: { id: 'fixture' } } }) },
        rpc: async (/** @type {string} */ name) => {
            if (name === 'requires_legal_acceptance') return { data: pending, error: null };
            assert.equal(name, 'accept_legal_documents');
            pending = false;
            return { error: null };
        }
    };
    const { handle } = runInNewContext(hooks + '\n({handle})', {
        safeAccountPath, createServerClient: () => supabase, PUBLIC_SUPABASE_URL: '', PUBLIC_SUPABASE_PUBLISHABLE_KEY: '', redirect,
        error: (/** @type {number} */ status) => { throw { status }; }
    });
    const locals = { supabase };
    const event = { locals, route: { id: '/profile' }, url: new URL('https://deepmap.cc/profile'), cookies: {} };
    assert.equal(await handle({ event, resolve: () => 'ok' }), 'ok');
    pending = true;
    await assert.rejects(handle({ event, resolve: () => 'ok' }), { status: 303, location: '/onboarding?next=%2Fprofile' });
    const { load, actions } = runInNewContext(server + '\n({load,actions})', {
        TERMS_VERSION, PRIVACY_VERSION, safeAccountPath, authenticatedAccountPath, redirect,
        fail: (/** @type {number} */ status, /** @type {unknown} */ data) => ({ status, data })
    });
    assert.deepEqual(JSON.parse(JSON.stringify(await load({ locals, url: new URL('https://deepmap.cc/onboarding') }))), {});
    const form = new FormData();
    form.set('accepted', 'yes'); form.set('terms_version', TERMS_VERSION); form.set('privacy_version', PRIVACY_VERSION);
    await assert.rejects(actions.default({ locals, url: new URL('https://deepmap.cc/onboarding'), request: { formData: async () => form } }),
        { status: 303, location: '/profile' });
    assert.equal(pending, false);
    assert.equal(await handle({ event, resolve: () => 'ok' }), 'ok');
});

test('missing acceptance RPC fails closed and never redirects as accepted', async () => {
    const { actions } = runInNewContext(server + '\n({actions})', {
        TERMS_VERSION, PRIVACY_VERSION, safeAccountPath, authenticatedAccountPath, redirect,
        fail: (/** @type {number} */ status, /** @type {unknown} */ data) => ({ status, data })
    });
    const form = new FormData();
    form.set('accepted', 'yes'); form.set('terms_version', TERMS_VERSION); form.set('privacy_version', PRIVACY_VERSION);
    const result = await actions.default({
        locals: { supabase: { auth: { getUser: async () => ({ data: { user: { id: 'fixture' } } }) },
            rpc: async (/** @type {string} */ name) => name === 'requires_legal_acceptance'
                ? { data: true, error: null } : { error: { code: 'PGRST202' } } } },
        url: new URL('https://deepmap.cc/onboarding'), request: { formData: async () => form }
    });
    assert.equal(result.status, 503);
    assert.equal(result.data.error, 'save');
});

test('grandfathered and stale accepted POSTs redirect without parsing acceptance or calling its RPC', async () => {
    const { actions } = runInNewContext(server + '\n({actions})', {
        TERMS_VERSION, PRIVACY_VERSION, safeAccountPath, authenticatedAccountPath, redirect,
        fail: (/** @type {number} */ status, /** @type {unknown} */ data) => ({ status, data })
    });
    for (const row of [null, { accepted_at: '2026-10-19T12:00:00Z' }]) {
        const calls = /** @type {string[]} */ ([]);
        const locals = { supabase: { auth: { getUser: async () => ({ data: { user: { id: 'fixture' } } }) },
            rpc: async (/** @type {string} */ name) => {
                calls.push(name); assert.equal(name, 'requires_legal_acceptance');
                return { data: row !== null && row.accepted_at === null, error: null };
            } } };
        await assert.rejects(actions.default({ locals, url: new URL('https://deepmap.cc/onboarding?next=%2Fprofile%3Ftab%3Dactivity'),
            request: { formData: async () => { throw Error('Non-pending POST must not parse acceptance'); } } }),
        { status: 303, location: '/profile?tab=activity' });
        assert.deepEqual(calls, ['requires_legal_acceptance']);
    }
});

test('POST cohort lookup fails closed on errors and non-boolean responses before any acceptance', async () => {
    const { actions } = runInNewContext(server + '\n({actions})', {
        TERMS_VERSION, PRIVACY_VERSION, safeAccountPath, authenticatedAccountPath, redirect,
        fail: (/** @type {number} */ status, /** @type {unknown} */ data) => ({ status, data })
    });
    for (const response of [{ data: null, error: {} }, { data: false, error: {} },
        { data: null, error: null }, { data: 'false', error: null }, { data: undefined, error: null }]) {
        const calls = /** @type {string[]} */ ([]);
        const result = await actions.default({
            locals: { supabase: { auth: { getUser: async () => ({ data: { user: { id: 'fixture' } } }) },
                rpc: async (/** @type {string} */ name) => { calls.push(name); return response; } } },
            url: new URL('https://deepmap.cc/onboarding'),
            request: { formData: async () => { throw Error('Must fail before parsing'); } }
        });
        assert.equal(result.status, 503); assert.deepEqual(calls, ['requires_legal_acceptance']);
    }
});

test('C updates only existing cohort rows and B verifies its exact definition before any enforcement', () => {
    const correction = read('../../../supabase/migrations/20261019121500_legal_acceptance_cohort_guard.sql');
    const enforcement = read('../../../supabase/migrations/20261019123000_legal_acceptance_enforcement.sql');
    const body = correction.split('AS $cohort_guard$')[1].split('$cohort_guard$;')[0];
    assert.doesNotMatch(body, /\bINSERT\b|\bDELETE\b|ON CONFLICT/);
    assert.match(body, /WHERE user_id = v_user_id FOR UPDATE/);
    assert.match(body, /LEGAL_ONBOARDING_NOT_REQUIRED/);
    assert.match(body, /LEGAL_VERSION_MISMATCH/);
    assert.match(body, /IF v_row.accepted_at IS NULL THEN\s+UPDATE private\.legal_onboarding SET accepted_at = pg_catalog\.now\(\)/);
    assert.match(body, /v_row.terms_version IS DISTINCT FROM p_terms_version/);
    assert.match(body, /v_row.privacy_version IS DISTINCT FROM p_privacy_version/);
    assert.doesNotMatch(body, /can_deepmap_interact|can_moderate_deepmap/);
    assert.match(correction, /REVOKE ALL ON FUNCTION public.accept_legal_documents\(text, text\) FROM PUBLIC, anon, authenticated/);
    assert.match(correction, /GRANT EXECUTE ON FUNCTION public.accept_legal_documents\(text, text\) TO authenticated/);
    const expected = enforcement.split('pg_catalog.regexp_replace($cohort_guard$')[1].split('$cohort_guard$,')[0];
    assert.equal(expected.replace(/\s/g, ''), body.replace(/\s/g, ''));
    const historical = read('../../../supabase/migrations/20261019120000_legal_acceptance_onboarding.sql')
        .split('AS $$')[3]?.split('$$;')[0];
    assert.notEqual(expected.replace(/\s/g, ''), historical?.replace(/\s/g, ''));
    assert.ok(enforcement.indexOf('LEGAL_ACCEPTANCE_COHORT_GUARD_REQUIRED') < enforcement.indexOf('CREATE OR REPLACE FUNCTION public.can_deepmap_interact()'));
    assert.match(enforcement, /NOT pg_catalog.has_function_privilege\('anon', p.oid, 'EXECUTE'\)/);
});

test('applied migration A is immutable, timestamp remains DB-owned, B gates staff without gating acceptance', () => {
    const preparation = read('../../../supabase/migrations/20261019120000_legal_acceptance_onboarding.sql').replace(/\r\n/g, '\n');
    assert.equal(createHash('sha256').update(preparation).digest('hex'), '28d76921bb0e62e531b1dcfd5c2bf565fe0bdcd1cb291794dd27459af0ba0e47');
    assert.match(preparation, /pg_catalog\.now\(\)/);
    assert.match(preparation, /COALESCE\(legal_onboarding\.accepted_at, EXCLUDED\.accepted_at\)/);
    assert.match(preparation, /user_id = \(SELECT auth\.uid\(\)\) AND accepted_at IS NULL/);
    const enforcement = read('../../../supabase/migrations/20261019123000_legal_acceptance_enforcement.sql');
    for (const helper of ['is_deepmap_admin', 'is_deepmap_moderator', 'can_moderate_deepmap']) {
        const body = enforcement.split(`CREATE OR REPLACE FUNCTION private.${helper}()`)[1]?.split('$$;')[0];
        assert.ok(body?.includes('public.can_deepmap_interact()'), helper);
    }
    assert.match(enforcement, /CREATE POLICY marker_submissions_legal_update/);
    assert.doesNotMatch(enforcement, /CREATE OR REPLACE FUNCTION public\.(accept_legal_documents|requires_legal_acceptance)/);
    // Acceptance functions installed by A do not call an enforcement/role helper.
    assert.doesNotMatch(preparation, /can_deepmap_interact|can_moderate_deepmap|is_deepmap_admin/);
});

test('return destinations preserve internal queries and fragments but reject external URLs and auth loops', () => {
    const origin = 'https://deepmap.cc';
    for (const path of ['/profile?tab=activity#latest', '/games/game/map?marker=123#layer']) {
        assert.equal(safeAccountPath(path, origin), path);
    }
    for (const path of ['https://evil.example', '//evil.example', '/%2fevil.example', '/%09/evil.example',
        '/login?next=/onboarding', '/onboarding?next=/login', '/auth/callback', '/reset-password',
        '/%6cogin', '/%256fnboarding', '/auth%2Fcontinue']) {
        assert.equal(safeAccountPath(path, origin), '/profile', path);
    }
});

test('existing, pending and accepted accounts share the same authenticated destination contract', async () => {
    const origin = 'https://deepmap.cc', next = '/games/game/map?marker=123';
    for (const row of [null, { accepted_at: null }, { accepted_at: '2026-10-19T12:00:00Z' }]) {
        const pending = row !== null && row.accepted_at === null;
        const supabase = /** @type {any} */ ({ rpc: async () => ({ data: pending, error: null }) });
        assert.equal(await authenticatedAccountPath(supabase, next, origin),
            pending ? '/onboarding?next=' + encodeURIComponent(next) : next);
    }
    for (const data of [null, undefined, 'false']) {
        await assert.rejects(authenticatedAccountPath(/** @type {any} */ ({ rpc: async () => ({ data, error: null }) }), next, origin), { status: 503 });
    }
});

test('email confirmation, OAuth and password continuation converge to onboarding with a safe return path', async () => {
    const origin = 'https://deepmap.cc', next = '/games/game/map?marker=123';
    const callback = read('../../routes/auth/callback/+server.js').replace(/^import[^;]*;/gm, '').replace('export const GET', 'const GET');
    const confirm = read('../../routes/auth/confirm/+server.js').replace(/^import[^;]*;/gm, '').replace('export const GET', 'const GET');
    const continuation = read('../../routes/auth/continue/+server.js').replace(/^import[^;]*;/gm, '').replace('export const GET', 'const GET');
    const { safeInternalPath } = await import('./internal-path.js');
    const supabase = {
        rpc: async () => ({ data: true, error: null }),
        auth: { getUser: async () => ({ data: { user: { id: 'fixture' } } }),
            verifyOtp: async () => ({ error: null }), exchangeCodeForSession: async () => ({ error: null }) }
    };
    for (const [source, path] of [
        [callback, '/auth/callback?code=fixture'],
        [callback, '/auth/callback?type=email&token_hash=fixture'],
        [confirm, '/auth/confirm?type=email&token_hash=fixture'],
        [continuation, '/auth/continue?session=fixture']
    ]) {
        const { GET } = runInNewContext(source + '\n({GET})', { redirect, safeAccountPath, safeInternalPath, authenticatedAccountPath });
        await assert.rejects(GET({ locals: { supabase }, url: new URL(origin + path + '&next=' + encodeURIComponent(next)) }),
            { status: 303, location: '/onboarding?next=' + encodeURIComponent(next) });
        await assert.rejects(GET({ locals: { supabase }, url: new URL(origin + path + '&next=//evil.example') }),
            (/** @type {any} */ e) => e.status === 303 && e.location.startsWith('/onboarding?next=%2F') && !e.location.includes('evil.example'));
    }
});

test('pending accounts can browse public routes but cannot navigate past account gates', async () => {
    const supabase = { auth: { getUser: async () => ({ data: { user: { id: 'fixture' } } }) }, rpc: async () => ({ data: true, error: null }) };
    const { handle } = runInNewContext(hooks + '\n({handle})', {
        safeAccountPath, createServerClient: () => supabase, PUBLIC_SUPABASE_URL: '', PUBLIC_SUPABASE_PUBLISHABLE_KEY: '', redirect,
        error: (/** @type {number} */ status) => { throw { status }; }
    });
    for (const [route, path] of [['/', '/'], ['/games/[game]/map', '/games/game/map'], ['/u/[username]', '/u/fixture']]) {
        assert.equal(await handle({ event: { locals: {}, route: { id: route }, url: new URL('https://deepmap.cc' + path), cookies: {} }, resolve: () => 'public' }), 'public');
    }
    for (const path of ['/profile', '/admin', '/moderation', '/notifications']) {
        await assert.rejects(handle({ event: { locals: {}, route: { id: path }, url: new URL('https://deepmap.cc' + path + '?tab=activity'), cookies: {} }, resolve: () => 'private' }),
            { status: 303, location: '/onboarding?next=' + encodeURIComponent(path + '?tab=activity') });
    }
});

test('existing and accepted users never see a repeated onboarding form', async () => {
    const { load } = runInNewContext(server + '\n({load})', { safeAccountPath, authenticatedAccountPath, redirect });
    const locals = { supabase: { auth: { getUser: async () => ({ data: { user: { id: 'fixture' } } }) }, rpc: async () => ({ data: false, error: null }) } };
    await assert.rejects(load({ locals, url: new URL('https://deepmap.cc/onboarding?next=%2Fprofile') }), { status: 303, location: '/profile' });
});

test('email signup has no unversioned checkbox and handles confirmed and immediate-session registration', async () => {
    const login = read('../../routes/login/+page.svelte').replace(/\r/g, '');
    assert.doesNotMatch(login, /acceptedTerms|terms-consent|type="checkbox"/);
    assert.match(login, /href="\/terms"/); assert.match(login, /href="\/privacy"/);
    const registration = login.slice(login.indexOf('    async function registerWithEmail('), login.indexOf('    async function recoverPassword('));
    for (const session of [null, { user: { id: 'fixture' } }]) {
        const navigations = /** @type {string[]} */ ([]), requests = /** @type {any[]} */ ([]);
        const context = {
            working: false, errorKey: '', successKey: '', password: 'password123', confirmPassword: 'password123', email: 'fixture@example.invalid',
            showPassword: false, showConfirmPassword: false, returnTo: '/games/game/map?marker=123',
            window: { location: { origin: 'https://deepmap.cc' } },
            continuePath: () => '/auth/continue?next=%2Fgames%2Fgame%2Fmap%3Fmarker%3D123',
            goto: async (/** @type {string} */ path) => { navigations.push(path); },
            getSupabaseBrowserClient: () => ({ auth: { signUp: async (/** @type {any} */ request) => { requests.push(request); return { data: { session }, error: null }; } } })
        };
        const { registerWithEmail } = runInNewContext(registration + '\n({registerWithEmail})', context);
        await registerWithEmail({ preventDefault() {} });
        assert.equal(requests.length, 1);
        assert.equal(new URL(requests[0].options.emailRedirectTo).searchParams.get('next'), context.returnTo);
        assert.equal(navigations.length, session ? 1 : 0);
        if (session) assert.match(navigations[0], /^\/auth\/continue\?/);
    }
});
