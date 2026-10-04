import { categories as eldenRingCategories, categoryGroups as eldenRingCategoryGroups } from '$lib/games/elden-ring/categories.js';
import { locations as eldenRingLocations } from '$lib/games/elden-ring/locations.js';
import { mapDefinitions as eldenRingMapDefinitions } from '$lib/games/elden-ring/maps.js';

const registry = [
    {
        id: 'elden-ring',
        name: 'Elden Ring',
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
