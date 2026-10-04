<script>
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { getSiteLanguage, subscribeSiteLanguage } from '$lib/i18n/site.js';
    import { deepMapGames } from '$lib/games/registry.js';
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

    onMount(() => {
        language = getSiteLanguage();
        const unsubscribe = subscribeSiteLanguage((next) => { language = next; });
        void (async()=>{
            const supabase=getSupabaseBrowserClient();
            const {data:userData}=await supabase.auth.getUser();
            if(!userData.user){ await goto(`/login?next=${encodeURIComponent('/admin')}`); return; }
            const {data:role,error}=await supabase.rpc('get_deepmap_role');
            allowed=!error&&role==='admin';
            checking=false;
        })();
        return unsubscribe;
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
                <div class="maps-section"><p>{t.mapsHelp}</p><div class="map-grid">{#each deepMapGames as game}<article><div><span>Game map</span><h2>{game.name}</h2><code>{game.id}</code></div><a href={game.editorHref}>{t.openEditor}</a></article>{/each}</div></div>
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
</style>
