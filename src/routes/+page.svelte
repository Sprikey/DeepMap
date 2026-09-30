<script>
    import { onMount } from 'svelte';
    import { getSiteLanguage, setSiteLanguage } from '$lib/i18n/site.js';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { getDisplayName, getAvatarPresentation } from '$lib/avatar/avatars.js';

    let currentLanguage = $state('en');
    let accountUser = $state(null);
    let checkingSession = $state(true);
    let profileUsername = $state(null);
    let avatarFailed = $state(false);
    let accountDisplayName = $derived(accountUser ? getDisplayName(accountUser) : '');
    let accountAvatar = $derived(accountUser ? getAvatarPresentation(accountUser).image : null);
    let accountName = $derived(profileUsername ? `@${profileUsername}` : accountDisplayName || accountUser?.email?.split('@')[0] || 'Explorer');
    let accountInitial = $derived(accountName.replace(/^@/, '').charAt(0).toLocaleUpperCase('pt-PT') || 'D');

    const copy = {
        en: {
            language: 'Language',
            metaTitle: 'DeepMap — Your Journey’s Companion',
            metaDescription: 'DeepMap is growing into a home for interactive gaming maps and a community of explorers. Join us at the beginning of the journey.',
            signIn: 'Sign in',
            account: 'Log in / Create account',
            myProfile: 'My profile',
            signedIn: 'SIGNED IN',
            checkingAccount: 'Checking account…',
            supportingSignedIn: 'You’re already part of the journey. Your explorer profile is ready whenever you want to visit it.',
            communityTextSignedIn: 'You’re already part of the explorers shaping our next chapter. Thanks for joining the journey!',
            navJourney: 'Our first world',
            navVision: 'Our vision',
            navFollow: 'Follow us',
            exploreVision: 'Explore our vision',
            socialSoon: 'Coming soon',
            join: 'Join the community',
            badge: 'A new adventure is taking shape',
            heroStart: 'Every explorer',
            heroEnd: 'belongs here.',
            mottoLabel: 'OUR MOTTO',
            slogan: 'Your Journey’s Companion.',
            introduction: 'DeepMap is becoming a home for interactive game maps, discoveries and the people who love exploring every corner of a world.',
            supporting: 'We’re building the experience, one location at a time. Create your account and be part of the community from the start.',
            statusLabel: 'Currently in development',
            statusTitle: 'The journey starts with Elden Ring.',
            statusDescription: 'Our first interactive map is being developed. More games and community features are planned for the road ahead.',
            pathLabel: 'THE ROAD AHEAD',
            pathTitle: 'Built for curious explorers.',
            feature1Tag: '01 / FIND',
            feature1Title: 'Discover the world',
            feature1Description: 'Interactive maps designed to make finding locations and collectibles easier.',
            feature2Tag: '02 / CONTRIBUTE',
            feature2Title: 'Share discoveries',
            feature2Description: 'Tools for suggesting locations and helping maps grow, with community moderation planned.',
            feature3Tag: '03 / CONNECT',
            feature3Title: 'Explore together',
            feature3Description: 'Profiles, conversations and new ways to connect explorers are part of our vision.',
            futureNotice: 'These features are part of our development roadmap and are not all available yet.',
            communityLabel: 'BE HERE FROM THE BEGINNING',
            communityTitle: 'Your journey is part of ours.',
            communityText: 'The world is still being mapped. Make yourself at home and join the explorers helping shape what comes next.',
            communityButton: 'Create an account or sign in',
            socialsLabel: 'FOLLOW THE JOURNEY',
            socialsText: 'Keep up with the project and be part of the journey from the beginning.',
            privacy: 'Privacy Policy',
            terms: 'Terms of Use',
            contact: 'Contact',
            copyright: 'DeepMap. Made for explorers.',
            comingSoon: 'Coming soon'
        },
        pt: {
            language: 'Idioma',
            metaTitle: 'DeepMap — O teu companheiro de aventura',
            metaDescription: 'O DeepMap está a crescer como espaço de mapas interativos de videojogos e de uma comunidade de exploradores. Junta-te ao início da jornada.',
            signIn: 'Iniciar sessão',
            account: 'Entrar / Criar conta',
            myProfile: 'O meu perfil',
            signedIn: 'SESSÃO INICIADA',
            checkingAccount: 'A verificar conta…',
            supportingSignedIn: 'Já fazes parte da jornada. O teu perfil de explorador está à tua espera.',
            communityTextSignedIn: 'Já fazes parte dos exploradores que vão ajudar a construir o que vem a seguir. Obrigado por te juntares a nós!',
            navJourney: 'Primeiro mundo',
            navVision: 'A nossa visão',
            navFollow: 'Segue-nos',
            exploreVision: 'Conhece a nossa visão',
            socialSoon: 'Brevemente',
            join: 'Juntar-me à comunidade',
            badge: 'Uma nova aventura está a ganhar forma',
            heroStart: 'Há lugar para',
            heroEnd: 'cada explorador.',
            mottoLabel: 'O NOSSO LEMA',
            slogan: 'O teu companheiro de aventura.',
            introduction: 'O DeepMap está a tornar-se um espaço para mapas interativos de videojogos, descobertas e pessoas que gostam de explorar cada canto de um mundo.',
            supporting: 'Estamos a construir a experiência, uma localização de cada vez. Cria a tua conta e faz parte da comunidade desde o início.',
            statusLabel: 'Em desenvolvimento',
            statusTitle: 'A jornada começa com Elden Ring.',
            statusDescription: 'O nosso primeiro mapa interativo está em desenvolvimento. Há mais jogos e funcionalidades comunitárias planeados para o futuro.',
            pathLabel: 'O QUE VEM A SEGUIR',
            pathTitle: 'Criado para exploradores curiosos.',
            feature1Tag: '01 / DESCOBRIR',
            feature1Title: 'Descobre o mundo',
            feature1Description: 'Mapas interativos pensados para facilitar a procura de localizações e colecionáveis.',
            feature2Tag: '02 / CONTRIBUIR',
            feature2Title: 'Partilha descobertas',
            feature2Description: 'Ferramentas para sugerir localizações e fazer crescer os mapas, com moderação comunitária planeada.',
            feature3Tag: '03 / LIGAR',
            feature3Title: 'Explora em conjunto',
            feature3Description: 'Perfis, conversas e novas formas de ligar exploradores fazem parte da nossa visão.',
            futureNotice: 'Estas funcionalidades fazem parte do roadmap e ainda não estão todas disponíveis.',
            communityLabel: 'FAZ PARTE DESDE O INÍCIO',
            communityTitle: 'A tua jornada faz parte da nossa.',
            communityText: 'O mundo ainda está a ser mapeado. Sente-te em casa e junta-te aos exploradores que vão ajudar a construir o que vem a seguir.',
            communityButton: 'Criar conta ou iniciar sessão',
            socialsLabel: 'ACOMPANHA A JORNADA',
            socialsText: 'Acompanha o projeto e faz parte desta jornada desde o início.',
            privacy: 'Política de Privacidade',
            terms: 'Termos de Utilização',
            contact: 'Contacto',
            copyright: 'DeepMap. Criado para exploradores.',
            comingSoon: 'Brevemente'
        }
    };

    let t = $derived(copy[currentLanguage] ?? copy.en);

    // Só ligar perfis com endereço conhecido; não criar URLs fictícios.
    const socials = [
        { key: 'instagram', name: 'Instagram', url: 'https://www.instagram.com/deepmap.cc/' },
        { key: 'tiktok', name: 'TikTok', url: 'https://www.tiktok.com/@deepmap.cc' },
        { key: 'x', name: 'X', url: 'https://x.com/deepmapcc' },
        { key: 'youtube', name: 'YouTube', url: 'https://www.youtube.com/@deepmapcc' },
        { key: 'facebook', name: 'Facebook', url: 'https://www.facebook.com/deepmapcc' }
    ];

    onMount(() => {
        currentLanguage = getSiteLanguage();
        const supabase = getSupabaseBrowserClient();
        let active = true;
        let accountVersion = 0;
        let authEventVersion = 0;

        function applyUser(user) {
            const version = ++accountVersion;
            accountUser = user ?? null;
            profileUsername = null;
            avatarFailed = false;
            checkingSession = false;

            if (!user?.id) return;

            // O username público está em public.profiles, não nos metadados de autenticação.
            void supabase.from('profiles')
                .select('username')
                .eq('id', user.id)
                .maybeSingle()
                .then(({ data, error }) => {
                    if (active && version === accountVersion && !error) {
                        profileUsername = data?.username ?? null;
                    }
                })
                .catch(() => {
                    // O nome de apresentação continua disponível caso a leitura falhe.
                });
        }

        const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
            if (!active || event === 'INITIAL_SESSION') return;
            if (['SIGNED_IN', 'SIGNED_OUT', 'USER_UPDATED'].includes(event)) {
                authEventVersion++;
                // Evitar operações de BD diretamente dentro do callback de Auth.
                Promise.resolve().then(() => {
                    if (active) applyUser(session?.user ?? null);
                });
            }
        });

        const initialAuthVersion = authEventVersion;
        void supabase.auth.getUser()
            .then(({ data, error }) => {
                if (active && initialAuthVersion === authEventVersion) {
                    applyUser(error ? null : data.user);
                }
            })
            .catch(() => {
                if (active && initialAuthVersion === authEventVersion) applyUser(null);
            });

        return () => {
            active = false;
            accountVersion++;
            subscription.unsubscribe();
        };
    });

    function changeLanguage(event) {
        currentLanguage = setSiteLanguage(event.currentTarget.value);
    }
</script>

<svelte:head>
    <title>{t.metaTitle}</title>
    <meta name="description" content={t.metaDescription} />
    <link rel="canonical" href="https://deepmap.cc/" />
</svelte:head>

{#snippet socialIcons()}
    {#each socials as social (social.key)}
        {#if social.url}
            <a class="social-icon" href={social.url} target="_blank" rel="noopener noreferrer" aria-label={`DeepMap on ${social.name}`} title={social.name}>
                {#if social.key === 'instagram'}
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4"/><path d="M17.5 6.5h.01" stroke-width="2.8"/></svg>
                {:else if social.key === 'tiktok'}
                    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16 2c.3 2.4 1.6 3.8 4 4.1V9a9.1 9.1 0 0 1-4-1.1v7.4a6 6 0 1 1-6-6c.4 0 .9 0 1.3.1v3.2A3 3 0 1 0 13 15.4V2h3Z"/></svg>
                {:else if social.key === 'x'}
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="square" aria-hidden="true"><path d="M4 3 20 21M20 3 4 21"/><path d="M4 3h4M16 21h4"/></svg>
                {:else if social.key === 'youtube'}
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" aria-hidden="true"><rect x="2" y="5" width="20" height="14" rx="4"/><path d="m10 9 5 3-5 3Z" fill="currentColor" stroke="none"/></svg>
                {:else if social.key === 'facebook'}
                    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M14.2 21v-7.6h2.6l.4-3h-3V8.5c0-.9.3-1.5 1.5-1.5h1.6V4.3A21 21 0 0 0 15 4c-2.6 0-4.3 1.6-4.3 4.4v2H8v3h2.7V21h3.5Z"/></svg>
                {/if}
            </a>
        {:else}
            <span class="social-icon social-pending" title={`${social.name} — ${t.socialSoon}`} aria-label={`${social.name} — ${t.socialSoon}`}>
                {#if social.key === 'youtube'}
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" aria-hidden="true"><rect x="2" y="5" width="20" height="14" rx="4"/><path d="m10 9 5 3-5 3Z" fill="currentColor" stroke="none"/></svg>
                {:else if social.key === 'facebook'}
                    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M14.2 21v-7.6h2.6l.4-3h-3V8.5c0-.9.3-1.5 1.5-1.5h1.6V4.3A21 21 0 0 0 15 4c-2.6 0-4.3 1.6-4.3 4.4v2H8v3h2.7V21h3.5Z"/></svg>
                {/if}
            </span>
        {/if}
    {/each}
{/snippet}

<main class="landing-page">
    <div class="site-shell">
        <header class="site-header">
            <a href="/" class="brand-link" aria-label="DeepMap — Home">
                <img src="/brand/logo.png" alt="DeepMap" class="brand-logo" />
            </a>
            <nav class="header-navigation" aria-label="Site navigation">
                <a href="#journey">{t.navJourney}</a>
                <a href="#vision">{t.navVision}</a>
                <a href="#follow">{t.navFollow}</a>
            </nav>
            <div class="header-actions">
                <label class="language-wrap">
                    <span class="sr-only">{t.language}</span>
                    <select value={currentLanguage} onchange={changeLanguage} aria-label={t.language}>
                        <option value="en">EN</option>
                        <option value="pt">PT</option>
                    </select>
                </label>
                {#if checkingSession}
                    <span class="header-join account-loading" aria-live="polite">{t.checkingAccount}</span>
                {:else if accountUser}
                    <a class="header-join account-link" href="/profile" aria-label={`${t.myProfile} — ${accountName}`} title={t.myProfile}>
                        <span class="account-avatar" aria-hidden="true">
                            {#if accountAvatar && !avatarFailed}
                                <img src={accountAvatar} alt="" referrerpolicy="no-referrer" onerror={() => avatarFailed = true} />
                            {:else}
                                <span>{accountInitial}</span>
                            {/if}
                        </span>
                        <span class="account-copy">
                            <span class="account-status">{t.signedIn}</span>
                            <strong class="account-name">{accountName}</strong>
                        </span>
                        <span class="account-arrow" aria-hidden="true">↗</span>
                    </a>
                {:else}
                    <a class="header-join" href="/login">{t.account}<span aria-hidden="true"> ↗</span></a>
                {/if}
            </div>
        </header>

        <section class="hero" aria-labelledby="landing-title">
            <div class="hero-halo" aria-hidden="true"></div>
            <div class="hero-lines" aria-hidden="true">
                <span></span><span></span><span></span><span></span>
            </div>
            <div class="hero-content">
                <div class="hero-badge"><span class="badge-dot" aria-hidden="true"></span>{t.badge}</div>
                <p class="eyebrow">DEEPMAP <span class="eyebrow-line"></span> {t.comingSoon}</p>
                <h1 id="landing-title">{t.heroStart}<br /><em>{t.heroEnd}</em></h1>
                <div class="hero-motto">
                    <span class="motto-label"><span class="motto-diamond" aria-hidden="true">✦</span> {t.mottoLabel}</span>
                    <p class="hero-slogan">“{t.slogan}”</p>
                </div>
                <p class="hero-intro">{t.introduction}</p>
                <p class="hero-support">{accountUser ? t.supportingSignedIn : t.supporting}</p>
                <div class="hero-actions">
                    {#if checkingSession}
                        <span class="primary-button cta-loading" aria-live="polite">{t.checkingAccount}</span>
                    {:else}
                        <a class="primary-button" href={accountUser ? '/profile' : '/login'}>{accountUser ? t.myProfile : t.join}<span aria-hidden="true"> ↗</span></a>
                    {/if}
                    <a class="secondary-button" href="#vision">{t.exploreVision}</a>
                </div>
                <div class="hero-socials"><span>{t.socialsLabel}</span><div class="social-links">{@render socialIcons()}</div></div>
            </div>
            <div class="hero-art" aria-hidden="true">
                <div class="art-halo"></div>
                <div class="art-ruin ruin-left"></div>
                <div class="art-ruin ruin-right"></div>
                <div class="art-ridge ridge-back"></div>
                <div class="art-ridge ridge-front"></div>
                <div class="art-compass"><span>✧</span></div>
            </div>
            <div class="hero-bottom" aria-hidden="true"><span>✦</span><span class="hero-bottom-line"></span><span>✦</span></div>
        </section>

        <section class="status-card" id="journey" aria-label={t.statusLabel}>
            <div class="status-symbol" aria-hidden="true">✧</div>
            <div class="status-copy">
                <span class="section-label">{t.statusLabel}</span>
                <h2>{t.statusTitle}</h2>
                <p>{t.statusDescription}</p>
            </div>
            <div class="status-pill">{t.comingSoon}</div>
        </section>

        <section class="roadmap" id="vision" aria-labelledby="roadmap-title">
            <div class="section-heading">
                <span class="section-label">{t.pathLabel}</span>
                <h2 id="roadmap-title">{t.pathTitle}</h2>
            </div>
            <div class="feature-grid">
                <article class="feature-card">
                    <div class="feature-symbol" aria-hidden="true">
                        <svg viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" aria-hidden="true"><path d="m7 11 11-4 12 4 11-4v30l-11 4-12-4-11 4z"/><path d="M18 7v30M30 11v30"/><circle cx="30" cy="22" r="3"/><path d="m30 25-5 7"/></svg>
                    </div>
                    <span class="feature-tag">{t.feature1Tag}</span>
                    <h3>{t.feature1Title}</h3>
                    <p>{t.feature1Description}</p>
                </article>
                <article class="feature-card">
                    <div class="feature-symbol" aria-hidden="true">
                        <svg viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 12h32v23H8zM14 20h20M14 26h13"/><path d="m29 36 8-8 3 3-8 8-5 2z"/></svg>
                    </div>
                    <span class="feature-tag">{t.feature2Tag}</span>
                    <h3>{t.feature2Title}</h3>
                    <p>{t.feature2Description}</p>
                </article>
                <article class="feature-card">
                    <div class="feature-symbol" aria-hidden="true">
                        <svg viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="16" cy="16" r="6"/><circle cx="33" cy="18" r="5"/><path d="M5 38v-4c0-6 5-10 11-10s11 4 11 10v4zM29 28c6-2 14 2 14 9v1H30"/></svg>
                    </div>
                    <span class="feature-tag">{t.feature3Tag}</span>
                    <h3>{t.feature3Title}</h3>
                    <p>{t.feature3Description}</p>
                </article>
            </div>
            <p class="roadmap-note">{t.futureNotice}</p>
        </section>

        <section class="community" aria-labelledby="community-title">
            <div class="community-decoration" aria-hidden="true">✦</div>
            <span class="section-label">{t.communityLabel}</span>
            <h2 id="community-title">{t.communityTitle}</h2>
            <p>{accountUser ? t.communityTextSignedIn : t.communityText}</p>
            {#if checkingSession}
                <span class="primary-button cta-loading" aria-live="polite">{t.checkingAccount}</span>
            {:else}
                <a class="primary-button" href={accountUser ? '/profile' : '/login'}>{accountUser ? t.myProfile : t.communityButton}<span aria-hidden="true"> ↗</span></a>
            {/if}
        </section>

        <footer class="site-footer" id="follow">
            <div class="footer-top">
                <a href="/" class="footer-logo" aria-label="DeepMap — Home"><img src="/brand/logo.png" alt="DeepMap" /></a>
                <div class="footer-social">
                    <span class="section-label">{t.socialsLabel}</span>
                    <p>{t.socialsText}</p>
                    <div class="social-links footer-social-links">{@render socialIcons()}</div>
                </div>
            </div>
            <div class="footer-bottom">
                <span>© {new Date().getFullYear()} {t.copyright}</span>
                <div class="footer-links">
                    <a href="/privacy">{t.privacy}</a>
                    <a href="/terms">{t.terms}</a>
                    <a href="mailto:contact@deepmap.cc">{t.contact}</a>
                </div>
            </div>
        </footer>
    </div>
</main>

<style>
    :global(html) { background: #061018; }
    :global(body) { margin: 0; }
    :global(*) { box-sizing: border-box; }
    .landing-page { min-height: 100vh; min-height: 100dvh; background: #061018; color: #e9e5dd; font-family: 'Segoe UI', Arial, sans-serif; overflow: hidden; }
    .site-shell { max-width: 1440px; margin: auto; background: linear-gradient(180deg, #07121a 0%, #080b10 42%, #0b0b0e 100%); }
    .site-header { position: relative; z-index: 3; min-height: 94px; padding: 20px clamp(20px, 6vw, 86px); display: flex; align-items: center; justify-content: space-between; gap: 18px; border-bottom: 1px solid rgba(40, 208, 235, .13); background: rgba(4, 11, 16, .94); }
    .header-navigation { display: flex; gap: clamp(15px, 2vw, 34px); align-items: center; margin-left: auto; }
    .header-navigation a { color: #c8c1bd; font-size: .85rem; text-decoration: none; white-space: nowrap; }
    .header-navigation a:hover { color: #d8b86f; }
    .brand-link { display: flex; align-items: center; flex: none; }
    .brand-logo { display: block; max-width: 166px; width: auto; height: auto; max-height: 57px; object-fit: contain; }
    .header-actions { display: flex; align-items: center; gap: 23px; }
    .language-wrap select { border: 1px solid #245b66; border-radius: 7px; padding: 8px; background: #0b1820; color: #dbc28c; font: inherit; font-size: .76rem; cursor: pointer; }
    .header-join, .footer-links a { color: #e1dcd4; text-decoration: none; font-size: .86rem; }
    .footer-links a:hover { color: #d8b86f; }
    .header-join { border: 1px solid #c8a355; background: linear-gradient(135deg, #c8a355, #d5b56d); padding: 11px 16px; border-radius: 7px; color: #17130c; font-weight: 800; box-shadow: 0 0 24px rgba(200, 163, 85, .12); }
    .header-join:hover { background: linear-gradient(135deg, #d5b56d, #e1c886); }
    .account-loading, .cta-loading { opacity: .68; cursor: default; }
    .account-link { display: inline-flex; align-items: center; gap: 10px; min-width: 0; max-width: 235px; }
    .account-avatar { width: 31px; height: 31px; flex: none; display: grid; place-items: center; overflow: hidden; border: 1px solid #c8a355; border-radius: 50%; background: #10212a; color: #e6c88c; font-size: .85rem; font-weight: 800; }
    .account-avatar img { display: block; width: 100%; height: 100%; object-fit: cover; }
    .account-copy { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
    .account-status { color: #b4a48b; font-size: .56rem; font-weight: 800; letter-spacing: .085em; }
    .account-name { color: #f0d39a; font-size: .81rem; line-height: 1.15; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .account-arrow { flex: none; }
    .hero { isolation: isolate; position: relative; display: flex; justify-content: flex-start; align-items: center; padding: 94px clamp(20px,6vw,86px) 106px; min-height: 670px; border-bottom: 1px solid #17313a; background-image: linear-gradient(90deg, rgba(3, 12, 18, .98) 0%, rgba(3, 12, 18, .93) 27%, rgba(3, 12, 18, .67) 49%, rgba(3, 12, 18, .18) 72%, rgba(3, 12, 18, .10) 100%), url('/brand/home-hero-world.webp'); background-size: cover; background-position: center center; background-repeat: no-repeat; overflow: hidden; text-align: left; }
    .hero::before { content: ''; position: absolute; z-index: -1; inset: 0; background: radial-gradient(circle at 73% 56%, rgba(18, 210, 234, .08), transparent 32%), linear-gradient(180deg, rgba(0,0,0,.02) 55%, rgba(2,9,13,.56) 100%); }
    .hero::after { content: ''; position: absolute; z-index: -1; inset: auto 0 0; height: 170px; background: linear-gradient(180deg, transparent, rgba(4, 12, 17, .82)); }
    .hero-halo { display: none; }
    .hero-lines span { display: none; }
    .hero-lines span:nth-child(1) { left: 12%; top: 15%; } .hero-lines span:nth-child(2) { right: 14%; top: 20%; } .hero-lines span:nth-child(3) { left: 23%; bottom: 18%; } .hero-lines span:nth-child(4) { right: 23%; bottom: 15%; }
    .hero-content { position: relative; z-index: 1; width: 100%; max-width: 620px; }
    .hero-badge { display: inline-flex; align-items: center; gap: 9px; padding: 9px 14px; border: 1px solid #a388573d; border-radius: 999px; background: #231f1bcc; color: #ddc394; font-size: .77rem; letter-spacing: .02em; }
    .badge-dot { width: 6px; height: 6px; background: #c8a355; border-radius: 50%; box-shadow: 0 0 10px #d1ad6c; }
    .eyebrow { display: flex; justify-content: flex-start; align-items: center; gap: 13px; margin: 35px 0 17px; color: #b69a68; font-size: .73rem; font-weight: 700; letter-spacing: .2em; text-transform: uppercase; }
    .eyebrow-line { display: inline-block; width: 28px; height: 1px; background: #a28657; }
    h1, h2, h3, p { margin-top: 0; }
    .hero h1 { font-family: Georgia, 'Times New Roman', serif; font-weight: 500; letter-spacing: -.06em; font-size: clamp(3.2rem, 6.2vw, 6rem); line-height: 1.09; margin: 0 0 15px; color: #f1e8d9; text-wrap: balance; }
    .hero h1 em { font-weight: 400; color: #d3b476; }
    .hero-motto { display: block; width: fit-content; max-width: 100%; margin: 24px 0 27px; padding: 13px 21px 14px; border-left: 3px solid #c8a355; background: linear-gradient(90deg, #c8a35512, transparent); }
    .motto-label { display: flex; align-items: center; gap: 7px; color: #c8a355; font-size: .66rem; letter-spacing: .2em; font-weight: 750; }
    .motto-diamond { font-size: .8rem; }
    .hero-slogan { color: #edcf96; font-family: Georgia, 'Times New Roman', serif; font-size: clamp(1.26rem, 2.1vw, 1.7rem); letter-spacing: .01em; line-height: 1.3; margin: 9px 0 0; text-wrap: balance; }
    .hero-intro { font-size: clamp(1rem, 1.5vw, 1.12rem); line-height: 1.7; color: #dbd5cb; max-width: 600px; margin: 0 0 10px; }
    .hero-support { font-size: .94rem; line-height: 1.7; max-width: 600px; margin: 0; color: #a9a4a6; }
    .hero-actions { display: flex; align-items: center; justify-content: flex-start; gap: 13px; flex-wrap: wrap; margin-top: 32px; }
    .primary-button, .secondary-button { display: inline-flex; align-items: center; justify-content: center; min-height: 47px; padding: 12px 20px; border-radius: 8px; text-decoration: none; font-size: .87rem; font-weight: 700; transition: background .18s, border-color .18s, transform .18s; }
    .primary-button { color: #17130c; background: linear-gradient(135deg, #c8a355, #d5b56d); border: 1px solid #c8a355; box-shadow: 0 0 28px rgba(200, 163, 85, .12); }
    .primary-button:hover { background: linear-gradient(135deg, #d5b56d, #e1c886); transform: translateY(-1px); }
    .secondary-button { color: #e9e5dd; background: rgba(14, 13, 12, .72); border: 1px solid #6d5c3e; }
    .secondary-button:hover { background: #211d18; border-color: #c8a355; }
    .hero-bottom { position: absolute; display: flex; align-items: center; gap: 13px; color: #9b8051; bottom: 33px; left: 50%; transform: translateX(-50%); font-size: .75rem; }
    .hero-bottom-line { width: 90px; height: 1px; background: linear-gradient(90deg,transparent,#9b8051,transparent); }
    .status-card { margin: 54px clamp(20px,6vw,86px) 70px; padding: 27px 30px; display: flex; gap: 23px; align-items: center; background: linear-gradient(115deg,#201e20,#18181c); border: 1px solid #484037; border-radius: 13px; }
    .status-symbol { flex: none; display: grid; place-items: center; width: 64px; height: 64px; color: #dbc083; background: #312b23; border: 1px solid #68583e; border-radius: 12px; font-size: 2rem; }
    .section-label { color: #bca06e; display: block; text-transform: uppercase; letter-spacing: .14em; font-size: .69rem; font-weight: 700; }
    .status-copy { flex: 1; }
    .status-copy h2 { margin: 7px 0; font-family: Georgia, 'Times New Roman', serif; font-weight: 500; font-size: clamp(1.4rem,2.5vw,1.9rem); }
    .status-copy p { margin: 0; color: #afa9a8; line-height: 1.65; font-size: .86rem; }
    .status-pill { flex: none; white-space: nowrap; border: 1px solid #715d40; background: #342b20; color: #e1c891; font-size: .75rem; padding: 9px 12px; border-radius: 999px; }
    .roadmap { padding: 20px clamp(20px,6vw,86px) 86px; }
    .section-heading { max-width: 650px; margin-bottom: 28px; }
    .section-heading h2 { margin: 10px 0 0; font-family: Georgia, 'Times New Roman', serif; font-size: clamp(2rem,3.2vw,2.8rem); font-weight: 500; letter-spacing: -.035em; }
    .feature-grid { display: grid; grid-template-columns: repeat(3,minmax(0,1fr)); gap: 16px; }
    .feature-card { min-width: 0; background: linear-gradient(145deg,#1c1b21,#151519); border: 1px solid #34323a; border-radius: 12px; padding: 28px; }
    .feature-symbol { color: #c8a355; width: 47px; height: 47px; margin-bottom: 26px; }
    .feature-symbol svg { width: 100%; height: 100%; }
    .feature-tag { color: #b29765; font-size: .7rem; letter-spacing: .12em; font-weight: 700; }
    .feature-card h3 { font-family: Georgia, 'Times New Roman', serif; font-weight: 500; font-size: 1.45rem; color: #efe9df; margin: 10px 0 12px; }
    .feature-card p { font-size: .88rem; line-height: 1.7; color: #aaa4a7; margin: 0; }
    .roadmap-note { color: #8d898c; margin: 16px 0 0; font-size: .76rem; }
    .community { position: relative; isolation: isolate; text-align: center; margin: 0 clamp(20px,6vw,86px) 72px; padding: 60px 25px; overflow: hidden; border-radius: 14px; border: 1px solid #65533b; background: radial-gradient(ellipse at 50% -20%, #3d3124, #242125 51%, #17171b 95%); }
    .community-decoration { position: absolute; z-index: -1; top: -108px; left: 50%; transform: translateX(-50%); color: #c8a3550a; font-size: 340px; line-height: 1; }
    .community h2 { font-size: clamp(2rem,3.8vw,3.3rem); letter-spacing: -.045em; font-family: Georgia,'Times New Roman',serif; font-weight: 500; margin: 13px 0 14px; }
    .community p { max-width: 560px; margin: 0 auto 25px; color: #c0b5aa; line-height: 1.7; font-size: .94rem; }
    .site-footer { padding: 0 clamp(20px,6vw,86px) 28px; }
    .footer-top { display: flex; justify-content: space-between; gap: 30px; border-bottom: 1px solid #33323a; padding: 0 0 32px; }
    .footer-logo img { display: block; width: auto; max-width: 145px; height: auto; max-height: 52px; }
    .footer-social { max-width: 360px; text-align: right; }
    .footer-social p { font-size: .79rem; color: #a6a0a5; margin: 8px 0 0; line-height: 1.55; }
    .social-links { display: flex; align-items: center; flex-wrap: wrap; gap: 9px; }
    .social-icon { display: inline-flex; align-items: center; justify-content: center; width: 40px; height: 40px; border: 1px solid #6d5c3e; border-radius: 10px; background: rgba(8, 18, 24, .88); color: #e5c995; text-decoration: none; transition: border-color .15s, background .15s, color .15s, transform .15s; }
    .social-icon svg { width: 19px; height: 19px; }
    a.social-icon:hover { color: #f2dfb2; border-color: #c8a355; background: #221d16; transform: translateY(-2px); }
    .social-pending { opacity: .43; cursor: not-allowed; }
    .hero-socials { display: flex; flex-wrap: wrap; align-items: center; gap: 15px; margin-top: 28px; }
    .hero-socials > span { font-size: .7rem; letter-spacing: .12em; font-weight: 700; color: #b99d6b; }
    .footer-social-links { justify-content: flex-end; margin-top: 13px; }
    .hero-art { display: none; }
    .art-halo { position: absolute; width: min(520px, 68vw); aspect-ratio: 1; right: 8%; top: 10%; border: 2px solid #cba55945; border-radius: 50%; box-shadow: 0 0 38px #d1ad6c32, 0 0 0 21px #d1ad6c07, 0 0 0 70px #d1ad6c06, inset 0 0 64px #ad8c4820; background: radial-gradient(circle at 50% 46%,#f5ce7840,transparent 58%); }
    .art-halo::before, .art-halo::after { content: ''; position: absolute; inset: 13%; border: 1px solid #d8b87645; border-radius: 50%; }
    .art-halo::after { inset: 26%; border-style: dashed; transform: rotate(21deg); }
    .art-ruin { position: absolute; bottom: 18%; width: 84px; height: 235px; border: 8px solid #1a1a1d; border-bottom: 0; border-radius: 43px 43px 0 0; box-shadow: -17px 9px 0 #262329, 18px 15px 0 #12151a, 0 0 42px #c5a66d1a; }
    .art-ruin::after { content: ''; position: absolute; inset: 32px 15px 0; border: 5px solid #121317; border-bottom: 0; border-radius: 30px 30px 0 0; }
    .ruin-left { left: 17%; transform: rotate(-5deg); }
    .ruin-right { right: 10%; height: 306px; width: 106px; transform: rotate(7deg); }
    .art-ridge { position: absolute; left: -15%; width: 135%; bottom: -18%; height: 52%; border-radius: 48% 56% 0 0; }
    .ridge-back { bottom: -10%; background: #262529; transform: rotate(-9deg); box-shadow: 0 -13px 42px #d0b16b19; }
    .ridge-front { bottom: -27%; background: #111419; transform: rotate(8deg); box-shadow: 0 -12px 36px #0a0d12; }
    .art-compass { position: absolute; z-index: 1; right: 31%; top: 37%; display: grid; place-items: center; width: 146px; height: 146px; border: 1px solid #f6d99670; border-radius: 50%; background: #b9975426; color: #ebcd88; box-shadow: 0 0 65px #eac47a4a, inset 0 0 30px #dbb87a44; }
    .art-compass span { font-family: Georgia,serif; font-size: 108px; line-height: 1; margin-top: -5px; }
    .footer-bottom { display: flex; justify-content: space-between; align-items: center; gap: 20px; padding-top: 25px; color: #89838a; font-size: .78rem; }
    .footer-links { display: flex; gap: 24px; }
    .footer-links a { font-size: .78rem; }
    .sr-only { position: absolute; height: 1px; width: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
    a:focus-visible, select:focus-visible { outline: 2px solid #28d9ec; outline-offset: 4px; }
    @media (max-width: 770px) {
        .site-header { min-height: 78px; padding: 16px 20px; }
        .brand-logo { max-width: 135px; max-height: 48px; }
        .header-actions { gap: 12px; }
        .header-join { padding: 9px 11px; font-size: .78rem; }
        .header-navigation { display: none; }
        .hero-art { left: 45%; opacity: .72; }
        .hero { min-height: 600px; padding: 85px 20px 84px; }
        .feature-grid { grid-template-columns: 1fr; }
        .feature-card { padding: 25px; }
        .feature-symbol { margin-bottom: 15px; }
        .status-card { margin-top: 35px; }
    }
    @media (max-width: 500px) {
        .site-header { gap: 9px; }
        .brand-logo { max-width: 103px; }
        .header-actions { gap: 9px; }
        .header-join { display: inline-flex; padding: 9px 10px; font-size: .72rem; text-align: center; }
        .account-link { gap: 6px; max-width: min(43vw, 165px); }
        .account-status { display: none; }
        .account-avatar { width: 26px; height: 26px; font-size: .72rem; }
        .account-name { max-width: 88px; font-size: .72rem; }
        .account-arrow { display: none; }
        .language-wrap select { padding: 7px 5px; }
        .hero { min-height: 0; align-items: flex-start; padding: 26px 19px 75px; background-position: 61% center; }
        .hero-art { inset: 0; opacity: .26; }
        .hero-halo { right: -40%; top: 13%; }
        .hero::before { background: linear-gradient(180deg, rgba(2,10,15,.34) 0%, rgba(2,10,15,.73) 44%, rgba(2,10,15,.95) 100%), linear-gradient(90deg, rgba(2,10,15,.86) 0%, rgba(2,10,15,.50) 72%, rgba(2,10,15,.18) 100%); }
        .hero-socials { align-items: flex-start; flex-direction: column; gap: 10px; }
        .footer-social-links { justify-content: flex-start; }
        .hero h1 { font-size: clamp(2.72rem,12vw,3.8rem); }
        .hero-badge { font-size: .68rem; }
        .hero-intro { font-size: .94rem; }
        .hero-support { font-size: .85rem; }
        .status-card { padding: 20px; display: block; }
        .status-symbol { width: 48px; height: 48px; margin-bottom: 14px; font-size: 1.5rem; }
        .status-pill { display: inline-block; margin-top: 17px; }
        .roadmap { padding-bottom: 50px; }
        .community { margin-bottom: 45px; padding: 46px 19px; }
        .footer-top, .footer-bottom { flex-direction: column; align-items: flex-start; }
        .footer-social { text-align: left; }
    }
    :global(html) { scroll-behavior: smooth; }
    @media (prefers-reduced-motion: reduce) { .primary-button, .secondary-button { transition: none; } }

    /* Sessão iniciada: botão outline, sem preenchimento dourado */
    .header-join.account-link {
        border-color: rgba(200, 163, 85, .58);
        background: rgba(10, 14, 18, .72);
        color: #f2eee7;
        box-shadow: none;
    }

    .header-join.account-link:hover,
    .header-join.account-link:focus-visible {
        border-color: #c8a355;
        background: rgba(200, 163, 85, .08);
        color: #fff;
    }

    .header-join.account-link .account-status {
        color: #c8a355;
    }

    .header-join.account-link .account-name {
        color: #f2eee7;
    }
</style>
