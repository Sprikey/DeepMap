<script>
    import { onMount } from 'svelte';
    import { getSiteLanguage, setSiteLanguage, subscribeSiteLanguage } from '$lib/i18n/site.js';

    let currentLanguage = $state('en');

    onMount(() => {
        currentLanguage = setSiteLanguage(getSiteLanguage());
        const unsubscribeLanguage = subscribeSiteLanguage((language) => { currentLanguage = language; });
        return unsubscribeLanguage;
    });

    const content = {
        "en": {
            "title": "Privacy Policy",
            "description": "How DeepMap handles account, profile, contribution, moderation and platform-usage data.",
            "language": "Language",
            "eyebrow": "TRUST & TRANSPARENCY",
            "subtitle": "Your journey matters. So does your privacy.",
            "updated": "Last updated: 18 October 2026",
            "intro": "This policy describes DeepMap’s current processing for site access, authentication, profiles, map contributions, moderation, notifications and usage statistics. It explains what is public and what you can request about your data.",
            "contactLabel": "CONTACT",
            "accountLabel": "DEEPMAP ACCOUNT",
            "asideTitle": "A note about your profile",
            "aside": "A private profile restricts its details but may still show a username and avatar. Your account email is not public. Approved contributions and their attribution do not become private through this choice.",
            "request": "Request access or deletion",
            "sections": [
                {
                    "title": "Controller and contact",
                    "paragraphs": [
                        "DeepMap (deepmap.cc) is operated by Rafael Silva in Portugal, under the DeepMap name, as controller of personal data processed through the platform. For privacy questions or to exercise your rights, contact contact@deepmap.cc."
                    ]
                },
                {
                    "title": "Account and authentication",
                    "paragraphs": [
                        "We process your email, stable account identifier (UUID), authentication method, creation/access dates and the session/security data needed for registration, email confirmation, sign-in and password recovery or changes. Email/password authentication is managed by Supabase Auth; we do not display your password on your profile or make it available to other users.",
                        "If you choose Google OAuth, we receive the basic data authorised in that process, such as name, email, picture and provider identifiers. We do not request access to your Google inbox or files. Google also processes the data needed for its own authentication service."
                    ]
                },
                {
                    "title": "Profile and public identity",
                    "paragraphs": [
                        "Profiles include a username, display name, biography, avatar, visibility and membership information. An initial username may be generated. We also retain information needed to manage username changes and temporary reservations. An avatar can be a platform preset, a Google picture or a custom image stored in Supabase Storage.",
                        "New profiles are public by default; you can change visibility in settings. Public profiles display the name, username, biography, avatar and membership information. Making a profile private restricts its details but does not hide all identity: the username, active avatar and private-profile status remain accessible. A permanent profile link and a custom-avatar address may contain the UUID. Custom avatars are served through public URLs; profile privacy does not make the file itself private.",
                        "The platform does not publicly display your authentication email. Do not put your email, sensitive information or other people’s data in public fields. Content you publish yourself may disclose personal information."
                    ]
                },
                {
                    "title": "Contributions, moderation and notifications",
                    "paragraphs": [
                        "We store proposals for new markers and corrections, the associated game and marker, game coordinates, text, image/video references, notes, status and dates. Submitted coordinates refer to the video-game map, not your physical location. Images can be flagged through the correction workflow.",
                        "We store authorship by UUID, submission versions, moderation decisions, notes and the identity of participants, editing/approval records, permission grants/removals and suspensions, including reasons and any expiry. We store account notifications and their read status.",
                        "Pending submissions and internal history are accessible to their author or authorised staff according to permissions. Approved content may become public and show its creator’s username even if their profile is private. An incorporated correction and minimal public identity do not become private when profile visibility changes."
                    ]
                },
                {
                    "title": "Purposes and legal bases",
                    "paragraphs": [
                        "Performance of the requested service: creating/authenticating accounts, managing profiles and preferences, receiving/processing contributions and presenting related notifications. Authentication data is necessary for account features; without it you can still browse the available public areas.",
                        "Legitimate interests: protecting accounts and the platform, preventing abuse, reviewing content, maintaining coherent maps and necessary authorship, decision and security records, answering enquiries and understanding service use. We balance these interests against your rights, particularly for children. Truly anonymous statistics are not personal data; any personal data needed to produce them requires a legal basis and compliance with applicable tracking rules.",
                        "Legal obligations: responding to requests and retaining or disclosing data where an applicable law or lawful order requires it. Consent is used only where legally needed for a specific processing activity, not as a blanket basis for accounts. Accepting the Terms or reading this policy does not amount to consent to every processing activity."
                    ]
                },
                {
                    "title": "Providers and other recipients",
                    "paragraphs": [
                        "Supabase provides authentication, the database and storage for custom avatars. Vercel hosts/delivers the site and provides Web Analytics. Google is involved when you choose its sign-in or when its resources, such as pictures or videos, are loaded. Confirmation and recovery emails are triggered through Supabase Auth and delivered by the email service configured for that purpose.",
                        "Providers and their subprocessors receive data needed for their role under the applicable terms. Authorised staff may access data needed for support, administration and moderation. We may disclose data to authorities when legally required. Public-content recipients include platform visitors. Cloudflare R2 is not used for storage or uploads at this stage."
                    ]
                },
                {
                    "title": "Web Analytics and external resources",
                    "paragraphs": [
                        "DeepMap integrates Vercel Web Analytics for usage statistics, such as pages visited, referral sources, approximate country and browser/device characteristics. According to Vercel’s documentation, its default setup provides aggregated statistics, does not use third-party cookies and does not keep a permanent visitor identifier; its technical visit identification is short-lived.",
                        "We do not configure custom events containing email or UUID. However, page addresses are processed for measurement and may include, for example, a public username. The absence of third-party cookies does not mean no data is processed or guarantee absolute anonymity for every technical request.",
                        "Google avatars, external images and YouTube/Vimeo videos may be requested directly by your browser when displaying content, including when opening a map popup. Those third parties may receive your IP, browser and request information and apply their own cookies or technologies under their rules. Embedded videos currently have no dedicated consent control in DeepMap. Opening external content does not itself constitute consent to unnecessary tracking."
                    ]
                },
                {
                    "title": "Cookies and browser storage",
                    "paragraphs": [
                        "We use cookies needed for authentication, session continuity and secure completion of sign-in/recovery flows. They can persist between visits and be renewed; the current library’s default cookie lifetime is up to 400 days, subject to browser rules. This is not the token validity period or a promise of account access for that duration. Signing out removes the applicable session data.",
                        "Your language preference is stored in browser localStorage without an application-defined automatic expiry, until you change it or clear local data. We do not configure sessionStorage for preferences. You can manage cookies and storage in your browser; blocking necessary storage may prevent authentication. The third-party technologies described above also follow their providers’ terms."
                    ]
                },
                {
                    "title": "Retention",
                    "paragraphs": [
                        "Account/profile data: while the account exists and the data is needed for the service, subject to erasure requests and retention obligations. Deletion is currently handled on request, not by an automatic button or a scheduled inactivity period.",
                        "Published contributions: while useful to map content and lawfully retained; they may outlast the account. Submissions, versions, audit and moderation: while needed for content integrity, abuse prevention, review of decisions and legal claims, with personal data limited to what is necessary. These records have no single automatic expiry period.",
                        "Notifications: while needed for account information and service management; limiting the displayed items does not delete older ones. Technical data and backups: according to providers’ operational cycles and the time needed to investigate incidents or meet legal duties. Enquiries: while resolving the request and, where necessary, to evidence the response or defend rights. We do not promise technical deletion deadlines the system cannot guarantee; you can ask about retention relevant to your case."
                    ]
                },
                {
                    "title": "Account and contribution deletion",
                    "paragraphs": [
                        "To request deletion, write to contact@deepmap.cc, preferably from the account email. If you no longer have access, explain the situation so we can verify identity proportionately. Do not send your password. Making a profile private or signing out does not delete the account.",
                        "Deleting the authentication account and profile does not automatically delete published markers, submissions, versions or audit records. Public attribution may stop resolving to a profile, but the historical UUID and other elements may remain in internal records where retention is justified. Retaining a historical identifier does not amount to complete anonymisation.",
                        "We separately assess personal data within content, avatars, notifications and related records, removing or unlinking eligible data and explaining any legal exceptions. Preserving contributions is not a blanket reason to refuse erasure. External copies already made by third parties may be outside our control."
                    ]
                },
                {
                    "title": "Rights and complaints",
                    "paragraphs": [
                        "You can request access, rectification, erasure, restriction, objection to processing based on legitimate interests and portability where applicable. Where processing depends on consent, you can withdraw it without affecting earlier lawful processing. Rights have legal conditions and exceptions; we will explain the decision in your case.",
                        "Send requests to contact@deepmap.cc. We normally respond within one month and will tell you within that period if a justified legal extension is needed. Additional identification is requested only where necessary and proportionate. You can complain to Portugal’s Comissão Nacional de Proteção de Dados (CNPD), at www.cnpd.pt, or the competent authority in your country."
                    ]
                },
                {
                    "title": "International transfers and security",
                    "paragraphs": [
                        "International providers may process data outside the European Economic Area, including for support and subprocessing, even where primary hosting is in a European region. We do not claim all data stays in the EU. Transfers subject to the GDPR must have an applicable safeguard, such as an adequacy decision or European Commission standard contractual clauses, with additional measures where necessary. Contact us for information about relevant safeguards.",
                        "We use appropriate technical and organisational measures, including access controls and separation between public information and authorised operations. Security also depends on providers and careful handling of credentials; absolute security cannot be guaranteed."
                    ]
                },
                {
                    "title": "Children",
                    "paragraphs": [
                        "DeepMap is not specifically directed at children and does not collect dates of birth or automatically verify age. If you are a minor, involve your legal representative where the law requires permission to use the service.",
                        "Where processing relies on consent for information-society services offered directly to children, the applicable legal consent age applies: in Portugal, 13 under Article 16 of Law 58/2019; below that threshold, the legal representative must be involved. This specific rule does not replace contractual-capacity rules or requirements in the country of residence. Contact us if you believe a child’s data is being processed improperly."
                    ]
                },
                {
                    "title": "Changes to this policy",
                    "paragraphs": [
                        "The date on this page identifies the current version. We will communicate material changes in a way appropriate to their importance, through the platform or direct contact where required, before starting new processing that requires additional information or consent. New upload/storage services will receive a separate review before being made available."
                    ]
                }
            ]
        },
        "pt": {
            "title": "Política de Privacidade",
            "description": "Como o DeepMap trata dados de conta, perfis, contribuições, moderação e utilização da plataforma.",
            "language": "Idioma",
            "eyebrow": "CONFIANÇA E TRANSPARÊNCIA",
            "subtitle": "A tua jornada importa. A tua privacidade também.",
            "updated": "Última atualização: 18 de outubro de 2026",
            "intro": "Esta política descreve os tratamentos atuais do DeepMap: acesso ao site, autenticação, perfis, contribuições para mapas, moderação, notificações e estatísticas de utilização. Explica o que é público e o que podes pedir relativamente aos teus dados.",
            "contactLabel": "CONTACTO",
            "accountLabel": "CONTA DEEPMAP",
            "asideTitle": "Sobre o teu perfil",
            "aside": "Um perfil privado restringe os detalhes, mas pode continuar a mostrar username e avatar. O email da conta não é público. Contribuições aprovadas e a respetiva autoria não ficam privadas por essa escolha.",
            "request": "Pedir acesso ou eliminação",
            "sections": [
                {
                    "title": "Responsável e contacto",
                    "paragraphs": [
                        "O DeepMap (deepmap.cc) é operado por Rafael Silva, em Portugal, sob o nome DeepMap, responsável pelo tratamento dos dados pessoais da plataforma. Para questões de privacidade ou exercício de direitos, contacta contact@deepmap.cc."
                    ]
                },
                {
                    "title": "Conta e autenticação",
                    "paragraphs": [
                        "Tratamos o email, o identificador estável da conta (UUID), o método de autenticação, datas de criação e acesso e os dados de sessão e segurança necessários ao registo, confirmação de email, início de sessão e recuperação ou alteração da palavra-passe. A autenticação por email/palavra-passe é gerida pelo Supabase Auth; não mostramos a palavra-passe no perfil nem a disponibilizamos a outros utilizadores.",
                        "Se escolheres Google OAuth, recebemos os dados básicos autorizados nesse processo, como nome, email, fotografia e identificadores do fornecedor. Não pedimos acesso à tua caixa de correio ou aos teus ficheiros Google. A Google trata também os dados necessários ao seu próprio serviço de autenticação."
                    ]
                },
                {
                    "title": "Perfil e identidade pública",
                    "paragraphs": [
                        "O perfil inclui username, nome de apresentação, biografia, avatar, visibilidade e informação de antiguidade. Pode ser gerado um username inicial. Guardamos também informação necessária à gestão de alterações e reserva temporária de usernames. O avatar pode ser uma opção da plataforma, uma fotografia Google ou uma imagem personalizada guardada no Supabase Storage.",
                        "Os novos perfis são públicos por defeito; podes mudar a visibilidade nas definições. Um perfil público apresenta nome, username, biografia, avatar e antiguidade. Torná-lo privado restringe os detalhes, mas não oculta toda a identidade: o username, o avatar ativo e a indicação de perfil privado continuam acessíveis. Um link permanente e o endereço de um avatar personalizado podem conter o UUID. Avatares personalizados são servidos por URL público; a privacidade do perfil não transforma o ficheiro num recurso privado.",
                        "O email de autenticação não é apresentado publicamente pela plataforma. Não coloques o teu email, dados sensíveis ou dados de terceiros em campos públicos. Conteúdo que tu próprio publiques pode revelar informação pessoal."
                    ]
                },
                {
                    "title": "Contribuições, moderação e notificações",
                    "paragraphs": [
                        "Guardamos propostas de novos marcadores e correções, o jogo e marcador associados, coordenadas do jogo, textos, referências de imagens/vídeos, notas, estado e datas. As coordenadas submetidas referem-se ao mapa do videojogo, não à tua localização física. Podem ser sinalizadas imagens através do fluxo de correção.",
                        "Guardamos a autoria por UUID, versões das submissões, decisões, notas e identidade dos intervenientes na moderação, registos de edição/aprovação, atribuição ou remoção de permissões e suspensões, incluindo motivo e eventual termo. Guardamos notificações da conta e o respetivo estado de leitura.",
                        "Submissões pendentes e o histórico interno são acessíveis ao autor ou à equipa autorizada conforme as permissões. Conteúdo aprovado pode tornar-se público e mostrar o username do criador, mesmo com perfil privado. Uma correção incorporada no mapa e a identidade pública mínima não se tornam privadas por alterares a visibilidade do perfil."
                    ]
                },
                {
                    "title": "Finalidades e fundamentos jurídicos",
                    "paragraphs": [
                        "Execução do serviço pedido: criar e autenticar a conta, gerir perfil e preferências, receber e processar contribuições e apresentar notificações relacionadas. Os dados de autenticação são necessários para funções com conta; sem eles podes continuar a consultar as áreas públicas disponíveis.",
                        "Interesses legítimos: proteger contas e plataforma, prevenir abuso, rever conteúdo, manter a coerência dos mapas e um histórico necessário de autoria, decisões e segurança, responder a contactos e compreender a utilização do serviço. Ponderamos estes interesses com os teus direitos, especialmente no caso de menores. As estatísticas efetivamente anónimas não são dados pessoais; os dados pessoais eventualmente necessários à sua produção exigem fundamento e as regras de rastreio aplicáveis.",
                        "Obrigação legal: responder a pedidos e conservar ou comunicar dados quando uma norma aplicável ou uma ordem legítima o exigir. O consentimento é usado apenas quando legalmente necessário para um tratamento específico, não como fundamento genérico para a conta. Aceitar os Termos ou conhecer esta política não equivale a consentir em todo o tratamento."
                    ]
                },
                {
                    "title": "Prestadores e outros destinatários",
                    "paragraphs": [
                        "O Supabase presta autenticação, base de dados e armazenamento dos avatares personalizados. A Vercel aloja/disponibiliza o site e presta Web Analytics. A Google intervém quando escolhes o seu login e quando são carregados recursos seus, como fotografias ou vídeos. Os emails de confirmação e recuperação são acionados pelo Supabase Auth e entregues pelo serviço de email configurado para esse efeito.",
                        "Os prestadores e os seus subcontratantes recebem os dados necessários à função que desempenham, nos termos aplicáveis. A equipa autorizada pode aceder aos dados necessários ao suporte, administração e moderação. Podemos comunicar dados a autoridades quando legalmente exigido. Os destinatários de conteúdo público incluem visitantes da plataforma. Não usamos Cloudflare R2 para armazenamento ou uploads nesta fase."
                    ]
                },
                {
                    "title": "Web Analytics e recursos externos",
                    "paragraphs": [
                        "O DeepMap integra Vercel Web Analytics para estatísticas de utilização, como páginas visitadas, origem das visitas, país aproximado e características de navegador/dispositivo. Segundo a documentação da Vercel, a configuração padrão fornece estatísticas agregadas, não usa cookies de terceiros e não mantém um identificador permanente de visitante; a identificação técnica de visita é de curta duração.",
                        "Não configuramos eventos personalizados com email ou UUID. Contudo, os endereços de páginas são tratados na medição e podem conter, por exemplo, um username público. A ausência de cookies de terceiros não significa ausência de qualquer tratamento de dados nem permite garantir anonimato absoluto de todos os pedidos técnicos.",
                        "Avatares Google, imagens externas e vídeos YouTube/Vimeo podem ser pedidos diretamente pelo teu navegador ao apresentar o conteúdo, incluindo ao abrir um popup do mapa. Esses terceiros podem receber IP, dados do navegador e informação do pedido, e aplicar cookies ou tecnologias próprias segundo as suas regras. Atualmente os vídeos incorporados não têm um controlo de consentimento específico no DeepMap. Abrir conteúdo externo não constitui, por si só, consentimento para rastreio não necessário."
                    ]
                },
                {
                    "title": "Cookies e armazenamento no navegador",
                    "paragraphs": [
                        "Usamos cookies necessários à autenticação, continuidade da sessão e conclusão segura dos fluxos de login/recuperação. Podem persistir entre visitas e ser renovados; na biblioteca atualmente utilizada, o prazo padrão do cookie é até 400 dias, sujeito às regras do navegador. Esse prazo não é a validade do token nem uma garantia de acesso à conta durante esse período. Ao terminar sessão, o serviço remove os dados de sessão aplicáveis.",
                        "A preferência de idioma é guardada no localStorage do navegador, sem prazo automático definido pela aplicação, até a alterares ou limpares os dados locais. Não configuramos sessionStorage para preferências. Podes gerir cookies e armazenamento nas definições do navegador; bloquear os necessários pode impedir a autenticação. As tecnologias de terceiros referidas acima seguem também as respetivas condições."
                    ]
                },
                {
                    "title": "Conservação",
                    "paragraphs": [
                        "Conta e perfil: enquanto a conta existir e forem necessários ao serviço, com avaliação de pedidos de apagamento e de obrigações de conservação. A eliminação é atualmente tratada por pedido, não por um botão automático ou um prazo de inatividade programado.",
                        "Contribuições publicadas: enquanto forem úteis ao conteúdo dos mapas e a conservação for legítima; podem subsistir à conta. Submissões, versões, auditoria e moderação: enquanto necessários à integridade do conteúdo, prevenção de abuso, avaliação de decisões e defesa de direitos, com limitação dos dados pessoais ao necessário. Não existe um prazo único de expiração automática destes registos.",
                        "Notificações: enquanto necessárias à informação da conta e gestão do serviço; o limite de itens apresentados não apaga os anteriores. Dados técnicos e cópias de segurança: pelos ciclos operacionais dos prestadores e pelo tempo necessário a investigar incidentes ou cumprir deveres legais. Contactos: durante a resolução do pedido e, se necessário, para comprovar a resposta ou defender direitos. Não prometemos prazos técnicos de eliminação que o sistema não assegura; podes pedir informação sobre a conservação aplicável ao teu caso."
                    ]
                },
                {
                    "title": "Eliminação da conta e das contribuições",
                    "paragraphs": [
                        "Para pedir eliminação, escreve para contact@deepmap.cc, preferencialmente a partir do email da conta. Se já não tiveres acesso, explica a situação para verificarmos a identidade por um meio proporcionado. Não envies a palavra-passe. Tornar o perfil privado ou sair da sessão não elimina a conta.",
                        "Eliminar a conta de autenticação e o perfil não apaga automaticamente marcadores publicados, submissões, versões ou auditoria. A atribuição pública pode deixar de resolver para um perfil, mas o UUID histórico e outros elementos podem continuar em registos internos quando a conservação for justificada. A conservação de um identificador histórico não equivale a anonimização completa.",
                        "Analisamos separadamente os dados presentes no próprio conteúdo, avatares, notificações e registos relacionados, retirando ou desassociando dados elegíveis e explicando eventuais exceções legais. Não usamos a preservação de contribuições para recusar indiscriminadamente pedidos de apagamento. Cópias externas já feitas por terceiros podem não estar sob o nosso controlo."
                    ]
                },
                {
                    "title": "Direitos e reclamações",
                    "paragraphs": [
                        "Podes pedir acesso, retificação, apagamento, limitação, oposição ao tratamento baseado em interesse legítimo e portabilidade quando aplicável. Se um tratamento depender de consentimento, podes retirá-lo sem afetar o tratamento lícito anterior. Os direitos têm condições e exceções legais; explicaremos a decisão no teu caso.",
                        "Envia o pedido para contact@deepmap.cc. Respondemos, em regra, no prazo de um mês, informando dentro desse prazo se houver uma prorrogação legal justificada. Só pediremos identificação adicional quando necessária e proporcional. Podes reclamar à Comissão Nacional de Proteção de Dados (CNPD), em www.cnpd.pt, ou à autoridade de controlo competente no teu país."
                    ]
                },
                {
                    "title": "Transferências internacionais e segurança",
                    "paragraphs": [
                        "O uso de prestadores internacionais pode envolver tratamento fora do Espaço Económico Europeu, incluindo operações de suporte e subcontratação, mesmo quando o alojamento principal está numa região europeia. Não afirmamos que todos os dados ficam na UE. As transferências sujeitas ao RGPD devem ter uma garantia aplicável, como decisão de adequação ou cláusulas contratuais-tipo da Comissão Europeia, com as medidas adicionais necessárias. Podes contactar-nos para obter informação sobre as salvaguardas relevantes.",
                        "Usamos medidas técnicas e organizativas adequadas, incluindo controlo de acesso e separação entre informação pública e operações autorizadas. A segurança depende também dos prestadores e do cuidado com as credenciais; não existe garantia de segurança absoluta."
                    ]
                },
                {
                    "title": "Menores",
                    "paragraphs": [
                        "O DeepMap não é dirigido especificamente a crianças e não recolhe a data de nascimento nem verifica automaticamente a idade. Se fores menor, deves recorrer ao teu representante legal quando a lei exigir autorização para usar o serviço.",
                        "Quando o tratamento assentar em consentimento na oferta direta de serviços da sociedade da informação, aplica-se a idade legal de consentimento: em Portugal, 13 anos nos termos do artigo 16.º da Lei n.º 58/2019; abaixo desse limiar, é necessária intervenção do representante legal. Esta regra específica não substitui as regras de capacidade para aceitar contratos nem os requisitos do país de residência. Contacta-nos se considerares que dados de uma criança estão a ser tratados indevidamente."
                    ]
                },
                {
                    "title": "Alterações a esta política",
                    "paragraphs": [
                        "A data desta página identifica a versão atual. Comunicaremos alterações materiais de forma adequada à sua relevância, pela plataforma ou por contacto quando exigido, antes de iniciar um novo tratamento que necessite de informação ou consentimento adicionais. Novos serviços de uploads/storage terão uma revisão própria antes da sua disponibilização."
                    ]
                }
            ]
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
        <div class="privacy-card">

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
    .privacy-card { border: 1px solid #333340; border-radius: 14px; background: #16161a; padding: 34px; }
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
    a:focus-visible, select:focus-visible { outline: 2px solid #d1ad6c; outline-offset: 3px; }
    @media (max-width: 790px) { .content-grid { grid-template-columns: 1fr; } .side-column { position: static; grid-row: 1; grid-template-columns: repeat(2, minmax(0,1fr)); } }
    @media (max-width: 590px) { .privacy-page { padding: 20px 12px 35px; } .privacy-card { padding: 15px; } .hero { padding: 23px 19px; } .side-column { grid-template-columns: 1fr; } .policy-section, .aside-card { padding: 18px; } .section-heading { gap: 10px; } .section-heading h2 { font-size: 1.03rem; } .hero::after { width: 180px; height: 180px; right: -90px; top: -90px; } }
</style>
