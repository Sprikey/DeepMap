<script>
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { getSiteLanguage, subscribeSiteLanguage } from '$lib/i18n/site.js';

    let language=$state('en');
    let loading=$state(true);
    let status=$state(null);
    const TEXT={en:{title:'Account suspended',intro:'Your account can still browse public DeepMap content, but community interactions are disabled while this suspension is active.',reason:'Reason',until:'Until',permanent:'Permanent suspension',browse:'Continue browsing',logout:'Log out',active:'This account is not suspended.'},pt:{title:'Conta suspensa',intro:'A tua conta pode continuar a consultar o conteúdo público do DeepMap, mas as interações da comunidade ficam bloqueadas enquanto esta suspensão estiver ativa.',reason:'Motivo',until:'Até',permanent:'Suspensão permanente',browse:'Continuar a explorar',logout:'Terminar sessão',active:'Esta conta não está suspensa.'}};
    let t=$derived(TEXT[language]??TEXT.en);

    function formatDate(value){if(!value)return t.permanent;const d=new Date(value);if(Number.isNaN(d.getTime()))return t.permanent;return new Intl.DateTimeFormat(language==='pt'?'pt-PT':'en-GB',{dateStyle:'long',timeStyle:'short'}).format(d);}
    async function logout(){await getSupabaseBrowserClient().auth.signOut();await goto('/');}

    onMount(()=>{
        language=getSiteLanguage();const unsub=subscribeSiteLanguage(next=>language=next);
        void (async()=>{
            const supabase=getSupabaseBrowserClient();const {data:userData}=await supabase.auth.getUser();
            if(!userData.user){await goto('/login');return;}
            const {data,error}=await supabase.rpc('get_deepmap_account_status');
            if(!error)status=Array.isArray(data)?data[0]:data;
            loading=false;
            if(status && status.is_banned!==true) await goto('/profile');
        })();
        return unsub;
    });
</script>

<svelte:head><title>{t.title} · DeepMap</title><meta name="robots" content="noindex,nofollow" /></svelte:head>
<main class="suspended-page">{#if loading}<div class="card">…</div>{:else if status?.is_banned}<div class="card"><span>DeepMap</span><h1>{t.title}</h1><p>{t.intro}</p><dl><div><dt>{t.reason}</dt><dd>{status.reason||'—'}</dd></div><div><dt>{status.expires_at?t.until:t.permanent}</dt><dd>{status.expires_at?formatDate(status.expires_at):t.permanent}</dd></div></dl><div class="actions"><a href="/">{t.browse}</a><button type="button" onclick={logout}>{t.logout}</button></div></div>{:else}<div class="card"><p>{t.active}</p></div>{/if}</main>
<style>.suspended-page{min-height:70vh;display:grid;place-items:center;padding:28px;color:#eee}.card{width:min(520px,100%);box-sizing:border-box;padding:24px;border:1px solid #5a3a3f;border-radius:14px;background:#121013;box-shadow:0 20px 60px rgba(0,0,0,.35)}.card>span{color:#c8a355;font-size:.7rem;font-weight:900;text-transform:uppercase}.card h1{margin:5px 0 7px}.card p{color:#aaaab3}.card dl{display:grid;gap:8px;margin:18px 0}.card dl div{padding:10px;border:1px solid #333039;border-radius:9px;background:#0d0d10}.card dt{color:#8f8f98;font-size:.68rem}.card dd{margin:4px 0 0;color:#eee}.actions{display:grid;grid-template-columns:1fr 1fr;gap:8px}.card button,.card a{width:100%;box-sizing:border-box;padding:10px;border:1px solid #c8a355;border-radius:8px;background:#211d14;color:#efd184;font-weight:800;cursor:pointer;text-align:center;text-decoration:none}.card button{font:inherit}@media(max-width:520px){.actions{grid-template-columns:1fr}}</style>
