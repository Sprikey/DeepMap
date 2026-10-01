<script>
    import { onMount } from 'svelte';
    import { getSiteLanguage, setSiteLanguage, subscribeSiteLanguage } from '$lib/i18n/site.js';
    import { publicProfileTranslations } from '$lib/i18n/public-profile.js';

    let { data } = $props();

    let currentLanguage = $state('en');
    let avatarFailed = $state(false);

    let t = $derived(
        publicProfileTranslations[currentLanguage] ?? publicProfileTranslations.en
    );

    let ui = $derived(currentLanguage === 'pt' ? {
        memberSince: 'Membro desde',
        markers: 'Marcadores',
        followers: 'Seguidores',
        following: 'A seguir',
        badges: 'Badges & Títulos',
        activity: 'Atividade recente',
        comingSoon: 'Indisponível por agora',
        planned: 'Planeado',
        explorerBadge: 'Explorador',
        manageProfile: 'Gerir o meu perfil',
        statsLabel: 'Estatísticas futuras do perfil',
        activityPlaceholder: 'A atividade da comunidade vai aparecer aqui quando esta funcionalidade estiver disponível.',
        privateEyebrow: 'Perfil privado',
        privateCardTitle: 'Este perfil é privado',
        privateCardText: 'Este explorador optou por manter os detalhes do perfil privados.',
        unavailable: 'Perfil indisponível',
        unavailableText: 'Não encontrámos este explorador.',
        backHome: 'Voltar à página inicial'
    } : {
        memberSince: 'Member since',
        markers: 'Markers',
        followers: 'Followers',
        following: 'Following',
        badges: 'Badges & Titles',
        activity: 'Recent activity',
        comingSoon: 'Unavailable for now',
        planned: 'Planned',
        explorerBadge: 'Explorer',
        manageProfile: 'Manage my profile',
        statsLabel: 'Future profile statistics',
        activityPlaceholder: 'Community activity will appear here when this feature becomes available.',
        privateEyebrow: 'Private profile',
        privateCardTitle: 'This profile is private',
        privateCardText: 'This explorer has chosen to keep their profile details private.',
        unavailable: 'Profile unavailable',
        unavailableText: 'We could not find this explorer.',
        backHome: 'Back to homepage'
    });

    let profile = $derived(data.profile);

    let initial = $derived(
        (profile?.displayName || profile?.username || '?')
            .charAt(0)
            .toLocaleUpperCase('pt-PT')
    );

    onMount(() => {
        currentLanguage = setSiteLanguage(getSiteLanguage());
        const unsubscribeLanguage = subscribeSiteLanguage((language) => { currentLanguage = language; });
        return unsubscribeLanguage;
    });
</script>

<svelte:head>
    <title>
        {data.kind === 'public'
            ? `${profile.displayName} (@${profile.username}) — DeepMap`
            : data.kind === 'private'
                ? `${t.private_title} (@${profile.username}) — DeepMap`
                : `${t.not_found_title} — DeepMap`}
    </title>

    <meta
        name="description"
        content={data.kind === 'public'
            ? `${profile.displayName} — ${t.explorer}`
            : data.kind === 'private'
                ? t.private_message
                : t.not_found_message}
    />

    <meta
        name="robots"
        content={data.kind === 'public' && profile.isPublic && !data.isVisitorPreview
            ? 'index,follow'
            : 'noindex,nofollow'}
    />
</svelte:head>

<main class="public-page">
    <div class="page-container">
        {#if data.isVisitorPreview}
            <div class="visitor-preview-banner" role="status">
                <div class="visitor-preview-copy">
                    <strong>{t.visitor_preview_title}</strong>
                    <span>{t.visitor_preview_message}</span>
                </div>

                <a href="/profile" class="outline-button">{t.exit_preview}</a>
            </div>
        {/if}

        {#if data.kind === 'not_found'}
            <section class="state-panel" aria-labelledby="not-found-heading">
                <span class="state-symbol" aria-hidden="true">✦</span>
                <h1 id="not-found-heading">{ui.unavailable}</h1>
                <p>{ui.unavailableText}</p>
                <a href="/" class="solid-button">{ui.backHome}</a>
            </section>

        {:else if data.kind === 'private'}
            <section class="profile-showcase" aria-labelledby="private-profile-heading">
                <div class="profile-banner">
                    <div class="profile-banner-shade"></div>
                </div>

                <div class="profile-identity-shell private-identity-shell">
                    <div class="profile-avatar-column">
                        <div class="avatar profile-main-avatar" aria-hidden="true">
                            {#if profile.avatarUrl && !avatarFailed}
                                <img
                                    src={profile.avatarUrl}
                                    alt=""
                                    referrerpolicy="no-referrer"
                                    onerror={() => avatarFailed = true}
                                />
                            {:else}
                                <span>{initial}</span>
                            {/if}
                        </div>
                    </div>

                    <div class="profile-identity-main">
                        <div class="profile-title-row">
                            <div>
                                <h1 id="private-profile-heading">@{profile.username}</h1>
                                <div class="private-profile-label">
                                    <svg
                                        viewBox="0 0 24 24"
                                        width="15"
                                        height="15"
                                        fill="none"
                                        stroke="currentColor"
                                        stroke-width="1.9"
                                        stroke-linecap="round"
                                        stroke-linejoin="round"
                                        aria-hidden="true"
                                    >
                                        <rect x="4" y="10" width="16" height="11" rx="2" />
                                        <path d="M8 10V7a4 4 0 0 1 8 0v3" />
                                    </svg>
                                    {ui.privateEyebrow}
                                </div>
                            </div>

                            <span class="explorer-title-badge">
                                <span aria-hidden="true">✦</span>
                                {ui.explorerBadge}
                            </span>
                        </div>
                    </div>
                </div>
            </section>

            <section class="profile-panel private-message-panel">
                <div class="private-lock" aria-hidden="true">
                    <svg
                        viewBox="0 0 24 24"
                        width="24"
                        height="24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="1.8"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                    >
                        <rect x="4" y="10" width="16" height="11" rx="2" />
                        <path d="M8 10V7a4 4 0 0 1 8 0v3" />
                    </svg>
                </div>

                <div>
                    <span class="panel-eyebrow">{ui.privateEyebrow}</span>
                    <h2>{ui.privateCardTitle}</h2>
                    <p>{ui.privateCardText}</p>
                </div>
            </section>

            {#if data.isOwner && !data.isVisitorPreview}
                <div class="owner-actions">
                    <a href="/profile" class="outline-button">{ui.manageProfile}</a>
                </div>
            {/if}

        {:else}
            {#if !profile.isPublic && data.isOwner && !data.isVisitorPreview}
                <div class="privacy-banner" role="status">
                    <strong>{t.private_preview}</strong>
                    <span>{t.private_preview_message}</span>
                </div>
            {/if}

            <section class="profile-showcase" aria-labelledby="public-profile-name">
                <div class="profile-banner">
                    <div class="profile-banner-shade"></div>
                </div>

                <div class="profile-identity-shell">
                    <div class="profile-avatar-column">
                        <div class="avatar profile-main-avatar" aria-hidden="true">
                            {#if profile.avatarUrl && !avatarFailed}
                                <img
                                    src={profile.avatarUrl}
                                    alt=""
                                    referrerpolicy="no-referrer"
                                    onerror={() => avatarFailed = true}
                                />
                            {:else}
                                <span>{initial}</span>
                            {/if}
                        </div>
                    </div>

                    <div class="profile-identity-main">
                        <div class="profile-title-row">
                            <div>
                                <h1 id="public-profile-name">{profile.displayName}</h1>
                                <div class="public-handle-row">
                                    <span class="username-handle">@{profile.username}</span>
                                </div>
                            </div>

                            <span class="explorer-title-badge">
                                <span aria-hidden="true">✦</span>
                                {ui.explorerBadge}
                            </span>
                        </div>

                        <p class:bio-empty={!profile.bio} class="profile-public-bio">
                            {profile.bio || t.about_empty}
                        </p>

                        {#if profile.joinedYear}
                            <div class="profile-meta-row">
                                <span>
                                    <svg
                                        viewBox="0 0 24 24"
                                        width="16"
                                        height="16"
                                        fill="none"
                                        stroke="currentColor"
                                        stroke-width="1.8"
                                        aria-hidden="true"
                                    >
                                        <rect x="3" y="5" width="18" height="16" rx="2" />
                                        <path d="M16 3v4M8 3v4M3 10h18" />
                                    </svg>
                                    {ui.memberSince} {profile.joinedYear}
                                </span>
                            </div>
                        {/if}

                        {#if data.isOwner && !data.isVisitorPreview}
                            <div class="identity-actions">
                                <a href="/profile" class="outline-button">{ui.manageProfile}</a>
                            </div>
                        {/if}
                    </div>
                </div>
            </section>

            <div class="profile-dashboard">
                <div class="profile-dashboard-main">
                    <section class="profile-stats-grid" aria-label={ui.statsLabel}>
                        <article class="profile-stat-card">
                            <span class="stat-icon">⌖</span>
                            <strong>—</strong>
                            <span>{ui.markers}</span>
                        </article>

                        <article class="profile-stat-card">
                            <span class="stat-icon">✧</span>
                            <strong>—</strong>
                            <span>{ui.followers}</span>
                        </article>

                        <article class="profile-stat-card">
                            <span class="stat-icon">↗</span>
                            <strong>—</strong>
                            <span>{ui.following}</span>
                        </article>
                    </section>

                    <section class="profile-panel">
                        <div class="panel-heading">
                            <div>
                                <span class="panel-eyebrow">{ui.comingSoon}</span>
                                <h2>{ui.badges}</h2>
                            </div>
                            <span class="planned-tag">{ui.planned}</span>
                        </div>

                        <div class="badge-preview">
                            <span class="badge-preview-icon">✦</span>
                            <div>
                                <strong>DeepMap Explorer</strong>
                                <span>{ui.comingSoon}</span>
                            </div>
                        </div>
                    </section>
                </div>

                <section class="profile-panel profile-activity-panel">
                    <div class="panel-heading">
                        <div>
                            <span class="panel-eyebrow">{ui.comingSoon}</span>
                            <h2>{ui.activity}</h2>
                        </div>
                        <span class="planned-tag">{ui.planned}</span>
                    </div>

                    <div class="activity-placeholder">
                        <span aria-hidden="true">◷</span>
                        <p>{ui.activityPlaceholder}</p>
                    </div>
                </section>
            </div>
        {/if}
    </div>
</main>

<style>
    :global(body) {
        margin: 0;
        background: #071019;
    }

    .public-page {
        min-height: 100vh;
        min-height: 100dvh;
        box-sizing: border-box;
        padding: 32px 20px 64px;
        color: #e0e0e0;
        background:
            radial-gradient(circle at 80% -10%, rgba(200, 163, 85, .07), transparent 28rem),
            linear-gradient(180deg, #071019 0%, #0a1119 55%, #081018 100%);
        font-family: 'Segoe UI', Arial, sans-serif;
    }

    .page-container {
        width: 100%;
        max-width: 1180px;
        margin: 0 auto;
    }

    .outline-button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        box-sizing: border-box;
        min-height: 40px;
        padding: 8px 13px;
        border: 1px solid rgba(200, 163, 85, .48);
        border-radius: 9px;
        background: rgba(200, 163, 85, .07);
        color: #d9bd84;
        font: inherit;
        font-size: .82rem;
        font-weight: 700;
        text-decoration: none;
        transition:
            background .18s ease,
            border-color .18s ease,
            color .18s ease,
            transform .18s ease;
    }

    .outline-button:hover,
    .outline-button:focus-visible {
        border-color: #c8a355;
        background: rgba(200, 163, 85, .15);
        color: #f0d99f;
        transform: translateY(-1px);
    }

    .outline-button:focus-visible,
    .solid-button:focus-visible {
        outline: 2px solid rgba(200, 163, 85, .36);
        outline-offset: 3px;
    }

    .visitor-preview-banner,
    .privacy-banner {
        display: flex;
        align-items: center;
        justify-content: space-between;
        flex-wrap: wrap;
        gap: 14px;
        margin-bottom: 14px;
        padding: 13px 15px;
        border: 1px solid rgba(200, 163, 85, .4);
        border-radius: 10px;
        background: rgba(200, 163, 85, .08);
        color: #e8d5a8;
    }

    .visitor-preview-copy,
    .privacy-banner {
        line-height: 1.45;
    }

    .visitor-preview-copy {
        display: flex;
        flex-direction: column;
        gap: 4px;
    }

    .visitor-preview-copy span,
    .privacy-banner span {
        color: #b9b2a5;
        font-size: .8rem;
    }

    .privacy-banner {
        display: grid;
        justify-content: stretch;
        gap: 4px;
    }

    .profile-showcase {
        overflow: hidden;
        border: 1px solid #2c3d4b;
        border-radius: 16px 16px 0 0;
        background: #0d151e;
        box-shadow: 0 24px 80px rgba(0, 0, 0, .18);
    }

    .profile-banner {
        position: relative;
        min-height: 285px;
        background:
            linear-gradient(90deg, rgba(5,12,18,.78) 0%, rgba(5,12,18,.12) 55%, rgba(5,12,18,.28) 100%),
            url('/brand/home-hero-world.webp') center 48% / cover no-repeat,
            linear-gradient(135deg, #122334, #0a121a);
    }

    .profile-banner-shade {
        position: absolute;
        inset: 0;
        background: linear-gradient(180deg, rgba(4,10,16,.06), rgba(4,10,16,.52));
        pointer-events: none;
    }

    .profile-identity-shell {
        position: relative;
        display: grid;
        grid-template-columns: 168px minmax(0, 1fr);
        gap: 24px;
        min-height: 170px;
        padding: 0 30px 26px;
        border-top: 1px solid rgba(255,255,255,.04);
    }

    .profile-avatar-column {
        position: relative;
        width: 150px;
        margin-top: -72px;
        align-self: start;
    }

    .avatar {
        display: grid;
        place-items: center;
        overflow: hidden;
        border-radius: 50%;
        color: #d4ab5c;
        font-size: 2.8rem;
        font-weight: 800;
    }

    .avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
    }

    .profile-main-avatar {
        width: 146px;
        height: 146px;
        margin: 0;
        border: 4px solid #d4ab5c;
        background: #172431;
        box-shadow:
            0 0 0 6px #0d151e,
            0 12px 30px rgba(0,0,0,.38);
    }

    .profile-identity-main {
        min-width: 0;
        padding-top: 22px;
    }

    .profile-title-row {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 18px;
    }

    .profile-title-row h1 {
        margin: 0;
        color: #f3efe8;
        font-size: clamp(1.8rem, 4vw, 2.55rem);
        letter-spacing: -.035em;
        overflow-wrap: anywhere;
    }

    .public-handle-row {
        display: flex;
        align-items: center;
        gap: 7px;
        margin-top: 3px;
    }

    .username-handle,
    .private-profile-label {
        color: #d6b773;
        font-size: 1rem;
        font-weight: 700;
        overflow-wrap: anywhere;
    }

    .private-profile-label {
        display: inline-flex;
        align-items: center;
        gap: 7px;
        margin-top: 7px;
        font-size: .82rem;
    }

    .explorer-title-badge {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        flex: none;
        padding: 8px 12px;
        border: 1px solid #6b5633;
        border-radius: 999px;
        background: rgba(190,145,67,.09);
        color: #dfc27e;
        font-size: .74rem;
        font-weight: 800;
        letter-spacing: .06em;
        text-transform: uppercase;
    }

    .profile-public-bio {
        max-width: 730px;
        margin: 14px 0 0;
        color: #d2d9df;
        line-height: 1.55;
        white-space: pre-wrap;
        overflow-wrap: anywhere;
    }

    .profile-public-bio.bio-empty {
        color: #8795a1;
        font-style: italic;
    }

    .profile-meta-row {
        display: flex;
        flex-wrap: wrap;
        gap: 10px 22px;
        margin-top: 16px;
        color: #aeb9c3;
        font-size: .8rem;
    }

    .profile-meta-row span {
        display: inline-flex;
        align-items: center;
        gap: 7px;
    }

    .profile-meta-row svg {
        color: #d2ad63;
    }

    .identity-actions {
        margin-top: 17px;
    }

    .profile-dashboard {
        display: grid;
        grid-template-columns: minmax(330px, 1.2fr) minmax(280px, 1fr);
        gap: 16px;
        margin-top: 16px;
    }

    .profile-dashboard-main {
        display: grid;
        gap: 16px;
        min-width: 0;
    }

    .profile-panel {
        min-width: 0;
        margin: 0;
        padding: 21px;
        border: 1px solid #2b3b49;
        border-radius: 12px;
        background: linear-gradient(180deg, #101922, #0d151e);
    }

    .panel-heading {
        display: flex;
        align-items: center;
        justify-content: space-between;
        flex-wrap: wrap;
        gap: 10px;
    }

    .panel-eyebrow {
        display: block;
        margin: 0 0 7px;
        color: #d0ae69;
        font-size: .68rem;
        font-weight: 700;
        letter-spacing: .11em;
        text-transform: uppercase;
    }

    .panel-heading h2,
    .private-message-panel h2 {
        margin: 0;
        color: #eff3f4;
        font-size: 1.14rem;
        line-height: 1.3;
    }

    .planned-tag {
        display: inline-flex;
        padding: 5px 9px;
        border: 1px solid #464550;
        border-radius: 20px;
        background: #24242b;
        color: #aaaab6;
        font-size: .69rem;
        white-space: nowrap;
    }

    .profile-stats-grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 1px;
        overflow: hidden;
        border: 1px solid #2b3b49;
        border-radius: 12px;
        background: #2b3b49;
    }

    .profile-stat-card {
        min-width: 0;
        display: grid;
        justify-items: center;
        gap: 5px;
        padding: 20px 8px 18px;
        background: #101922;
        text-align: center;
    }

    .profile-stat-card .stat-icon {
        color: #c8a355;
        font-size: 1.15rem;
    }

    .profile-stat-card strong {
        color: #f1f5f6;
        font-size: 1.25rem;
    }

    .profile-stat-card span:last-child {
        color: #8ea0ad;
        font-size: .74rem;
    }

    .badge-preview {
        display: flex;
        align-items: center;
        gap: 14px;
        margin-top: 18px;
        padding: 15px;
        border: 1px solid #344451;
        border-radius: 11px;
        background: #111c26;
    }

    .badge-preview-icon {
        width: 52px;
        height: 52px;
        display: grid;
        place-items: center;
        flex: none;
        border: 1px solid #80652e;
        border-radius: 50%;
        color: #e4bd63;
        font-size: 1.55rem;
        box-shadow: inset 0 0 18px rgba(223,178,80,.08);
    }

    .badge-preview div {
        display: grid;
        gap: 3px;
        min-width: 0;
    }

    .badge-preview strong {
        color: #e6c36d;
    }

    .badge-preview span {
        color: #8899a5;
        font-size: .78rem;
    }

    .activity-placeholder {
        min-height: 180px;
        display: grid;
        place-items: center;
        align-content: center;
        gap: 12px;
        margin-top: 18px;
        padding: 24px;
        border: 1px dashed #354756;
        border-radius: 11px;
        color: #81929e;
        text-align: center;
    }

    .activity-placeholder > span {
        color: #c8a355;
        font-size: 1.5rem;
    }

    .activity-placeholder p {
        max-width: 300px;
        margin: 0;
        color: #81929e;
        font-size: .8rem;
        line-height: 1.55;
    }

    .private-message-panel {
        display: flex;
        align-items: flex-start;
        gap: 16px;
        margin-top: 16px;
    }

    .private-message-panel p {
        max-width: 610px;
        margin: 9px 0 0;
        color: #8f9da8;
        font-size: .85rem;
        line-height: 1.6;
    }

    .private-lock {
        width: 44px;
        height: 44px;
        display: grid;
        place-items: center;
        flex: none;
        border: 1px solid #6b5633;
        border-radius: 11px;
        background: rgba(190,145,67,.08);
        color: #d4ab5c;
    }

    .owner-actions {
        display: flex;
        justify-content: flex-end;
        margin-top: 14px;
    }

    .solid-button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 42px;
        margin-top: 12px;
        padding: 10px 17px;
        border: 1px solid #c8a355;
        border-radius: 9px;
        background: #c8a355;
        color: #171717;
        font: inherit;
        font-size: .84rem;
        font-weight: 800;
        text-decoration: none;
    }

    .solid-button:hover {
        border-color: #d9b76c;
        background: #d9b76c;
    }

    .state-panel {
        padding: 38px 24px;
        border: 1px solid #2b3b49;
        border-radius: 14px;
        background: linear-gradient(180deg, #101922, #0d151e);
        text-align: center;
    }

    .state-symbol {
        color: #c8a355;
        font-size: 2rem;
    }

    .state-panel h1 {
        margin: 13px 0 8px;
        color: #f3efe8;
        font-size: 1.55rem;
    }

    .state-panel p {
        margin: 0;
        color: #8f9da8;
        line-height: 1.6;
    }

    @media (max-width: 920px) {
        .profile-dashboard {
            grid-template-columns: 1fr;
        }
    }

    @media (max-width: 650px) {
        .public-page {
            padding: 14px 10px 35px;
        }

        .profile-banner {
            min-height: 178px;
            background-position: center 48%;
        }

        .profile-identity-shell {
            grid-template-columns: 92px minmax(0, 1fr);
            gap: 13px;
            min-height: 125px;
            padding: 0 15px 18px;
        }

        .profile-avatar-column {
            width: 88px;
            margin-top: -43px;
        }

        .profile-main-avatar {
            width: 86px;
            height: 86px;
            border-width: 3px;
            box-shadow:
                0 0 0 4px #0d151e,
                0 8px 20px rgba(0,0,0,.35);
            font-size: 2rem;
        }

        .profile-identity-main {
            padding-top: 12px;
        }

        .profile-title-row {
            display: block;
        }

        .profile-title-row h1 {
            font-size: 1.45rem;
        }

        .username-handle {
            font-size: .85rem;
        }

        .explorer-title-badge {
            margin-top: 9px;
            padding: 6px 9px;
            font-size: .62rem;
        }

        .profile-public-bio {
            margin-top: 11px;
            font-size: .82rem;
        }

        .profile-meta-row {
            gap: 8px 13px;
            margin-top: 11px;
            font-size: .7rem;
        }

        .profile-dashboard {
            gap: 12px;
            margin-top: 12px;
        }

        .profile-panel {
            padding: 17px 15px;
        }

        .private-message-panel {
            align-items: center;
        }
    }

    @media (max-width: 480px) {

        .visitor-preview-banner {
            align-items: stretch;
        }

        .visitor-preview-banner .outline-button {
            width: 100%;
        }

        .private-message-panel {
            display: grid;
        }

        .private-lock {
            width: 40px;
            height: 40px;
        }

        .owner-actions .outline-button {
            width: 100%;
        }
    }

    @media (max-width: 390px) {
        .profile-identity-shell {
            grid-template-columns: 78px minmax(0, 1fr);
            padding-left: 11px;
            padding-right: 11px;
        }

        .profile-avatar-column {
            width: 74px;
        }

        .profile-main-avatar {
            width: 72px;
            height: 72px;
        }

        .profile-title-row h1 {
            font-size: 1.28rem;
        }

        .profile-stat-card {
            padding-left: 4px;
            padding-right: 4px;
        }
    }

    @media (prefers-reduced-motion: reduce) {
        *,
        *::before,
        *::after {
            scroll-behavior: auto !important;
            transition-duration: .01ms !important;
        }
    }
</style>
