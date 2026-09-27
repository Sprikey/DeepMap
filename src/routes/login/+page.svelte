<script>
    import { onMount } from 'svelte';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';

    // Sessão
    let userEmail = $state(null);
    let checkingSession = $state(true);
    let working = $state(false);

    // login | register | recover
    let authMode = $state('login');

    // Formulário
    let email = $state('');
    let password = $state('');
    let confirmPassword = $state('');

    // Mensagens
    let errorMessage = $state('');
    let successMessage = $state('');

    // ==========================================
    // VERIFICAR SESSÃO
    // ==========================================

    onMount(() => {
        const supabase = getSupabaseBrowserClient();
        let active = true;

        const params = new URLSearchParams(window.location.search);

        if (params.get('email_confirmed') === '1') {
            successMessage = 'Email confirmado! Já podes iniciar sessão.';
        }

        if (params.get('password_reset') === '1') {
            successMessage = 'Palavra-passe alterada! Já podes entrar com a nova palavra-passe.';
        }

        if (params.has('auth_error')) {
            errorMessage = 'Não foi possível concluir a autenticação. Tenta novamente.';
        }

        async function checkSession() {
            const { data, error } = await supabase.auth.getUser();

            if (!active) return;

            userEmail = error ? null : (data.user?.email ?? null);
            checkingSession = false;
        }

        checkSession();

        const { data: { subscription } } =
            supabase.auth.onAuthStateChange((_event, session) => {
                if (active) {
                    userEmail = session?.user?.email ?? null;
                }
            });

        return () => {
            active = false;
            subscription.unsubscribe();
        };
    });

    // ==========================================
    // MUDAR MODO
    // ==========================================

    function changeAuthMode(mode) {
        authMode = mode;
        password = '';
        confirmPassword = '';
        errorMessage = '';
        successMessage = '';
    }

    // ==========================================
    // LOGIN POR EMAIL
    // ==========================================

    async function loginWithEmail(event) {
        event.preventDefault();

        working = true;
        errorMessage = '';
        successMessage = '';

        const supabase = getSupabaseBrowserClient();

        const { data, error } = await supabase.auth.signInWithPassword({
            email: email.trim(),
            password
        });

        working = false;

        if (error) {
            if (error.code === 'invalid_credentials') {
                errorMessage = 'Email ou palavra-passe incorretos.';
            } else if (error.code === 'email_not_confirmed') {
                errorMessage = 'Tens de confirmar o email antes de entrar.';
            } else {
                errorMessage = error.message;
            }

            return;
        }

        userEmail = data.user?.email ?? null;
        password = '';
    }

    // ==========================================
    // REGISTO POR EMAIL
    // ==========================================

    async function registerWithEmail(event) {
        event.preventDefault();

        errorMessage = '';
        successMessage = '';

        if (password !== confirmPassword) {
            errorMessage = 'As palavras-passe não coincidem.';
            return;
        }

        if (password.length < 8) {
            errorMessage = 'A palavra-passe deve ter pelo menos 8 caracteres.';
            return;
        }

        working = true;

        const supabase = getSupabaseBrowserClient();

        const { error } = await supabase.auth.signUp({
            email: email.trim(),
            password,
            options: {
                emailRedirectTo:
                    `${window.location.origin}/auth/callback?next=%2Flogin%3Femail_confirmed%3D1`
            }
        });

        working = false;

        if (error) {
            errorMessage = error.message;
            return;
        }

        successMessage =
            'Se o endereço puder ser registado, receberás um email de confirmação. Verifica também o spam.';

        password = '';
        confirmPassword = '';
    }

    // ==========================================
    // RECUPERAR PALAVRA-PASSE
    // ==========================================

    async function recoverPassword(event) {
        event.preventDefault();

        working = true;
        errorMessage = '';
        successMessage = '';

        const supabase = getSupabaseBrowserClient();

        const redirectTo =
            `${window.location.origin}/auth/callback?next=%2Freset-password`;

        const { error } = await supabase.auth.resetPasswordForEmail(
            email.trim(),
            { redirectTo }
        );

        working = false;

        if (error) {
            errorMessage = error.message;
            return;
        }

        successMessage =
            'Se existir uma conta associada a esse email, receberás um link para alterar a palavra-passe. Verifica também o spam.';
    }

    // ==========================================
    // LOGIN GOOGLE
    // ==========================================

    async function loginWithGoogle() {
        working = true;
        errorMessage = '';
        successMessage = '';

        const supabase = getSupabaseBrowserClient();

        const { error } = await supabase.auth.signInWithOAuth({
            provider: 'google',
            options: {
                redirectTo:
                    `${window.location.origin}/auth/callback?next=%2Flogin`,
                queryParams: {
                    prompt: 'select_account'
                }
            }
        });

        if (error) {
            errorMessage = error.message;
            working = false;
        }
    }

    // ==========================================
    // LOGOUT
    // ==========================================

    async function logout() {
        working = true;
        errorMessage = '';
        successMessage = '';

        const supabase = getSupabaseBrowserClient();

        const { error } = await supabase.auth.signOut();

        if (error) {
            errorMessage = error.message;
        } else {
            userEmail = null;
            authMode = 'login';
            email = '';
            password = '';
            confirmPassword = '';
        }

        working = false;
    }
</script>

<svelte:head>
    <title>Entrar — DeepMap</title>
</svelte:head>

<main class="auth-page">
    <div class="auth-card">

        <img
            src="/brand/logo.png"
            alt="DeepMap"
            class="auth-logo"
        />

        <h1>Conta DeepMap</h1>

        {#if checkingSession}

            <p>A verificar sessão...</p>

        {:else if userEmail}

            <!-- SESSÃO INICIADA -->

            <p>Sessão iniciada como:</p>

            <div class="user-email">
                {userEmail}
            </div>

            <button
                type="button"
                class="logout-button"
                onclick={logout}
                disabled={working}
            >
                {working ? 'A terminar sessão...' : 'Terminar sessão'}
            </button>

        {:else if authMode === 'recover'}

            <!-- RECUPERAÇÃO -->

            <p>
                Introduz o email da tua conta.
                Vamos enviar-te um link para definires uma nova palavra-passe.
            </p>

            <form onsubmit={recoverPassword}>

                <label for="recover-email">Email</label>

                <input
                    id="recover-email"
                    type="email"
                    bind:value={email}
                    autocomplete="email"
                    placeholder="O teu email"
                    required
                    disabled={working}
                />

                <button
                    type="submit"
                    class="submit-button"
                    disabled={working}
                >
                    {working
                        ? 'A enviar...'
                        : 'Enviar link de recuperação'}
                </button>

            </form>

            <button
                type="button"
                class="text-button"
                onclick={() => changeAuthMode('login')}
                disabled={working}
            >
                ← Voltar ao login
            </button>

        {:else}

            <!-- GOOGLE -->

            <p>Entra ou cria a tua conta DeepMap.</p>

            <button
                type="button"
                class="google-button"
                onclick={loginWithGoogle}
                disabled={working}
            >
                <span class="google-logo">G</span>
                Continuar com Google
            </button>

            <div class="separator">ou</div>

            <!-- SEPARADORES -->

            <div class="auth-tabs">
                <button
                    type="button"
                    class:active={authMode === 'login'}
                    onclick={() => changeAuthMode('login')}
                    disabled={working}
                >
                    Entrar
                </button>

                <button
                    type="button"
                    class:active={authMode === 'register'}
                    onclick={() => changeAuthMode('register')}
                    disabled={working}
                >
                    Criar conta
                </button>
            </div>

            <h2>
                {authMode === 'login'
                    ? 'Entrar com email'
                    : 'Criar conta com email'}
            </h2>

            <!-- FORMULÁRIO EMAIL -->

            <form
                onsubmit={authMode === 'login'
                    ? loginWithEmail
                    : registerWithEmail}
            >

                <label for="auth-email">Email</label>

                <input
                    id="auth-email"
                    type="email"
                    bind:value={email}
                    autocomplete="email"
                    placeholder="O teu email"
                    required
                    disabled={working}
                />

                <label for="auth-password">Palavra-passe</label>

                <input
                    id="auth-password"
                    type="password"
                    bind:value={password}
                    autocomplete={authMode === 'login'
                        ? 'current-password'
                        : 'new-password'}
                    placeholder={authMode === 'login'
                        ? 'A tua palavra-passe'
                        : 'Mínimo de 8 caracteres'}
                    minlength={authMode === 'register' ? 8 : undefined}
                    required
                    disabled={working}
                />

                {#if authMode === 'register'}

                    <label for="auth-confirm">
                        Confirmar palavra-passe
                    </label>

                    <input
                        id="auth-confirm"
                        type="password"
                        bind:value={confirmPassword}
                        autocomplete="new-password"
                        placeholder="Repete a palavra-passe"
                        minlength="8"
                        required
                        disabled={working}
                    />

                {/if}

                <button
                    type="submit"
                    class="submit-button"
                    disabled={working}
                >
                    {working
                        ? 'A processar...'
                        : authMode === 'login'
                            ? 'Entrar'
                            : 'Criar conta'}
                </button>

            </form>

            {#if authMode === 'login'}
                <button
                    type="button"
                    class="text-button"
                    onclick={() => changeAuthMode('recover')}
                    disabled={working}
                >
                    Esqueci-me da palavra-passe
                </button>
            {/if}

        {/if}

        <!-- MENSAGENS -->

        {#if errorMessage}
            <p class="error-message" role="alert">
                {errorMessage}
            </p>
        {/if}

        {#if successMessage}
            <p class="success-message" role="status">
                {successMessage}
            </p>
        {/if}

        <a href="/" class="back-link">
            ← Voltar ao mapa
        </a>

    </div>
</main>

<style>
    /* O mapa bloqueia o scroll global. Libertá-lo só na rota de login. */
    :global(html:has(.auth-page)),
    :global(body:has(.auth-page)) {
        height: auto !important;
        overflow-y: auto !important;
    }

    .auth-page {
        min-height: 100vh;
        min-height: 100dvh;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        padding: 24px 16px;
        box-sizing: border-box;
        background: #0b0b0e;
        color: #e0e0e0;
        font-family: 'Segoe UI', Arial, sans-serif;
    }

    .auth-card {
        width: 100%;
        max-width: 390px;
        flex-shrink: 0;
        margin-block: auto;
        padding: 32px 25px;
        box-sizing: border-box;
        background: #16161a;
        border: 1px solid #333340;
        border-radius: 12px;
        text-align: center;
    }

    .auth-logo {
        max-width: 150px;
        max-height: 65px;
        object-fit: contain;
    }

    h1 {
        color: #c8a355;
        font-size: 1.4rem;
        margin: 20px 0 12px;
    }

    h2 {
        color: #e0e0e0;
        font-size: 1rem;
        margin: 20px 0;
    }

    p {
        color: #a0a0aa;
        font-size: 0.9rem;
        line-height: 1.5;
    }

    button {
        width: 100%;
        padding: 13px;
        border: 0;
        border-radius: 6px;
        font: inherit;
        font-weight: 700;
        cursor: pointer;
    }

    button:disabled {
        opacity: 0.6;
        cursor: wait;
    }

    .google-button {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 12px;
        margin-top: 25px;
        background: #ffffff;
        color: #222222;
    }

    .google-logo {
        font-size: 1.3rem;
        font-weight: 800;
        color: #4285f4;
    }

    .separator {
        margin: 24px 0;
        color: #777783;
        font-size: 0.85rem;
    }

    .auth-tabs {
        display: flex;
        gap: 8px;
        margin-top: 24px;
    }

    .auth-tabs button {
        background: #292933;
        color: #a0a0aa;
        font-size: 0.85rem;
    }

    .auth-tabs button.active {
        background: #c8a355;
        color: #171717;
    }

    form {
        display: flex;
        flex-direction: column;
        gap: 10px;
        text-align: left;
    }

    label {
        margin-top: 7px;
        color: #bdbdc6;
        font-size: 0.85rem;
    }

    input {
        width: 100%;
        padding: 12px;
        box-sizing: border-box;
        background: #22222a;
        border: 1px solid #41414d;
        border-radius: 6px;
        color: #ffffff;
        font: inherit;
    }

    input:focus {
        outline: 2px solid #c8a355;
        outline-offset: 1px;
    }

    .submit-button {
        margin-top: 15px;
        background: #c8a355;
        color: #171717;
    }

    .logout-button {
        margin-top: 20px;
        background: #292933;
        color: #ffffff;
    }

    .text-button {
        width: auto;
        margin-top: 18px;
        padding: 4px;
        background: none;
        color: #c8a355;
        font-size: 0.85rem;
        font-weight: 400;
    }

    .text-button:hover {
        text-decoration: underline;
    }

    .user-email {
        color: #c8a355;
        overflow-wrap: anywhere;
        font-weight: 600;
    }

    .error-message {
        color: #ff8585;
    }

    .success-message {
        color: #9ee0ac;
    }

    .back-link {
        display: inline-block;
        margin-top: 25px;
        color: #c8a355;
        text-decoration: none;
        font-size: 0.85rem;
    }

    .back-link:hover {
        text-decoration: underline;
    }
</style>
