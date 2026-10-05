<script>
    import { tick } from 'svelte';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';

    let { language = 'en', active = false } = $props();

    const TEXT = {
        en: {
            title:'Users', all:'All', users:'Users', moderators:'Moderators', search:'Search @username or name', searchButton:'Search', clear:'Clear', refresh:'Refresh', refreshing:'Refreshing…', refreshed:'Updated just now ✓', perPage:'Per page',
            none:'No users found.', page:'Page', role:'Role', user:'User', moderator:'Moderator', admin:'Admin', joined:'Joined', contributions:'Contributions', pending:'Pending',
            approved:'Approved', rejected:'Rejected', makeModerator:'Make moderator', removeModerator:'Remove moderator', working:'Working…', loadError:'Could not load users.',
            updateError:'Could not update this role.', promoted:'User is now a moderator.', removed:'Moderator access removed.', promoteConfirm:'Make @{username} a moderator?',
            removeConfirm:'Remove moderator access from @{username}?', adminProtected:'Admin accounts cannot be changed here.', openProfile:'Open profile', suspended:'Suspended / banned',
            active:'Active', ban:'Suspend / ban', unban:'Remove suspension', reason:'Reason', duration:'Duration', oneDay:'1 day', sevenDays:'7 days', thirtyDays:'30 days', permanent:'Permanent',
            cancel:'Cancel', confirmBan:'Confirm suspension', banReasonRequired:'Add a reason before confirming.', banError:'Could not suspend this user.', unbanError:'Could not remove the suspension.',
            bannedOk:'User suspended.', unbannedOk:'Suspension removed.', suspendedUntil:'Suspended until', permanentBan:'Permanent suspension'
        },
        pt: {
            title:'Utilizadores', all:'Todos', users:'Utilizadores', moderators:'Moderadores', search:'Procurar @username ou nome', searchButton:'Procurar', clear:'Limpar', refresh:'Atualizar', refreshing:'A atualizar…', refreshed:'Atualizado agora ✓', perPage:'Por página',
            none:'Nenhum utilizador encontrado.', page:'Página', role:'Função', user:'Utilizador', moderator:'Moderador', admin:'Admin', joined:'Membro desde', contributions:'Contribuições', pending:'Pendentes',
            approved:'Aprovadas', rejected:'Reprovadas', makeModerator:'Tornar moderador', removeModerator:'Remover moderador', working:'A processar…', loadError:'Não foi possível carregar os utilizadores.',
            updateError:'Não foi possível alterar esta função.', promoted:'O utilizador é agora moderador.', removed:'Acesso de moderador removido.', promoteConfirm:'Tornar @{username} moderador?',
            removeConfirm:'Remover o acesso de moderador de @{username}?', adminProtected:'As contas de administrador não podem ser alteradas aqui.', openProfile:'Abrir perfil', suspended:'Suspenso / banido',
            active:'Ativo', ban:'Suspender / banir', unban:'Remover suspensão', reason:'Motivo', duration:'Duração', oneDay:'1 dia', sevenDays:'7 dias', thirtyDays:'30 dias', permanent:'Permanente',
            cancel:'Cancelar', confirmBan:'Confirmar suspensão', banReasonRequired:'Indica um motivo antes de confirmar.', banError:'Não foi possível suspender este utilizador.', unbanError:'Não foi possível remover a suspensão.',
            bannedOk:'Utilizador suspenso.', unbannedOk:'Suspensão removida.', suspendedUntil:'Suspenso até', permanentBan:'Suspensão permanente'
        }
    };

    let languageKey = $derived(String(language ?? '').toLowerCase().startsWith('pt') ? 'pt' : 'en');
    let t = $derived(TEXT[languageKey] ?? TEXT.en);
    let roleFilter = $state('all');
    let searchInput = $state('');
    let searchTerm = $state('');
    let page = $state(1);
    let pageSize = $state(10);
    let users = $state([]);
    let total = $state(0);
    let loading = $state(false);
    let refreshFeedback = $state('');
    let refreshTimer;
    let workingId = $state(null);
    let errorMessage = $state('');
    let successMessage = $state('');
    let loadedOnce = false;
    let banEditingId = $state(null);
    let banReason = $state('');
    let banDuration = $state('7d');

    let pageCount = $derived(Math.max(1, Math.ceil(total / pageSize)));

    function roleLabel(role){ if(role==='admin')return t.admin; if(role==='moderator')return t.moderator; return t.user; }
    function formatDate(value){ if(!value)return '—'; const d=new Date(value); if(Number.isNaN(d.getTime()))return '—'; return new Intl.DateTimeFormat(languageKey==='pt'?'pt-PT':'en-GB',{dateStyle:'medium'}).format(d); }
    function visiblePages(){ const maxVisible=5; let start=Math.max(1,page-Math.floor(maxVisible/2)); let end=Math.min(pageCount,start+maxVisible-1); start=Math.max(1,end-maxVisible+1); return Array.from({length:end-start+1},(_,i)=>start+i); }

    async function loadUsers(){
        if(!active || loading)return;
        loading=true; errorMessage='';
        try{
            const {data,error}=await getSupabaseBrowserClient().rpc('get_deepmap_users',{p_role_filter:roleFilter,p_search:searchTerm||null,p_limit:pageSize,p_offset:(page-1)*pageSize});
            if(error)throw error;
            users=(data??[]).map(row=>({
                id:row.user_id, username:row.username??'', displayName:row.display_name??'Explorer', joinedAt:row.joined_at, role:row.role??'user',
                contributions:Number(row.contribution_count??0), pending:Number(row.pending_count??0), approved:Number(row.approved_count??0), rejected:Number(row.rejected_count??0),
                banned:row.is_banned===true, banReason:row.ban_reason??'', banExpiresAt:row.ban_expires_at??null
            }));
            total=data?.length?Number(data[0].total_count??0):0;
            if(page>pageCount)page=pageCount;
        }catch(error){console.error('DeepMap users admin:',error);users=[];total=0;errorMessage=t.loadError;}
        finally{loading=false;}
    }

    async function refreshUsers(){
        if(loading||workingId!==null)return;
        refreshFeedback='';
        if(refreshTimer)clearTimeout(refreshTimer);
        await loadUsers();
        if(!errorMessage){
            refreshFeedback=t.refreshed;
            refreshTimer=setTimeout(()=>{refreshFeedback='';},2200);
        }
    }

    async function handlePageSizeChange(){
        page=1;
        banEditingId=null;
        await tick();
        await loadUsers();
    }

    async function setFilter(next){ if(roleFilter===next&&page===1)return; roleFilter=next; page=1; banEditingId=null; await loadUsers(); }
    async function submitSearch(event){event?.preventDefault?.();searchTerm=searchInput.trim().toLowerCase();page=1;banEditingId=null;await loadUsers();}
    async function clearSearch(){searchInput='';searchTerm='';page=1;banEditingId=null;await loadUsers();}
    async function goPage(next){if(next<1||next>pageCount||next===page)return;page=next;banEditingId=null;await loadUsers();}

    async function toggleModerator(user){
        if(!user||workingId||user.role==='admin')return;
        const enable=user.role!=='moderator';
        const template=enable?t.promoteConfirm:t.removeConfirm;
        if(!window.confirm(template.replace('{username}',user.username||user.displayName||'user')))return;
        workingId=user.id;errorMessage='';successMessage='';
        try{
            const {error}=await getSupabaseBrowserClient().rpc('set_deepmap_moderator',{p_user_id:user.id,p_enabled:enable});
            if(error)throw error;
            successMessage=enable?t.promoted:t.removed;
            await loadUsers();
        }catch(error){console.error('DeepMap moderator role update:',error);errorMessage=t.updateError;}
        finally{workingId=null;}
    }

    function openBanEditor(user){
        if(user.role==='admin')return;
        if(user.banned){ void clearBan(user); return; }
        banEditingId=user.id;banReason='';banDuration='7d';errorMessage='';successMessage='';
    }

    function cancelBan(){banEditingId=null;banReason='';banDuration='7d';}

    function expiryForDuration(){
        if(banDuration==='permanent')return null;
        const days=banDuration==='1d'?1:banDuration==='30d'?30:7;
        return new Date(Date.now()+days*24*60*60*1000).toISOString();
    }

    async function confirmBan(user){
        if(!user||workingId)return;
        if(!banReason.trim()){errorMessage=t.banReasonRequired;return;}
        workingId=user.id;errorMessage='';successMessage='';
        try{
            const {error}=await getSupabaseBrowserClient().rpc('set_deepmap_user_ban',{p_user_id:user.id,p_reason:banReason.trim(),p_expires_at:expiryForDuration()});
            if(error)throw error;
            successMessage=t.bannedOk;cancelBan();await loadUsers();
        }catch(error){console.error('DeepMap user ban:',error);errorMessage=t.banError;}
        finally{workingId=null;}
    }

    async function clearBan(user){
        if(!user||workingId||user.role==='admin')return;
        if(!window.confirm(`${t.unban}: @${user.username||user.displayName}?`))return;
        workingId=user.id;errorMessage='';successMessage='';
        try{
            const {error}=await getSupabaseBrowserClient().rpc('clear_deepmap_user_ban',{p_user_id:user.id});
            if(error)throw error;
            successMessage=t.unbannedOk;await loadUsers();
        }catch(error){console.error('DeepMap user unban:',error);errorMessage=t.unbanError;}
        finally{workingId=null;}
    }

    $effect(()=>{if(!active||loadedOnce)return;loadedOnce=true;void loadUsers();});
</script>

{#if active}
<section class="users-panel" aria-label={t.title}>
    <div class="panel-heading"><div><span class="eyebrow">DeepMap</span><strong>{t.title}</strong></div><div class="heading-actions"><label class="page-size"><span>{t.perPage}</span><select bind:value={pageSize} onchange={handlePageSizeChange} disabled={loading||workingId!==null}><option value={10}>10</option><option value={20}>20</option><option value={50}>50</option></select></label><div class="refresh-control"><button class="small-button" type="button" onclick={refreshUsers} disabled={loading||workingId!==null}>{loading?t.refreshing:t.refresh}</button>{#if refreshFeedback}<small class="refresh-feedback" role="status">{refreshFeedback}</small>{/if}</div></div></div>
    <div class="role-tabs" role="tablist" aria-label={t.role}><button class:active={roleFilter==='all'} type="button" onclick={()=>setFilter('all')}>{t.all}</button><button class:active={roleFilter==='user'} type="button" onclick={()=>setFilter('user')}>{t.users}</button><button class:active={roleFilter==='moderator'} type="button" onclick={()=>setFilter('moderator')}>{t.moderators}</button></div>
    <form class="search-row" onsubmit={submitSearch}><input bind:value={searchInput} placeholder={t.search} autocomplete="off" spellcheck="false"/><button type="submit" disabled={loading}>{t.searchButton}</button>{#if searchTerm}<button class="clear-button" type="button" onclick={clearSearch} disabled={loading}>{t.clear}</button>{/if}</form>
    {#if errorMessage}<p class="message error" role="alert">{errorMessage}</p>{/if}{#if successMessage}<p class="message success" role="status">{successMessage}</p>{/if}

    {#if loading && !users.length}<div class="empty-state">…</div>
    {:else if !users.length}<div class="empty-state">{t.none}</div>
    {:else}
        <div class="user-list">
            {#each users as user (user.id)}
                <article class="user-card">
                    <div class="user-main"><div class="identity"><strong>{user.username?`@${user.username}`:'—'}</strong><span>{user.displayName}</span></div><div class="badges"><span class:admin={user.role==='admin'} class:moderator={user.role==='moderator'} class="role-badge">{roleLabel(user.role)}</span>{#if user.banned}<span class="ban-badge">{t.suspended}</span>{/if}</div></div>
                    <div class="user-meta"><span>{t.joined}<strong>{formatDate(user.joinedAt)}</strong></span><span>{t.contributions}<strong>{user.contributions}</strong></span><span>{t.pending}<strong>{user.pending}</strong></span><span>{t.approved}<strong>{user.approved}</strong></span><span>{t.rejected}<strong>{user.rejected}</strong></span></div>
                    {#if user.banned}<div class="ban-summary"><strong>{user.banExpiresAt?`${t.suspendedUntil} ${formatDate(user.banExpiresAt)}`:t.permanentBan}</strong><span>{user.banReason||'—'}</span></div>{/if}
                    <div class="user-actions">
                        {#if user.username}<a href={`/u/${encodeURIComponent(user.username)}`} target="_blank" rel="noreferrer">{t.openProfile}</a>{/if}
                        {#if user.role==='admin'}<span class="admin-note">{t.adminProtected}</span>
                        {:else}
                            <button class:remove={user.role==='moderator'} type="button" onclick={()=>toggleModerator(user)} disabled={workingId!==null}>{workingId===user.id?t.working:(user.role==='moderator'?t.removeModerator:t.makeModerator)}</button>
                            <button class:danger={!user.banned} class:restore={user.banned} type="button" onclick={()=>openBanEditor(user)} disabled={workingId!==null}>{user.banned?t.unban:t.ban}</button>
                        {/if}
                    </div>
                    {#if banEditingId===user.id}
                        <div class="ban-editor">
                            <label><span>{t.reason} *</span><textarea rows="2" bind:value={banReason}></textarea></label>
                            <label><span>{t.duration}</span><select bind:value={banDuration}><option value="1d">{t.oneDay}</option><option value="7d">{t.sevenDays}</option><option value="30d">{t.thirtyDays}</option><option value="permanent">{t.permanent}</option></select></label>
                            <div><button class="danger solid" type="button" onclick={()=>confirmBan(user)} disabled={workingId!==null}>{t.confirmBan}</button><button type="button" onclick={cancelBan} disabled={workingId!==null}>{t.cancel}</button></div>
                        </div>
                    {/if}
                </article>
            {/each}
        </div>
    {/if}

    {#if total>pageSize}<nav class="pagination" aria-label={`${t.page} ${page}`}><button type="button" onclick={()=>goPage(page-1)} disabled={loading||page<=1}>‹</button>{#each visiblePages() as p}<button class:active={p===page} type="button" onclick={()=>goPage(p)} disabled={loading}>{p}</button>{/each}<button type="button" onclick={()=>goPage(page+1)} disabled={loading||page>=pageCount}>›</button></nav>{/if}
</section>
{/if}

<style>
.users-panel{display:grid;gap:11px;padding:14px;border:1px solid rgba(200,163,85,.45);border-radius:10px;background:#101014;color:#eee}.panel-heading{display:flex;align-items:center;justify-content:space-between;gap:10px}.panel-heading>div:first-child{display:grid;gap:2px}.heading-actions{display:flex;align-items:flex-end;gap:8px}.page-size{display:grid;gap:3px;min-width:110px}.page-size span{color:#888;font-size:.62rem;white-space:nowrap}.page-size select{width:100%;padding:6px 28px 6px 8px;border:1px solid #3a3a45;border-radius:8px;background:#17171c;color:#ddd}.refresh-control{display:grid;justify-items:end;gap:3px}.refresh-feedback{color:#8fd3a3;font-size:.62rem;font-weight:800;white-space:nowrap}.eyebrow{color:#c8a355;font-size:.68rem;font-weight:900;text-transform:uppercase}.small-button,.role-tabs button,.search-row button,.user-actions button,.user-actions a,.pagination button,.ban-editor button{border:1px solid #3a3a45;border-radius:8px;background:#17171c;color:#ddd;cursor:pointer;text-decoration:none}.small-button{padding:7px 10px}.role-tabs{display:grid;grid-template-columns:repeat(3,1fr);gap:6px}.role-tabs button{padding:8px;font-weight:800}.role-tabs button.active,.pagination button.active{border-color:#c8a355;background:#211d14;color:#f1d58e}.search-row{display:grid;grid-template-columns:minmax(0,1fr) auto auto;gap:7px}.search-row input,.ban-editor textarea,.ban-editor select{width:100%;box-sizing:border-box;padding:8px;border:1px solid #34343e;border-radius:8px;background:#0d0d11;color:#eee}.search-row button{padding:8px 10px}.user-list{display:grid;gap:8px}.user-card{display:grid;gap:9px;padding:11px;border:1px solid #303039;border-radius:10px;background:#0c0c10}.user-main{display:flex;align-items:flex-start;justify-content:space-between;gap:10px}.identity{display:grid}.identity strong{color:#e8cf8d}.identity span{color:#aaa;font-size:.72rem}.badges{display:flex;gap:5px;flex-wrap:wrap;justify-content:flex-end}.role-badge,.ban-badge{padding:4px 7px;border:1px solid #41414b;border-radius:999px;color:#aaa;font-size:.62rem;font-weight:900;text-transform:uppercase}.role-badge.moderator{border-color:#66593b;color:#d8b86f}.role-badge.admin{border-color:#7a5f2a;background:#241e12;color:#f0d28a}.ban-badge{border-color:#704047;background:#281519;color:#ffb4bd}.user-meta{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:6px}.user-meta span{display:grid;color:#777;font-size:.62rem}.user-meta strong{color:#ddd;font-size:.75rem}.ban-summary{display:grid;gap:3px;padding:8px;border:1px solid #56353a;border-radius:8px;background:#211216}.ban-summary strong{color:#ffb4bd;font-size:.72rem}.ban-summary span{color:#c7a7ab;font-size:.72rem}.user-actions{display:flex;gap:7px;align-items:center;flex-wrap:wrap}.user-actions button,.user-actions a{padding:7px 9px;font-size:.7rem}.user-actions button.remove{border-color:#66593b;color:#d8b86f}.user-actions button.danger,.ban-editor button.danger{border-color:#704047;color:#ffc0c8}.user-actions button.restore{border-color:#476b4f;color:#bcebc7}.admin-note{color:#777;font-size:.68rem}.ban-editor{display:grid;grid-template-columns:minmax(0,1fr) 170px;gap:8px;padding:9px;border:1px solid #56353a;border-radius:9px;background:#151014}.ban-editor label{display:grid;gap:4px}.ban-editor label span{color:#aaa;font-size:.68rem;font-weight:700}.ban-editor>div{grid-column:1/-1;display:flex;gap:7px}.ban-editor button{padding:8px 10px}.ban-editor button.solid{background:#7d3942;color:#fff}.message{margin:0;padding:8px;border-radius:8px;font-size:.76rem}.message.error{background:#2b1519;color:#ffc0c8}.message.success{background:#15251a;color:#bcebc7}.empty-state{min-height:110px;display:grid;place-items:center;border:1px solid #303039;border-radius:10px;background:#0c0c10;color:#8f8f98}.pagination{display:flex;justify-content:center;gap:5px;flex-wrap:wrap}.pagination button{min-width:32px;height:32px}.small-button:disabled,.role-tabs button:disabled,.search-row button:disabled,.user-actions button:disabled,.pagination button:disabled,.ban-editor button:disabled{opacity:.5;cursor:not-allowed}
@media(max-width:700px){.panel-heading{align-items:stretch;flex-direction:column}.heading-actions{display:grid;grid-template-columns:auto minmax(0,1fr);align-items:end}.refresh-control{justify-items:stretch}.refresh-feedback{text-align:center}.user-meta{grid-template-columns:repeat(2,minmax(0,1fr))}.search-row{grid-template-columns:1fr 1fr}.search-row input{grid-column:1/-1}.ban-editor{grid-template-columns:1fr}.ban-editor>div{grid-column:auto}.user-actions>*{flex:1;text-align:center}.user-main{align-items:flex-start}.badges{max-width:48%}}
</style>
