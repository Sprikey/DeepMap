import { categories as eldenRingCategories, categoryGroups as eldenRingCategoryGroups, defaultCategoryVisibility as eldenRingCategoryVisibility } from './elden-ring/categories.js';
import { locations as eldenRingLocations } from './elden-ring/locations.js';
import { mapDefinitions as eldenRingMapDefinitions } from './elden-ring/maps.js';

import { translations as eldenRingTranslations } from './elden-ring/translations.js';

/** @typedef {{ gameSlug: string, mapHref: string, editorHref: string, legacyGameId?: string, defaultLayerKey: string, translations: Record<string, Record<string, string>>, defaultCategoryVisibility: Record<string, boolean>, fallback: { categories: Record<string, any>, categoryGroups: any[], locations: any[], mapDefinitions: Record<string, any>, mapLabels: any[] } }} GameRenderer */

// Renderer capabilities only: DB games/modules/maps remain the catalog authority.
/** @type {GameRenderer[]} */
const rendererRegistry = [
    {
        gameSlug: 'elden-ring',
        // Legacy writer payload adapter; never inferred from the current DB slug.
        legacyGameId: 'elden-ring',
        defaultLayerKey: 'surface',
        translations: eldenRingTranslations,
        defaultCategoryVisibility: { ...eldenRingCategoryVisibility },
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

/** Required by the remaining legacy TEXT writer contracts, not by public routing.
 * @param {{ legacyGameId?: string | null } | null} renderer
 */
export function requireRendererLegacyGameId(renderer) {
    if (typeof renderer?.legacyGameId !== 'string' || !renderer.legacyGameId.trim()) {
        throw new Error('MAP_RENDERER_LEGACY_GAME_ID_REQUIRED');
    }
    return renderer.legacyGameId;
}
