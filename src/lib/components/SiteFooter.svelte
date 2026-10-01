<script>
    import { onMount } from 'svelte';
    import {
        getSiteLanguage,
        subscribeSiteLanguage,
        siteFooterTranslations
    } from '$lib/i18n/site.js';

    let currentLanguage = $state('en');
    let t = $derived(siteFooterTranslations[currentLanguage] ?? siteFooterTranslations.en);
    const year = new Date().getFullYear();

    onMount(() => {
        currentLanguage = getSiteLanguage();
        const unsubscribe = subscribeSiteLanguage((language) => {
            currentLanguage = language;
        });
        return unsubscribe;
    });
</script>

<footer class="site-footer-global">
    <div class="footer-inner">
        <p class="footer-copy">© {year} DeepMap. {t.copyright}</p>

        <nav class="footer-links" aria-label={t.navigationLabel}>
            <a href="/privacy">{t.privacy}</a>
            <a href="/terms">{t.terms}</a>
            <a href="mailto:contact@deepmap.cc">{t.contact}</a>
        </nav>
    </div>
</footer>

<style>
    .site-footer-global {
        position: relative;
        z-index: 2;
        border-top: 1px solid rgba(200, 163, 85, 0.18);
        background: #090a0d;
        color: #8f8b91;
        font-family: 'Segoe UI', Arial, sans-serif;
    }

    .footer-inner {
        width: min(1440px, 100%);
        margin: 0 auto;
        padding: 22px clamp(18px, 4vw, 56px);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 24px;
        box-sizing: border-box;
    }

    .footer-copy {
        margin: 0;
        font-size: 0.78rem;
        line-height: 1.5;
    }

    .footer-links {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        justify-content: flex-end;
        gap: 22px;
    }

    .footer-links a {
        color: #bbb5b2;
        text-decoration: none;
        font-size: 0.78rem;
        font-weight: 600;
        transition: color 0.16s ease;
    }

    .footer-links a:hover {
        color: #d8b86f;
    }

    .footer-links a:focus-visible {
        outline: 2px solid #d8b86f;
        outline-offset: 3px;
        border-radius: 3px;
    }

    @media (max-width: 620px) {
        .footer-inner {
            padding-top: 20px;
            padding-bottom: 22px;
            align-items: flex-start;
            flex-direction: column;
            gap: 13px;
        }

        .footer-links {
            justify-content: flex-start;
            gap: 16px 20px;
        }
    }
</style>
