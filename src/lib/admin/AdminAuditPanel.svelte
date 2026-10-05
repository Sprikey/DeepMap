<script>
    import { tick } from 'svelte';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';

    let { language = 'en', active = true } = $props();

    const TEXT = {
        en: {
            title:'Audit log', refresh:'Refresh', refreshing:'Refreshing…', refreshed:'Updated now ✓', none:'No audit events yet.', page:'Page', loadError:'Could not load audit log.',
            actor:'By', target:'Target', game:'Game', submission:'Submission', date:'Date', details:'Details', close:'Close', reason:'Reason', note:'Note', suspendedUntil:'Suspended until', permanent:'Permanent suspension', event:'Event', perPage:'Per page', proposal:'Submitted proposal', revisions:'Revision history', loadingDetails:'Loading details…', noExtraDetails:'No extra submission details available.'
        },
        pt: {
            title:'Histórico administrativo', refresh:'Atualizar', refreshing:'A atualizar…', refreshed:'Atualizado agora ✓', none:'Ainda não existem eventos de auditoria.', page:'Página', loadError:'Não foi possível carregar o histórico.',
            actor:'Por', target:'Alvo', game:'Jogo', submission:'Submissão', date:'Data', details:'Detalhes', close:'Fechar', reason:'Motivo', note:'Nota', suspendedUntil:'Suspenso até', permanent:'Suspensão permanente', event:'Evento', perPage:'Por página', proposal:'Proposta submetida', revisions:'Histórico de versões', loadingDetails:'A carregar detalhes…', noExtraDetails:'Sem detalhes adicionais disponíveis para esta submissão.'
        }
    };

    let languageKey = $derived(String(language ?? '').toLowerCase().startsWith('pt') ? 'pt' : 'en');
    let t = $derived(TEXT[languageKey] ?? TEXT.en);
    let items = $state([]);
    let total = $state(0);
    let page = $state(1);
    let pageSize = $state(10);
    let loading = $state(false);
    let errorMessage = $state('');
    let loadedOnce = false;
    let pageCount = $derived(Math.max(1, Math.ceil(total / pageSize)));
    let expandedId = $state(null);
    let refreshFeedback = $state('');
    let refreshTimer;
    let detailCache = $state({});

    function formatDate(value){
        if(!value) return '—';
        const date = new Date(value);
        if(Number.isNaN(date.getTime())) return '—';
        return new Intl.DateTimeFormat(languageKey === 'pt' ? 'pt-PT' : 'en-GB',{dateStyle:'medium',timeStyle:'short'}).format(date);
    }

    function label(action){
        const pt = languageKey === 'pt';
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

    function parseBanDetail(detail){
        const raw = String(detail ?? '').trim();
        if(!raw) return { reason:'', expiresAt:null, permanent:false, fallback:'' };

        const untilMatch = raw.match(/^(.*?)\s*·\s*until\s+(.+)$/i);
        if(untilMatch){
            return { reason:untilMatch[1].trim(), expiresAt:untilMatch[2].trim(), permanent:false, fallback:'' };
        }

        const permanentMatch = raw.match(/^(.*?)\s*·\s*permanent\s*$/i);
        if(permanentMatch){
            return { reason:permanentMatch[1].trim(), expiresAt:null, permanent:true, fallback:'' };
        }

        return { reason:raw, expiresAt:null, permanent:false, fallback:raw };
    }

    function detailInfo(item){
        if(item?.action === 'user_banned') return parseBanDetail(item.detail);
        return { reason:'', expiresAt:null, permanent:false, fallback:String(item?.detail ?? '').trim() };
    }

    function prettyValue(value){
        if(value == null || value === '') return '—';
        if(Array.isArray(value)) return value.length ? JSON.stringify(value, null, 2) : '—';
        if(typeof value === 'object') return JSON.stringify(value, null, 2);
        return String(value);
    }

    function payloadEntries(payload){
        if(!payload || typeof payload !== 'object') return [];
        const preferred=['title_en','title_pt','category_id','map_layer','region_id','description_en','description_pt','video_url','coordinate_x','coordinate_y','image_url','image_action','target_image_id','content_items'];
        const keys=[...preferred.filter((key)=>key in payload),...Object.keys(payload).filter((key)=>!preferred.includes(key))];
        return keys.map((key)=>({key,value:payload[key]}));
    }

    async function loadSubmissionDetail(item){
        if(!item?.submission_id || detailCache[item.event_id]?.loaded || detailCache[item.event_id]?.loading) return;
        detailCache={...detailCache,[item.event_id]:{loading:true,loaded:false,submission:null,revisions:[],error:''}};
        try{
            const supabase=getSupabaseBrowserClient();
            const [{data:submission,error:submissionError},{data:revisions,error:revisionError}]=await Promise.all([
                supabase.from('marker_submissions').select('id, game_id, marker_id, submission_type, correction_kind, status, payload, note, review_note, created_at, reviewed_at, updated_at').eq('id',item.submission_id).maybeSingle(),
                supabase.rpc('get_marker_submission_revisions',{p_submission_id:item.submission_id})
            ]);
            if(submissionError) throw submissionError;
            if(revisionError) throw revisionError;
            detailCache={...detailCache,[item.event_id]:{loading:false,loaded:true,submission:submission??null,revisions:revisions??[],error:''}};
        }catch(error){
            console.warn('DeepMap admin audit submission detail:',error);
            detailCache={...detailCache,[item.event_id]:{loading:false,loaded:true,submission:null,revisions:[],error:t.noExtraDetails}};
        }
    }

    function visiblePages(){
        const maxVisible=5;
        let start=Math.max(1,page-Math.floor(maxVisible/2));
        let end=Math.min(pageCount,start+maxVisible-1);
        start=Math.max(1,end-maxVisible+1);
        return Array.from({length:end-start+1},(_,i)=>start+i);
    }

    async function load({ manual = false } = {}){
        if(!active || loading) return;
        loading=true; errorMessage='';
        if(manual){
            refreshFeedback='';
            if(refreshTimer) clearTimeout(refreshTimer);
        }
        try{
            const {data,error}=await getSupabaseBrowserClient().rpc('get_deepmap_admin_audit',{p_limit:pageSize,p_offset:(page-1)*pageSize});
            if(error) throw error;
            items=data ?? [];
            total=items.length ? Number(items[0].total_count ?? 0) : 0;
            if(expandedId && !items.some((item)=>item.event_id===expandedId)) expandedId=null;
            if(manual){
                refreshFeedback=t.refreshed;
                refreshTimer=setTimeout(()=>{refreshFeedback='';},2200);
            }
        }catch(error){
            console.error('DeepMap admin audit:',error);
            items=[]; total=0; errorMessage=t.loadError;
        }finally{loading=false;}
    }

    async function refresh(){ await load({manual:true}); }
    async function handlePageSizeChange(){ page=1;expandedId=null;await tick();await load(); }
    async function goPage(next){ if(next<1||next>pageCount||next===page)return; page=next; expandedId=null; await load(); }
    async function toggleDetails(item){
        const id=item.event_id;
        if(expandedId===id){expandedId=null;return;}
        expandedId=id;
        if(item.submission_id) await loadSubmissionDetail(item);
    }

    $effect(()=>{ if(!active || loadedOnce)return; loadedOnce=true; void load(); });
</script>

{#if active}
<section class="audit-panel">
    <div class="heading">
        <div><span>DeepMap</span><h2>{t.title}</h2></div>
        <div class="heading-actions">
            <label class="page-size"><span>{t.perPage}</span><select bind:value={pageSize} onchange={handlePageSizeChange} disabled={loading}><option value={10}>10</option><option value={20}>20</option><option value={50}>50</option></select></label>
            <div class="refresh-control">
                <button type="button" onclick={refresh} disabled={loading}>{loading?t.refreshing:t.refresh}</button>
                {#if refreshFeedback}<small class="refresh-feedback" role="status">{refreshFeedback}</small>{/if}
            </div>
        </div>
    </div>
    {#if errorMessage}<p class="error">{errorMessage}</p>{/if}
    {#if loading && !items.length}<div class="empty">…</div>
    {:else if !items.length}<div class="empty">{t.none}</div>
    {:else}
        <div class="events">
            {#each items as item (item.event_id)}
                {@const info = detailInfo(item)}
                <article class:expanded={expandedId===item.event_id}>
                    <button class="event-summary" type="button" onclick={()=>toggleDetails(item)} aria-expanded={expandedId===item.event_id}>
                        <span class="event-title"><strong>{label(item.action)}</strong><time>{formatDate(item.created_at)}</time></span>
                        <span class="meta">
                            {#if item.actor_username}<span>{t.actor}: <b>@{item.actor_username}</b></span>{/if}
                            {#if item.target_username}<span>{t.target}: <b>@{item.target_username}</b></span>{/if}
                            {#if item.game_id}<span>{t.game}: <b>{item.game_id}</b></span>{/if}
                            {#if item.submission_id}<span>{t.submission}: <b>#{item.submission_id}</b></span>{/if}
                        </span>
                        <span class="expand-label">{expandedId===item.event_id?t.close:t.details} <b>{expandedId===item.event_id?'−':'+'}</b></span>
                    </button>

                    {#if expandedId===item.event_id}
                        <div class="event-details">
                            <dl>
                                <div><dt>{t.event}</dt><dd>{label(item.action)}</dd></div>
                                <div><dt>{t.date}</dt><dd>{formatDate(item.created_at)}</dd></div>
                                {#if item.actor_username}<div><dt>{t.actor}</dt><dd>@{item.actor_username}</dd></div>{/if}
                                {#if item.target_username}<div><dt>{t.target}</dt><dd>@{item.target_username}</dd></div>{/if}
                                {#if item.game_id}<div><dt>{t.game}</dt><dd>{item.game_id}</dd></div>{/if}
                                {#if item.submission_id}<div><dt>{t.submission}</dt><dd>#{item.submission_id}</dd></div>{/if}
                                {#if item.action==='user_banned'}
                                    {#if info.reason}<div class="wide"><dt>{t.reason}</dt><dd>{info.reason}</dd></div>{/if}
                                    <div class="wide"><dt>{info.permanent?t.permanent:t.suspendedUntil}</dt><dd>{info.permanent?t.permanent:(info.expiresAt?formatDate(info.expiresAt):'—')}</dd></div>
                                {:else if info.fallback}
                                    <div class="wide"><dt>{item.action?.startsWith('submission_')?t.note:t.details}</dt><dd>{info.fallback}</dd></div>
                                {/if}
                            </dl>
                            {#if item.submission_id}
                                {@const detail = detailCache[item.event_id]}
                                {#if detail?.loading}<p class="detail-loading">{t.loadingDetails}</p>
                                {:else if detail?.submission}
                                    <section class="submission-detail">
                                        <strong>{t.proposal}</strong>
                                        {#if detail.submission.note}<p><b>{t.note}:</b> {detail.submission.note}</p>{/if}
                                        {#if detail.submission.review_note}<p><b>{t.reason}:</b> {detail.submission.review_note}</p>{/if}
                                        <div class="payload-grid">
                                            {#each payloadEntries(detail.submission.payload) as entry}
                                                <div><span>{entry.key}</span><pre>{prettyValue(entry.value)}</pre></div>
                                            {/each}
                                        </div>
                                    </section>
                                    {#if detail.revisions?.length}
                                        <section class="submission-detail">
                                            <strong>{t.revisions}</strong>
                                            {#each detail.revisions as revision}
                                                <article class="revision"><header><b>#{revision.revision_no}</b><span>{revision.edited_username?`@${revision.edited_username}`:'—'} · {formatDate(revision.created_at)}</span></header>{#if revision.note}<p>{revision.note}</p>{/if}<div class="payload-grid">{#each payloadEntries(revision.payload) as entry}<div><span>{entry.key}</span><pre>{prettyValue(entry.value)}</pre></div>{/each}</div></article>
                                            {/each}
                                        </section>
                                    {/if}
                                {:else if detail?.loaded}<p class="detail-loading">{detail.error||t.noExtraDetails}</p>{/if}
                            {/if}
                        </div>
                    {/if}
                </article>
            {/each}
        </div>
        {#if total>pageSize}<nav class="pagination"><button type="button" onclick={()=>goPage(page-1)} disabled={loading||page<=1}>‹</button>{#each visiblePages() as p}<button class:active={p===page} type="button" onclick={()=>goPage(p)} disabled={loading}>{p}</button>{/each}<button type="button" onclick={()=>goPage(page+1)} disabled={loading||page>=pageCount}>›</button></nav>{/if}
    {/if}
</section>
{/if}

<style>
.audit-panel{display:grid;gap:14px;color:#eee}.heading{display:flex;justify-content:space-between;align-items:flex-end;gap:10px}.heading span{color:#c8a355;font-size:.68rem;font-weight:900;text-transform:uppercase}.heading h2{margin:2px 0 0}.heading-actions{display:flex;align-items:flex-end;gap:8px}.page-size{display:grid;gap:3px;min-width:110px}.page-size span{color:#888;font-size:.62rem;white-space:nowrap}.page-size select{width:100%;padding:7px 28px 7px 8px;border:1px solid #3b3b45;border-radius:8px;background:#17171c;color:#ddd}.heading button,.pagination button{border:1px solid #3b3b45;border-radius:8px;background:#17171c;color:#ddd;padding:8px 10px;cursor:pointer}.refresh-control{display:grid;justify-items:end;gap:4px}.refresh-feedback{color:#8fd3a3;font-size:.64rem;font-weight:800;white-space:nowrap}.events{display:grid;gap:8px}.events article{border:1px solid #303039;border-radius:10px;background:#101014;overflow:hidden}.events article.expanded{border-color:#5b5037}.event-summary{display:grid;width:100%;padding:11px;border:0;background:transparent;color:inherit;text-align:left;cursor:pointer}.event-title{display:flex;justify-content:space-between;gap:10px}.event-title strong{color:#e8cf8d}.event-title time{color:#777;font-size:.68rem}.meta{display:flex;gap:12px;flex-wrap:wrap;margin-top:6px;color:#92929c;font-size:.72rem}.meta b{color:#d0d0d7}.expand-label{justify-self:end;margin-top:7px;color:#c8a355;font-size:.67rem;font-weight:800}.expand-label b{font-size:.9rem}.event-details{padding:0 11px 11px;border-top:1px solid #292931}.event-details dl{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:7px;margin:10px 0 0}.event-details dl>div{display:grid;gap:2px;padding:8px;border:1px solid #292931;border-radius:8px;background:#0c0c10}.event-details dl>div.wide{grid-column:1/-1}.event-details dt{color:#7f7f89;font-size:.64rem;font-weight:800;text-transform:uppercase;letter-spacing:.04em}.event-details dd{margin:0;color:#d8d8de;font-size:.75rem;overflow-wrap:anywhere}.detail-loading{margin:10px 0 0;color:#8f8f98;font-size:.74rem}.submission-detail{display:grid;gap:8px;margin-top:10px;padding:10px;border:1px solid #292931;border-radius:9px;background:#0b0b0f}.submission-detail>strong{color:#d8b86f}.submission-detail>p{margin:0;color:#c5c5cc;font-size:.74rem}.payload-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:6px}.payload-grid>div{min-width:0;padding:7px;border:1px solid #25252d;border-radius:7px;background:#111116}.payload-grid span{display:block;margin-bottom:3px;color:#777;font-size:.61rem;font-weight:800;text-transform:uppercase}.payload-grid pre{margin:0;white-space:pre-wrap;overflow-wrap:anywhere;color:#d8d8de;font:inherit;font-size:.7rem}.revision{padding:8px;border:1px solid #26262e;border-radius:8px;background:#101014}.revision header{display:flex;justify-content:space-between;gap:8px}.revision header span{color:#777;font-size:.64rem}.revision p{margin:5px 0;color:#bbb;font-size:.72rem}.empty{min-height:130px;display:grid;place-items:center;border:1px solid #303039;border-radius:10px;background:#101014;color:#92929c}.error{padding:9px;border-radius:8px;background:#2b1519;color:#ffc0c8}.pagination{display:flex;justify-content:center;gap:5px}.pagination button{min-width:32px}.pagination button.active{border-color:#c8a355;background:#211d14;color:#f0d28a}.heading button:disabled,.pagination button:disabled{opacity:.55;cursor:not-allowed}@media(max-width:600px){.event-title{display:grid}.heading{align-items:stretch;flex-direction:column}.heading-actions{display:grid;grid-template-columns:auto minmax(0,1fr);align-items:end}.payload-grid{grid-template-columns:1fr}.refresh-control{width:100%;justify-items:stretch}.refresh-control button{width:100%}.refresh-feedback{text-align:center}.event-details dl{grid-template-columns:1fr}.event-details dl>div.wide{grid-column:auto}}
</style>
