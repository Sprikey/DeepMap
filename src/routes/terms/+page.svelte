<script>
    import { onMount } from 'svelte';
    import { getSiteLanguage, setSiteLanguage } from '$lib/i18n/site.js';

    let currentLanguage = $state('en');

    onMount(() => {
        currentLanguage = setSiteLanguage(getSiteLanguage());
    });

    function changeLanguage(event) {
        currentLanguage = setSiteLanguage(event.currentTarget.value);
    }

    const content = {
        en: {
            title: 'Terms of Use',
            description: 'The rules for using DeepMap, your account and the platform.',
            back: 'Back to DeepMap',
            language: 'Language',
            eyebrow: 'FAIR PLAY',
            subtitle: 'Explore freely. Respect the journey.',
            updated: 'Last updated: 30 September 2026',
            intro: 'These Terms explain the rules for accessing and using DeepMap. By creating an account or using the platform, you agree to these Terms and to our Privacy Policy.',
            contactLabel: 'Contact',
            asideTitle: 'DeepMap account',
            aside: 'Keep your login details secure and use the platform responsibly. Your account is personal to you and you are responsible for activity carried out through it.',
            privacyLabel: 'Privacy Policy',
            sections: [
                {
                    title: 'About DeepMap',
                    paragraphs: [
                        'DeepMap (deepmap.cc) is an independent platform operated by Rafael Silva in Portugal. It provides interactive gaming maps, profile features and other tools intended to help players explore games and communities.',
                        'DeepMap is not affiliated with, endorsed by or sponsored by the publishers, developers or trademark owners of the games represented on the platform unless expressly stated.'
                    ]
                },
                {
                    title: 'Using the platform',
                    paragraphs: [
                        'You may use DeepMap for personal, lawful purposes. You must not misuse the platform, attempt to disrupt its operation, bypass security controls, scrape or automate access in a way that harms the service, or use it to infringe the rights of others.',
                        'You must comply with applicable law and with any additional rules shown for specific features.'
                    ]
                },
                {
                    title: 'Accounts',
                    paragraphs: [
                        'Some features require an account. You must provide accurate information where required and keep access to your account secure. Do not share credentials or deliberately allow another person to impersonate you.',
                        'We may restrict, suspend or remove access where reasonably necessary to protect the platform, other users, legal rights or security, including in cases of abuse, fraud, repeated rule violations or technical misuse.'
                    ]
                },
                {
                    title: 'Profiles and public information',
                    paragraphs: [
                        'If you choose a public profile, the profile information you make public may be visible to other visitors and accessible through a shareable link. You are responsible for the information you choose to publish.',
                        'Do not use names, images, biographies or other profile content that is unlawful, abusive, deceptive, infringes third-party rights or impersonates another person or organisation.'
                    ]
                },
                {
                    title: 'Maps, locations and accuracy',
                    paragraphs: [
                        'DeepMap aims to provide useful map information, but map positions, descriptions, collectibles, routes and other game information may be incomplete, outdated or inaccurate.',
                        'You remain responsible for how you use information from the platform. DeepMap does not guarantee that every marker, coordinate, route or description will match a particular game version, patch, platform or playthrough.'
                    ]
                },
                {
                    title: 'Intellectual property',
                    paragraphs: [
                        'The DeepMap name, branding, interface, original graphics, platform code and original content are protected by applicable intellectual-property law.',
                        'Game names, logos, screenshots, artwork, characters and other third-party material remain the property of their respective owners. Their appearance on DeepMap does not transfer ownership to DeepMap.',
                        'You may not copy, republish, sell, reverse engineer or commercially exploit substantial parts of DeepMap without permission, except where applicable law expressly permits it.'
                    ]
                },
                {
                    title: 'Availability and changes',
                    paragraphs: [
                        'DeepMap is under active development. Features may change, be added, removed, limited or temporarily unavailable. We may perform maintenance or make technical changes where necessary.',
                        'We do not promise uninterrupted or error-free availability. Where practical, significant changes affecting users will be communicated through the platform or other appropriate channels.'
                    ]
                },
                {
                    title: 'External services and links',
                    paragraphs: [
                        'DeepMap relies on third-party services for parts of its operation and may link to external websites or services. Those third parties operate under their own terms and privacy practices.',
                        'DeepMap is not responsible for the content, availability or practices of external services that it does not control.'
                    ]
                },
                {
                    title: 'Liability',
                    paragraphs: [
                        'Nothing in these Terms excludes or limits liability where doing so would be unlawful. Subject to mandatory law, DeepMap is provided on an as-available basis and is not responsible for indirect losses caused by reliance on optional map information, temporary outages or third-party services beyond our reasonable control.',
                        'These Terms do not affect any rights you may have under mandatory consumer or data-protection law.'
                    ]
                },
                {
                    title: 'Future community features',
                    paragraphs: [
                        'DeepMap may later introduce comments, community contributions, moderation tools, donations, premium features or other interactive services. Additional rules may apply to those features before they are made available.',
                        'Until such features are launched, these Terms do not grant users a right to publish markers, edit official maps or access administrative tools.'
                    ]
                },
                {
                    title: 'Changes to these Terms',
                    paragraphs: [
                        'We may update these Terms as DeepMap evolves. The latest version and its update date will be published on this page. Where required, material changes will be communicated before they take effect.'
                    ]
                },
                {
                    title: 'Applicable law and contact',
                    paragraphs: [
                        'These Terms are governed by Portuguese law, without limiting any mandatory protections that may apply to you under the law of your country of residence.',
                        'Questions about these Terms can be sent to contact@deepmap.cc.'
                    ]
                }
            ],
            footer: 'Every explorer belongs here.'
        },
        pt: {
            title: 'Termos de Utilização',
            description: 'As regras de utilização do DeepMap, da tua conta e da plataforma.',
            back: 'Voltar ao DeepMap',
            language: 'Idioma',
            eyebrow: 'JOGO LIMPO',
            subtitle: 'Explora livremente. Respeita a jornada.',
            updated: 'Última atualização: 30 de setembro de 2026',
            intro: 'Estes Termos explicam as regras de acesso e utilização do DeepMap. Ao criares uma conta ou utilizares a plataforma, aceitas estes Termos e a nossa Política de Privacidade.',
            contactLabel: 'Contacto',
            asideTitle: 'Conta DeepMap',
            aside: 'Mantém os teus dados de acesso seguros e utiliza a plataforma de forma responsável. A tua conta é pessoal e és responsável pela atividade realizada através dela.',
            privacyLabel: 'Política de Privacidade',
            sections: [
                {
                    title: 'Sobre o DeepMap',
                    paragraphs: [
                        'O DeepMap (deepmap.cc) é uma plataforma independente operada por Rafael Silva em Portugal. Disponibiliza mapas interativos de videojogos, funcionalidades de perfil e outras ferramentas destinadas a ajudar jogadores a explorar jogos e comunidades.',
                        'O DeepMap não é afiliado, aprovado ou patrocinado pelos editores, produtores ou titulares das marcas dos jogos representados na plataforma, salvo indicação expressa em contrário.'
                    ]
                },
                {
                    title: 'Utilização da plataforma',
                    paragraphs: [
                        'Podes utilizar o DeepMap para fins pessoais e lícitos. Não deves utilizar abusivamente a plataforma, tentar perturbar o seu funcionamento, contornar mecanismos de segurança, automatizar ou extrair dados de forma prejudicial ao serviço, nem utilizá-la para violar direitos de terceiros.',
                        'Deves cumprir a legislação aplicável e quaisquer regras adicionais apresentadas para funcionalidades específicas.'
                    ]
                },
                {
                    title: 'Contas',
                    paragraphs: [
                        'Algumas funcionalidades exigem uma conta. Deves fornecer informação correta quando necessária e manter o acesso à conta seguro. Não partilhes credenciais nem permitas deliberadamente que outra pessoa se faça passar por ti.',
                        'Podemos limitar, suspender ou remover o acesso quando seja razoavelmente necessário para proteger a plataforma, outros utilizadores, direitos legais ou a segurança, incluindo situações de abuso, fraude, violações repetidas das regras ou utilização técnica indevida.'
                    ]
                },
                {
                    title: 'Perfis e informação pública',
                    paragraphs: [
                        'Se escolheres um perfil público, a informação que tornes pública poderá ser visível a outros visitantes e acessível através de um link partilhável. És responsável pela informação que escolhas publicar.',
                        'Não utilizes nomes, imagens, biografias ou outro conteúdo de perfil que seja ilegal, abusivo, enganador, viole direitos de terceiros ou se faça passar por outra pessoa ou organização.'
                    ]
                },
                {
                    title: 'Mapas, localizações e exatidão',
                    paragraphs: [
                        'O DeepMap procura disponibilizar informação útil, mas posições no mapa, descrições, colecionáveis, rotas e outros dados de jogo podem estar incompletos, desatualizados ou incorretos.',
                        'Continuas responsável pela forma como utilizas a informação da plataforma. O DeepMap não garante que todos os marcadores, coordenadas, rotas ou descrições correspondam a uma determinada versão, atualização, plataforma ou partida do jogo.'
                    ]
                },
                {
                    title: 'Propriedade intelectual',
                    paragraphs: [
                        'O nome DeepMap, a identidade visual, a interface, os gráficos originais, o código da plataforma e o conteúdo original estão protegidos pela legislação aplicável em matéria de propriedade intelectual.',
                        'Nomes de jogos, logótipos, capturas de ecrã, arte, personagens e outros materiais de terceiros continuam a pertencer aos respetivos titulares. A sua presença no DeepMap não transfere a propriedade para o DeepMap.',
                        'Não podes copiar, republicar, vender, fazer engenharia inversa ou explorar comercialmente partes substanciais do DeepMap sem autorização, salvo quando a lei aplicável o permita expressamente.'
                    ]
                },
                {
                    title: 'Disponibilidade e alterações',
                    paragraphs: [
                        'O DeepMap encontra-se em desenvolvimento ativo. As funcionalidades podem ser alteradas, adicionadas, removidas, limitadas ou ficar temporariamente indisponíveis. Poderemos realizar manutenção ou alterações técnicas quando necessário.',
                        'Não garantimos disponibilidade contínua ou ausência total de erros. Sempre que possível, alterações significativas que afetem os utilizadores serão comunicadas através da plataforma ou de outros meios adequados.'
                    ]
                },
                {
                    title: 'Serviços e links externos',
                    paragraphs: [
                        'O DeepMap depende de serviços de terceiros para parte do seu funcionamento e pode disponibilizar links para websites ou serviços externos. Esses terceiros funcionam segundo os seus próprios termos e práticas de privacidade.',
                        'O DeepMap não é responsável pelo conteúdo, disponibilidade ou práticas de serviços externos que não controla.'
                    ]
                },
                {
                    title: 'Responsabilidade',
                    paragraphs: [
                        'Nada nestes Termos exclui ou limita responsabilidade quando tal seja proibido por lei. Sem prejuízo da legislação imperativa, o DeepMap é disponibilizado conforme disponível e não responde por perdas indiretas resultantes da utilização de informação opcional dos mapas, interrupções temporárias ou serviços de terceiros fora do nosso controlo razoável.',
                        'Estes Termos não afetam direitos que tenhas ao abrigo de legislação imperativa de defesa do consumidor ou de proteção de dados.'
                    ]
                },
                {
                    title: 'Funcionalidades futuras da comunidade',
                    paragraphs: [
                        'O DeepMap poderá vir a incluir comentários, contribuições da comunidade, ferramentas de moderação, donativos, funcionalidades premium ou outros serviços interativos. Antes do lançamento dessas funcionalidades poderão ser aplicadas regras adicionais.',
                        'Até essas funcionalidades serem lançadas, estes Termos não atribuem aos utilizadores o direito de publicar marcadores, editar mapas oficiais ou aceder a ferramentas administrativas.'
                    ]
                },
                {
                    title: 'Alterações aos Termos',
                    paragraphs: [
                        'Podemos atualizar estes Termos à medida que o DeepMap evolui. A versão mais recente e a respetiva data de atualização serão publicadas nesta página. Quando exigido, alterações relevantes serão comunicadas antes de produzirem efeitos.'
                    ]
                },
                {
                    title: 'Lei aplicável e contacto',
                    paragraphs: [
                        'Estes Termos são regidos pela lei portuguesa, sem limitar proteções obrigatórias que possam ser aplicáveis ao abrigo da lei do teu país de residência.',
                        'Questões sobre estes Termos podem ser enviadas para contact@deepmap.cc.'
                    ]
                }
            ],
            footer: 'Every explorer belongs here.'
        }
    };

    let t = $derived(content[currentLanguage] ?? content.en);
</script>

<svelte:head>
    <title>{t.title} | DeepMap</title>
    <meta name="description" content={t.description} />
    <meta name="robots" content="index,follow" />
    <link rel="canonical" href="https://deepmap.cc/terms" />
</svelte:head>

<main class="privacy-page">
    <div class="privacy-container">
        <nav class="top-navigation" aria-label="DeepMap">
            <a href="/" class="back-link"><span aria-hidden="true">←</span> {t.back}</a>
            <select class="language-select" value={currentLanguage} onchange={changeLanguage} aria-label={t.language}>
                <option value="en">EN</option>
                <option value="pt">PT</option>
            </select>
        </nav>

        <div class="privacy-card">
            <header class="brandbar">
                <a href="/" aria-label="DeepMap home">
                    <img src="/brand/logo.png" alt="DeepMap" class="brand-logo" />
                </a>
            </header>

            <section class="hero" aria-labelledby="terms-title">
                <span class="eyebrow"><span aria-hidden="true">✦</span> {t.eyebrow}</span>
                <h1 id="terms-title">{t.title}</h1>
                <p class="subtitle">{t.subtitle}</p>
                <p class="updated">{t.updated}</p>
            </section>

            <div class="content-grid">
                <div class="main-column">
                    <div class="introduction">{t.intro}</div>

                    {#each t.sections as section, index}
                        <section class="policy-section" aria-labelledby={`terms-heading-${index}`}>
                            <div class="section-heading">
                                <span class="section-number">{String(index + 1).padStart(2, '0')}</span>
                                <h2 id={`terms-heading-${index}`}>{section.title}</h2>
                            </div>
                            {#each section.paragraphs as paragraph}
                                <p>{paragraph}</p>
                            {/each}
                        </section>
                    {/each}
                </div>

                <aside class="side-column" aria-label={t.contactLabel}>
                    <div class="aside-card">
                        <h2>{currentLanguage === 'pt' ? 'Conta DeepMap' : 'DeepMap Account'}</h2>
                        <p>{t.aside}</p>
                        <p class="reference-link"><a href="/privacy">{t.privacyLabel} →</a></p>
                    </div>

                    <div class="aside-card contact-card">
                        <h2>{t.contactLabel}</h2>
                        <a href="mailto:contact@deepmap.cc" class="contact-email">contact@deepmap.cc</a>
                    </div>
                </aside>
            </div>

            <footer class="page-footer">
                <span>{currentLanguage === 'pt' ? '© 2026 DeepMap. Criado para exploradores.' : '© 2026 DeepMap. Built for explorers.'}</span>
            </footer>
        </div>
    </div>
</main>

<style>
    .privacy-page {
        min-height: 100vh;
        min-height: 100dvh;
        box-sizing: border-box;
        padding: 35px 20px 55px;
        background: #0b0b0e;
        color: #e0e0e0;
        font-family: 'Segoe UI', Arial, sans-serif;
    }
    .privacy-container { max-width: 1060px; margin: 0 auto; }
    .top-navigation { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 20px; }
    .back-link { color: #c8a355; text-decoration: none; font-size: .9rem; }
    .back-link:hover, .back-link:focus-visible { text-decoration: underline; }
    .language-select { background: #22222a; border: 1px solid #454550; border-radius: 6px; padding: 6px 9px; color: #c8a355; font: inherit; font-size: .84rem; cursor: pointer; }
    .privacy-card { border: 1px solid #333340; border-radius: 14px; background: #16161a; padding: 34px; }
    .brandbar { display: flex; justify-content: center; align-items: center; margin-bottom: 24px; }
    .brand-logo { display: block; max-width: 170px; max-height: 70px; width: auto; height: auto; object-fit: contain; }
    .hero { position: relative; overflow: hidden; border: 1px solid #514333; border-radius: 13px; background: linear-gradient(120deg,#262018 0%,#1b1a20 55%,#17171b 100%); padding: 34px; margin-bottom: 20px; }
    .hero::after { position: absolute; content: ''; width: 230px; height: 230px; right: -84px; top: -113px; border: 1px solid rgba(200,163,85,.18); box-shadow: 0 0 0 29px rgba(200,163,85,.025),0 0 0 58px rgba(200,163,85,.018); border-radius: 50%; pointer-events: none; }
    .hero > * { position: relative; z-index: 1; }
    .eyebrow, .aside-eyebrow { font-size: .7rem; font-weight: 700; letter-spacing: .11em; color: #d1ad6c; }
    .hero h1 { margin: 13px 0 8px; color: #f2efeb; font-size: clamp(1.8rem,4vw,2.8rem); line-height: 1.14; letter-spacing: -.03em; }
    .subtitle { color: #e3d4b8; font-size: 1.03rem; margin: 0 0 17px; }
    .updated { color: #aaa39a; font-size: .78rem; margin: 0; }
    .content-grid { display: grid; grid-template-columns: minmax(0, 1fr) 260px; align-items: start; gap: 18px; }
    .main-column, .side-column { display: grid; gap: 15px; min-width: 0; }
    .introduction { border: 1px solid #454039; border-left: 3px solid #c8a355; border-radius: 9px; padding: 18px 20px; background: #222024; color: #ded5c8; line-height: 1.65; font-size: .93rem; }
    .policy-section, .aside-card { border: 1px solid #35343c; border-radius: 11px; background: #1a1a20; padding: 23px; }
    .section-heading { display: flex; align-items: baseline; gap: 12px; margin-bottom: 13px; }
    .section-number { color: #c8a355; font-size: .78rem; font-weight: 700; letter-spacing: .05em; flex: none; }
    .section-heading h2 { color: #f2efeb; margin: 0; line-height: 1.35; font-size: 1.13rem; }
    .policy-section p, .aside-card p { margin: 0 0 13px; color: #bdbbc1; font-size: .89rem; line-height: 1.72; overflow-wrap: anywhere; }
    .policy-section p:last-child, .aside-card p:last-child { margin-bottom: 0; }
    .aside-card h2 { color: #f0e9db; font-size: 1rem; margin: 10px 0; }
    .side-column { position: sticky; top: 20px; }
    .contact-card { background: #201e20; border-color: #514333; }
    .contact-email { display: block; color: #e0c187; overflow-wrap: anywhere; text-decoration: none; margin: 10px 0 0; font-size: .91rem; }
    .contact-email:hover, .reference-link a:hover { text-decoration: underline; }
    .reference-link a { color: #d6b67a; text-decoration: none; }
    .page-footer { margin-top: 23px; padding-top: 19px; border-top: 1px solid #35343c; display: flex; flex-wrap: wrap; justify-content: space-between; gap: 10px; color: #908e99; font-size: .77rem; }
    a:focus-visible, select:focus-visible { outline: 2px solid #d1ad6c; outline-offset: 3px; }
    @media (max-width: 790px) { .content-grid { grid-template-columns: 1fr; } .side-column { position: static; grid-row: 1; grid-template-columns: repeat(2, minmax(0,1fr)); } }
    @media (max-width: 590px) { .privacy-page { padding: 20px 12px 35px; } .privacy-card { padding: 15px; } .brandbar { margin: 4px 0 19px; } .brand-logo { max-width: 150px; } .hero { padding: 23px 19px; } .side-column { grid-template-columns: 1fr; } .policy-section, .aside-card { padding: 18px; } .section-heading { gap: 10px; } .section-heading h2 { font-size: 1.03rem; } .hero::after { width: 180px; height: 180px; right: -90px; top: -90px; } }
</style>
