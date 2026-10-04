<script>
    import { onMount } from 'svelte';
    import { page } from '$app/state';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { getDisplayName, getAvatarPresentation } from '$lib/avatar/avatars.js';
    import NotificationBell from '$lib/components/NotificationBell.svelte';

    let { language = 'en' } = $props();

    let user = $state(null);
    let role = $state('user');
    let checkingSession = $state(true);
    let avatarFailed = $state(false);
    let menuOpen = $state(false);
    let menuWrap;

    let accountLabel = $derived(language === 'pt' ? 'A minha conta' : 'My account');
    let loginLabel = $derived(language === 'pt' ? 'Entrar' : 'Log in');
    let adminLabel = $derived(language === 'pt' ? 'Administração' : 'Administration');
    let moderationLabel = $derived(language === 'pt' ? 'Moderação' : 'Moderation');
    let profileLabel = $derived(language === 'pt' ? 'Ver perfil' : 'View profile');
    let logoutLabel = $derived(language === 'pt' ? 'Terminar sessão' : 'Log out');
    let suspendedLabel = $derived(language === 'pt' ? 'Conta suspensa' : 'Account suspended');
    let displayName = $derived(getDisplayName(user));
    let avatarPresentation = $derived(getAvatarPresentation(user));
    let initials = $derived(avatarPresentation.symbol);
    let avatarUrl = $derived(avatarFailed ? null : avatarPresentation.image);

    async function refreshAccess() {
        if (!user) {
            role = 'user';
            return;
        }

        const supabase = getSupabaseBrowserClient();
        const [{ data: roleData }, { data: statusData }] = await Promise.all([
            supabase.rpc('get_deepmap_role'),
            supabase.rpc('get_deepmap_account_status')
        ]);

        const status = Array.isArray(statusData) ? statusData[0] : statusData;
        role = status?.is_banned === true ? 'banned' : (typeof roleData === 'string' ? roleData : 'user');
    }

    function announceHeaderPanelOpen(source = 'account') {
        if (typeof window !== 'undefined') {
            window.dispatchEvent(new CustomEvent('deepmap:header-panel-open', { detail: { source } }));
        }
    }

    function toggleMenu() {
        menuOpen = !menuOpen;
        if (menuOpen) {
            announceHeaderPanelOpen('account');
            void refreshAccess();
        }
    }

    async function logout() {
        menuOpen = false;
        await getSupabaseBrowserClient().auth.signOut();
        window.location.assign('/');
    }

    function closeMenu() {
        menuOpen = false;
    }

    function handleDocumentPointerDown(event) {
        if (!menuOpen || !menuWrap) return;
        if (!menuWrap.contains(event.target)) menuOpen = false;
    }

    function handleDocumentKeyDown(event) {
        if (event.key === 'Escape') menuOpen = false;
    }

    onMount(() => {
        const supabase = getSupabaseBrowserClient();
        let active = true;

        document.addEventListener('pointerdown', handleDocumentPointerDown);
        document.addEventListener('keydown', handleDocumentKeyDown);

        const { data: { subscription } } = supabase.auth.onAuthStateChange(
            async (_event, session) => {
                if (!active) return;
                user = session?.user ?? null;
                avatarFailed = false;
                checkingSession = false;
                await refreshAccess();
            }
        );

        async function loadUser() {
            const { data, error } = await supabase.auth.getUser();
            if (!active) return;
            user = error ? null : (data.user ?? null);
            checkingSession = false;
            await refreshAccess();
        }

        void loadUser();

        return () => {
            active = false;
            subscription.unsubscribe();
            document.removeEventListener('pointerdown', handleDocumentPointerDown);
            document.removeEventListener('keydown', handleDocumentKeyDown);
        };
    });
</script>

{#if checkingSession}
    <span class="auth-placeholder" aria-label={language === 'pt' ? 'A verificar sessão' : 'Checking session'}></span>
{:else if user}
    <NotificationBell userId={user.id} {language} />
    <div class="account-wrap" bind:this={menuWrap}>
        <button
            type="button"
            class="avatar-link"
            title={accountLabel}
            aria-label={`${accountLabel}: ${displayName}`}
            aria-expanded={menuOpen}
            onclick={toggleMenu}
        >
            {#if avatarUrl}
                <img src={avatarUrl} alt="" referrerpolicy="no-referrer" onerror={() => { avatarFailed = true; }} />
            {:else}
                <span aria-hidden="true">{initials}</span>
            {/if}
        </button>

        {#if menuOpen}
            <div class="account-menu">
                <div class="account-summary">
                    <strong>{displayName}</strong>
                    {#if role === 'admin'}<small>Admin</small>{:else if role === 'moderator'}<small>{moderationLabel}</small>{:else if role === 'banned'}<small>{suspendedLabel}</small>{/if}
                </div>
                {#if role === 'banned'}
                    <a class="staff suspended" href="/suspended" onclick={closeMenu}>{suspendedLabel}</a>
                {:else}
                    <a href="/profile" onclick={closeMenu}>{profileLabel}</a>
                    {#if role === 'admin'}
                        <a class="staff" href="/admin" onclick={closeMenu}>{adminLabel}</a>
                    {:else if role === 'moderator'}
                        <a class="staff" href="/moderation" onclick={closeMenu}>{moderationLabel}</a>
                    {/if}
                {/if}
                <button class="logout-action" type="button" onclick={logout}>{logoutLabel}</button>
            </div>
        {/if}
    </div>
{:else}
    <a class="login-link" href={`/login?next=${encodeURIComponent(page.url.pathname + page.url.search + page.url.hash)}`}>{loginLabel}</a>
{/if}

<style>
    .auth-placeholder{display:block;width:36px;height:36px;flex:0 0 36px}.login-link,.avatar-link{display:inline-flex;align-items:center;justify-content:center;flex:0 0 auto;box-sizing:border-box;text-decoration:none;cursor:pointer}.login-link{min-height:34px;padding:0 11px;border:1px solid #c8a355;border-radius:6px;color:#c8a355;background:#22222a;font-size:.82rem;font-weight:700;white-space:nowrap}.login-link:hover{background:#35312a}.account-wrap{position:relative;display:inline-flex}.avatar-link{width:36px;height:36px;padding:0;overflow:hidden;border:2px solid #c8a355;border-radius:50%;background:#292933;color:#c8a355;font-size:.95rem;font-weight:700}.avatar-link img{width:100%;height:100%;object-fit:cover}.account-menu{position:absolute;top:44px;right:0;width:190px;padding:7px;border:1px solid #3a352a;border-radius:10px;background:rgba(13,13,16,.99);box-shadow:0 16px 42px rgba(0,0,0,.5);z-index:90000}.account-summary{display:grid;gap:2px;padding:7px 8px 9px;border-bottom:1px solid #2a2a30}.account-summary strong{overflow:hidden;color:#eee;font-size:.78rem;text-overflow:ellipsis;white-space:nowrap}.account-summary small{color:#777;font-size:.62rem}.account-menu a,.logout-action{display:block;width:100%;box-sizing:border-box;margin-top:4px;padding:8px 9px;border:0;border-radius:7px;background:transparent;color:#c9c9cf;text-align:left;text-decoration:none;font:inherit;font-size:.75rem;font-weight:700;cursor:pointer}.account-menu a:hover,.logout-action:hover{background:#1b1b21;color:#efd184}.account-menu a.staff{color:#d8b86f}.account-menu a.suspended{color:#ffb4bd}.logout-action{color:#aaa}.login-link:focus-visible,.avatar-link:focus-visible{outline:2px solid #fff;outline-offset:3px}
    @media(max-width:768px){.login-link{padding:0 8px;font-size:.75rem}.avatar-link,.auth-placeholder{width:32px;height:32px;flex-basis:32px}.account-menu{position:fixed;top:calc(var(--deepmap-site-header-height,62px) + 6px);right:8px;width:min(230px,calc(100vw - 16px))}}
</style>
