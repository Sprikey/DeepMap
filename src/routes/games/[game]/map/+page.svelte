<script>
    import GameMapPage from '$lib/map/GameMapPage.svelte';
    import { getGameRendererBySlug } from '$lib/games/registry.js';

    /** @type {{data: import('./$types').PageData}} */
    let { data } = $props();
    let renderer = $derived(getGameRendererBySlug(data.gameContext.slug));
</script>

{#if renderer && renderer.legacyGameId?.trim()}
    {#key JSON.stringify([data.gameContext.gameUuid, data.gameContext.gameMapUuid, data.gameContext.slug])}
        <GameMapPage gameContext={data.gameContext} {renderer} />
    {/key}
{:else}
    <div class="map-unavailable" role="status">Map temporarily unavailable.</div>
{/if}

<style>
    .map-unavailable { padding: calc(var(--deepmap-site-header-height, 72px) + 32px) 24px 32px; }
</style>
