
<script>
    import { onMount } from 'svelte';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';

    let checkingSession = $state(true);
    let canReset = $state(false);
    let working = $state(false);
    let finished = $state(false);

    let password = $state('');
    let confirmPassword = $state('');

    let errorMessage = $state('');
    let successMessage = $state('');

    // ==========================================
    // VALIDAR SESSÃO RECEBIDA PELO LINK
    // ==========================================

    onMount(() => {
        let active = true;

        async function checkSession() {
            const supabase = getSupabaseBrowserClient();

            const { data, error } = await supabase.auth.getUser();

            if (!active) return;

            canReset = !error && !!data.user;
            checkingSession = false;
        }

        checkSession();

        return () => {
            active = false;
        };
    });

    // ==========================================
    // DEFINIR NOVA PALAVRA-PASSE
    // ==========================================

    async function updatePassword(event) {
        event.preventDefault();

        errorMessage = '';
        successMessage = '';

        if (password.length < 8) {
            errorMessage = 'A palavra-passe deve ter pelo menos 8 caracteres.';
            return;
        }

        if (password !== confirmPassword) {
            errorMessage = 'As palavras-passe não coincidem.';
            return;
        }

        working = true;

        const supabase = getSupabaseBrowserClient();

        const { error } = await supabase.auth.updateUser({
            password
        });

        if (error) {
            errorMessage = error.message;
            working = false;
            return;
        }

        // Limpar os campos após a alteração.
        password = '';
        confirmPassword = '';
        finished = true;

        // Depois da alteração, pedir novo login.
        const { error: logoutError } = await supabase.auth.signOut();

        working = false;

        if (logoutError) {
            successMessage =
                'Palavra-passe alterada! Termina a sessão atual antes de voltares a entrar.';
            return;
        }

        // Regressar ao login, já sem sessão iniciada.
        window.location.replace('/login?password_reset=1');
    }
</script>

<svelte:head>
    <title>Nova palavra-passe — DeepMap</title>
</svelte:head>

<main class="auth-page">
    <div class="auth-card">

        <img
            src="/brand/logo.png"
            alt="DeepMap"
            class="auth-logo"
        />

        <h1>Nova palavra-passe</h1>

        {#if checkingSession}

            <p>A verificar o link de recuperação...</p>

        {:else if !canReset}

            <p class="error-message">
                Não foi possível validar a sessão de recuperação.
                O link pode ter expirado ou já ter sido utilizado.
            </p>

            <a href="/login" class="back-link">
                Voltar ao login
            </a>

        {:else if finished}

            <p class="success-message">
                {successMessage || 'Palavra-passe alterada com sucesso!'}
            </p>

            <a href="/login" class="back-link">
                Voltar ao login
            </a>

        {:else}

            <p>
                Escolhe uma nova palavra-passe para a tua conta DeepMap.
            </p>

            <form onsubmit={updatePassword}>

                <label for="new-password">
                    Nova palavra-passe
                </label>

                <input
                    id="new-password"
                    type="password"
                    bind:value={password}
                    autocomplete="new-password"
                    placeholder="Mínimo de 8 caracteres"
                    minlength="8"
                    required
                    disabled={working}
                />

                <label for="confirm-password">
                    Confirmar palavra-passe
                </label>

                <input
                    id="confirm-password"
                    type="password"
                    bind:value={confirmPassword}
                    autocomplete="new-password"
                    placeholder="Repete a nova palavra-passe"
                    minlength="8"
                    required
                    disabled={working}
                />

                <button
                    type="submit"
                    disabled={working}
                >
                    {working
                        ? 'A guardar...'
                        : 'Guardar nova palavra-passe'}
                </button>

            </form>

            {#if errorMessage}
                <p class="error-message" role="alert">
                    {errorMessage}
                </p>
            {/if}

            <a href="/login" class="back-link">
                ← Voltar ao login
            </a>

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
</style>
