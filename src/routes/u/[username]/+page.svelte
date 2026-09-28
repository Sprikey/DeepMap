<script>
    import { onMount } from 'svelte';
    import { getSiteLanguage, setSiteLanguage } from '$lib/i18n/site.js';
    import { publicProfileTranslations } from '$lib/i18n/public-profile.js';

    let { data } = $props();
    let currentLanguage = $state('en');
    let avatarFailed = $state(false);
    let t = $derived(publicProfileTranslations[currentLanguage] ?? publicProfileTranslations.en);
    let profile = $derived(data.profile);
    let initial = $derived((profile?.displayName || profile?.username || '?').charAt(0).toLocaleUpperCase('pt-PT'));

    onMount(() => {
        currentLanguage = setSiteLanguage(getSiteLanguage());
    });

    function changeLanguage(event) {
        currentLanguage = setSiteLanguage(event.currentTarget.value);
    }
</script>

<svelte:head>
    <title>{data.kind === 'public' ? `${profile.displayName} (@${profile.username}) — DeepMap` : data.kind === 'private' ? `${t.private_title} (@${profile.username}) — DeepMap` : `${t.not_found_title} — DeepMap`}</title>
    <meta name="description" content={data.kind === 'public' ? `${profile.displayName} — ${t.explorer}` : data.kind === 'private' ? t.private_message : t.not_found_message} />
    <meta name="robots" content={data.kind === 'public' && profile.isPublic && !data.isVisitorPreview ? 'index,follow' : 'noindex,nofollow'} />
</svelte:head>

<main class="public-page">
    <div class="page-container">
        <nav class="top-navigation" aria-label="DeepMap">
            <a class="back-link" href="/">{t.back_map}</a>
            <select
                class="language-picker"
                value={currentLanguage}
                onchange={changeLanguage}
                aria-label={t.language}
            >
                <option value="en">EN</option>
                <option value="pt">PT</option>
            </select>
        </nav>

        <div class="brandbar">
            <a href="/" aria-label="DeepMap — Home">
                <img src="/brand/logo.png" alt="DeepMap" class="brand-logo" />
            </a>
        </div>

        {#if data.isVisitorPreview}
            <div class="visitor-preview-banner" role="status">
                <div class="visitor-preview-copy">
                    <strong>{t.visitor_preview_title}</strong>
                    <span>{t.visitor_preview_message}</span>
                </div>
                <a href="/profile" class="visitor-preview-exit">{t.exit_preview}</a>
            </div>
        {/if}

        {#if data.kind === 'not_found'}
            <section class="state-panel not-found-panel" aria-labelledby="not-found-heading">
                <div class="state-icon" aria-hidden="true">✦</div>
                <h1 id="not-found-heading">{t.not_found_title}</h1>
                <p>{t.not_found_message}</p>
                <a href="/" class="primary-link">{t.back_home}</a>
            </section>
        {:else if data.kind === 'private'}
            <section class="private-profile" aria-labelledby="private-profile-heading">
                <div class="hero-decoration" aria-hidden="true"></div>
                <div class="private-content">
                    <div class="private-status"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="4" y="10" width="16" height="11" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></svg>{t.private_badge}</div>
                    <div class="avatar private-avatar" aria-hidden="true">
                        {#if profile.avatarUrl && !avatarFailed}
                            <img src={profile.avatarUrl} alt="" referrerpolicy="no-referrer" onerror={() => avatarFailed = true} />
                        {:else}
                            <span>{initial}</span>
                        {/if}
                    </div>
                    <div class="username private-username">@{profile.username}</div>
                    <div class="private-message">
                        <svg viewBox="0 0 24 24" width="27" height="27" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                            <rect x="4" y="10" width="16" height="11" rx="2" />
                            <path d="M8 10V7a4 4 0 0 1 8 0v3" />
                        </svg>
                        <h1 id="private-profile-heading">{t.private_title}</h1>
                        <p>{t.private_message}</p>
                    </div>
                    {#if data.isOwner && !data.isVisitorPreview}
                        <a href="/profile" class="manage-profile">{t.edit_your_profile}</a>
                    {/if}
                </div>
            </section>
        {:else}
            {#if !profile.isPublic && data.isOwner && !data.isVisitorPreview}
                <div class="privacy-banner" role="status">
                    <strong>{t.private_preview}</strong>
                    <span>{t.private_preview_message}</span>
                </div>
            {/if}

            <section class="explorer-hero" aria-labelledby="public-profile-name">
                <div class="hero-decoration" aria-hidden="true"></div>
                <div class="hero-content">
                    <div class="hero-topline">
                        <span class="account-badge"><span aria-hidden="true">✦</span> {t.explorer}</span>
                        {#if profile.joinedYear}
                            <span class="member-since">{t.member_since} {profile.joinedYear}</span>
                        {/if}
                    </div>
                    <div class="avatar" aria-hidden="true">
                        {#if profile.avatarUrl && !avatarFailed}
                            <img src={profile.avatarUrl} alt="" referrerpolicy="no-referrer" onerror={() => avatarFailed = true} />
                        {:else}
                            <span>{initial}</span>
                        {/if}
                    </div>
                    <h1 id="public-profile-name">{profile.displayName}</h1>
                    <div class="username">@{profile.username}</div>
                    <p class:empty={!profile.bio} class="bio">{profile.bio || t.about_empty}</p>
                    {#if data.isOwner && !data.isVisitorPreview}
                        <a class="manage-profile" href="/profile">{t.edit_your_profile}</a>
                    {/if}
                </div>
            </section>

            <section class="future-panel" aria-labelledby="future-heading">
                <h2 id="future-heading">{t.future_section}</h2>
                <p>{t.future_description}</p>
            </section>
        {/if}
    </div>
</main>

<style>
    :global(body) { margin: 0; }
    .public-page { min-height: 100vh; min-height: 100dvh; padding: 35px 20px 65px; box-sizing: border-box; color: #e0e0e0; background: #0b0b0e; font-family: 'Segoe UI', Arial, sans-serif; }
    .page-container { width: 100%; max-width: 640px; margin: 0 auto; }
    .top-navigation { display: flex; justify-content: space-between; gap: 12px; align-items: center; margin-bottom: 20px; }
    .back-link { color: #c8a355; font-size: .9rem; text-decoration: none; }
    .back-link:hover { text-decoration: underline; }
    .language-picker { padding: 6px 8px; background: #22222a; border: 1px solid #454550; border-radius: 6px; color: #c8a355; font: inherit; font-size: .85rem; }
    .brandbar { display: flex; align-items: center; justify-content: center; min-height: 56px; margin-bottom: 24px; }
    .brand-logo { display: block; width: auto; max-width: 150px; max-height: 55px; height: auto; object-fit: contain; }
    .state-panel, .future-panel { border: 1px solid #333340; border-radius: 14px; background: #16161a; padding: 30px; text-align: center; }
    .state-panel h1 { color: #fff; font-size: 1.5rem; margin: 12px 0; }
    .state-panel p, .future-panel p { color: #a0a0aa; line-height: 1.6; }
    .state-icon { color: #c8a355; font-size: 2.2rem; }
    .primary-link, .manage-profile { display: inline-flex; justify-content: center; align-items: center; border: 1px solid #a98a53; border-radius: 7px; padding: 10px 16px; color: #171717; background: #c8a355; font-weight: 650; text-decoration: none; }
    .primary-link { margin-top: 12px; }
    .primary-link:hover, .manage-profile:hover { background: #e3c482; }
    .privacy-banner { display: grid; gap: 4px; padding: 12px 15px; margin-bottom: 14px; border: 1px solid #655632; border-radius: 9px; background: #29251b; color: #e6cf97; font-size: .85rem; }
    .privacy-banner span { color: #cdc2ae; }
    .explorer-hero { position: relative; isolation: isolate; overflow: hidden; border: 1px solid #5e4b32; border-radius: 14px; background: linear-gradient(135deg, #27221d 0%, #1c1c22 49%, #18181d 100%); padding: 23px 28px 30px; text-align: center; }
    .hero-decoration { pointer-events: none; position: absolute; right: -115px; top: -150px; width: 350px; height: 350px; border: 1px solid rgba(200, 163, 85, .21); border-radius: 50%; box-shadow: 0 0 0 31px rgba(200,163,85,.025), 0 0 0 62px rgba(200,163,85,.028), 0 0 0 92px rgba(200,163,85,.025); z-index: -1; }
    .hero-content { position: relative; z-index: 1; }
    .hero-topline { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; margin-bottom: 24px; }
    .account-badge { display: inline-block; padding: 6px 11px; border: 1px solid #5c4b2c; border-radius: 20px; color: #c8a355; background: #29251b; font-size: .75rem; font-weight: 700; }
    .member-since { color: #aaa39a; font-size: .78rem; }
    .avatar { width: 105px; height: 105px; display: flex; justify-content: center; align-items: center; margin: 0 auto 16px; border: 3px solid #c8a355; border-radius: 50%; background: #292933; color: #c8a355; overflow: hidden; font-size: 2.6rem; font-weight: 700; box-shadow: 0 0 0 5px rgba(200,163,85,.1); }
    .avatar img { width: 100%; height: 100%; object-fit: cover; }
    h1 { margin: 0; color: #fff; font-size: 1.75rem; overflow-wrap: anywhere; }
    .username { margin: 8px 0 0; color: #c8a355; font-size: .95rem; font-weight: 650; overflow-wrap: anywhere; }
    .bio { margin: 15px auto 0; color: #d4d0d4; max-width: 460px; line-height: 1.6; white-space: pre-wrap; overflow-wrap: anywhere; }
    .bio.empty { color: #95939c; font-style: italic; }
    .manage-profile { margin-top: 20px; }
    .future-panel { margin-top: 18px; text-align: left; }
    .future-panel h2 { margin: 0 0 8px; color: #fff; font-size: 1.1rem; }
    .future-panel p { margin: 0; font-size: .88rem; }
    @media (max-width: 480px) { .public-page { padding: 20px 14px 45px; } .brandbar { margin-bottom: 17px; } .brand-logo { max-width: 125px; max-height: 46px; } .explorer-hero { padding: 20px 18px 25px; } .hero-topline { justify-content: center; margin-bottom: 20px; } .member-since { width: 100%; text-align: center; } .hero-decoration { right: -200px; top: -180px; } .state-panel, .future-panel { padding: 22px; } }
    @media (prefers-reduced-motion: reduce) { *, *::before, *::after { scroll-behavior: auto !important; transition-duration: .01ms !important; } }

    /* Estados públicos, privados e inexistentes. */
    .private-profile { position: relative; isolation: isolate; overflow: hidden; border: 1px solid #5e4b32; border-radius: 14px; background: linear-gradient(135deg, #27221d 0%, #1c1c22 49%, #18181d 100%); padding: 28px 24px 32px; text-align: center; }
    .private-content { position: relative; z-index: 1; }
    .private-status { display: inline-flex; gap: 7px; align-items: center; margin-bottom: 28px; border-radius: 20px; border: 1px solid #60543e; padding: 7px 14px; font-size: .78rem; color: #e1c48a; background: #29251b; font-weight: 700; }
    .private-avatar { margin-bottom: 13px; }
    .private-username { margin: 0 0 26px; font-size: 1rem; }
    .private-message { border: 1px solid #3c3b45; background: #222128; padding: 26px 17px; border-radius: 12px; display: flex; flex-direction: column; align-items: center; gap: 10px; }
    .private-message svg { color: #d1ad6c; }
    .private-message h1 { margin: 0; font-size: 1.35rem; }
    .private-message p { margin: 0; color: #aba9b4; line-height: 1.6; max-width: 380px; font-size: .9rem; }
    .private-profile .manage-profile { margin-top: 22px; }
    .visitor-preview-banner { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 14px; margin-bottom: 15px; border: 1px solid #665532; background: #2a241a; padding: 13px 15px; border-radius: 10px; color: #e8d5a8; }
    .visitor-preview-copy { display: flex; flex-direction: column; gap: 4px; }
    .visitor-preview-copy span { font-size: .82rem; line-height: 1.5; color: #c7bca5; }
    .visitor-preview-exit { display: inline-flex; justify-content: center; align-items: center; border: 1px solid #a98a53; padding: 9px 13px; border-radius: 7px; color: #191611; background: #c8a355; font-weight: 700; font-size: .82rem; text-decoration: none; }
    .visitor-preview-exit:hover { background: #e3c482; }
    .visitor-preview-exit:focus-visible { outline: 2px solid #fff; outline-offset: 3px; }
    @media (max-width: 480px) { .private-profile { padding: 23px 17px; } .visitor-preview-exit { width: 100%; box-sizing: border-box; } }
</style>
