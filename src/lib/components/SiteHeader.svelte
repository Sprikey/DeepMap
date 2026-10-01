<script>
    import { onMount } from 'svelte';
    import AuthHeader from '$lib/components/AuthHeader.svelte';
    import {
        getSiteLanguage,
        setSiteLanguage,
        siteHeaderTranslations
    } from '$lib/i18n/site.js';

    let currentLanguage = $state('en');
    let mobileMenuOpen = $state(false);

    let t = $derived(
        siteHeaderTranslations[currentLanguage] ?? siteHeaderTranslations.en
    );

    onMount(() => {
        currentLanguage = setSiteLanguage(getSiteLanguage());
    });

    function changeLanguage(event) {
        currentLanguage = setSiteLanguage(event.currentTarget.value);
    }

    function toggleMobileMenu() {
        mobileMenuOpen = !mobileMenuOpen;
    }

    function closeMobileMenu() {
        mobileMenuOpen = false;
    }
</script>

<header class="site-header-global">
    <div class="site-header-inner">
        <a href="/" class="brand-link" aria-label="DeepMap — Home" onclick={closeMobileMenu}>
            <img src="/brand/logo.png" alt="DeepMap" class="brand-logo" />
        </a>

        <nav class="desktop-nav" aria-label={t.navigationLabel}>
            <a href="/#journey">{t.navJourney}</a>
            <a href="/#vision">{t.navVision}</a>
            <a href="/#follow">{t.navFollow}</a>
        </nav>

        <div class="header-actions">
            <label class="language-wrap">
                <span class="sr-only">{t.language}</span>
                <select
                    value={currentLanguage}
                    onchange={changeLanguage}
                    aria-label={t.language}
                >
                    <option value="en">EN</option>
                    <option value="pt">PT</option>
                </select>
            </label>

            <AuthHeader language={currentLanguage} />

            <button
                type="button"
                class="mobile-nav-toggle"
                class:active={mobileMenuOpen}
                aria-expanded={mobileMenuOpen}
                aria-controls="deepmap-mobile-site-nav"
                aria-label={mobileMenuOpen ? t.closeMenu : t.openMenu}
                onclick={toggleMobileMenu}
            >
                <span class="menu-lines" aria-hidden="true"></span>
            </button>
        </div>
    </div>

    <nav
        id="deepmap-mobile-site-nav"
        class="mobile-nav"
        class:open={mobileMenuOpen}
        aria-label={t.navigationLabel}
    >
        <a href="/#journey" onclick={closeMobileMenu}>{t.navJourney}</a>
        <a href="/#vision" onclick={closeMobileMenu}>{t.navVision}</a>
        <a href="/#follow" onclick={closeMobileMenu}>{t.navFollow}</a>
    </nav>
</header>

<style>
    .site-header-global {
        position: fixed;
        top: 0;
        left: 0;
        right: 0;
        height: var(--deepmap-site-header-height, 72px);
        z-index: 50000;
        color: #e9e5dd;
        background: rgba(8, 10, 13, 0.97);
        border-bottom: 1px solid rgba(200, 163, 85, 0.22);
        box-shadow: 0 10px 28px rgba(0, 0, 0, 0.22);
        backdrop-filter: blur(14px);
        font-family: 'Segoe UI', Arial, sans-serif;
    }

    .site-header-inner {
        width: min(1440px, 100%);
        height: 100%;
        margin: 0 auto;
        padding: 0 clamp(18px, 4vw, 56px);
        display: flex;
        align-items: center;
        gap: 28px;
        box-sizing: border-box;
    }

    .brand-link {
        display: inline-flex;
        align-items: center;
        flex: none;
        min-width: 0;
    }

    .brand-logo {
        display: block;
        width: auto;
        height: auto;
        max-width: 148px;
        max-height: 48px;
        object-fit: contain;
    }

    .desktop-nav {
        display: flex;
        align-items: center;
        gap: clamp(18px, 2.6vw, 38px);
        margin-left: auto;
    }

    .desktop-nav a,
    .mobile-nav a {
        color: #c8c1bd;
        text-decoration: none;
        font-size: 0.84rem;
        font-weight: 600;
        white-space: nowrap;
        transition: color 0.16s ease, background 0.16s ease, border-color 0.16s ease;
    }

    .desktop-nav a:hover,
    .mobile-nav a:hover {
        color: #e4c982;
    }

    .header-actions {
        display: flex;
        align-items: center;
        gap: 12px;
        flex: none;
    }

    .language-wrap {
        display: inline-flex;
        align-items: center;
    }

    .language-wrap select {
        height: 34px;
        min-width: 48px;
        padding: 0 7px;
        border: 1px solid #4b4130;
        border-radius: 7px;
        background: #171719;
        color: #d8b86f;
        font: inherit;
        font-size: 0.76rem;
        font-weight: 800;
        cursor: pointer;
        outline: none;
    }

    .language-wrap select:hover {
        border-color: #c8a355;
        background: #211d18;
    }

    .mobile-nav-toggle {
        display: none;
        width: 36px;
        height: 36px;
        padding: 0;
        border: 1px solid #4b4130;
        border-radius: 7px;
        background: #171719;
        color: #d8b86f;
        cursor: pointer;
        align-items: center;
        justify-content: center;
    }

    .menu-lines,
    .menu-lines::before,
    .menu-lines::after {
        display: block;
        width: 16px;
        height: 2px;
        border-radius: 999px;
        background: currentColor;
        transition: transform 0.18s ease, opacity 0.18s ease;
        content: '';
    }

    .menu-lines {
        position: relative;
    }

    .menu-lines::before {
        position: absolute;
        top: -5px;
        left: 0;
    }

    .menu-lines::after {
        position: absolute;
        top: 5px;
        left: 0;
    }

    .mobile-nav-toggle.active .menu-lines {
        background: transparent;
    }

    .mobile-nav-toggle.active .menu-lines::before {
        transform: translateY(5px) rotate(45deg);
    }

    .mobile-nav-toggle.active .menu-lines::after {
        transform: translateY(-5px) rotate(-45deg);
    }

    .mobile-nav {
        display: none;
    }

    .sr-only {
        position: absolute;
        width: 1px;
        height: 1px;
        padding: 0;
        margin: -1px;
        overflow: hidden;
        clip: rect(0, 0, 0, 0);
        white-space: nowrap;
        border: 0;
    }

    a:focus-visible,
    select:focus-visible,
    button:focus-visible {
        outline: 2px solid #d8b86f;
        outline-offset: 3px;
    }

    @media (max-width: 820px) {
        .site-header-inner {
            padding: 0 12px;
            gap: 10px;
        }

        .brand-logo {
            max-width: 112px;
            max-height: 40px;
        }

        .desktop-nav {
            display: none;
        }

        .header-actions {
            margin-left: auto;
            gap: 8px;
        }

        .mobile-nav-toggle {
            display: inline-flex;
        }

        .mobile-nav {
            position: absolute;
            top: 100%;
            left: 0;
            right: 0;
            display: flex;
            flex-direction: column;
            gap: 3px;
            padding: 10px 12px 14px;
            border-bottom: 1px solid rgba(200, 163, 85, 0.24);
            background: rgba(12, 12, 14, 0.985);
            box-shadow: 0 18px 30px rgba(0, 0, 0, 0.35);
            opacity: 0;
            visibility: hidden;
            transform: translateY(-6px);
            pointer-events: none;
            transition: opacity 0.16s ease, transform 0.16s ease, visibility 0.16s ease;
        }

        .mobile-nav.open {
            opacity: 1;
            visibility: visible;
            transform: translateY(0);
            pointer-events: auto;
        }

        .mobile-nav a {
            padding: 11px 12px;
            border: 1px solid transparent;
            border-radius: 7px;
        }

        .mobile-nav a:hover {
            border-color: #4f432f;
            background: #1d1915;
        }
    }

    @media (max-width: 420px) {
        .brand-logo {
            max-width: 98px;
        }

        .language-wrap select {
            min-width: 44px;
            padding: 0 5px;
        }
    }
</style>
