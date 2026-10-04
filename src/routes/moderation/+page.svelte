<script>
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { getSiteLanguage, subscribeSiteLanguage } from '$lib/i18n/site.js';
    import GlobalModerationPanel from '$lib/admin/GlobalModerationPanel.svelte';

    let language=$state('en');
    let checking=$state(true);
    let allowed=$state(false);
    let role=$state('user');
    const TEXT={en:{title:'Moderation',subtitle:'Community submissions from every DeepMap map',denied:'Moderator access required.',admin:'Open administration'},pt:{title:'Moderação',subtitle:'Submissões da comunidade de todos os mapas DeepMap',denied:'É necessário acesso de moderador.',admin:'Abrir administração'}};
    let t=$derived(TEXT[language]??TEXT.en);

    onMount(()=>{
        language=getSiteLanguage();
        const unsub=subscribeSiteLanguage((next)=>language=next);
        void (async()=>{
            const supabase=getSupabaseBrowserClient();
            const {data:userData}=await supabase.auth.getUser();
            if(!userData.user){await goto(`/login?next=${encodeURIComponent('/moderation')}`);return;}
            const {data,error}=await supabase.rpc('get_deepmap_role');
            role=error?'user':data;
            allowed=role==='moderator'||role==='admin';
            checking=false;
        })();
        return unsub;
    });
</script>

<svelte:head><title>{t.title} · DeepMap</title><meta name="robots" content="noindex,nofollow" /></svelte:head>

<main class="moderation-page">
    {#if checking}<div class="state">…</div>
    {:else if !allowed}<div class="state"><strong>{t.denied}</strong></div>
    {:else}
        <header><div><span>DeepMap</span><h1>{t.title}</h1><p>{t.subtitle}</p></div>{#if role==='admin'}<a href="/admin">{t.admin}</a>{/if}</header>
        <section class="panel"><GlobalModerationPanel {language} active={true}/></section>
    {/if}
</main>

<style>
.moderation-page{width:min(1240px,calc(100% - 28px));margin:0 auto;padding:34px 0 70px;color:#eee;font-family:'Segoe UI',Arial,sans-serif}.moderation-page>header{display:flex;align-items:flex-end;justify-content:space-between;gap:12px;margin-bottom:16px}.moderation-page header span{color:#c8a355;font-size:.72rem;font-weight:900;text-transform:uppercase}.moderation-page h1{margin:4px 0 3px}.moderation-page p{margin:0;color:#93939d}.moderation-page header a{padding:9px 11px;border:1px solid #c8a355;border-radius:8px;color:#d8b86f;text-decoration:none;font-weight:800;font-size:.76rem}.panel{padding:16px;border:1px solid #2e2e36;border-radius:12px;background:rgba(11,11,14,.96)}.state{min-height:55vh;display:grid;place-items:center;color:#aaa}.state strong{color:#e5c978}@media(max-width:700px){.moderation-page{width:min(100% - 18px,1240px);padding-top:18px}.moderation-page>header{align-items:flex-start;flex-direction:column}.moderation-page header a{width:100%;box-sizing:border-box;text-align:center}.panel{padding:10px}}
</style>
