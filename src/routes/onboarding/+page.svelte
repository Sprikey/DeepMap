<script>
    import { onMount } from 'svelte';
    import { getSiteLanguage, subscribeSiteLanguage } from '$lib/i18n/site.js';
    import { TERMS_VERSION, PRIVACY_VERSION } from '$lib/auth/legal.js';
    let { form } = $props();
    let language = $state('en');
    let working = $state(false);
    onMount(() => {
        language = getSiteLanguage();
        return subscribeSiteLanguage((/** @type {string} */ value) => language = value);
    });
    let pt = $derived(language === 'pt');
</script>

<main>
    <h1>{pt ? 'Concluir registo' : 'Complete registration'}</h1>
    <form method="POST" onsubmit={() => working = true}>
        <input type="hidden" name="terms_version" value={TERMS_VERSION} />
        <input type="hidden" name="privacy_version" value={PRIVACY_VERSION} />
        <label>
            <input type="checkbox" name="accepted" value="yes" required />
            <span>{pt ? 'Concordo com os' : 'I agree to the'}
                <a href="/terms" target="_blank" rel="noreferrer">{pt ? 'Termos de Utilização' : 'Terms of Use'}</a>
                {pt ? 'e declaro que tomei conhecimento da' : 'and acknowledge the'}
                <a href="/privacy" target="_blank" rel="noreferrer">{pt ? 'Política de Privacidade' : 'Privacy Policy'}</a>. *</span>
        </label>
        <p>{pt ? 'Versão dos documentos:' : 'Document versions:'} {TERMS_VERSION} / {PRIVACY_VERSION}</p>
        {#if form?.error}
            <p role="alert">{form.error === 'required'
                ? (pt ? 'É necessário aceitar os Termos e tomar conhecimento da Política.' : 'Agree to the Terms and acknowledge the Policy to continue.')
                : form.error === 'version'
                    ? (pt ? 'Recarrega a página para consultar a versão atual.' : 'Reload the page to review the current version.')
                    : (pt ? 'Não foi possível guardar a aceitação. Tenta novamente.' : 'Could not save your acceptance. Please try again.')}</p>
        {/if}
        <button type="submit" disabled={working}>{working ? (pt ? 'A guardar…' : 'Saving…') : (pt ? 'Aceitar e continuar' : 'Accept and continue')}</button>
    </form>
</main>

<style>
    main { max-width: 640px; margin: 0 auto; padding: 40px 20px; color: #eee; }
    h1 { font-size: 1.5rem; }
    form { display: grid; gap: 20px; }
    label { display: flex; align-items: flex-start; gap: 12px; line-height: 1.6; }
    input[type='checkbox'] { min-width: 20px; height: 20px; margin-top: 3px; }
    a { color: #d8b86f; }
    p { font-size: .85rem; color: #b8b8c0; }
    button { padding: 12px 20px; border: 1px solid #544a35; border-radius: 6px; background: #111116; color: #d8b86f; cursor: pointer; }
    button:disabled { opacity: .6; cursor: wait; }
</style>
