<script>
    import { onMount, untrack } from 'svelte';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import {
        NOTIFICATIONS_PAGE_SIZE, getNotificationText, loadNotificationsPage,
        loadUnreadNotificationCount, markNotificationRead, markAllNotificationsRead,
        notificationTitle, notificationBody, notificationHref, formatNotificationDate
    } from '$lib/notifications/notification-data.js';

    /** @type {{ userId?: string | null, language?: string }} */
    let { userId = null, language = 'en' } = $props();
    let t = $derived(getNotificationText(language));
    let open = $state(false);
    /** @type {import('$lib/notifications/notification-data.js').Notification[]} */
    let notifications = $state([]);
    let loading = $state(false);
    let unreadCount = $state(0);
    let mounted = $state(false);
    /** @type {string | null} */
    let sessionUserId = $state(null);
    let authRevision = $state(0);
    /** @type {HTMLDivElement} */
    let notificationWrap;
    /** @type {import('@supabase/supabase-js').RealtimeChannel | null} */
    let notificationChannel = null;
    /** @type {ReturnType<typeof setTimeout> | null} */
    let refreshTimer = null;
    /** @type {string | null} */
    let activeUser = null;
    let activeAuthRevision = -1;
    let alive = false;
    let sessionGeneration = 0;
    let listGeneration = 0;
    let countGeneration = 0;
    let pendingWrites = 0;
    let refreshDirty = false;

    /** @param {string | null} user @param {number} epoch */
    function isSessionCurrent(user, epoch) {
        return alive && epoch === sessionGeneration && user !== null && user === activeUser
            && user === userId && user === sessionUserId && activeAuthRevision === authRevision;
    }

    async function loadUnreadCount() {
        const user = activeUser;
        const epoch = sessionGeneration;
        const request = ++countGeneration;
        if (!isSessionCurrent(user, epoch)) return;
        if (pendingWrites) { refreshDirty = true; return; }
        try {
            const count = await loadUnreadNotificationCount({ supabase: getSupabaseBrowserClient(), userId: user });
            if (isSessionCurrent(user, epoch) && request === countGeneration) unreadCount = count;
        } catch (error) {
            if (isSessionCurrent(user, epoch) && request === countGeneration) console.warn('DeepMap notification count:', error);
        }
    }

    async function loadNotifications() {
        const user = activeUser;
        const epoch = sessionGeneration;
        const request = ++listGeneration;
        const countRequest = ++countGeneration;
        const isCurrent = () => isSessionCurrent(user, epoch) && request === listGeneration;
        if (!isCurrent()) return;
        if (pendingWrites) { refreshDirty = true; return; }
        loading = true;
        try {
            const supabase = getSupabaseBrowserClient();
            const [result, count] = await Promise.all([
                loadNotificationsPage({ supabase, userId: user, limit: NOTIFICATIONS_PAGE_SIZE, offset: 0 }),
                loadUnreadNotificationCount({ supabase, userId: user })
            ]);
            if (!isCurrent()) return;
            notifications = result.items;
            if (countRequest === countGeneration) unreadCount = count;
        } catch (error) {
            if (!isCurrent()) return;
            console.warn('DeepMap notifications:', error);
            notifications = [];
        } finally {
            if (isCurrent()) loading = false;
        }
    }

    function queueRefresh() {
        if (!isSessionCurrent(activeUser, sessionGeneration)) return;
        // Invalidate immediately, including responses arriving before the timer fires.
        listGeneration += 1;
        countGeneration += 1;
        refreshDirty = true;
        if (pendingWrites || refreshTimer !== null) return;
        refreshTimer = setTimeout(() => {
            refreshTimer = null;
            refreshDirty = false;
            void loadNotifications();
        }, 0);
    }

    function beginWrite() {
        refreshDirty = refreshDirty || loading;
        listGeneration += 1;
        countGeneration += 1;
        loading = false;
        pendingWrites += 1;
    }

    /** @param {string | null} user @param {number} epoch */
    function finishWrite(user, epoch) {
        if (!isSessionCurrent(user, epoch)) return;
        pendingWrites -= 1;
        if (!pendingWrites && refreshDirty) queueRefresh();
    }

    /** @param {string} id */
    async function markRead(id) {
        const user = activeUser;
        const epoch = sessionGeneration;
        const item = notifications.find((notification) => notification.id === id);
        if (!isSessionCurrent(user, epoch) || !item || item.isRead) return;
        beginWrite();
        item.isRead = true;
        notifications = [...notifications];
        unreadCount = Math.max(0, unreadCount - 1);
        try {
            await markNotificationRead({ supabase: getSupabaseBrowserClient(), userId: user, notificationId: id });
        } catch (error) {
            if (isSessionCurrent(user, epoch)) {
                console.warn('DeepMap notification read:', error);
                refreshDirty = true;
            }
        } finally { finishWrite(user, epoch); }
    }

    async function markAllRead() {
        const user = activeUser;
        const epoch = sessionGeneration;
        if (!isSessionCurrent(user, epoch) || unreadCount === 0) return;
        beginWrite();
        notifications = notifications.map((item) => ({ ...item, isRead: true }));
        unreadCount = 0;
        try {
            await markAllNotificationsRead({ supabase: getSupabaseBrowserClient(), userId: user });
        } catch (error) {
            if (isSessionCurrent(user, epoch)) {
                console.warn('DeepMap notifications mark all:', error);
                refreshDirty = true;
            }
        } finally { finishWrite(user, epoch); }
    }

    /** @param {MouseEvent} event @param {import('$lib/notifications/notification-data.js').Notification} item */
    async function openNotification(event, item) {
        event.preventDefault();
        const user = activeUser;
        const epoch = sessionGeneration;
        const href = notificationHref(item);
        await markRead(item.id);
        if (!isSessionCurrent(user, epoch)) return;
        open = false;
        window.location.href = href;
    }

    function toggle() {
        open = !open;
        if (open) {
            window.dispatchEvent(new CustomEvent('deepmap:header-panel-open', { detail: { source: 'notifications' } }));
            void loadNotifications();
        }
    }

    /** @param {Event} event */
    function handleHeaderPanelOpen(event) {
        const source = /** @type {CustomEvent} */ (event).detail?.source;
        if (source === 'account' || source === 'navigation') open = false;
    }

    /** @param {PointerEvent} event */
    function handleDocumentPointerDown(event) {
        if (open && notificationWrap && !notificationWrap.contains(/** @type {Node} */ (event.target))) open = false;
    }
    /** @param {KeyboardEvent} event */
    function handleDocumentKeyDown(event) { if (event.key === 'Escape') open = false; }
    /** @param {Event} event */
    function handleNotificationCountSync(event) {
        const next = Number(/** @type {CustomEvent} */ (event).detail?.unreadCount);
        countGeneration += 1;
        if (Number.isSafeInteger(next) && next >= 0) unreadCount = next;
        else void loadUnreadCount();
    }

    /** @param {string | null} user @param {number} revision */
    function activateUser(user, revision) {
        if (user === activeUser && revision === activeAuthRevision) return;
        const changedUser = user !== activeUser;
        sessionGeneration += 1;
        listGeneration += 1;
        countGeneration += 1;
        activeUser = user;
        activeAuthRevision = revision;
        pendingWrites = 0;
        refreshDirty = false;
        loading = false;
        if (refreshTimer !== null) clearTimeout(refreshTimer);
        refreshTimer = null;
        const supabase = getSupabaseBrowserClient();
        if (notificationChannel) void supabase.removeChannel(notificationChannel);
        notificationChannel = null;
        if (changedUser || !user) { notifications = []; unreadCount = 0; }
        if (!user) { open = false; return; }
        const epoch = sessionGeneration;
        notificationChannel = supabase.channel(`deepmap-notifications-${user}`)
            .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'user_notifications', filter: `user_id=eq.${user}` }, (payload) => {
                if (!isSessionCurrent(user, epoch)) return;
                // Raw rows lack route context: only their kind is used for the existing account event.
                const kind = payload.new.kind;
                if (kind === 'account_suspended' || kind === 'account_reinstated') {
                    window.dispatchEvent(new CustomEvent('deepmap:account-status-changed', { detail: { kind } }));
                }
                queueRefresh();
            }).subscribe();
        if (open) void loadNotifications();
        else void loadUnreadCount();
    }

    onMount(() => {
        alive = true;
        mounted = true;
        const supabase = getSupabaseBrowserClient();
        document.addEventListener('pointerdown', handleDocumentPointerDown);
        document.addEventListener('keydown', handleDocumentKeyDown);
        window.addEventListener('deepmap:notifications-count-sync', handleNotificationCountSync);
        window.addEventListener('deepmap:header-panel-open', handleHeaderPanelOpen);
        const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
            if (!alive) return;
            const next = session?.user.id ?? null;
            if (event === 'TOKEN_REFRESHED' && next === sessionUserId) return;
            sessionUserId = next;
            authRevision += 1;
            if (next !== activeUser) { notifications = []; unreadCount = 0; }
        });
        return () => {
            alive = false;
            sessionGeneration += 1;
            listGeneration += 1;
            countGeneration += 1;
            if (refreshTimer !== null) clearTimeout(refreshTimer);
            subscription.unsubscribe();
            document.removeEventListener('pointerdown', handleDocumentPointerDown);
            document.removeEventListener('keydown', handleDocumentKeyDown);
            window.removeEventListener('deepmap:notifications-count-sync', handleNotificationCountSync);
            window.removeEventListener('deepmap:header-panel-open', handleHeaderPanelOpen);
            if (notificationChannel) void supabase.removeChannel(notificationChannel);
            notificationChannel = null;
            notifications = [];
            unreadCount = 0;
        };
    });

    $effect(() => {
        const user = userId && userId === sessionUserId ? userId : null;
        const revision = authRevision;
        if (mounted) untrack(() => activateUser(user, revision));
    });
</script>

<div class="notification-wrap" bind:this={notificationWrap}>
    <button
        class:has-unread={unreadCount > 0}
        class="bell-button"
        type="button"
        aria-label={t.title}
        aria-expanded={open}
        onclick={toggle}
    >
        <svg aria-hidden="true" viewBox="0 0 24 24">
            <path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9Z"></path>
            <path d="M10 21h4"></path>
        </svg>
        {#if unreadCount > 0}<b>{unreadCount > 99 ? '99+' : unreadCount}</b>{/if}
    </button>

    {#if open}
        <div class="notification-popover">
            <div class="popover-heading">
                <strong>{t.title}</strong>
                {#if unreadCount > 0}<button type="button" onclick={markAllRead}>{t.markAll}</button>{/if}
            </div>

            {#if loading && !notifications.length}
                <p class="empty">{t.loading}</p>
            {:else if !notifications.length}
                <p class="empty">{t.empty}</p>
            {:else}
                <div class="notification-list">
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
                </div>
            {/if}

            <a class="view-all" href="/notifications" onclick={() => { open = false; }}>{t.viewAll}</a>
        </div>
    {/if}
</div>

<style>
.notification-wrap{position:relative;display:inline-flex;align-items:center;touch-action:pan-x pan-y}.bell-button{position:relative;width:36px;height:36px;display:grid;place-items:center;padding:0;border:1px solid #4b4130;border-radius:50%;background:#171719;color:#d8b86f;cursor:pointer;font-size:1.12rem;line-height:1}.bell-button svg{width:17px;height:17px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}.bell-button.has-unread{border-color:#c8a355;background:#211d18}.bell-button b{position:absolute;top:-4px;right:-5px;min-width:16px;height:16px;display:grid;place-items:center;padding:0 3px;border-radius:999px;background:#c85f67;color:#fff;font-size:.58rem;line-height:1;box-sizing:border-box}.notification-popover{position:absolute;top:44px;right:-42px;width:min(360px,calc(100vw - 24px));max-height:min(520px,70vh);overflow:auto;border:1px solid #3a352a;border-radius:12px;background:rgba(13,13,16,.99);box-shadow:0 18px 52px rgba(0,0,0,.62);z-index:80000;color:#eee;touch-action:pan-y;overscroll-behavior:contain}.popover-heading{position:sticky;top:0;z-index:2;display:flex;align-items:center;justify-content:space-between;gap:10px;padding:11px 12px;border-bottom:1px solid #2b2b32;background:rgba(13,13,16,.99)}.popover-heading strong{color:#e6c878;font-size:.82rem}.popover-heading button{padding:5px 7px;border:0;background:transparent;color:#9d9da6;font-size:.66rem;cursor:pointer}.notification-list{display:grid}.notification-list a{display:grid;grid-template-columns:10px minmax(0,1fr);gap:9px;padding:11px 12px;border-bottom:1px solid #24242a;color:inherit;text-decoration:none;background:#111115}.notification-list a:hover{background:#17171d}.notification-list a.unread{background:#191710}.status-dot{width:7px;height:7px;margin-top:5px;border-radius:50%;background:#555}.unread .status-dot{background:#d8b86f}.copy{display:grid;gap:3px;min-width:0}.copy strong{font-size:.76rem;color:#eee}.copy small{font-size:.7rem;line-height:1.35;color:#aaaab3}.copy .note{padding-top:3px;color:#c7c7ce}.copy .note b{color:#d8b86f}.copy time{font-size:.61rem;color:#70707a}.empty{margin:0;padding:22px 14px;color:#8d8d96;font-size:.75rem;text-align:center}.view-all{display:block;padding:10px 12px;border-top:1px solid #2b2b32;background:#0f0f13;color:#d8b86f;text-align:center;text-decoration:none;font-size:.7rem;font-weight:800}.view-all:hover{background:#17171d}@media(max-width:820px){.bell-button{width:32px;height:32px}.notification-popover{position:fixed;top:calc(var(--deepmap-site-header-height,62px) + 6px);left:8px;right:8px;width:auto;max-height:calc(100dvh - var(--deepmap-site-header-height,62px) - 16px)}}
</style>
