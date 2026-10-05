<script>
    import { onMount, tick } from 'svelte';
    import { goto } from '$app/navigation';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { getSiteLanguage, subscribeSiteLanguage } from '$lib/i18n/site.js';
    import {
        getNotificationText,
        loadNotificationsPage,
        loadUnreadNotificationCount,
        markNotificationRead,
        markAllNotificationsRead,
        notificationTitle,
        notificationBody,
        notificationHref,
        formatNotificationDate
    } from '$lib/notifications/notification-data.js';

    let language = $state('en');
    let t = $derived(getNotificationText(language));
    let userId = $state(null);
    let notifications = $state([]);
    let total = $state(0);
    let unreadCount = $state(0);
    let page = $state(1);
    let pageSize = $state(10);
    let loading = $state(true);
    let errorMessage = $state('');

    let pageCount = $derived(Math.max(1, Math.ceil(total / pageSize)));

    function visiblePages() {
        const maxVisible = 5;
        let start = Math.max(1, page - Math.floor(maxVisible / 2));
        let end = Math.min(pageCount, start + maxVisible - 1);
        start = Math.max(1, end - maxVisible + 1);
        return Array.from({ length: end - start + 1 }, (_, index) => start + index);
    }

    async function loadPage() {
        if (!userId) return;
        loading = true;
        errorMessage = '';
        try {
            const supabase = getSupabaseBrowserClient();
            const [pageResult, countResult] = await Promise.all([
                loadNotificationsPage({
                    supabase,
                    userId,
                    limit: pageSize,
                    offset: (page - 1) * pageSize
                }),
                loadUnreadNotificationCount({ supabase, userId })
            ]);
            notifications = pageResult.items;
            total = pageResult.total;
            unreadCount = countResult;
            if (page > pageCount) page = pageCount;
        } catch (error) {
            console.error('DeepMap notifications page:', error);
            notifications = [];
            total = 0;
            errorMessage = language === 'pt'
                ? 'Não foi possível carregar as notificações.'
                : 'Could not load notifications.';
        } finally {
            loading = false;
        }
    }

    async function handlePageSizeChange() {
        page = 1;
        await tick();
        await loadPage();
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    async function goPage(nextPage) {
        if (nextPage < 1 || nextPage > pageCount || nextPage === page) return;
        page = nextPage;
        await loadPage();
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    async function openNotification(event, item) {
        event.preventDefault();
        if (!item.isRead) {
            item.isRead = true;
            notifications = [...notifications];
            unreadCount = Math.max(0, unreadCount - 1);
            try {
                await markNotificationRead({
                    supabase: getSupabaseBrowserClient(),
                    userId,
                    notificationId: item.id
                });
            } catch (error) {
                console.warn('DeepMap notification read:', error?.message ?? error);
            }
        }
        window.location.href = notificationHref(item);
    }

    async function markAll() {
        if (!userId || unreadCount === 0) return;
        notifications = notifications.map((item) => ({ ...item, isRead: true }));
        unreadCount = 0;
        window.dispatchEvent(new CustomEvent('deepmap:notifications-count-sync', { detail: { unreadCount: 0 } }));
        try {
            await markAllNotificationsRead({
                supabase: getSupabaseBrowserClient(),
                userId
            });
        } catch (error) {
            console.warn('DeepMap notifications mark all:', error?.message ?? error);
            await loadPage();
        }
    }

    onMount(() => {
        language = getSiteLanguage();
        const unsubscribeLanguage = subscribeSiteLanguage((next) => { language = next; });
        let active = true;

        void (async () => {
            const supabase = getSupabaseBrowserClient();
            const { data, error } = await supabase.auth.getUser();
            if (!active) return;
            if (error || !data.user) {
                await goto(`/login?next=${encodeURIComponent('/notifications')}`);
                return;
            }
            userId = data.user.id;
            await loadPage();
        })();

        return () => {
            active = false;
            unsubscribeLanguage();
        };
    });
</script>

<svelte:head>
    <title>{t.title} · DeepMap</title>
    <meta name="robots" content="noindex,nofollow" />
</svelte:head>

<main class="notifications-page">
    <header class="page-heading">
        <div>
            <span>DeepMap</span>
            <h1>{t.title}</h1>
        </div>
        <div class="page-actions">
            <label class="page-size"><span>{t.perPage}</span><select bind:value={pageSize} onchange={handlePageSizeChange} disabled={loading}><option value={10}>10</option><option value={20}>20</option><option value={50}>50</option></select></label>
            {#if unreadCount > 0}
                <button type="button" onclick={markAll}>{t.markAll}</button>
            {/if}
        </div>
    </header>

    {#if errorMessage}<p class="message error" role="alert">{errorMessage}</p>{/if}

    {#if loading && !notifications.length}
        <div class="empty">{t.loading}</div>
    {:else if !notifications.length}
        <div class="empty">{t.empty}</div>
    {:else}
        <section class="notification-list" aria-label={t.title}>
            {#each notifications as item (item.id)}
                <a
                    class:unread={!item.isRead}
                    href={notificationHref(item)}
                    onclick={(event) => openNotification(event, item)}
                >
                    <span class="status-dot" aria-hidden="true"></span>
                    <span class="copy">
                        <strong>{notificationTitle(item, t)}</strong>
                        <small>{notificationBody(item, t)}</small>
                        {#if item.reviewNote}<small class="note"><b>{t.moderatorNote}:</b> {item.reviewNote}</small>{/if}
                        <time>{formatNotificationDate(item.createdAt, language)}</time>
                    </span>
                </a>
            {/each}
        </section>

        {#if total > pageSize}
            <nav class="pagination" aria-label={`${t.page} ${page}`}>
                <button type="button" onclick={() => goPage(page - 1)} disabled={page <= 1}>‹</button>
                {#each visiblePages() as number}
                    <button class:active={number === page} type="button" onclick={() => goPage(number)}>{number}</button>
                {/each}
                <button type="button" onclick={() => goPage(page + 1)} disabled={page >= pageCount}>›</button>
            </nav>
        {/if}
    {/if}
</main>

<style>
.notifications-page{width:min(820px,calc(100% - 28px));margin:0 auto;padding:34px 0 70px;color:#eee;font-family:'Segoe UI',Arial,sans-serif}.page-heading{display:flex;align-items:flex-end;justify-content:space-between;gap:18px;margin-bottom:18px}.page-heading span{color:#c8a355;font-size:.7rem;font-weight:900;text-transform:uppercase;letter-spacing:.1em}.page-heading h1{margin:4px 0 5px;font-size:clamp(1.7rem,4vw,2.4rem)}.page-heading p{max-width:640px;margin:0;color:#91919b;font-size:.82rem;line-height:1.5}.page-actions{display:flex;align-items:flex-end;gap:8px}.page-size{display:grid;gap:3px;min-width:110px}.page-size span{color:#888;font-size:.62rem;white-space:nowrap}.page-size select{width:100%;padding:8px 28px 8px 9px;border:1px solid #3a3a45;border-radius:8px;background:#17171c;color:#ddd}.page-heading button,.pagination button{border:1px solid #3a3a45;border-radius:8px;background:#17171c;color:#ddd;cursor:pointer}.page-heading button{flex:none;padding:9px 12px}.notification-list{display:grid;overflow:hidden;border:1px solid #303039;border-radius:12px;background:#101014}.notification-list a{display:grid;grid-template-columns:12px minmax(0,1fr);gap:10px;padding:14px;border-bottom:1px solid #26262d;color:inherit;text-decoration:none;background:#111115}.notification-list a:last-child{border-bottom:0}.notification-list a:hover{background:#17171d}.notification-list a.unread{background:#191710}.status-dot{width:8px;height:8px;margin-top:6px;border-radius:50%;background:#555}.unread .status-dot{background:#d8b86f}.copy{display:grid;gap:4px}.copy strong{font-size:.86rem}.copy small{color:#aaaab3;font-size:.77rem;line-height:1.4}.copy .note{color:#c7c7ce}.copy .note b{color:#d8b86f}.copy time{color:#70707a;font-size:.67rem}.pagination{display:flex;justify-content:center;gap:5px;flex-wrap:wrap;margin-top:16px}.pagination button{min-width:34px;height:34px}.pagination button.active{border-color:#c8a355;background:#211d14;color:#f0d28a}.pagination button:disabled{opacity:.45;cursor:not-allowed}.empty{min-height:180px;display:grid;place-items:center;border:1px solid #303039;border-radius:12px;background:#101014;color:#8f8f98}.message{padding:9px 11px;border-radius:8px}.message.error{background:#2b1519;color:#ffc0c8}@media(max-width:650px){.notifications-page{width:min(100% - 18px,820px);padding-top:20px}.page-heading{align-items:stretch;flex-direction:column}.page-actions{display:grid;grid-template-columns:auto minmax(0,1fr);align-items:end}.page-heading button{width:100%}.notification-list a{padding:12px}.copy strong{font-size:.8rem}.copy small{font-size:.72rem}}
</style>
