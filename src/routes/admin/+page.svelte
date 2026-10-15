<script>
    import { onMount, untrack } from 'svelte';
    import { goto } from '$app/navigation';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { getSiteLanguage, subscribeSiteLanguage } from '$lib/i18n/site.js';
    import { getGameRendererBySlug } from '$lib/games/registry.js';
    import { loadAdminGameCatalog } from '$lib/games/game-context.js';
    import GlobalModerationPanel from '$lib/admin/GlobalModerationPanel.svelte';
    import AdminAuditPanel from '$lib/admin/AdminAuditPanel.svelte';
    import UserManagementPanel from '$lib/editor/UserManagementPanel.svelte';

    let language = $state('en');
    let checking = $state(true);
    let allowed = $state(false);
    let section = $state('maps');

    const TEXT = {
        en:{title:'Administration',subtitle:'Global DeepMap management',maps:'Maps',moderation:'Moderation',users:'Users',audit:'Audit log',reports:'Reports',future:'Coming later',openEditor:'Open map editor',mapsHelp:'Each map keeps its own editor. Global moderation and user management stay here.',denied:'Admin access required.'},
        pt:{title:'Administração',subtitle:'Gestão global do DeepMap',maps:'Mapas',moderation:'Moderação',users:'Utilizadores',audit:'Histórico',reports:'Reports',future:'Mais tarde',openEditor:'Abrir editor do mapa',mapsHelp:'Cada mapa mantém o seu próprio editor. A moderação global e a gestão de utilizadores ficam aqui.',denied:'É necessário acesso de administrador.'}
    };
    let t = $derived(TEXT[language] ?? TEXT.en);

    /** @type {Record<string, Record<string, string>>} */
    const CATALOG_TEXT = {
        en: { loading:'Loading catalog...', loadError:'Could not load the game catalog.', empty:'No games found.',
            noMaps:'No maps configured.', noRenderer:'Map renderer unavailable.', absent:'Map module not configured.',
            disabled:'Map module disabled.', enabled:'Map module enabled.', defaultMap:'Default map',
            draft:'Draft', coming_soon:'Coming soon', published:'Published' },
        pt: { loading:'A carregar o catálogo...', loadError:'Não foi possível carregar o catálogo de jogos.', empty:'Nenhum jogo encontrado.',
            noMaps:'Sem mapas configurados.', noRenderer:'Renderer de mapa indisponível.', absent:'Módulo de mapa não configurado.',
            disabled:'Módulo de mapa desativado.', enabled:'Módulo de mapa ativo.', defaultMap:'Mapa predefinido',
            draft:'Rascunho', coming_soon:'Em breve', published:'Publicado' }
    };
    let catalogText = $derived(CATALOG_TEXT[language] ?? CATALOG_TEXT.en);
    let catalog = $state(/** @type {Awaited<ReturnType<typeof loadAdminGameCatalog>>} */ ([]));
    let catalogLoading = $state(false);
    let catalogError = $state(false);
    let mounted = false;
    /** @type {string | null} */
    let currentUserId = null;
    let sessionGeneration = 0;
    let accessGeneration = 0;
    let catalogGeneration = 0;
    let sessionInitialized = false;
    /** @type {ReturnType<typeof setTimeout> | null} */
    let accessTimer = null;

    /** @param {string} status */
    function statusLabel(status) { return catalogText[status] ?? status; }

    /** The current editor lives on the public, published-default map route.
     * Renderer support alone does not make draft/disabled/nondefault maps openable.
     * @param {import('$lib/games/game-context.js').AdminCatalogGame} game
     * @param {import('$lib/games/game-context.js').AdminGameMap} map
     */
    function editorHref(game, map) {
        const renderer = getGameRendererBySlug(game.gameSlug);
        if (!renderer || game.gameStatus !== 'published' || game.mapModuleState !== 'enabled'
            || map.gameUuid !== game.gameUuid || !game.maps.some((entry) => entry.gameMapUuid === map.gameMapUuid)
            || map.mapStatus !== 'published' || !map.isDefault
            || game.maps.filter((entry) => entry.isDefault).length !== 1) return null;
        const base = '/games/' + encodeURIComponent(game.gameSlug) + '/map';
        return renderer.mapHref === base && renderer.editorHref === base + '?editor=1' ? renderer.editorHref : null;
    }

    function clearCatalog() {
        catalogGeneration += 1;
        catalog = [];
        catalogLoading = false;
        catalogError = false;
    }

    async function loadCatalog() {
        const request = ++catalogGeneration;
        const epoch = sessionGeneration;
        const user = currentUserId;
        const isCurrent = () => mounted && allowed && !!user && user === currentUserId
            && epoch === sessionGeneration && request === catalogGeneration;
        if (!isCurrent()) return;
        catalog = [];
        catalogLoading = true;
        catalogError = false;
        try {
            const result = await loadAdminGameCatalog({ supabase: getSupabaseBrowserClient() });
            if (isCurrent()) catalog = result;
        } catch {
            if (isCurrent()) { catalog = []; catalogError = true; }
        } finally {
            if (isCurrent()) catalogLoading = false;
        }
    }

    async function checkAccess() {
        const request = ++accessGeneration;
        const epoch = sessionGeneration;
        const user = currentUserId;
        clearCatalog();
        if (allowed && section === 'maps') catalogLoading = true;
        const isCurrent = () => mounted && !!user && user === currentUserId
            && epoch === sessionGeneration && request === accessGeneration;
        if (!isCurrent()) return;
        try {
            const { data: role, error } = await getSupabaseBrowserClient().rpc('get_deepmap_role');
            if (!isCurrent()) return;
            const wasAllowed = allowed;
            allowed = !error && role === 'admin';
            checking = false;
            if (!allowed) clearCatalog();
            else if (wasAllowed && section === 'maps') void loadCatalog();
        } catch {
            if (isCurrent()) { allowed = false; checking = false; clearCatalog(); }
        }
    }

    /** @param {string | null} user */
    function sessionChanged(user) {
        if (!mounted) return;
        sessionInitialized = true;
        sessionGeneration += 1;
        accessGeneration += 1;
        clearCatalog();
        currentUserId = user;
        allowed = false;
        checking = !!user;
        if (accessTimer !== null) clearTimeout(accessTimer);
        const epoch = sessionGeneration;
        // Return from the auth callback before any browser-client request.
        accessTimer = setTimeout(() => {
            accessTimer = null;
            if (!mounted || epoch !== sessionGeneration) return;
            if (user) void checkAccess();
            else void goto('/login?next=' + encodeURIComponent('/admin'));
        }, 0);
    }

    onMount(() => {
        mounted = true;
        language = getSiteLanguage();
        const unsubscribe = subscribeSiteLanguage((/** @type {string} */ next) => { language = next; });
        const requestedSection = new URL(window.location.href).searchParams.get('section');
        if (requestedSection && ['maps','moderation','users','audit'].includes(requestedSection)) section = requestedSection;
        const supabase = getSupabaseBrowserClient();
        const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
            if (!mounted) return;
            const user = session?.user.id ?? null;
            if (sessionInitialized && user === currentUserId && (event === 'TOKEN_REFRESHED' || event === 'INITIAL_SESSION')) return;
            sessionChanged(user);
        });
        const initialGeneration = sessionGeneration;
        void (async () => {
            try {
                const { data, error } = await supabase.auth.getUser();
                if (mounted && initialGeneration === sessionGeneration) sessionChanged(error ? null : data.user?.id ?? null);
            } catch {
                if (mounted && initialGeneration === sessionGeneration) sessionChanged(null);
            }
        })();
        const accountChanged = () => sessionChanged(currentUserId);
        const recheck = () => { if (mounted && currentUserId) void checkAccess(); };
        window.addEventListener('deepmap:account-status-changed', accountChanged);
        window.addEventListener('focus', recheck);
        return () => {
            mounted = false;
            sessionGeneration += 1;
            accessGeneration += 1;
            currentUserId = null;
            allowed = false;
            clearCatalog();
            if (accessTimer !== null) clearTimeout(accessTimer);
            subscription.unsubscribe();
            unsubscribe();
            window.removeEventListener('deepmap:account-status-changed', accountChanged);
            window.removeEventListener('focus', recheck);
        };
    });

    $effect(() => {
        if (allowed && section === 'maps') untrack(() => { void loadCatalog(); });
    });
</script>

<svelte:head><title>{t.title} · DeepMap</title><meta name="robots" content="noindex,nofollow" /></svelte:head>

<main class="admin-page">
    {#if checking}<div class="state">…</div>
    {:else if !allowed}<div class="state"><strong>{t.denied}</strong></div>
    {:else}
        <header class="page-head"><span>DeepMap</span><h1>{t.title}</h1><p>{t.subtitle}</p></header>
        <nav class="admin-nav" aria-label={t.title}>
            <button class:active={section==='maps'} type="button" onclick={()=>section='maps'}>{t.maps}</button>
            <button class:active={section==='moderation'} type="button" onclick={()=>section='moderation'}>{t.moderation}</button>
            <button class:active={section==='users'} type="button" onclick={()=>section='users'}>{t.users}</button>
            <button class:active={section==='audit'} type="button" onclick={()=>section='audit'}>{t.audit}</button>
            <button class="future" type="button" disabled>{t.reports}<small>{t.future}</small></button>
        </nav>

        <section class="admin-content">
            {#if section==='maps'}
                <div class="maps-section">
                    <p>{t.mapsHelp}</p>
                    {#if catalogLoading}<p role="status">{catalogText.loading}</p>
                    {:else if catalogError}<p role="alert">{catalogText.loadError}</p>
                    {:else if !catalog.length}<p>{catalogText.empty}</p>
                    {:else}
                        <div class="map-grid">
                            {#each catalog as game (game.gameUuid)}
                                <article><div class="game-details">
                                    <span>{statusLabel(game.gameStatus)}</span><h2>{game.gameName}</h2><code>{game.gameSlug}</code>
                                    <p class="catalog-state">{catalogText[game.mapModuleState]}</p>
                                    {#if !getGameRendererBySlug(game.gameSlug)}<p class="catalog-state">{catalogText.noRenderer}</p>{/if}
                                    {#if !game.maps.length}<p class="catalog-state">{catalogText.noMaps}</p>
                                    {:else}<ul class="game-maps">
                                        {#each game.maps as map (map.gameMapUuid)}
                                            {@const href = editorHref(game, map)}
                                            <li><div><strong>{map.mapName}</strong><code>{map.mapSlug}</code><small>{statusLabel(map.mapStatus)}{#if map.isDefault} &middot; {catalogText.defaultMap}{/if}</small></div>
                                                {#if href}<a {href}>{t.openEditor}</a>{/if}
                                            </li>
                                        {/each}
                                    </ul>{/if}
                                </div></article>
                            {/each}
                        </div>
                    {/if}
                </div>
            {:else if section==='moderation'}
                <GlobalModerationPanel {language} active={true}/>
            {:else if section==='users'}
                <UserManagementPanel {language} active={true}/>
            {:else if section==='audit'}
                <AdminAuditPanel {language} active={true}/>
            {/if}
        </section>
    {/if}
</main>

<style>
.admin-page{width:min(1240px,calc(100% - 28px));margin:0 auto;padding:34px 0 70px;color:#eee;font-family:'Segoe UI',Arial,sans-serif}.page-head{margin-bottom:18px}.page-head>span{color:#c8a355;font-size:.72rem;font-weight:900;text-transform:uppercase;letter-spacing:.12em}.page-head h1{margin:4px 0 3px;font-size:clamp(1.7rem,3vw,2.5rem)}.page-head p{margin:0;color:#93939d}.admin-nav{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:8px;margin-bottom:16px}.admin-nav button{min-height:54px;border:1px solid #34343e;border-radius:10px;background:#121216;color:#bbb;cursor:pointer;font-weight:800}.admin-nav button.active{border-color:#c8a355;background:#211d14;color:#efd184}.admin-nav button.future{display:grid;place-items:center;gap:2px;opacity:.55}.admin-nav small{font-size:.58rem;color:#777}.admin-content{min-height:360px;padding:16px;border:1px solid #2e2e36;border-radius:12px;background:rgba(11,11,14,.96);box-shadow:0 16px 48px rgba(0,0,0,.26)}.maps-section>p{margin:0 0 14px;color:#9a9aa4}.map-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:12px}.map-grid article{display:flex;align-items:center;justify-content:space-between;gap:14px;padding:15px;border:1px solid #33333c;border-radius:11px;background:#111115}.map-grid article span{color:#c8a355;font-size:.65rem;font-weight:800;text-transform:uppercase}.map-grid h2{margin:4px 0;font-size:1.15rem}.map-grid code{color:#777}.map-grid a{flex:none;padding:9px 11px;border:1px solid #c8a355;border-radius:8px;color:#d8b86f;text-decoration:none;font-weight:800;font-size:.76rem}.state{min-height:55vh;display:grid;place-items:center;color:#aaa}.state strong{color:#e5c978}
@media(max-width:760px){.admin-page{width:min(100% - 18px,1240px);padding-top:18px}.admin-nav{grid-template-columns:repeat(2,1fr)}.admin-nav button.future{display:none}.admin-content{padding:10px}.map-grid article{align-items:flex-start;flex-direction:column}.map-grid a{width:100%;box-sizing:border-box;text-align:center}}
.game-details{min-width:0;width:100%;overflow-wrap:anywhere}.catalog-state{margin:8px 0;color:#9a9aa4;font-size:.78rem}.game-maps{list-style:none;display:grid;gap:10px;margin:12px 0 0;padding:0}.game-maps li{display:flex;align-items:center;justify-content:space-between;gap:12px;padding-top:10px;border-top:1px solid #33333c}.game-maps li>div{display:grid;gap:4px;min-width:0}.game-maps small{color:#9a9aa4}.map-grid article{min-width:0}@media(max-width:760px){.game-maps li{align-items:stretch;flex-direction:column}}
</style>
