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

/** @typedef {{ moduleUuid: string, gameUuid: string, moduleKey: string, enabled: boolean, position: number }} AdminGameModule */
/** @typedef {{ gameMapUuid: string, gameUuid: string, mapSlug: string, mapName: string, mapStatus: string, isDefault: boolean, position: number }} AdminGameMap */
/** @typedef {{ gameUuid: string, gameSlug: string, gameName: string, gameStatus: string, modules: AdminGameModule[], mapModuleState: 'absent' | 'disabled' | 'enabled', maps: AdminGameMap[] }} AdminCatalogGame */

const ADMIN_CATALOG_BATCH_SIZE = 200;

/** Read complete catalog relations without relying on PostgREST's default row cap.
 * @param {(offset: number) => PromiseLike<{ data: any, error: unknown }>} query
 * @returns {Promise<any[]>}
 */
async function readAdminCatalogRows(query) {
    const rows = [];
    for (let offset = 0; ; offset += ADMIN_CATALOG_BATCH_SIZE) {
        const batch = await readQuery(() => query(offset));
        if (!Array.isArray(batch)) throw new GameContextError('CONFIGURATION_UNAVAILABLE');
        rows.push(...batch);
        if (batch.length < ADMIN_CATALOG_BATCH_SIZE) return rows;
    }
}

/** Complete RLS-visible Admin inventory. Renderer capabilities are a separate
 * client concern. Unlike moderation, child-read failures fail the whole catalog
 * rather than turning unknown module/map state into apparent absence.
 * @param {{ supabase: import('@supabase/supabase-js').SupabaseClient }} options
 * @returns {Promise<AdminCatalogGame[]>}
 */
export async function loadAdminGameCatalog({ supabase }) {
    const games = await readAdminCatalogRows((offset) => supabase.from('games')
        .select('id, slug, name, status').order('name').order('id')
        .range(offset, offset + ADMIN_CATALOG_BATCH_SIZE - 1));
    const gameUuids = new Set();
    const gameSlugs = new Set();
    for (const game of games) {
        if (!game || !isUuid(game.id) || typeof game.slug !== 'string' || !SLUG_PATTERN.test(game.slug)
            || !isName(game.name) || !['draft', 'coming_soon', 'published'].includes(game.status)
            || gameUuids.has(game.id) || gameSlugs.has(game.slug)) {
            throw new GameContextError('CONFIGURATION_UNAVAILABLE');
        }
        gameUuids.add(game.id);
        gameSlugs.add(game.slug);
    }
    /** @type {AdminCatalogGame[]} */
    const catalog = games.map((game) => ({ gameUuid: game.id, gameSlug: game.slug,
        gameName: game.name, gameStatus: game.status, modules: [], mapModuleState: 'absent', maps: [] }));
    const catalogByUuid = new Map(catalog.map((game) => [game.gameUuid, game]));
    const moduleUuids = new Set();
    const mapUuids = new Set();
    // Bound UUID filter sizes as well as relation pages. All associations are UUID-only.
    for (let start = 0; start < catalog.length; start += ADMIN_CATALOG_BATCH_SIZE) {
        const ids = catalog.slice(start, start + ADMIN_CATALOG_BATCH_SIZE).map((game) => game.gameUuid);
        const [modules, maps] = await Promise.all([
            readAdminCatalogRows((offset) => supabase.from('game_modules')
                .select('id, game_id, module_key, enabled, position').in('game_id', ids)
                .order('position').order('id').range(offset, offset + ADMIN_CATALOG_BATCH_SIZE - 1)),
            readAdminCatalogRows((offset) => supabase.from('game_maps')
                .select('id, game_id, slug, name, status, position, is_default').in('game_id', ids)
                .order('position').order('id').range(offset, offset + ADMIN_CATALOG_BATCH_SIZE - 1))
        ]);
        for (const module of modules) {
            const game = module ? catalogByUuid.get(module.game_id) : undefined;
            if (!game || !ids.includes(module.game_id) || !isUuid(module.id) || moduleUuids.has(module.id)
                || typeof module.module_key !== 'string' || !/^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$/.test(module.module_key)
                || ['overview', 'settings'].includes(module.module_key) || typeof module.enabled !== 'boolean'
                || !Number.isSafeInteger(module.position) || module.position < 0 || module.position > 2147483647
                || game.modules.some((existing) => existing.moduleKey === module.module_key)) {
                throw new GameContextError('CONFIGURATION_UNAVAILABLE');
            }
            moduleUuids.add(module.id);
            game.modules.push({ moduleUuid: module.id, gameUuid: module.game_id,
                moduleKey: module.module_key, enabled: module.enabled, position: module.position });
            if (module.module_key === 'map') game.mapModuleState = module.enabled ? 'enabled' : 'disabled';
        }
        for (const map of maps) {
            const game = map ? catalogByUuid.get(map.game_id) : undefined;
            if (!game || !ids.includes(map.game_id) || !isUuid(map.id) || mapUuids.has(map.id)
                || typeof map.slug !== 'string' || !SLUG_PATTERN.test(map.slug) || !isName(map.name)
                || !['draft', 'published'].includes(map.status) || typeof map.is_default !== 'boolean'
                || !Number.isSafeInteger(map.position) || map.position < 0 || map.position > 2147483647
                || game.maps.some((existing) => existing.mapSlug === map.slug || (existing.isDefault && map.is_default))) {
                throw new GameContextError('CONFIGURATION_UNAVAILABLE');
            }
            mapUuids.add(map.id);
            game.maps.push({ gameMapUuid: map.id, gameUuid: map.game_id, mapSlug: map.slug,
                mapName: map.name, mapStatus: map.status, isDefault: map.is_default, position: map.position });
        }
    }
    return catalog;
}

/**
 * RLS-visible staff filters. Missing visual metadata only disables map links.
 * @param {{supabase: import('@supabase/supabase-js').SupabaseClient}} options
 */
export async function loadModerationGameCatalog({ supabase }) {
    const games = await readQuery(() => supabase.from('games')
        .select('id, slug, name, status').order('name'));
    if (!Array.isArray(games) || games.some((game) => !isUuid(game.id)
        || typeof game.slug !== 'string' || !SLUG_PATTERN.test(game.slug) || !isName(game.name)
        || !['draft', 'coming_soon', 'published'].includes(game.status))) {
        throw new GameContextError('CONFIGURATION_UNAVAILABLE');
    }
    const ids = games.map((game) => game.id);
    const catalog = games.map((game) => ({
        gameUuid: game.id, gameSlug: game.slug, gameName: game.name,
        status: game.status, publicGameMapUuid: /** @type {string | null} */ (null)
    }));
    if (!ids.length) return catalog;
    try {
        const [maps, modules] = await Promise.all([
            readQuery(() => supabase.from('game_maps').select('id, game_id, status, is_default')
                .in('game_id', ids).eq('status', 'published').eq('is_default', true)),
            readQuery(() => supabase.from('game_modules').select('game_id, module_key, enabled')
                .in('game_id', ids).eq('module_key', 'map').eq('enabled', true))
        ]);
        if (!Array.isArray(maps) || !Array.isArray(modules)) return catalog;
        for (const game of catalog) {
            const defaults = maps.filter((map) => map.game_id === game.gameUuid);
            if (game.status === 'published' && defaults.length === 1 && isUuid(defaults[0].id)
                && defaults[0].status === 'published' && defaults[0].is_default === true
                && modules.some((module) => module.game_id === game.gameUuid && module.module_key === 'map' && module.enabled === true)) {
                game.publicGameMapUuid = defaults[0].id;
            }
        }
    } catch {
        // RLS visibility can be narrower than SECURITY DEFINER submission reads.
    }
    return catalog;
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
