<script>
    import { page } from '$app/state';
    import favicon from '$lib/assets/favicon.svg';
    import SiteHeader from '$lib/components/SiteHeader.svelte';
    import SiteFooter from '$lib/components/SiteFooter.svelte';

    let { children } = $props();

    let isMapRoute = $derived(page.url.pathname.startsWith('/games/elden-ring/map'));
</script>

<svelte:head>
    <link rel="icon" href={favicon} />
</svelte:head>

<SiteHeader />

<div class:page-with-global-header={!isMapRoute}>
    {@render children()}
    {#if !isMapRoute}
        <SiteFooter />
    {/if}
</div>

<style>
    :global(:root) {
        --deepmap-site-header-height: 72px;
        --deepmap-game-subheader-height: 54px;
    }

    .page-with-global-header {
        min-height: 100vh;
        min-height: 100dvh;
        padding-top: var(--deepmap-site-header-height);
        box-sizing: border-box;
    }

    .page-with-global-header :global(main) {
        min-height: calc(100vh - var(--deepmap-site-header-height));
        min-height: calc(100dvh - var(--deepmap-site-header-height));
    }

    @media (max-width: 820px) {
        :global(:root) {
            --deepmap-site-header-height: 62px;
            --deepmap-game-subheader-height: 52px;
        }
    }
</style>
