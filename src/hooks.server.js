import { createServerClient } from '@supabase/ssr';
import { error, redirect } from '@sveltejs/kit';
import { safeAccountPath } from '$lib/auth/account-path.js';

import {
    PUBLIC_SUPABASE_URL,
    PUBLIC_SUPABASE_PUBLISHABLE_KEY
} from '$env/static/public';

/** @type {import('@sveltejs/kit').Handle} */
export const handle = async ({ event, resolve }) => {

    event.locals.supabase = createServerClient(
        PUBLIC_SUPABASE_URL,
        PUBLIC_SUPABASE_PUBLISHABLE_KEY,
        {
            cookies: {
                getAll() {
                    return event.cookies.getAll();
                },

                setAll(cookiesToSet, headers = {}) {

                    cookiesToSet.forEach(({ name, value, options }) => {
                        event.cookies.set(name, value, {
                            ...options,
                            path: '/'
                        });
                    });

                    if (Object.keys(headers).length > 0) {
                        event.setHeaders(headers);
                    }
                }
            }
        }
    );

    // Verificar e, se necessário, renovar a sessão
    // ANTES de o SvelteKit gerar a resposta.
    const { data: { user } } = await event.locals.supabase.auth.getUser();
    const exempt = /^\/(?:auth(?:\/|$)|onboarding\/?$|terms\/?$|privacy\/?$|login\/?$|reset-password\/?$|suspended\/?$)/;
    const publicRoute = ['/', '/games/[game]/map', '/u/[username]', '/p/[id]'].includes(event.route.id ?? '');
    if (user && event.route.id && !publicRoute && !exempt.test(event.url.pathname)) {
        const { data: required, error: legalError } = await event.locals.supabase.rpc('requires_legal_acceptance');
        // Deploy after preparation migration A; DB enforcement B follows rollout.
        // Missing preparation must not silently bypass onboarding.
        if (legalError || typeof required !== 'boolean') error(503, 'Account onboarding is temporarily unavailable.');
        if (required) {
            const next = safeAccountPath(event.url.pathname + event.url.search, event.url.origin);
            redirect(303, `/onboarding?next=${encodeURIComponent(next)}`);
        }
    }

    return resolve(event, {
        filterSerializedResponseHeaders(name) {
            return (
                name === 'content-range' ||
                name === 'x-supabase-api-version'
            );
        }
    });
};
