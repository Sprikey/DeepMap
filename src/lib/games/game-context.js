const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export class GameContextError extends Error {
    /** @param {'NOT_FOUND' | 'CONFIGURATION_UNAVAILABLE' | 'UPSTREAM_ERROR'} code */
    constructor(code) {
        super(code);
        this.name = 'GameContextError';
        this.code = code;
    }
}

/** @param {string} pathname */
export function gameSlugFromMapPathname(pathname) {
    const match = /^\/games\/([a-z0-9]+(?:-[a-z0-9]+)*)\/map\/?$/.exec(pathname);
    if (!match) throw new GameContextError('NOT_FOUND');
    return match[1];
}

/** @param {unknown} value */
function isUuid(value) {
    return typeof value === 'string' && UUID_PATTERN.test(value);
}

/** @param {unknown} value */
function isName(value) {
    return typeof value === 'string' && value.trim().length > 0;
}

/**
 * @template T
 * @param {() => PromiseLike<{ data: T, error: unknown }>} query
 * @returns {Promise<T>}
 */
async function readQuery(query) {
    try {
        const result = await query();
        if (!result || result.error) throw new GameContextError('UPSTREAM_ERROR');
        return result.data;
    } catch {
        // Keep upstream details out of the public route's error response.
        throw new GameContextError('UPSTREAM_ERROR');
    }
}

/** @param {{ supabase: import('@supabase/supabase-js').SupabaseClient, gameSlug: string }} options */
export async function resolvePublicGameContext({ supabase, gameSlug }) {
    if (typeof gameSlug !== 'string' || !SLUG_PATTERN.test(gameSlug)) {
        throw new GameContextError('NOT_FOUND');
    }

    const game = await readQuery(() => supabase
        .from('games')
        .select('id, slug, name, status')
        .eq('slug', gameSlug)
        .eq('status', 'published')
        .maybeSingle());

    if (game === null) throw new GameContextError('NOT_FOUND');
    if (!game || !isUuid(game.id) || game.slug !== gameSlug || !isName(game.name)
        || !['draft', 'coming_soon', 'published'].includes(game.status)) {
        throw new GameContextError('CONFIGURATION_UNAVAILABLE');
    }
    if (game.status !== 'published') throw new GameContextError('NOT_FOUND');

    const mapModule = await readQuery(() => supabase
        .from('game_modules')
        .select('game_id, module_key, enabled')
        .eq('game_id', game.id)
        .eq('module_key', 'map')
        .eq('enabled', true)
        .maybeSingle());

    if (mapModule === null) throw new GameContextError('NOT_FOUND');
    if (!mapModule || mapModule.game_id !== game.id || mapModule.module_key !== 'map'
        || typeof mapModule.enabled !== 'boolean') {
        throw new GameContextError('CONFIGURATION_UNAVAILABLE');
    }
    if (!mapModule.enabled) throw new GameContextError('NOT_FOUND');

    // Read up to two rows so contradictory multiple defaults fail explicitly.
    const maps = await readQuery(() => supabase
        .from('game_maps')
        .select('id, game_id, slug, name, status, is_default')
        .eq('game_id', game.id)
        .eq('status', 'published')
        .eq('is_default', true)
        .limit(2));

    if (!Array.isArray(maps) || maps.length !== 1) {
        throw new GameContextError('CONFIGURATION_UNAVAILABLE');
    }
    const map = maps[0];
    if (!map || !isUuid(map.id) || map.game_id !== game.id
        || typeof map.slug !== 'string' || !SLUG_PATTERN.test(map.slug)
        || !isName(map.name) || map.status !== 'published' || map.is_default !== true) {
        throw new GameContextError('CONFIGURATION_UNAVAILABLE');
    }

    return {
        slug: game.slug,
        gameUuid: game.id,
        name: game.name,
        status: game.status,
        gameMapUuid: map.id,
        mapSlug: map.slug,
        mapName: map.name
    };
}
