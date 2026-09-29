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
            title: 'Privacy Policy',
            description: 'How DeepMap handles your information, your public profile and your privacy choices.',
            back: 'Back to DeepMap',
            language: 'Language',
            eyebrow: 'TRUST & TRANSPARENCY',
            subtitle: 'Your journey matters. So does your privacy.',
            updated: 'Last updated: 29 September 2026',
            intro: 'This policy explains how personal data is handled when you visit DeepMap, create an account or use its community profile features.',
            contactLabel: 'CONTACT',
            accountLabel: 'DEEPMAP ACCOUNT',
            asideTitle: 'A note about your profile',
            aside: 'Your email address is not part of your public profile. Your profile visibility setting controls public access; making a profile private is not the same as deleting your account or data.',
            request: 'Request access or deletion',
            sections: [
                {
                    title: 'Who is responsible?',
                    paragraphs: [
                        'DeepMap (deepmap.cc) is operated by Rafael Silva in Portugal, who is responsible for personal data processed through the platform. For privacy questions or requests, email contact@deepmap.cc.'
                    ]
                },
                {
                    title: 'What information do we process?',
                    paragraphs: [
                        'Account and sign-in information: email address, unique account identifier, authentication method and the information necessary to create, secure and manage your account. When you sign in with Google, basic account information made available through the Google sign-in process may include your name, email address and profile picture.',
                        'Profile information: your chosen display name, username, biography, avatar, profile visibility setting and membership information. If you upload a custom avatar, its image file is stored so that it can be displayed.',
                        'Technical information: information necessary to deliver and protect the service, which may include IP address, device/browser information, access records and security or error logs processed by our hosting and authentication providers.',
                        'If you contact us, we process the message and contact information needed to respond. A language preference is stored locally in your browser.'
                    ]
                },
                {
                    title: 'Public profiles and shared links',
                    paragraphs: [
                        'When your profile is public, visitors may see the profile information you choose to display, such as your display name, username, biography, avatar and membership information. A shareable profile link may contain your permanent account identifier.',
                        'You can change profile visibility in your profile settings. A private profile is intended to restrict public viewing, but it does not erase previously shared information, third-party copies or search-engine caches. Your email address and account settings are not shown as public profile information.'
                    ]
                },
                {
                    title: 'Why do we use this data?',
                    paragraphs: [
                        'We use account and profile information to provide your account, sign-in, profile and requested platform features (performance of our service agreement).',
                        'We use necessary technical and security information to maintain availability, prevent misuse and protect the platform and its users (legitimate interests in operating a secure service).',
                        'We may process information to comply with applicable legal duties (legal obligation). Where a future optional feature requires consent, we will request it before that processing starts.'
                    ]
                },
                {
                    title: 'Google sign-in',
                    paragraphs: [
                        'If you choose Google sign-in, Google helps authenticate you. DeepMap uses information supplied through that sign-in to create or access your DeepMap account and, where relevant, populate basic profile information. We do not use Google sign-in data for advertising.',
                        'The Google permissions requested must correspond to the sign-in functionality. If we introduce access to additional Google services or data, this policy and the relevant permission notice will be updated before that use.'
                    ]
                },
                {
                    title: 'Service providers and recipients',
                    paragraphs: [
                        'We use Supabase for authentication, account/profile data and avatar storage; Vercel to host and deliver the website; Google when you choose Google sign-in; Resend for service emails such as password-reset messages; and Cloudflare for domain/DNS and email routing.',
                        'These providers may process only the information relevant to their role, under their applicable contractual and privacy terms. Public profile information is also available to other visitors when your profile is set to public.'
                    ]
                },
                {
                    title: 'Storage and international transfers',
                    paragraphs: [
                        'Account and profile data is retained while your account is needed to provide the service, unless a shorter period applies or a longer period is required for legal, security or dispute-resolution reasons. If you request deletion, we assess and remove eligible data, subject to any lawful retention requirements. Technical records, email records and backups follow applicable operational and provider retention periods.',
                        'Depending on provider configurations and service operations, data may be processed outside the European Economic Area. Where required, such transfers must rely on an applicable legal transfer mechanism. Contact us for information about the safeguards relevant to your data.'
                    ]
                },
                {
                    title: 'Your rights and account deletion',
                    paragraphs: [
                        'Under applicable data-protection law, you may request access, correction or erasure of your personal data, restriction of processing, portability where applicable, and objection to processing based on legitimate interests. Where processing is based on consent, you may withdraw it without affecting earlier lawful processing.',
                        'DeepMap does not yet have an automatic account-deletion button. To request deletion of your account and associated eligible personal data, email contact@deepmap.cc from the address linked to your account. We may need to verify your identity before acting on a request. Making your profile private does not delete the account.',
                        'You also have the right to complain to the Portuguese data-protection authority (CNPD) or another competent supervisory authority.'
                    ]
                },
                {
                    title: 'Security and browser storage',
                    paragraphs: [
                        'We use technical and organisational measures appropriate to the service and rely on service providers for parts of its security. No internet service can guarantee absolute security.',
                        'Browser storage is used for functions such as your selected language and authenticated session. We will review this policy before introducing optional analytics, advertising or other tracking that requires additional information or consent.'
                    ]
                },
                {
                    title: 'Changes to this policy',
                    paragraphs: [
                        'We may update this policy when the service or its data practices change. The updated date will appear on this page. Material changes will be communicated where required. Features not yet available, such as community posts, donations or premium services, will be addressed before they are introduced.'
                    ]
                }
            ],
            footer: 'Every explorer belongs here.'
        },
        pt: {
            title: 'Política de Privacidade',
            description: 'Como o DeepMap trata os teus dados, o teu perfil público e as tuas opções de privacidade.',
            back: 'Voltar ao DeepMap',
            language: 'Idioma',
            eyebrow: 'CONFIANÇA E TRANSPARÊNCIA',
            subtitle: 'A tua jornada importa. A tua privacidade também.',
            updated: 'Última atualização: 29 de setembro de 2026',
            intro: 'Esta política explica como são tratados os dados pessoais quando visitas o DeepMap, crias uma conta ou utilizas as funcionalidades de perfil da comunidade.',
            contactLabel: 'CONTACTO',
            accountLabel: 'CONTA DEEPMAP',
            asideTitle: 'Sobre o teu perfil',
            aside: 'O teu email não faz parte do perfil público. A opção de visibilidade controla o acesso público; tornar o perfil privado não equivale a apagar a conta ou os dados.',
            request: 'Pedir acesso ou eliminação',
            sections: [
                {
                    title: 'Quem é o responsável?',
                    paragraphs: [
                        'O DeepMap (deepmap.cc) é explorado por Rafael Silva, em Portugal, responsável pelo tratamento dos dados pessoais através da plataforma. Para questões ou pedidos relativos à privacidade, escreve para contact@deepmap.cc.'
                    ]
                },
                {
                    title: 'Que informações tratamos?',
                    paragraphs: [
                        'Conta e autenticação: endereço de email, identificador único da conta, método de autenticação e informação necessária para criar, proteger e gerir a conta. Se iniciares sessão com a Google, os dados básicos disponibilizados durante esse processo poderão incluir nome, email e fotografia de perfil.',
                        'Perfil: nome de apresentação, nome de utilizador, biografia, avatar, opção de visibilidade e informação de antiguidade. Se carregares um avatar personalizado, guardamos a imagem para a apresentar.',
                        'Dados técnicos: informação necessária ao funcionamento e segurança, que pode incluir endereço IP, dados do dispositivo/navegador, registos de acesso e registos de segurança ou de erros tratados pelos nossos fornecedores de alojamento e autenticação.',
                        'Se nos contactares, tratamos a mensagem e os dados de contacto necessários para responder. A preferência de idioma é guardada localmente no navegador.'
                    ]
                },
                {
                    title: 'Perfis públicos e links partilhados',
                    paragraphs: [
                        'Se o perfil estiver público, os visitantes poderão ver os dados que escolheste apresentar, como nome, nome de utilizador, biografia, avatar e informação de antiguidade. O link de partilha pode conter o identificador permanente da tua conta.',
                        'Podes mudar a visibilidade nas definições do perfil. Um perfil privado destina-se a restringir a visualização pública, mas não elimina informação já partilhada, cópias de terceiros ou caches de motores de pesquisa. O email e as definições da conta não são apresentados como dados públicos do perfil.'
                    ]
                },
                {
                    title: 'Para que usamos os dados?',
                    paragraphs: [
                        'Utilizamos os dados de conta e perfil para disponibilizar a conta, o início de sessão, o perfil e as funcionalidades pedidas (execução do serviço contratado).',
                        'Utilizamos dados técnicos e de segurança necessários para manter a disponibilidade, prevenir abusos e proteger a plataforma e os utilizadores (interesse legítimo no funcionamento seguro do serviço).',
                        'Podemos tratar informação para cumprir obrigações legais (obrigação legal). Se uma futura funcionalidade opcional exigir consentimento, iremos pedi-lo antes de iniciar esse tratamento.'
                    ]
                },
                {
                    title: 'Início de sessão com a Google',
                    paragraphs: [
                        'Se escolheres iniciar sessão com a Google, esta ajuda a autenticar-te. O DeepMap utiliza a informação recebida nesse processo para criar ou aceder à tua conta e, quando aplicável, preencher os dados básicos do perfil. Não utilizamos os dados recebidos no login Google para publicidade.',
                        'As permissões Google pedidas devem corresponder à autenticação. Antes de passarmos a aceder a outros serviços ou dados Google, atualizaremos esta política e o aviso de permissões aplicável.'
                    ]
                },
                {
                    title: 'Prestadores de serviços e destinatários',
                    paragraphs: [
                        'Utilizamos o Supabase para autenticação, dados de conta/perfil e armazenamento de avatares; a Vercel para alojar e disponibilizar o site; a Google se escolheres esse login; a Resend para emails de serviço, como reposição de palavra-passe; e a Cloudflare para domínio/DNS e encaminhamento de email.',
                        'Estes prestadores poderão tratar apenas informação relevante para a sua função, nos termos contratuais e de privacidade aplicáveis. Os dados de perfil público ficam também acessíveis a outros visitantes quando o perfil está definido como público.'
                    ]
                },
                {
                    title: 'Conservação e transferências internacionais',
                    paragraphs: [
                        'Os dados de conta e perfil são conservados enquanto a conta for necessária à prestação do serviço, salvo prazo menor aplicável ou necessidade de conservação por motivos legais, de segurança ou resolução de litígios. Após um pedido de eliminação, avaliamos e apagamos os dados elegíveis, sem prejuízo de retenções legalmente justificadas. Registos técnicos, emails e cópias de segurança seguem os períodos operacionais e de conservação dos prestadores aplicáveis.',
                        'Consoante a configuração e funcionamento dos prestadores, os dados poderão ser tratados fora do Espaço Económico Europeu. Quando exigido, essas transferências devem assentar num mecanismo legal aplicável. Contacta-nos para informação sobre as garantias relevantes para os teus dados.'
                    ]
                },
                {
                    title: 'Os teus direitos e eliminação de conta',
                    paragraphs: [
                        'Nos termos da legislação aplicável, podes pedir acesso, retificação ou apagamento dos teus dados pessoais, limitação do tratamento, portabilidade quando aplicável e oposição ao tratamento baseado em interesse legítimo. Quando o fundamento for o consentimento, podes retirá-lo sem afetar o tratamento lícito anterior.',
                        'O DeepMap ainda não disponibiliza um botão de eliminação automática de conta. Para pedir a eliminação da conta e dos dados pessoais elegíveis associados, envia um email para contact@deepmap.cc a partir do endereço associado à conta. Poderemos precisar de verificar a tua identidade antes de responder ao pedido. Tornar o perfil privado não elimina a conta.',
                        'Tens igualmente o direito de apresentar reclamação à Comissão Nacional de Proteção de Dados (CNPD) ou a outra autoridade de controlo competente.'
                    ]
                },
                {
                    title: 'Segurança e armazenamento no navegador',
                    paragraphs: [
                        'Adotamos medidas técnicas e organizativas adequadas ao serviço e recorremos a prestadores para parte da sua segurança. Nenhum serviço na Internet pode garantir segurança absoluta.',
                        'O armazenamento no navegador é usado para funções como o idioma selecionado e a sessão autenticada. Antes de introduzir ferramentas opcionais de análise, publicidade ou outros mecanismos de rastreio que exijam informação ou consentimento adicionais, reveremos esta política.'
                    ]
                },
                {
                    title: 'Alterações à política',
                    paragraphs: [
                        'Podemos atualizar esta política quando o serviço ou os tratamentos de dados mudarem. A data de atualização será apresentada nesta página. Alterações relevantes serão comunicadas quando exigido. Funcionalidades ainda indisponíveis, como publicações da comunidade, donativos ou serviços premium, serão abordadas antes de serem lançadas.'
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
    <link rel="canonical" href="https://deepmap.cc/privacy" />
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

            <section class="hero" aria-labelledby="privacy-title">
                <span class="eyebrow"><span aria-hidden="true">✦</span> {t.eyebrow}</span>
                <h1 id="privacy-title">{t.title}</h1>
                <p class="subtitle">{t.subtitle}</p>
                <p class="updated">{t.updated}</p>
            </section>

            <div class="content-grid">
                <div class="main-column">
                    <div class="introduction">{t.intro}</div>
                    {#each t.sections as section, index}
                        <section class="policy-section" aria-labelledby={`policy-heading-${index}`}>
                            <div class="section-heading">
                                <span class="section-number">{String(index + 1).padStart(2, '0')}</span>
                                <h2 id={`policy-heading-${index}`}>{section.title}</h2>
                            </div>
                            {#each section.paragraphs as paragraph}
                                <p>{paragraph}</p>
                            {/each}
                            {#if index === 7}
                                <p class="reference-link"><a href="https://www.cnpd.pt/" target="_blank" rel="noopener noreferrer">CNPD ↗</a></p>
                            {/if}
                        </section>
                    {/each}
                </div>

                <aside class="side-column" aria-label={t.contactLabel}>
                    <div class="aside-card">
                        <span class="aside-eyebrow">{t.accountLabel}</span>
                        <h2>{t.asideTitle}</h2>
                        <p>{t.aside}</p>
                    </div>
                    <div class="aside-card contact-card">
                        <span class="aside-eyebrow">{t.contactLabel}</span>
                        <a href="mailto:contact@deepmap.cc?subject=DeepMap%20-%20Privacy%20request" class="request-link">{t.request} <span aria-hidden="true">↗</span></a>
                    </div>
                </aside>
            </div>

            <footer class="page-footer">
                <span>© DeepMap</span>
                <span>{t.footer}</span>
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
    .contact-card .aside-eyebrow { display: block; margin-bottom: 18px; }
    .reference-link a:hover { text-decoration: underline; }
    .request-link { display: inline-flex; justify-content: space-between; gap: 12px; align-items: center; width: 100%; box-sizing: border-box; border: 1px solid #b8995a; background: #c8a355; color: #16161a; padding: 11px 12px; border-radius: 7px; text-decoration: none; font-size: .83rem; font-weight: 700; }
    .request-link:hover { background: #dec286; }
    .reference-link a { color: #d6b67a; text-decoration: none; }
    .page-footer { margin-top: 23px; padding-top: 19px; border-top: 1px solid #35343c; display: flex; flex-wrap: wrap; justify-content: space-between; gap: 10px; color: #908e99; font-size: .77rem; }
    a:focus-visible, select:focus-visible { outline: 2px solid #d1ad6c; outline-offset: 3px; }
    @media (max-width: 790px) { .content-grid { grid-template-columns: 1fr; } .side-column { position: static; grid-row: 1; grid-template-columns: repeat(2, minmax(0,1fr)); } }
    @media (max-width: 590px) { .privacy-page { padding: 20px 12px 35px; } .privacy-card { padding: 15px; } .brandbar { margin: 4px 0 19px; } .brand-logo { max-width: 150px; } .hero { padding: 23px 19px; } .side-column { grid-template-columns: 1fr; } .policy-section, .aside-card { padding: 18px; } .section-heading { gap: 10px; } .section-heading h2 { font-size: 1.03rem; } .hero::after { width: 180px; height: 180px; right: -90px; top: -90px; } }
</style>
