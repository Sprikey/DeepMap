<script>
    import { onMount } from 'svelte';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import {
        NOTIFICATIONS_PAGE_SIZE,
        getNotificationText,
        normaliseNotification,
        loadNotificationsPage,
        loadUnreadNotificationCount,
        markNotificationRead,
        markAllNotificationsRead,
        notificationTitle,
        notificationBody,
        notificationHref,
        formatNotificationDate
    } from '$lib/notifications/notification-data.js';

    let { userId = null, language = 'en' } = $props();

    let t = $derived(getNotificationText(language));
    let open = $state(false);
    let notifications = $state([]);
    let loading = $state(false);
    let unreadCount = $state(0);
    let loadedForUser = $state(null);
    let notificationWrap;
    let notificationChannel = null;

    async function loadUnreadCount() {
        if (!userId) { unreadCount = 0; return; }
        try {
            unreadCount = await loadUnreadNotificationCount({
                supabase: getSupabaseBrowserClient(),
                userId
            });
        } catch (error) {
            console.warn('DeepMap notification count:', error?.message ?? error);
        }
    }

    async function loadNotifications() {
        if (!userId) {
            notifications = [];
            unreadCount = 0;
            loadedForUser = null;
            return;
        }

        loading = true;
        try {
            const supabase = getSupabaseBrowserClient();
            const [pageResult, countResult] = await Promise.all([
                loadNotificationsPage({ supabase, userId, limit: NOTIFICATIONS_PAGE_SIZE, offset: 0 }),
                loadUnreadNotificationCount({ supabase, userId })
            ]);
            notifications = pageResult.items;
            unreadCount = countResult;
            loadedForUser = userId;
        } catch (error) {
            console.warn('DeepMap notifications:', error?.message ?? error);
            notifications = [];
            loadedForUser = userId;
        } finally {
            loading = false;
        }
    }

    async function markRead(id) {
        const item = notifications.find((notification) => notification.id === id);
        if (!item || item.isRead) return;

        item.isRead = true;
        notifications = [...notifications];
        unreadCount = Math.max(0, unreadCount - 1);

        try {
            await markNotificationRead({
                supabase: getSupabaseBrowserClient(),
                userId,
                notificationId: id
            });
        } catch (error) {
            console.warn('DeepMap notification read:', error?.message ?? error);
            void loadUnreadCount();
        }
    }

    async function markAllRead() {
        if (!userId || unreadCount === 0) return;
        notifications = notifications.map((item) => ({ ...item, isRead: true }));
        unreadCount = 0;

        try {
            await markAllNotificationsRead({
                supabase: getSupabaseBrowserClient(),
                userId
            });
        } catch (error) {
            console.warn('DeepMap notifications mark all:', error?.message ?? error);
            void loadUnreadCount();
        }
    }

    async function openNotification(event, item) {
        event.preventDefault();
        const href = notificationHref(item);
        await markRead(item.id);
        open = false;
        window.location.href = href;
    }

    function toggle() {
        open = !open;
        if (open) {
            if (typeof window !== 'undefined') {
                window.dispatchEvent(new CustomEvent('deepmap:header-panel-open', {
                    detail: { source: 'notifications' }
                }));
            }
            void loadNotifications();
        }
    }

    function handleDocumentPointerDown(event) {
        if (!open || !notificationWrap) return;
        if (!notificationWrap.contains(event.target)) open = false;
    }

    function handleDocumentKeyDown(event) {
        if (event.key === 'Escape') open = false;
    }

    function handleNotificationCountSync(event) {
        const next = Number(event?.detail?.unreadCount);
        if (Number.isFinite(next) && next >= 0) unreadCount = next;
        else void loadUnreadCount();
    }

    function subscribeToNotifications() {
        const supabase = getSupabaseBrowserClient();
        if (notificationChannel) {
            void supabase.removeChannel(notificationChannel);
            notificationChannel = null;
        }
        if (!userId) return;

        notificationChannel = supabase
            .channel(`deepmap-notifications-${userId}`)
            .on('postgres_changes', {
                event: 'INSERT',
                schema: 'public',
                table: 'user_notifications',
                filter: `user_id=eq.${userId}`
            }, (payload) => {
                const item = normaliseNotification(payload.new);
                notifications = [item, ...notifications.filter((notification) => notification.id !== item.id)]
                    .slice(0, NOTIFICATIONS_PAGE_SIZE);
                if (!item.isRead) unreadCount += 1;

                if (item.kind === 'account_suspended' || item.kind === 'account_reinstated') {
                    window.dispatchEvent(new CustomEvent('deepmap:account-status-changed', {
                        detail: { kind: item.kind }
                    }));
                }
            })
            .subscribe();
    }

    onMount(() => {
        document.addEventListener('pointerdown', handleDocumentPointerDown);
        document.addEventListener('keydown', handleDocumentKeyDown);
        window.addEventListener('deepmap:notifications-count-sync', handleNotificationCountSync);

        if (userId) {
            void loadUnreadCount();
            subscribeToNotifications();
        }

        return () => {
            document.removeEventListener('pointerdown', handleDocumentPointerDown);
            document.removeEventListener('keydown', handleDocumentKeyDown);
            window.removeEventListener('deepmap:notifications-count-sync', handleNotificationCountSync);
            if (notificationChannel) {
                void getSupabaseBrowserClient().removeChannel(notificationChannel);
                notificationChannel = null;
            }
        };
    });

    $effect(() => {
        if (!userId) {
            notifications = [];
            unreadCount = 0;
            loadedForUser = null;
            return;
        }
        if (loadedForUser === userId) return;
        void loadUnreadCount();
        subscribeToNotifications();
        loadedForUser = userId;
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
