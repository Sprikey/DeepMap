<script>
    import { onMount } from 'svelte';
    import { goto, afterNavigate } from '$app/navigation';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { getSiteLanguage, setSiteLanguage } from '$lib/i18n/site.js';
    import { authTranslations } from '$lib/i18n/auth.js';

    let currentLanguage = $state('en');
    let texts = $derived(authTranslations[currentLanguage] ?? authTranslations.en);

    let userEmail = $state(null);
    let checkingSession = $state(true);
    let working = $state(false);
    let authMode = $state('login'); // login | register | recover

    let email = $state('');
    let password = $state('');
    let confirmPassword = $state('');
    let showPassword = $state(false);
    let showConfirmPassword = $state(false);
    let errorKey = $state('');
    let successKey = $state('');

    let returnTo = $state('/profile');
    let previousPage = $state(null);
    let referrerPage = $state(null);
    // 'next' define o destino depois do login, nunca o destino do botão Voltar.
    let backDestination = $derived(previousPage ?? referrerPage ?? '/');

    // Guarda apenas uma página anterior do próprio DeepMap, nunca um site externo.
    function safePreviousPage(raw, currentPath) {
        if (!raw) return null;
        try {
            const url = new URL(raw, window.location.href);
            if (
                url.origin !== window.location.origin ||
                url.pathname === currentPath ||
                // Nunca regressar a uma conta privada pelo botão Voltar do login.
                url.pathname.replace(/\/+$/, '') === '/profile' ||
                url.pathname === '/reset-password' ||
                url.pathname.startsWith('/auth/')
            ) return null;
            return url.pathname + url.search + url.hash;
        } catch {
            return null;
        }
    }

    afterNavigate(({ from }) => {
        const previous = safePreviousPage(from?.url?.href, '/login');
        if (previous) previousPage = previous;
    });

    function goBack(event) {
        event.preventDefault();
        void goto(backDestination, { replaceState: true });
    }

    function changeLanguage(event) {
        currentLanguage = setSiteLanguage(event.currentTarget.value);
    }

    function safeReturnPath(raw) {
        if (
            typeof raw !== 'string' ||
            !raw.startsWith('/') ||
            raw.startsWith('//') ||
            raw.includes('\\') ||
            /[\u0000-\u001f\u007f]/.test(raw)
        ) return '/profile';

        try {
            const target = new URL(raw, window.location.origin);
            if (
                target.origin !== window.location.origin ||
                target.pathname === '/login' ||
                target.pathname === '/reset-password' ||
                target.pathname.startsWith('/auth/')
            ) return '/profile';

            return target.pathname + target.search + target.hash;
        } catch {
            return '/profile';
        }
    }

    function authErrorKey(error, fallback) {
        if (error?.code === 'invalid_credentials') return 'invalid_credentials';
        if (error?.code === 'email_not_confirmed') return 'email_not_confirmed';
        if (
            error?.status === 429 ||
            ['over_email_send_rate_limit', 'over_request_rate_limit', 'too_many_requests'].includes(error?.code)
        ) return 'rate_limit';
        return fallback;
    }

    onMount(() => {
        currentLanguage = getSiteLanguage();
        referrerPage = safePreviousPage(document.referrer, '/login');
        const supabase = getSupabaseBrowserClient();
        const params = new URLSearchParams(window.location.search);
        let active = true;

        returnTo = safeReturnPath(params.get('next'));

        if (params.get('email_confirmed') === '1') successKey = 'email_confirmed';
        if (params.get('password_reset') === '1') successKey = 'password_reset_done';
        if (params.has('auth_error')) errorKey = 'auth_error';

        async function checkSession() {
            const { data, error } = await supabase.auth.getUser();
            if (!active) return;

            userEmail = error ? null : (data.user?.email ?? null);
            const shouldRedirect = !error && data.user &&
                !params.has('email_confirmed') &&
                !params.has('password_reset') &&
                !params.has('auth_error');
            if (shouldRedirect) {
                try {
                    await goto(returnTo, { replaceState: true });
                } catch {
                    // Se a navegação falhar, manter o acesso manual ao perfil.
                }
            }
            if (active) checkingSession = false;
        }

        checkSession();

        const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
            if (active) userEmail = session?.user?.email ?? null;
        });

        return () => {
            active = false;
            subscription.unsubscribe();
        };
    });

    function changeAuthMode(mode) {
        authMode = mode;
        password = '';
        confirmPassword = '';
        showPassword = false;
        showConfirmPassword = false;
        errorKey = '';
        successKey = '';
    }

    async function loginWithEmail(event) {
        event.preventDefault();
        if (working) return;
        working = true;
        errorKey = '';
        successKey = '';

        const supabase = getSupabaseBrowserClient();
        const { data, error } = await supabase.auth.signInWithPassword({
            email: email.trim(), password
        });

        if (error) {
            working = false;
            errorKey = authErrorKey(error, 'sign_in_error');
            return;
        }

        userEmail = data.user?.email ?? null;
        password = '';
        showPassword = false;
        // Manter o formulário em estado de processamento até sair da rota.
        try {
            await goto(returnTo, { replaceState: true });
        } catch {
            working = false; // Aparece o acesso manual ao perfil se falhar.
        }
    }

    async function registerWithEmail(event) {
        event.preventDefault();
        if (working) return;
        errorKey = '';
        successKey = '';

        if (password !== confirmPassword) {
            errorKey = 'password_mismatch';
            return;
        }
        if (password.length < 8) {
            errorKey = 'password_too_short';
            return;
        }

        working = true;
        const supabase = getSupabaseBrowserClient();
        const { error } = await supabase.auth.signUp({
            email: email.trim(), password,
            options: {
                emailRedirectTo: `${window.location.origin}/auth/callback?next=%2Flogin%3Femail_confirmed%3D1`
            }
        });
        working = false;

        if (error) {
            errorKey = authErrorKey(error, 'registration_error');
            return;
        }

        successKey = 'registration_sent';
        password = '';
        confirmPassword = '';
        showPassword = false;
        showConfirmPassword = false;
    }

    async function recoverPassword(event) {
        event.preventDefault();
        if (working) return;
        working = true;
        errorKey = '';
        successKey = '';

        const supabase = getSupabaseBrowserClient();
        const redirectTo = `${window.location.origin}/auth/callback?next=%2Freset-password`;
        const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo });
        working = false;

        if (error) {
            errorKey = authErrorKey(error, 'recovery_error');
            return;
        }
        successKey = 'recovery_sent';
    }

    async function loginWithGoogle() {
        if (working) return;
        working = true;
        errorKey = '';
        successKey = '';

        const supabase = getSupabaseBrowserClient();
        const { error } = await supabase.auth.signInWithOAuth({
            provider: 'google',
            options: {
                redirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent(returnTo)}`,
                queryParams: { prompt: 'select_account' }
            }
        });
        if (error) {
            errorKey = 'google_error';
            working = false;
        }
    }

    async function logout() {
        if (working) return;
        working = true;
        errorKey = '';
        successKey = '';
        const supabase = getSupabaseBrowserClient();
        const { error } = await supabase.auth.signOut();

        if (error) {
            errorKey = 'sign_out_error';
        } else {
            userEmail = null;
            authMode = 'login';
            email = '';
            password = '';
            confirmPassword = '';
            showPassword = false;
            showConfirmPassword = false;
        }
        working = false;
    }
</script>

<svelte:head>
    <title>{texts.page_title}</title>
</svelte:head>

<main class="auth-page">
    <div class="auth-card">
        <div class="language-row">
            <label for="auth-language" class="language-label">{texts.language}</label>
            <select id="auth-language" value={currentLanguage} onchange={changeLanguage} aria-label={texts.language}>
                <option value="en">EN</option>
                <option value="pt">PT</option>
            </select>
        </div>

        <img src="/brand/logo.png" alt="DeepMap" class="auth-logo" />
        <h1>{texts.account}</h1>

        {#if checkingSession}
            <p>{texts.checking_session}</p>
        {:else if userEmail && !working}
            <p>{texts.signed_in_as}</p>
            <div class="user-email">{userEmail}</div>
            <a href="/profile" class="submit-button profile-link">
                {currentLanguage === 'pt' ? 'Ir para o perfil' : 'Go to profile'}
            </a>
            <button type="button" class="logout-button" onclick={logout} disabled={working}>
                {working ? texts.signing_out : texts.sign_out}
            </button>
        {:else if authMode === 'recover'}
            <p>{texts.recover_explanation}</p>
            <form onsubmit={recoverPassword}>
                <label for="recover-email">{texts.email}</label>
                <input id="recover-email" type="email" bind:value={email} autocomplete="email"
                    placeholder={texts.email_placeholder} required disabled={working} />
                <button type="submit" class="submit-button" disabled={working}>
                    {working ? texts.sending : texts.send_recovery}
                </button>
            </form>
            <button type="button" class="text-button" onclick={() => changeAuthMode('login')} disabled={working}>
                {texts.back_to_login}
            </button>
        {:else}
            <p>{texts.intro}</p>
            <button type="button" class="google-button" onclick={loginWithGoogle} disabled={working}>
                <span class="google-logo">G</span>{texts.continue_google}
            </button>
            <div class="separator">{texts.or}</div>

            <div class="auth-tabs">
                <button type="button" class:active={authMode === 'login'}
                    onclick={() => changeAuthMode('login')} disabled={working}>{texts.sign_in}</button>
                <button type="button" class:active={authMode === 'register'}
                    onclick={() => changeAuthMode('register')} disabled={working}>{texts.create_account}</button>
            </div>

            <h2>{authMode === 'login' ? texts.sign_in_email : texts.create_account_email}</h2>
            <form onsubmit={authMode === 'login' ? loginWithEmail : registerWithEmail}>
                <label for="auth-email">{texts.email}</label>
                <input id="auth-email" type="email" bind:value={email} autocomplete="email"
                    placeholder={texts.email_placeholder} required disabled={working} />

                <label for="auth-password">{texts.password}</label>
                <div class="password-field">
                    <input id="auth-password" type={showPassword ? 'text' : 'password'} bind:value={password}
                        autocomplete={authMode === 'login' ? 'current-password' : 'new-password'}
                        placeholder={authMode === 'login' ? texts.password_placeholder : texts.password_new_hint}
                        minlength={authMode === 'register' ? 8 : undefined} required disabled={working} />
                    <button type="button" class="password-toggle" onclick={() => showPassword = !showPassword}
                        aria-label={currentLanguage === 'pt' ? (showPassword ? 'Ocultar palavra-passe' : 'Mostrar palavra-passe') : (showPassword ? 'Hide password' : 'Show password')}
                        title={currentLanguage === 'pt' ? (showPassword ? 'Ocultar palavra-passe' : 'Mostrar palavra-passe') : (showPassword ? 'Hide password' : 'Show password')}
                        aria-pressed={showPassword} disabled={working}>
                        {#if showPassword}
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                <path d="M3 3l18 18" />
                                <path d="M10.6 5.1A10.6 10.6 0 0 1 12 5c6.4 0 10 7 10 7a14.5 14.5 0 0 1-3.1 3.8" />
                                <path d="M6.5 6.5C3.5 8.5 2 12 2 12s3.6 7 10 7c1.7 0 3.3-.5 4.6-1.2" />
                                <path d="M10.6 10.6a2 2 0 0 0 2.8 2.8" />
                            </svg>
                        {:else}
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                <path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12Z" />
                                <circle cx="12" cy="12" r="3" />
                            </svg>
                        {/if}
                    </button>
                </div>

                {#if authMode === 'register'}
                    <label for="auth-confirm">{texts.confirm_password}</label>
                    <div class="password-field">
                        <input id="auth-confirm" type={showConfirmPassword ? 'text' : 'password'} bind:value={confirmPassword}
                            autocomplete="new-password" placeholder={texts.confirm_password_placeholder}
                            minlength="8" required disabled={working} />
                        <button type="button" class="password-toggle" onclick={() => showConfirmPassword = !showConfirmPassword}
                            aria-label={currentLanguage === 'pt' ? (showConfirmPassword ? 'Ocultar confirmação da palavra-passe' : 'Mostrar confirmação da palavra-passe') : (showConfirmPassword ? 'Hide password confirmation' : 'Show password confirmation')}
                            title={currentLanguage === 'pt' ? (showConfirmPassword ? 'Ocultar confirmação da palavra-passe' : 'Mostrar confirmação da palavra-passe') : (showConfirmPassword ? 'Hide password confirmation' : 'Show password confirmation')}
                            aria-pressed={showConfirmPassword} disabled={working}>
                            {#if showConfirmPassword}
                                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                    <path d="M3 3l18 18" />
                                    <path d="M10.6 5.1A10.6 10.6 0 0 1 12 5c6.4 0 10 7 10 7a14.5 14.5 0 0 1-3.1 3.8" />
                                    <path d="M6.5 6.5C3.5 8.5 2 12 2 12s3.6 7 10 7c1.7 0 3.3-.5 4.6-1.2" />
                                    <path d="M10.6 10.6a2 2 0 0 0 2.8 2.8" />
                                </svg>
                            {:else}
                                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                    <path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12Z" />
                                    <circle cx="12" cy="12" r="3" />
                                </svg>
                            {/if}
                        </button>
                    </div>
                {/if}

                <button type="submit" class="submit-button" disabled={working}>
                    {working ? texts.processing : authMode === 'login' ? texts.sign_in : texts.create_account}
                </button>
            </form>

            {#if authMode === 'login'}
                <button type="button" class="text-button" onclick={() => changeAuthMode('recover')}
                    disabled={working}>{texts.forgot_password}</button>
            {/if}
        {/if}

        {#if !checkingSession && !userEmail && authMode !== 'recover'}
            <a href="/privacy" class="privacy-link">
                {currentLanguage === 'pt' ? 'Política de Privacidade' : 'Privacy Policy'}
            </a>
        {/if}

        {#if errorKey}
            <p class="error-message" role="alert">{texts[errorKey] ?? texts.auth_error}</p>
        {/if}
        {#if successKey}
            <p class="success-message" role="status">{texts[successKey] ?? ''}</p>
        {/if}
        <a href={backDestination} class="back-link" onclick={goBack}>
            {currentLanguage === 'pt' ? '← Voltar' : '← Back'}
        </a>
    </div>
</main>

<style>

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

    .password-field {
        position: relative;
        width: 100%;
    }

    .password-field input {
        padding-right: 52px;
    }

    .password-toggle {
        position: absolute;
        top: 50%;
        right: 4px;
        transform: translateY(-50%);
        display: flex;
        align-items: center;
        justify-content: center;
        width: 42px;
        height: 42px;
        padding: 0;
        background: transparent;
        color: #bdbdc6;
        border: 0;
        border-radius: 6px;
    }

    .password-toggle:hover:not(:disabled) { color: #c8a355; }
    .password-toggle:focus-visible { outline: 2px solid #c8a355; outline-offset: 1px; }
    .password-toggle svg { width: 21px; height: 21px; }

    .profile-link {
        display: block;
        margin-top: 16px;
        text-align: center;
        text-decoration: none;
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

    .privacy-link {
        display: inline-block;
        margin-top: 19px;
        color: #c8a355;
        text-decoration: underline;
        text-underline-offset: 3px;
        font-size: 0.83rem;
    }

    .privacy-link:hover { color: #e5c894; }
    .privacy-link:focus-visible { outline: 2px solid #c8a355; outline-offset: 4px; }

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

    /* Idioma disponível também fora do mapa. */
    .language-row {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        gap: 8px;
        margin-bottom: 16px;
    }
    .language-label {
        margin: 0;
        color: #a0a0aa;
        font-size: 0.76rem;
    }
    .language-row select {
        padding: 5px 7px;
        border: 1px solid #41414d;
        border-radius: 5px;
        background: #22222a;
        color: #c8a355;
        font: inherit;
        font-size: 0.78rem;
        cursor: pointer;
    }
</style>
