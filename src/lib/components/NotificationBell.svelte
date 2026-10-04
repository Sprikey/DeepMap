<script>
    import { onMount } from 'svelte';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';

    let { userId = null, language = 'en' } = $props();

    const TEXT = {
        en: {
            title: 'Notifications', markAll: 'Mark all read', loading: 'Loading…', empty: 'No notifications yet.', approved: 'Approved', rejected: 'Rejected',
            markerApproved: 'Your marker was approved.', suggestionApproved: 'Your suggestion was approved.', markerRejected: 'Your marker was rejected.', suggestionRejected: 'Your suggestion was rejected.',
            moderatorNote: 'Moderator note', moderatorGranted: 'You are now a DeepMap moderator.', moderatorRevoked: 'Your moderator access was removed.',
            moderatorGrantedTitle: 'Moderator access', moderatorRevokedTitle: 'Moderator access changed', accountSuspendedTitle: 'Account suspended', accountSuspended: 'Your DeepMap account was suspended.', accountReinstatedTitle: 'Account restored', accountReinstated: 'Your DeepMap account access was restored.'
        },
        pt: {
            title: 'Notificações', markAll: 'Marcar tudo como lido', loading: 'A carregar…', empty: 'Ainda não tens notificações.', approved: 'Aprovado', rejected: 'Reprovado',
            markerApproved: 'O teu marcador foi aprovado.', suggestionApproved: 'A tua sugestão foi aprovada.', markerRejected: 'O teu marcador foi reprovado.', suggestionRejected: 'A tua sugestão foi reprovada.',
            moderatorNote: 'Nota da moderação', moderatorGranted: 'Agora és moderador do DeepMap.', moderatorRevoked: 'O teu acesso de moderador foi removido.',
            moderatorGrantedTitle: 'Acesso de moderador', moderatorRevokedTitle: 'Acesso de moderador alterado', accountSuspendedTitle: 'Conta suspensa', accountSuspended: 'A tua conta DeepMap foi suspensa.', accountReinstatedTitle: 'Conta reativada', accountReinstated: 'O acesso à tua conta DeepMap foi reativado.'
        }
    };

    let t = $derived(TEXT[language] ?? TEXT.en);
    let open = $state(false);
    let notifications = $state([]);
    let loading = $state(false);
    let loadedForUser = $state(null);
    let notificationWrap;
    let notificationChannel = null;
    let unreadCount = $derived(notifications.filter((item) => !item.is_read).length);

    function normalise(row) {
        return {
            id: Number(row.id),
            kind: row.kind ?? 'submission_review',
            gameId: row.game_id ?? null,
            submissionId: row.submission_id == null ? null : Number(row.submission_id),
            markerId: row.marker_id == null ? null : Number(row.marker_id),
            submissionType: row.submission_type ?? null,
            decision: row.decision ?? null,
            reviewNote: row.review_note ?? '',
            metadata: row.metadata ?? {},
            is_read: row.is_read === true,
            createdAt: row.created_at
        };
    }

    function notificationTitle(item) {
        if (item.kind === 'moderator_granted') return t.moderatorGrantedTitle;
        if (item.kind === 'moderator_revoked') return t.moderatorRevokedTitle;
        if (item.kind === 'account_suspended') return t.accountSuspendedTitle;
        if (item.kind === 'account_reinstated') return t.accountReinstatedTitle;
        return item.decision === 'approved' ? t.approved : t.rejected;
    }

    function notificationBody(item) {
        if (item.kind === 'moderator_granted') return t.moderatorGranted;
        if (item.kind === 'moderator_revoked') return t.moderatorRevoked;
        if (item.kind === 'account_suspended') return t.accountSuspended;
        if (item.kind === 'account_reinstated') return t.accountReinstated;
        if (item.decision === 'approved') return item.submissionType === 'create' ? t.markerApproved : t.suggestionApproved;
        return item.submissionType === 'create' ? t.markerRejected : t.suggestionRejected;
    }

    function hrefFor(item) {
        if (item.kind === 'moderator_granted') return '/moderation';
        if (item.kind === 'moderator_revoked') return '/profile';
        if (item.kind === 'account_suspended') return '/suspended';
        if (item.kind === 'account_reinstated') return '/profile';
        if (!item.gameId) return '/profile';
        if (item.decision === 'approved' && item.markerId) return `/games/${encodeURIComponent(item.gameId)}/map?marker=${item.markerId}`;
        if (item.submissionId) return `/games/${encodeURIComponent(item.gameId)}/map?contribution=${item.submissionId}`;
        return '/profile';
    }

    function formatDate(value) {
        if (!value) return '';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return '';
        return new Intl.DateTimeFormat(language === 'pt' ? 'pt-PT' : 'en-GB', { dateStyle: 'short', timeStyle: 'short' }).format(date);
    }

    async function loadNotifications() {
        if (!userId) { notifications = []; loadedForUser = null; return; }
        loading = true;
        try {
            const supabase = getSupabaseBrowserClient();
            let result = await supabase.from('user_notifications').select('id, user_id, kind, game_id, submission_id, marker_id, submission_type, decision, review_note, metadata, is_read, created_at').eq('user_id', userId).order('created_at', { ascending: false }).limit(30);
            if (result.error && /kind|metadata/i.test(result.error.message ?? '')) {
                result = await supabase.from('user_notifications').select('id, user_id, game_id, submission_id, marker_id, submission_type, decision, review_note, is_read, created_at').eq('user_id', userId).order('created_at', { ascending: false }).limit(30);
            }
            if (result.error) throw result.error;
            notifications = (result.data ?? []).map(normalise);
            loadedForUser = userId;
        } catch (error) {
            console.warn('DeepMap notifications:', error?.message ?? error);
            notifications = [];
            loadedForUser = userId;
        } finally { loading = false; }
    }

    async function markRead(id) {
        const item = notifications.find((notification) => notification.id === id);
        if (!item || item.is_read) return;
        item.is_read = true;
        notifications = [...notifications];
        const { error } = await getSupabaseBrowserClient().from('user_notifications').update({ is_read: true }).eq('id', id).eq('user_id', userId);
        if (error) console.warn('DeepMap notification read:', error.message);
    }

    async function markAllRead() {
        if (!userId || unreadCount === 0) return;
        notifications = notifications.map((item) => ({ ...item, is_read: true }));
        const { error } = await getSupabaseBrowserClient().from('user_notifications').update({ is_read: true }).eq('user_id', userId).eq('is_read', false);
        if (error) console.warn('DeepMap notifications mark all:', error.message);
    }

    async function openNotification(event, item) {
        event.preventDefault();
        const href = hrefFor(item);
        await markRead(item.id);
        open = false;
        window.location.href = href;
    }

    function toggle() {
        open = !open;
        if (open) {
            if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent('deepmap:header-panel-open', { detail: { source: 'notifications' } }));
            void loadNotifications();
        }
    }
    function handleDocumentPointerDown(event) { if (!open || !notificationWrap) return; if (!notificationWrap.contains(event.target)) open = false; }
    function handleDocumentKeyDown(event) { if (event.key === 'Escape') open = false; }

    function subscribeToNotifications() {
        const supabase = getSupabaseBrowserClient();
        if (notificationChannel) { void supabase.removeChannel(notificationChannel); notificationChannel = null; }
        if (!userId) return;
        notificationChannel = supabase.channel(`deepmap-notifications-${userId}`).on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'user_notifications', filter: `user_id=eq.${userId}` }, (payload) => {
            const item = normalise(payload.new);
            notifications = [item, ...notifications.filter((notification) => notification.id !== item.id)].slice(0, 30);
            if (item.kind === 'account_suspended' || item.kind === 'account_reinstated') {
                window.dispatchEvent(new CustomEvent('deepmap:account-status-changed', { detail: { kind: item.kind } }));
            }
        }).subscribe();
    }

    onMount(() => {
        document.addEventListener('pointerdown', handleDocumentPointerDown);
        document.addEventListener('keydown', handleDocumentKeyDown);
        if (userId) { void loadNotifications(); subscribeToNotifications(); }
        return () => {
            document.removeEventListener('pointerdown', handleDocumentPointerDown);
            document.removeEventListener('keydown', handleDocumentKeyDown);
            if (notificationChannel) { void getSupabaseBrowserClient().removeChannel(notificationChannel); notificationChannel = null; }
        };
    });

    $effect(() => { if (!userId || loadedForUser === userId) return; void loadNotifications(); subscribeToNotifications(); });
</script>

<div class="notification-wrap" bind:this={notificationWrap}>
    <button class:has-unread={unreadCount > 0} class="bell-button" type="button" aria-label={t.title} aria-expanded={open} onclick={toggle}>
        <svg aria-hidden="true" viewBox="0 0 24 24"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9Z"></path><path d="M10 21h4"></path></svg>
        {#if unreadCount > 0}<b>{unreadCount > 9 ? '9+' : unreadCount}</b>{/if}
    </button>

    {#if open}
        <div class="notification-popover">
            <div class="popover-heading"><strong>{t.title}</strong>{#if unreadCount > 0}<button type="button" onclick={markAllRead}>{t.markAll}</button>{/if}</div>
            {#if loading && !notifications.length}<p class="empty">{t.loading}</p>
            {:else if !notifications.length}<p class="empty">{t.empty}</p>
            {:else}<div class="notification-list">{#each notifications as item (item.id)}<a class:unread={!item.is_read} href={hrefFor(item)} onclick={(event) => openNotification(event, item)}><span class="status-dot" aria-hidden="true"></span><span class="copy"><strong>{notificationTitle(item)}</strong><small>{notificationBody(item)}</small>{#if item.reviewNote}<small class="note"><b>{t.moderatorNote}:</b> {item.reviewNote}</small>{/if}<time>{formatDate(item.createdAt)}</time></span></a>{/each}</div>{/if}
        </div>
    {/if}
</div>

<style>
.notification-wrap{position:relative;display:inline-flex;align-items:center;touch-action:pan-x pan-y}.bell-button{position:relative;width:36px;height:36px;display:grid;place-items:center;padding:0;border:1px solid #4b4130;border-radius:50%;background:#171719;color:#d8b86f;cursor:pointer;font-size:1.12rem;line-height:1}.bell-button svg{width:17px;height:17px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}.bell-button.has-unread{border-color:#c8a355;background:#211d18}.bell-button b{position:absolute;top:-4px;right:-5px;min-width:16px;height:16px;display:grid;place-items:center;padding:0 3px;border-radius:999px;background:#c85f67;color:#fff;font-size:.58rem;line-height:1;box-sizing:border-box}.notification-popover{position:absolute;top:44px;right:-42px;width:min(360px,calc(100vw - 24px));max-height:min(520px,70vh);overflow:auto;border:1px solid #3a352a;border-radius:12px;background:rgba(13,13,16,.99);box-shadow:0 18px 52px rgba(0,0,0,.62);z-index:80000;color:#eee;touch-action:pan-y;overscroll-behavior:contain}.popover-heading{position:sticky;top:0;z-index:2;display:flex;align-items:center;justify-content:space-between;gap:10px;padding:11px 12px;border-bottom:1px solid #2b2b32;background:rgba(13,13,16,.99)}.popover-heading strong{color:#e6c878;font-size:.82rem}.popover-heading button{padding:5px 7px;border:0;background:transparent;color:#9d9da6;font-size:.66rem;cursor:pointer}.notification-list{display:grid}.notification-list a{display:grid;grid-template-columns:10px minmax(0,1fr);gap:9px;padding:11px 12px;border-bottom:1px solid #24242a;color:inherit;text-decoration:none;background:#111115}.notification-list a:hover{background:#17171d}.notification-list a.unread{background:#191710}.status-dot{width:7px;height:7px;margin-top:5px;border-radius:50%;background:#555}.unread .status-dot{background:#d8b86f}.copy{display:grid;gap:3px;min-width:0}.copy strong{font-size:.76rem;color:#eee}.copy small{font-size:.7rem;line-height:1.35;color:#aaaab3}.copy .note{padding-top:3px;color:#c7c7ce}.copy .note b{color:#d8b86f}.copy time{font-size:.61rem;color:#70707a}.empty{margin:0;padding:22px 14px;color:#8d8d96;font-size:.75rem;text-align:center}@media(max-width:820px){.bell-button{width:32px;height:32px}.notification-popover{position:fixed;top:calc(var(--deepmap-site-header-height,62px) + 6px);left:8px;right:8px;width:auto;max-height:calc(100dvh - var(--deepmap-site-header-height,62px) - 16px)}}
</style>
