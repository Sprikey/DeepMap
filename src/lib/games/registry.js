import { categories as eldenRingCategories, categoryGroups as eldenRingCategoryGroups } from '$lib/games/elden-ring/categories.js';
import { locations as eldenRingLocations } from '$lib/games/elden-ring/locations.js';
import { mapDefinitions as eldenRingMapDefinitions } from '$lib/games/elden-ring/maps.js';

// Renderer capabilities only: DB games/modules/maps remain the catalog authority.
const rendererRegistry = [
    {
        gameSlug: 'elden-ring',
        mapHref: '/games/elden-ring/map',
        editorHref: '/games/elden-ring/map?editor=1',
        fallback: {
            categories: { ...eldenRingCategories },
            categoryGroups: [...eldenRingCategoryGroups],
            locations: [...eldenRingLocations],
            mapDefinitions: { ...eldenRingMapDefinitions },
            mapLabels: []
        }
    }
];

/** Exact public-slug lookup; a DB game without a renderer is a normal state.
 * @param {string} gameSlug
 */
export function getGameRendererBySlug(gameSlug) {
    return rendererRegistry.find((renderer) => renderer.gameSlug === gameSlug) ?? null;
}

// Compatibility descriptors for B7f2's renderer-path check. These are NOT a
// game inventory. Retain their existing shape/semantics until the deferred audit.
const legacyNames = new Map([['elden-ring', 'Elden Ring']]);
const registry = rendererRegistry.map((renderer) => ({
    id: renderer.gameSlug,
    name: legacyNames.get(renderer.gameSlug) ?? renderer.gameSlug,
    mapHref: renderer.mapHref,
    editorHref: renderer.editorHref,
    fallback: renderer.fallback
}));
export const deepMapGames = registry;

export function getDeepMapGame(gameId) {
    return registry.find((game) => game.id === gameId) ?? null;
}

export function getDeepMapGameName(gameId) {
    return getDeepMapGame(gameId)?.name ?? gameId ?? 'Unknown game';
}

export function getDeepMapGameMapHref(gameId) {
    return getDeepMapGame(gameId)?.mapHref ?? `/games/${encodeURIComponent(gameId)}/map`;
}

export function getDeepMapGameFallback(gameId) {
    return getDeepMapGame(gameId)?.fallback ?? {
        categories: {},
        categoryGroups: [],
        locations: [],
        mapDefinitions: {},
        mapLabels: []
    };
}
