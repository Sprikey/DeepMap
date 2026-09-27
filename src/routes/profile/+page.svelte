
<script>
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';

    let user = $state(null);
    let checkingSession = $state(true);
    let working = $state(false);
    let errorMessage = $state('');
    let avatarFailed = $state(false);

    // Dados disponíveis na conta Supabase.
    // O Google fornece normalmente nome e fotografia.
    let displayName = $derived(
        user?.user_metadata?.full_name ||
        user?.user_metadata?.name ||
        user?.email?.split('@')[0] ||
        'Explorador'
    );

    let avatarUrl = $derived(
        user?.user_metadata?.avatar_url ||
        user?.user_metadata?.picture ||
        null
    );

    let initial = $derived(
        displayName.charAt(0).toLocaleUpperCase('pt-PT')
    );

    // ==========================================
    // VERIFICAR SESSÃO
    // ==========================================

    onMount(() => {
        const supabase = getSupabaseBrowserClient();
        let active = true;

        async function checkSession() {
            const { data, error } = await supabase.auth.getUser();

            if (!active) return;

            if (error && error.name !== 'AuthSessionMissingError') {
                errorMessage =
                    'Não foi possível verificar a sessão. Experimenta atualizar a página.';
            }

            user = error ? null : data.user;
            checkingSession = false;
        }

        checkSession();

        // Mantém o perfil atualizado quando a sessão muda.
        const { data: { subscription } } =
            supabase.auth.onAuthStateChange((event, session) => {
                if (!active || event === 'INITIAL_SESSION') return;

                user = session?.user ?? null;
                avatarFailed = false;
                checkingSession = false;
            });

        return () => {
            active = false;
            subscription.unsubscribe();
        };
    });

    // ==========================================
    // TERMINAR SESSÃO
    // ==========================================

    async function logout() {
        if (working) return;

        working = true;
        errorMessage = '';

        const supabase = getSupabaseBrowserClient();

        const { error } = await supabase.auth.signOut();

        if (error) {
            errorMessage = error.message;
            working = false;
            return;
        }

        await goto('/login');
    }
</script>

<svelte:head>
    <title>O meu perfil — DeepMap</title>
    <meta
        name="description"
        content="Perfil da tua conta DeepMap."
    />
</svelte:head>

<main class="profile-page">

    <div class="profile-container">

        <!-- NAVEGAÇÃO -->

        <div class="top-navigation">
            <a href="/" class="back-link">
                ← Voltar ao mapa
            </a>
        </div>

        <!-- PERFIL -->

        <section class="profile-card">

            <img
                src="/brand/logo.png"
                alt="DeepMap"
                class="brand-logo"
            />

            {#if checkingSession}

                <div class="status-message">
                    A carregar o teu perfil...
                </div>

            {:else if !user}

                <!-- UTILIZADOR SEM SESSÃO -->

                <div class="avatar fallback-avatar">
                    <span>?</span>
                </div>

                <h1>O meu perfil</h1>

                <p class="description">
                    Inicia sessão para acederes ao teu perfil DeepMap.
                </p>

                {#if errorMessage}
                    <p class="error-message" role="alert">
                        {errorMessage}
                    </p>
                {/if}

                <a href="/login?next=%2Fprofile" class="primary-link">
                    Entrar
                </a>

            {:else}

                <!-- UTILIZADOR AUTENTICADO -->

                <div class="profile-heading">
                    <div class="avatar">

                        {#if avatarUrl && !avatarFailed}

                            <img
                                src={avatarUrl}
                                alt={`Avatar de ${displayName}`}
                                referrerpolicy="no-referrer"
                                onerror={() => avatarFailed = true}
                            />

                        {:else}

                            <span>{initial}</span>

                        {/if}

                    </div>

                    <h1>{displayName}</h1>

                    <span class="account-badge">
                        Conta DeepMap
                    </span>
                </div>

                <div class="profile-details">

                    <div class="detail-row">
                        <span class="detail-label">
                            Nome
                        </span>

                        <strong>
                            {displayName}
                        </strong>
                    </div>

                    <div class="detail-row">
                        <span class="detail-label">
                            Email
                        </span>

                        <strong class="email-value">
                            {user.email || 'Não disponível'}
                        </strong>
                    </div>

                    <div class="detail-row">
                        <span class="detail-label">
                            Método de registo
                        </span>

                        <strong>
                            {user.app_metadata?.provider === 'google'
                                ? 'Google'
                                : 'Email'}
                        </strong>
                    </div>

                </div>

                <div class="profile-note">
                    Em breve poderás personalizar o nome,
                    escolher um avatar oficial do DeepMap
                    ou carregar a tua própria imagem.
                </div>

                {#if errorMessage}
                    <p class="error-message" role="alert">
                        {errorMessage}
                    </p>
                {/if}

                <button
                    type="button"
                    class="logout-button"
                    onclick={logout}
                    disabled={working}
                >
                    {working
                        ? 'A terminar sessão...'
                        : 'Terminar sessão'}
                </button>

            {/if}

        </section>

    </div>

</main>

<style>
    .profile-page {
        min-height: 100vh;
        min-height: 100dvh;
        width: 100%;
        box-sizing: border-box;

        display: flex;
        justify-content: center;

        padding: 35px 20px 50px;

        background: #0b0b0e;
        color: #e0e0e0;

        font-family:
            'Segoe UI',
            Arial,
            sans-serif;
    }

    .profile-container {
        width: 100%;
        max-width: 640px;
    }

    .top-navigation {
        margin-bottom: 20px;
    }

    .back-link {
        color: #c8a355;
        text-decoration: none;
        font-size: 0.9rem;
    }

    .back-link:hover {
        text-decoration: underline;
    }

    .profile-card {
        width: 100%;
        box-sizing: border-box;

        padding: 35px;

        background: #16161a;
        border: 1px solid #333340;
        border-radius: 14px;

        text-align: center;
    }

    .brand-logo {
        display: block;

        width: auto;
        max-width: 150px;
        height: auto;
        max-height: 65px;

        object-fit: contain;

        margin: 0 auto 28px;
    }

    .status-message {
        color: #a0a0aa;
        padding: 40px 0;
    }

    .profile-heading {
        display: flex;
        flex-direction: column;
        align-items: center;
    }

    .avatar {
        width: 100px;
        height: 100px;

        display: flex;
        align-items: center;
        justify-content: center;

        margin: 0 auto 15px;

        border-radius: 50%;
        border: 3px solid #c8a355;

        background: #292933;
        color: #c8a355;

        overflow: hidden;

        font-size: 2.5rem;
        font-weight: 700;
    }

    .avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
    }

    h1 {
        margin: 5px 0 12px;

        font-size: 1.65rem;
        color: #fff;
        overflow-wrap: anywhere;
    }

    .account-badge {
        display: inline-block;

        padding: 6px 12px;

        border: 1px solid #5c4b2c;
        border-radius: 20px;

        background: #29251b;
        color: #c8a355;

        font-size: 0.75rem;
        font-weight: 700;
    }

    .description {
        color: #a0a0aa;
        line-height: 1.6;
    }

    .profile-details {
        margin-top: 32px;

        border: 1px solid #333340;
        border-radius: 9px;

        overflow: hidden;
        text-align: left;
    }

    .detail-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 15px;

        padding: 17px 18px;

        border-bottom: 1px solid #333340;
    }

    .detail-row:last-child {
        border-bottom: none;
    }

    .detail-label {
        color: #a0a0aa;
        font-size: 0.85rem;
    }

    .detail-row strong {
        font-size: 0.9rem;
        text-align: right;
        overflow-wrap: anywhere;
        min-width: 0;
    }

    .email-value {
        color: #c8a355;
    }

    .profile-note {
        margin-top: 25px;
        padding: 16px;

        background: #222229;
        border: 1px solid #333340;
        border-radius: 8px;

        color: #a0a0aa;
        font-size: 0.85rem;
        line-height: 1.6;
    }

    .logout-button {
        width: 100%;

        margin-top: 25px;
        padding: 13px;

        border: 1px solid #454550;
        border-radius: 7px;

        background: #292933;
        color: #fff;

        font: inherit;
        font-weight: 600;

        cursor: pointer;
    }

    .logout-button:hover {
        background: #363640;
    }

    .logout-button:disabled {
        opacity: 0.6;
        cursor: wait;
    }

    .primary-link {
        display: block;

        margin-top: 25px;
        padding: 13px;

        border-radius: 7px;

        background: #c8a355;
        color: #171717;

        text-decoration: none;
        font-weight: 700;
    }

    .error-message {
        color: #ff8585;
        font-size: 0.85rem;
    }

    @media (max-width: 600px) {

        .profile-page {
            padding: 18px 12px 35px;
        }

        .profile-card {
            padding: 25px 17px;
        }

        .detail-row {
            align-items: flex-start;
            flex-direction: column;
            gap: 7px;
        }

        .detail-row strong {
            text-align: left;
        }

        .avatar {
            width: 85px;
            height: 85px;
        }

    }
</style>
