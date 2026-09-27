<script>
    import { onMount } from 'svelte';
    import { page } from '$app/state';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { getDisplayName, getAvatarPresentation } from '$lib/avatar/avatars.js';

    // Componente reutilizável: podemos usá-lo no mapa e, mais tarde, na homepage.
    let { language = 'en' } = $props();

    let user = $state(null);
    let checkingSession = $state(true);
    let avatarFailed = $state(false);

    let accountLabel = $derived(language === 'pt' ? 'A minha conta' : 'My account');
    let loginLabel = $derived(language === 'pt' ? 'Entrar' : 'Log in');

    let displayName = $derived(getDisplayName(user));
    let avatarPresentation = $derived(getAvatarPresentation(user));
    let initials = $derived(avatarPresentation.symbol);
    let avatarUrl = $derived(avatarFailed ? null : avatarPresentation.image);

    onMount(() => {
        const supabase = getSupabaseBrowserClient();
        let active = true;

        const { data: { subscription } } = supabase.auth.onAuthStateChange(
            (_event, session) => {
                if (!active) return;
                user = session?.user ?? null;
                avatarFailed = false;
                checkingSession = false;
            }
        );

        async function loadUser() {
            const { data, error } = await supabase.auth.getUser();
            if (!active) return;

            user = error ? null : (data.user ?? null);
            checkingSession = false;
        }

        loadUser();

        return () => {
            active = false;
            subscription.unsubscribe();
        };
    });
</script>

{#if checkingSession}
    <span class="auth-placeholder" aria-label={language === 'pt' ? 'A verificar sessão' : 'Checking session'}></span>
{:else if user}
    <!-- Avatar: abrir o perfil do utilizador autenticado. -->
    <a
        href="/profile"
        class="avatar-link"
        title={accountLabel}
        aria-label={`${accountLabel}: ${displayName}`}
    >
        {#if avatarUrl}
            <img
                src={avatarUrl}
                alt=""
                referrerpolicy="no-referrer"
                onerror={() => { avatarFailed = true; }}
            />
        {:else}
            <span aria-hidden="true">{initials}</span>
        {/if}
    </a>
{:else}
    <a
        class="login-link"
        href={`/login?next=${encodeURIComponent(page.url.pathname + page.url.search + page.url.hash)}`}
    >{loginLabel}</a>
{/if}

<style>
    .auth-placeholder {
        display: block;
        width: 36px;
        height: 36px;
        flex: 0 0 36px;
    }

    .login-link,
    .avatar-link {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex: 0 0 auto;
        box-sizing: border-box;
        text-decoration: none;
        cursor: pointer;
    }

    .login-link {
        min-height: 34px;
        padding: 0 11px;
        border: 1px solid #c8a355;
        border-radius: 6px;
        color: #c8a355;
        background: #22222a;
        font-size: 0.82rem;
        font-weight: 700;
        white-space: nowrap;
    }

    .login-link:hover {
        background: #35312a;
    }

    .avatar-link {
        width: 36px;
        height: 36px;
        overflow: hidden;
        border: 2px solid #c8a355;
        border-radius: 50%;
        background: #292933;
        color: #c8a355;
        font-size: 0.95rem;
        font-weight: 700;
    }

    .avatar-link img {
        width: 100%;
        height: 100%;
        object-fit: cover;
    }

    .login-link:focus-visible,
    .avatar-link:focus-visible {
        outline: 2px solid #ffffff;
        outline-offset: 3px;
    }

    @media (max-width: 768px) {
        .login-link {
            padding: 0 8px;
            font-size: 0.75rem;
        }

        .avatar-link,
        .auth-placeholder {
            width: 32px;
            height: 32px;
            flex-basis: 32px;
        }
    }
</style>
