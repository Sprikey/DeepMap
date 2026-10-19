<script>
    import { onMount } from 'svelte';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { getSiteLanguage, setSiteLanguage, subscribeSiteLanguage } from '$lib/i18n/site.js';
    import { authTranslations } from '$lib/i18n/auth.js';

    let currentLanguage = $state('en');
    let texts = $derived(authTranslations[currentLanguage] ?? authTranslations.en);

    let checkingSession = $state(true);
    let canReset = $state(false);
    let working = $state(false);
    let finished = $state(false);
    let password = $state('');
    let confirmPassword = $state('');
    let errorKey = $state('');
    let successKey = $state('');


    let mounted = false;
    /** @type {string | null} */
    let accountId = null;
    /** @type {string | null} */
    let sessionToken = null;
    let identityGeneration = 0;
    let mutationGeneration = 0;
    /** @typedef {{ actor: string, identity: number, mutation: number, phase: string, signedOut?: boolean }} PasswordOperation */
    /** @type {PasswordOperation | null} */
    let activeOperation = null;

    /** @param {PasswordOperation} operation */
    function ownsOperation(operation) {
        return mounted && activeOperation === operation && operation.identity === identityGeneration &&
            operation.mutation === mutationGeneration && (accountId === operation.actor ||
                (operation.phase === 'signout' && operation.signedOut === true && accountId === null));
    }

    /** @param {string} event @param {{ user: { id: string }, access_token?: string } | null} session */
    function replaceSession(event, session) {
        const operation = activeOperation;
        const sameAccount = !!session && session.user.id === accountId;
        const ownPasswordUpdate = operation && ownsOperation(operation) && operation.phase === 'password' &&
            event === 'USER_UPDATED' && !!sessionToken && session?.access_token === sessionToken &&
            session.user.id === operation.actor;
        const ownSignout = operation && ownsOperation(operation) && operation.phase === 'signout' &&
            event === 'SIGNED_OUT' && !session;
        identityGeneration += 1;
        accountId = session?.user.id ?? null;
        sessionToken = session?.access_token ?? null;
        if (operation && (ownPasswordUpdate || ownSignout)) {
            // Acknowledge only this operation's unchanged-session SDK event.
            operation.identity = identityGeneration;
            if (ownPasswordUpdate) operation.phase = 'password-acknowledged';
            if (ownSignout) operation.signedOut = true;
            return;
        }
        mutationGeneration += 1;
        activeOperation = null;
        canReset = accountId !== null && !!sessionToken;
        checkingSession = accountId !== null && !sessionToken;
        working = false;
        if (!sameAccount) {
            finished = false;
            password = '';
            confirmPassword = '';
            errorKey = '';
            successKey = '';
        } else if (operation) {
            // Cancelled update ownership must not erase this account's retry input.
            finished = false;
            errorKey = '';
            successKey = '';
        }
    }

    onMount(() => {
        mounted = true;
        currentLanguage = setSiteLanguage(getSiteLanguage());
        const unsubscribeLanguage = subscribeSiteLanguage((language) => { currentLanguage = language; });
        const supabase = getSupabaseBrowserClient();
        const initialGeneration = identityGeneration;
        const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
            if (mounted) replaceSession(event, session);
        });
        void (async () => {
            try {
                const { data, error } = await supabase.auth.getUser();
                if (mounted && identityGeneration === initialGeneration) {
                    // Only the auth subscription can supply the owning session token.
                    if (error || !data.user) replaceSession('BOOTSTRAP', null);
                }
            } catch {
                if (mounted && identityGeneration === initialGeneration) replaceSession('BOOTSTRAP', null);
            }
        })();
        return () => {
            mounted = false;
            identityGeneration += 1;
            mutationGeneration += 1;
            activeOperation = null;
            unsubscribeLanguage();
            subscription.unsubscribe();
        };
    });

    async function updatePassword(event) {
        event.preventDefault();
        if (working || !mounted || !canReset || !accountId || !sessionToken) return;
        errorKey = '';
        successKey = '';
        if (password.length < 8) { errorKey = 'password_too_short'; return; }
        if (password !== confirmPassword) { errorKey = 'password_mismatch'; return; }

        const operation = { actor: accountId, identity: identityGeneration,
            mutation: ++mutationGeneration, phase: 'password' };
        activeOperation = operation;
        working = true;
        const supabase = getSupabaseBrowserClient();
        try {
            const { error } = await supabase.auth.updateUser({ password });
            if (!ownsOperation(operation)) return;
            if (error) { errorKey = error.status === 429 ? 'rate_limit' : 'reset_update_error'; return; }
            password = '';
            confirmPassword = '';
            finished = true;
            operation.phase = 'signout';
            const { error: logoutError } = await supabase.auth.signOut();
            if (!ownsOperation(operation)) return;
            if (logoutError) { successKey = 'reset_signout_error'; return; }
            window.location.replace('/login?password_reset=1');
        } catch {
            if (ownsOperation(operation)) errorKey = 'reset_update_error';
        } finally {
            if (ownsOperation(operation)) {
                working = false;
                activeOperation = null;
            }
        }
    }
</script>

<svelte:head>
    <title>{texts.reset_page_title}</title>
</svelte:head>

<main class="auth-page">
    <div class="auth-card">
        <h1>{texts.reset_heading}</h1>

        {#if checkingSession}
            <p>{texts.checking_recovery}</p>
        {:else if !canReset}
            <p class="error-message" role="alert">{texts.invalid_recovery}</p>
            <a href="/login" class="back-link">{texts.login_link}</a>
        {:else if finished}
            <p class="success-message" role="status">{successKey ? texts[successKey] : texts.reset_success}</p>
            <a href="/login" class="back-link">{texts.login_link}</a>
        {:else}
            <p>{texts.reset_instruction}</p>
            <form onsubmit={updatePassword}>
                <label for="new-password">{texts.new_password}</label>
                <input id="new-password" type="password" bind:value={password}
                    autocomplete="new-password" placeholder={texts.password_new_hint}
                    minlength="8" required disabled={working} />

                <label for="confirm-password">{texts.confirm_password}</label>
                <input id="confirm-password" type="password" bind:value={confirmPassword}
                    autocomplete="new-password" placeholder={texts.repeat_new_password}
                    minlength="8" required disabled={working} />

                <button type="submit" disabled={working}>
                    {working ? texts.saving : texts.save_new_password}
                </button>
            </form>

            {#if errorKey}
                <p class="error-message" role="alert">{texts[errorKey] ?? texts.reset_update_error}</p>
            {/if}
            <a href="/login" class="back-link">{texts.back_to_login}</a>
        {/if}
    </div>
</main>

<style>

    .auth-page {
        min-height: 100dvh;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 20px;
        box-sizing: border-box;
        background: #0b0b0e;
        color: #e0e0e0;
        font-family: 'Segoe UI', Arial, sans-serif;
    }

    .auth-card {
        width: 100%;
        max-width: 390px;
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

    p {
        color: #a0a0aa;
        font-size: 0.9rem;
        line-height: 1.5;
    }

    form {
        display: flex;
        flex-direction: column;
        gap: 10px;
        margin-top: 24px;
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

    button {
        width: 100%;
        margin-top: 15px;
        padding: 13px;
        border: 0;
        border-radius: 6px;
        background: #c8a355;
        color: #171717;
        font: inherit;
        font-weight: 700;
        cursor: pointer;
    }

    button:disabled {
        opacity: 0.6;
        cursor: wait;
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

    /* Scroll correto em janelas baixas, como na página de login. */
    .auth-page {
        min-height: 100vh;
        min-height: 100dvh;
        flex-direction: column;
        padding: 24px 16px;
    }
    .auth-card {
        flex-shrink: 0;
        margin-block: auto;
    }
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
