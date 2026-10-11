import { error } from '@sveltejs/kit';
import {
    GameContextError,
    gameSlugFromMapPathname,
    resolvePublicGameContext
} from '$lib/games/game-context.js';

/** @type {import('./$types').PageServerLoad} */
export async function load({ locals, url }) {
    try {
        const gameSlug = gameSlugFromMapPathname(url.pathname);
        // The existing hook supplies this client; App.Locals has no declaration yet.
        const { supabase } = /** @type {App.Locals & { supabase: import('@supabase/supabase-js').SupabaseClient }} */ (locals);
        const gameContext = await resolvePublicGameContext({
            supabase,
            gameSlug
        });
        return { gameContext };
    } catch (cause) {
        if (cause instanceof GameContextError && cause.code === 'NOT_FOUND') {
            error(404, 'Map not found.');
        }
        error(503, 'Map temporarily unavailable.');
    }
}
