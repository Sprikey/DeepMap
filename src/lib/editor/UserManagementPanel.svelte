<script>
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';

    let {
        language = 'en',
        active = false
    } = $props();

    const PAGE_SIZE = 20;

    const TEXT = {
        en: {
            title: 'Users', all: 'All', users: 'Users', moderators: 'Moderators', search: 'Search @username',
            searchButton: 'Search', clear: 'Clear', refresh: 'Refresh', none: 'No users found.', page: 'Page',
            role: 'Role', user: 'User', moderator: 'Moderator', admin: 'Admin', joined: 'Joined',
            contributions: 'Contributions', pending: 'Pending', approved: 'Approved', rejected: 'Rejected',
            makeModerator: 'Make moderator', removeModerator: 'Remove moderator', working: 'Working…',
            loadError: 'Could not load users.', updateError: 'Could not update this role.',
            promoted: 'User is now a moderator.', removed: 'Moderator access removed.',
            promoteConfirm: 'Make @{username} a moderator?', removeConfirm: 'Remove moderator access from @{username}?',
            adminProtected: 'Admin roles cannot be changed here.', openProfile: 'Open profile'
        },
        pt: {
            title: 'Utilizadores', all: 'Todos', users: 'Utilizadores', moderators: 'Moderadores', search: 'Procurar @username',
            searchButton: 'Procurar', clear: 'Limpar', refresh: 'Atualizar', none: 'Nenhum utilizador encontrado.', page: 'Página',
            role: 'Função', user: 'Utilizador', moderator: 'Moderador', admin: 'Admin', joined: 'Membro desde',
            contributions: 'Contribuições', pending: 'Pendentes', approved: 'Aprovadas', rejected: 'Reprovadas',
            makeModerator: 'Tornar moderador', removeModerator: 'Remover moderador', working: 'A processar…',
            loadError: 'Não foi possível carregar os utilizadores.', updateError: 'Não foi possível alterar esta função.',
            promoted: 'O utilizador é agora moderador.', removed: 'Acesso de moderador removido.',
            promoteConfirm: 'Tornar @{username} moderador?', removeConfirm: 'Remover o acesso de moderador de @{username}?',
            adminProtected: 'As funções de administrador não podem ser alteradas aqui.', openProfile: 'Abrir perfil'
        }
    };

    let t = $derived(TEXT[language] ?? TEXT.en);
    let roleFilter = $state('all');
    let searchInput = $state('');
    let searchTerm = $state('');
    let page = $state(1);
    let users = $state([]);
    let total = $state(0);
    let loading = $state(false);
    let workingId = $state(null);
    let errorMessage = $state('');
    let successMessage = $state('');
    let loadedOnce = false;

    let pageCount = $derived(Math.max(1, Math.ceil(total / PAGE_SIZE)));

    function roleLabel(role) {
        if (role === 'admin') return t.admin;
        if (role === 'moderator') return t.moderator;
        return t.user;
    }

    function formatDate(value) {
        if (!value) return '—';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return '—';
        return new Intl.DateTimeFormat(language === 'pt' ? 'pt-PT' : 'en-GB', { dateStyle: 'medium' }).format(date);
    }

    function visiblePages() {
        const maxVisible = 5;
        let start = Math.max(1, page - Math.floor(maxVisible / 2));
        let end = Math.min(pageCount, start + maxVisible - 1);
        start = Math.max(1, end - maxVisible + 1);
        return Array.from({ length: end - start + 1 }, (_, index) => start + index);
    }

    async function loadUsers() {
        if (!active || loading) return;
        loading = true;
        errorMessage = '';
        try {
            const { data, error } = await getSupabaseBrowserClient().rpc('get_deepmap_users', {
                p_role_filter: roleFilter,
                p_search: searchTerm || null,
                p_limit: PAGE_SIZE,
                p_offset: (page - 1) * PAGE_SIZE
            });
            if (error) throw error;
            users = (data ?? []).map((row) => ({
                id: row.user_id,
                username: row.username ?? '',
                displayName: row.display_name ?? 'Explorer',
                joinedAt: row.joined_at,
                role: row.role ?? 'user',
                contributions: Number(row.contribution_count ?? 0),
                pending: Number(row.pending_count ?? 0),
                approved: Number(row.approved_count ?? 0),
                rejected: Number(row.rejected_count ?? 0)
            }));
            total = data?.length ? Number(data[0].total_count ?? 0) : 0;
            if (page > pageCount) page = pageCount;
        } catch (error) {
            console.error('DeepMap users admin:', error);
            users = [];
            total = 0;
            errorMessage = t.loadError;
        } finally {
            loading = false;
        }
    }

    async function setFilter(nextFilter) {
        if (roleFilter === nextFilter && page === 1) return;
        roleFilter = nextFilter;
        page = 1;
        await loadUsers();
    }

    async function submitSearch(event) {
        event?.preventDefault?.();
        searchTerm = searchInput.trim().replace(/^@+/, '').toLowerCase();
        page = 1;
        await loadUsers();
    }

    async function clearSearch() {
        searchInput = '';
        searchTerm = '';
        page = 1;
        await loadUsers();
    }

    async function goPage(nextPage) {
        if (nextPage < 1 || nextPage > pageCount || nextPage === page) return;
        page = nextPage;
        await loadUsers();
    }

    async function toggleModerator(user) {
        if (!user || workingId || user.role === 'admin') return;
        const enable = user.role !== 'moderator';
        const template = enable ? t.promoteConfirm : t.removeConfirm;
        if (!window.confirm(template.replace('{username}', user.username || user.displayName || 'user'))) return;

        workingId = user.id;
        errorMessage = '';
        successMessage = '';
        try {
            const { error } = await getSupabaseBrowserClient().rpc('set_deepmap_moderator', {
                p_user_id: user.id,
                p_enabled: enable
            });
            if (error) throw error;
            successMessage = enable ? t.promoted : t.removed;
            await loadUsers();
        } catch (error) {
            console.error('DeepMap moderator role update:', error);
            errorMessage = t.updateError;
        } finally {
            workingId = null;
        }
    }

    $effect(() => {
        if (!active || loadedOnce) return;
        loadedOnce = true;
        void loadUsers();
    });
</script>

{#if active}
    <section class="users-panel" aria-label={t.title}>
        <div class="panel-heading">
            <div><span class="eyebrow">DeepMap</span><strong>{t.title}</strong></div>
            <button class="small-button" type="button" onclick={loadUsers} disabled={loading || workingId !== null}>{t.refresh}</button>
        </div>

        <div class="role-tabs" role="tablist" aria-label={t.role}>
            <button class:active={roleFilter === 'all'} type="button" onclick={() => setFilter('all')}>{t.all}</button>
            <button class:active={roleFilter === 'user'} type="button" onclick={() => setFilter('user')}>{t.users}</button>
            <button class:active={roleFilter === 'moderator'} type="button" onclick={() => setFilter('moderator')}>{t.moderators}</button>
        </div>

        <form class="search-row" onsubmit={submitSearch}>
            <input bind:value={searchInput} placeholder={t.search} autocomplete="off" spellcheck="false" />
            <button type="submit" disabled={loading}>{t.searchButton}</button>
            {#if searchTerm}<button class="clear-button" type="button" onclick={clearSearch} disabled={loading}>{t.clear}</button>{/if}
        </form>

        {#if errorMessage}<p class="message error" role="alert">{errorMessage}</p>{/if}
        {#if successMessage}<p class="message success" role="status">{successMessage}</p>{/if}

        {#if loading}
            <div class="empty-state">…</div>
        {:else if !users.length}
            <div class="empty-state">{t.none}</div>
        {:else}
            <div class="user-list">
                {#each users as user (user.id)}
                    <article class="user-card">
                        <div class="user-main">
                            <div class="identity">
                                <strong>{user.username ? `@${user.username}` : '—'}</strong>
                                <span>{user.displayName}</span>
                            </div>
                            <span class:admin={user.role === 'admin'} class:moderator={user.role === 'moderator'} class="role-badge">{roleLabel(user.role)}</span>
                        </div>

                        <div class="user-meta">
                            <span>{t.joined}<strong>{formatDate(user.joinedAt)}</strong></span>
                            <span>{t.contributions}<strong>{user.contributions}</strong></span>
                            <span>{t.pending}<strong>{user.pending}</strong></span>
                            <span>{t.approved}<strong>{user.approved}</strong></span>
                            <span>{t.rejected}<strong>{user.rejected}</strong></span>
                        </div>

                        <div class="user-actions">
                            {#if user.username}
                                <a href={`/u/${encodeURIComponent(user.username)}`} target="_blank" rel="noreferrer">{t.openProfile}</a>
                            {/if}
                            {#if user.role === 'admin'}
                                <span class="admin-note">{t.adminProtected}</span>
                            {:else}
                                <button
                                    class:remove={user.role === 'moderator'}
                                    type="button"
                                    onclick={() => toggleModerator(user)}
                                    disabled={workingId !== null}
                                >
                                    {workingId === user.id ? t.working : user.role === 'moderator' ? t.removeModerator : t.makeModerator}
                                </button>
                            {/if}
                        </div>
                    </article>
                {/each}
            </div>
        {/if}

        {#if total > PAGE_SIZE}
            <nav class="pagination" aria-label={`${t.page} ${page}`}>
                <button type="button" onclick={() => goPage(page - 1)} disabled={loading || page <= 1}>‹</button>
                {#each visiblePages() as pageNumber}
                    <button class:active={pageNumber === page} type="button" onclick={() => goPage(pageNumber)} disabled={loading}>{pageNumber}</button>
                {/each}
                <button type="button" onclick={() => goPage(page + 1)} disabled={loading || page >= pageCount}>›</button>
            </nav>
        {/if}
    </section>
{/if}

<style>
    .users-panel{display:grid;gap:11px;padding:14px;border:1px solid rgba(200,163,85,.7);border-radius:9px;background:rgba(16,16,20,.98);color:#eee;touch-action:pan-y;overscroll-behavior:contain}
    .panel-heading,.user-main,.user-actions{display:flex;align-items:center;justify-content:space-between;gap:9px}.panel-heading>div{display:grid;gap:2px}.eyebrow{color:#c8a355;font-size:.68rem;font-weight:800;text-transform:uppercase;letter-spacing:.08em}.small-button,.role-tabs button,.search-row button,.user-actions button,.pagination button{border:1px solid #3a3a45;border-radius:7px;background:#17171c;color:#ddd;cursor:pointer}.small-button{padding:7px 9px;color:#d8b86f}.role-tabs{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:6px}.role-tabs button{padding:8px 6px;font-weight:800;font-size:.7rem}.role-tabs button.active,.pagination button.active{border-color:#c8a355;background:#211d14;color:#f1d58e}
    .search-row{display:grid;grid-template-columns:minmax(0,1fr) auto auto;gap:6px}.search-row input{min-width:0;padding:9px 10px;border:1px solid #34343e;border-radius:7px;background:#0e0e12;color:#eee;font:inherit}.search-row button{padding:8px 10px;font-weight:800}.search-row .clear-button{color:#999}.user-list{display:grid;gap:8px}.user-card{display:grid;gap:9px;padding:10px;border:1px solid #303039;border-radius:9px;background:#101014}.identity{display:grid;gap:2px;min-width:0}.identity strong{color:#e7e7e9;font-size:.84rem}.identity span{color:#92929c;font-size:.7rem;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.role-badge{padding:4px 7px;border:1px solid #3b3b44;border-radius:999px;color:#aaa;font-size:.62rem;font-weight:900;text-transform:uppercase}.role-badge.moderator{border-color:#66593b;color:#d8b86f;background:rgba(200,163,85,.08)}.role-badge.admin{border-color:#5b4771;color:#d0b5ee;background:rgba(124,81,164,.1)}
    .user-meta{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:6px}.user-meta span{display:flex;justify-content:space-between;gap:8px;padding:6px 7px;border-radius:6px;background:#0b0b0f;color:#8f8f99;font-size:.66rem}.user-meta strong{color:#ddd}.user-actions{align-items:flex-start}.user-actions a{padding:7px 9px;border:1px solid #3a3a45;border-radius:7px;color:#aaa;text-decoration:none;font-size:.68rem;font-weight:800}.user-actions button{padding:7px 9px;border-color:#66593b;color:#d8b86f;font-weight:800;font-size:.68rem}.user-actions button.remove{border-color:#704047;color:#ffc0c8}.admin-note{max-width:190px;color:#7f7f88;font-size:.64rem;text-align:right}.message{margin:0;padding:8px 9px;border-radius:7px;font-size:.72rem}.message.error{background:#2b1519;color:#ffc0c8}.message.success{background:#15251a;color:#bcebc7}.empty-state{min-height:90px;display:grid;place-items:center;padding:14px;border:1px solid #303039;border-radius:9px;background:#101014;color:#8f8f98;font-size:.75rem}.pagination{display:flex;justify-content:center;gap:5px;flex-wrap:wrap}.pagination button{min-width:32px;height:32px;padding:0 8px}.pagination button:disabled,.small-button:disabled,.role-tabs button:disabled,.search-row button:disabled,.user-actions button:disabled{opacity:.5;cursor:not-allowed}
    @media(max-width:560px){.search-row{grid-template-columns:minmax(0,1fr) auto}.search-row .clear-button{grid-column:1/-1}.user-meta{grid-template-columns:1fr 1fr}.user-actions{align-items:stretch;flex-direction:column}.user-actions a,.user-actions button{text-align:center}.admin-note{max-width:none;text-align:left}}
</style>
