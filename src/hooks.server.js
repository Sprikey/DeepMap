import { createServerClient } from '@supabase/ssr';

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
    await event.locals.supabase.auth.getUser();

    return resolve(event, {
        filterSerializedResponseHeaders(name) {
            return (
                name === 'content-range' ||
                name === 'x-supabase-api-version'
            );
        }
    });
};