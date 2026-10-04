<script>
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';

    let { language = 'en', active = true } = $props();
    const PAGE_SIZE = 25;

    const TEXT = {
        en: { title:'Audit log', refresh:'Refresh', none:'No audit events yet.', page:'Page', loadError:'Could not load audit log.', actor:'By', target:'Target', game:'Game', submission:'Submission' },
        pt: { title:'Histórico administrativo', refresh:'Atualizar', none:'Ainda não existem eventos de auditoria.', page:'Página', loadError:'Não foi possível carregar o histórico.', actor:'Por', target:'Alvo', game:'Jogo', submission:'Submissão' }
    };
    let t = $derived(TEXT[language] ?? TEXT.en);
    let items = $state([]);
    let total = $state(0);
    let page = $state(1);
    let loading = $state(false);
    let errorMessage = $state('');
    let loadedOnce = false;
    let pageCount = $derived(Math.max(1, Math.ceil(total / PAGE_SIZE)));

    function formatDate(value){
        if(!value) return '—';
        const date = new Date(value);
        if(Number.isNaN(date.getTime())) return '—';
        return new Intl.DateTimeFormat(language === 'pt' ? 'pt-PT' : 'en-GB',{dateStyle:'medium',timeStyle:'short'}).format(date);
    }

    function label(action){
        const pt = language === 'pt';
        const labels = {
            moderator_granted: pt ? 'Moderador atribuído' : 'Moderator granted',
            moderator_revoked: pt ? 'Moderador removido' : 'Moderator revoked',
            user_banned: pt ? 'Utilizador suspenso/banido' : 'User suspended/banned',
            user_unbanned: pt ? 'Suspensão removida' : 'Suspension removed',
            submission_approved: pt ? 'Submissão aprovada' : 'Submission approved',
            submission_rejected: pt ? 'Submissão rejeitada' : 'Submission rejected'
        };
        return labels[action] ?? action;
    }

    function visiblePages(){
        const maxVisible=5;
        let start=Math.max(1,page-Math.floor(maxVisible/2));
        let end=Math.min(pageCount,start+maxVisible-1);
        start=Math.max(1,end-maxVisible+1);
        return Array.from({length:end-start+1},(_,i)=>start+i);
    }

    async function load(){
        if(!active || loading) return;
        loading=true; errorMessage='';
        try{
            const {data,error}=await getSupabaseBrowserClient().rpc('get_deepmap_admin_audit',{p_limit:PAGE_SIZE,p_offset:(page-1)*PAGE_SIZE});
            if(error) throw error;
            items=data ?? [];
            total=items.length ? Number(items[0].total_count ?? 0) : 0;
        }catch(error){
            console.error('DeepMap admin audit:',error);
            items=[]; total=0; errorMessage=t.loadError;
        }finally{loading=false;}
    }

    async function goPage(next){ if(next<1||next>pageCount||next===page)return; page=next; await load(); }

    $effect(()=>{ if(!active || loadedOnce)return; loadedOnce=true; void load(); });
</script>

{#if active}
<section class="audit-panel">
    <div class="heading"><div><span>DeepMap</span><h2>{t.title}</h2></div><button type="button" onclick={load} disabled={loading}>{t.refresh}</button></div>
    {#if errorMessage}<p class="error">{errorMessage}</p>{/if}
    {#if loading && !items.length}<div class="empty">…</div>
    {:else if !items.length}<div class="empty">{t.none}</div>
    {:else}
        <div class="events">
            {#each items as item (item.event_id)}
                <article>
                    <div class="event-title"><strong>{label(item.action)}</strong><time>{formatDate(item.created_at)}</time></div>
                    <div class="meta">
                        {#if item.actor_username}<span>{t.actor}: <b>@{item.actor_username}</b></span>{/if}
                        {#if item.target_username}<span>{t.target}: <b>@{item.target_username}</b></span>{/if}
                        {#if item.game_id}<span>{t.game}: <b>{item.game_id}</b></span>{/if}
                        {#if item.submission_id}<span>{t.submission}: <b>#{item.submission_id}</b></span>{/if}
                    </div>
                    {#if item.detail}<p>{item.detail}</p>{/if}
                </article>
            {/each}
        </div>
        {#if total>PAGE_SIZE}<nav class="pagination"><button type="button" onclick={()=>goPage(page-1)} disabled={page<=1}>‹</button>{#each visiblePages() as p}<button class:active={p===page} type="button" onclick={()=>goPage(p)}>{p}</button>{/each}<button type="button" onclick={()=>goPage(page+1)} disabled={page>=pageCount}>›</button></nav>{/if}
    {/if}
</section>
{/if}

<style>
.audit-panel{display:grid;gap:14px;color:#eee}.heading{display:flex;justify-content:space-between;align-items:flex-end;gap:10px}.heading span{color:#c8a355;font-size:.68rem;font-weight:900;text-transform:uppercase}.heading h2{margin:2px 0 0}.heading button,.pagination button{border:1px solid #3b3b45;border-radius:8px;background:#17171c;color:#ddd;padding:8px 10px;cursor:pointer}.events{display:grid;gap:8px}.events article{padding:11px;border:1px solid #303039;border-radius:10px;background:#101014}.event-title{display:flex;justify-content:space-between;gap:10px}.event-title strong{color:#e8cf8d}.event-title time{color:#777;font-size:.68rem}.meta{display:flex;gap:12px;flex-wrap:wrap;margin-top:6px;color:#92929c;font-size:.72rem}.meta b{color:#d0d0d7}.events p{margin:7px 0 0;color:#aaaab3;font-size:.76rem}.empty{min-height:130px;display:grid;place-items:center;border:1px solid #303039;border-radius:10px;background:#101014;color:#92929c}.error{padding:9px;border-radius:8px;background:#2b1519;color:#ffc0c8}.pagination{display:flex;justify-content:center;gap:5px}.pagination button{min-width:32px}.pagination button.active{border-color:#c8a355;background:#211d14;color:#f0d28a}@media(max-width:600px){.event-title{display:grid}.heading{align-items:stretch;flex-direction:column}.heading button{width:100%}}
</style>
