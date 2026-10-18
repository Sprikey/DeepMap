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
            "title": "Terms of Use",
            "description": "Rules for using DeepMap maps, accounts, profiles and community contributions.",
            "language": "Language",
            "eyebrow": "FAIR PLAY",
            "subtitle": "Explore freely. Respect the journey.",
            "updated": "Last updated: 18 October 2026",
            "intro": "These Terms govern access to DeepMap and its available features. Read them before creating an account or submitting content. The Privacy Policy separately explains data processing; it is not a request for blanket consent.",
            "contactLabel": "Contact",
            "asideTitle": "DeepMap account",
            "aside": "Protect your credentials and report suspected unauthorised access. Use your account responsibly and submit only content you have the right to share.",
            "privacyLabel": "Privacy Policy",
            "sections": [
                {
                    "title": "The DeepMap service",
                    "paragraphs": [
                        "DeepMap (deepmap.cc), operated by Rafael Silva in Portugal, is an independent platform for video-game maps, exploration and content, with accounts, profiles and community contributions. Available features may differ between games. Administration and moderation tools are reserved for authorised people.",
                        "DeepMap is not affiliated with, sponsored by or endorsed by the publishers, developers or trademark owners of the games shown unless expressly stated."
                    ]
                },
                {
                    "title": "Accounts, capacity and security",
                    "paragraphs": [
                        "Some features require an email/password or Google account sign-in. Provide necessary information accurately, protect your email and credentials and report suspected unauthorised access to contact@deepmap.cc. Do not share credentials, impersonate others or bypass access restrictions.",
                        "You must have legal capacity to accept these Terms. If you are a minor, obtain your legal representative’s permission or involvement as required by applicable law. The Privacy Policy explains children’s data-consent rules; these do not establish a universal age for entering contracts. The platform does not automatically verify age."
                    ]
                },
                {
                    "title": "Usernames and profiles",
                    "paragraphs": [
                        "A username may initially be generated and is subject to the format, availability and change rules shown in your account. Do not use unlawful, abusive, misleading or infringing names, avatars or biographies.",
                        "Profile visibility controls its details, but the username and active avatar can remain public for a private profile. Approved contributions and authorship attribution do not become private through that choice. The authentication email is not a public profile field."
                    ]
                },
                {
                    "title": "Acceptable use",
                    "paragraphs": [
                        "Use the service lawfully and respectfully. Do not publish illegal content, threats, harassment, discrimination, other people’s personal data without a lawful basis, spam, malware or material infringing copyright or image rights.",
                        "Do not manipulate submissions or identities to deceive moderation, exploit vulnerabilities or evade suspensions. Do not automate access or extract data in a way that harms security, availability or third-party rights. This rule does not override uses permitted by law."
                    ]
                },
                {
                    "title": "Submissions and responsibility for content",
                    "paragraphs": [
                        "Available features let you propose new markers and corrections, including text, in-game coordinates and image/video references. You can flag an image through the correction workflow. The available options determine what you can submit, edit or cancel; contributing does not give you direct access to edit the published map.",
                        "You are responsible for having the necessary rights, permissions and lawful basis for what you submit, including avatars and external resources you reference. Do not submit third-party material without permission or another legally permitted use, or unnecessary personal information. A public URL does not mean its content can be freely reused."
                    ]
                },
                {
                    "title": "Contribution rights and licence",
                    "paragraphs": [
                        "You retain the rights you actually hold in your content. By submitting it, you grant DeepMap a non-exclusive, royalty-free, worldwide licence to host, reproduce, display and communicate it on the platform, integrate it into maps, format, translate and technically adapt, correct and moderate it as needed to provide the service. This includes providers acting on our behalf only for those purposes, not a general permission for exploitation unrelated to DeepMap.",
                        "The licence lasts while the content is lawfully retained in the service. Account deletion does not automatically withdraw content already integrated into maps. The licence does not replace third-party rights, grant rights you do not hold or limit erasure rights or other legal protections. Authorship may be shown as described in the Privacy Policy."
                    ]
                },
                {
                    "title": "Moderation and reporting problems",
                    "paragraphs": [
                        "Authorised staff may review, approve, reject or correct submissions and remove or restrict content for legality, security, third-party rights, quality or compliance with these Terms. Versions and decisions may be retained. Moderator submissions may be approved automatically; we do not promise prior human review of all content.",
                        "Publication or continued availability of a submission is not guaranteed. To report illegal content, rights infringement or another problem, email contact@deepmap.cc with the URL or marker, reasons and enough information for assessment. You can also request reconsideration through the same contact."
                    ]
                },
                {
                    "title": "Suspensions and restrictions",
                    "paragraphs": [
                        "We may restrict interactions, suspend accounts or withdraw permissions where necessary and proportionate to address violations, abuse, security risks or legal duties. An interaction suspension does not necessarily prevent access to public pages.",
                        "Where applicable, we communicate the reason and duration through account features or another appropriate channel, unless legal or security restrictions prevent it. You can contact us to ask about or contest a measure. These rules do not remove applicable legal safeguards."
                    ]
                },
                {
                    "title": "Account deletion and retention",
                    "paragraphs": [
                        "You can request deletion at contact@deepmap.cc. There is currently no automatic deletion button; proportionate identity verification may be needed. Signing out or making a profile private does not delete the account.",
                        "The account/profile are distinct from markers, incorporated contributions, versions and moderation/audit history. These may be lawfully retained without a public link to an existing profile; some historical identifiers may remain internally. We separately assess personal data, avatars, other related records and erasure requests. We do not promise automatic complete anonymisation or deletion of all external copies."
                    ]
                },
                {
                    "title": "Maps and intellectual property",
                    "paragraphs": [
                        "Maps and content may be incomplete, inaccurate or outdated and vary by game version, update, platform or playthrough. We do not guarantee completeness or fitness for a particular purpose, without affecting legally required guarantees.",
                        "DeepMap’s branding, interface, code, graphics and original content are protected as provided by law and applicable licences. Game names, trademarks, images, characters and other game materials belong to their respective owners. Contributions remain subject to their authors’ rights. Displaying such material does not transfer ownership to DeepMap.",
                        "Do not reuse protected parts of the service without permission or a lawful basis. Statutory exceptions and rights granted by licences for third-party components or materials remain available."
                    ]
                },
                {
                    "title": "External services",
                    "paragraphs": [
                        "Authentication, hosting and other components rely on providers. External links, images and videos may cause your browser to contact third parties under their own rules, as explained in the Privacy Policy.",
                        "We do not control external sites’ content or availability and displaying them is not an endorsement. This does not remove DeepMap’s responsibility for its own conduct or its legal obligations concerning providers it uses."
                    ]
                },
                {
                    "title": "Availability, changes and liability",
                    "paragraphs": [
                        "The service is under development and may undergo maintenance, interruptions or feature changes for technical, security, legal or product-development reasons. Uninterrupted or error-free availability is not guaranteed. Material changes or discontinuations will be communicated with reasonable notice where possible and legally required, respecting applicable rights.",
                        "DeepMap’s liability is determined by applicable law; these Terms do not impose a blanket exclusion. We do not exclude liability for intentional misconduct, gross negligence, personal injury or other cases where exclusion is prohibited. We do not limit mandatory consumer or data-protection rights or legally available remedies."
                    ]
                },
                {
                    "title": "Version and changes to these Terms",
                    "paragraphs": [
                        "The current version and date are published here. Material changes will be communicated appropriately, with the notice and acceptance required by law and without improper retroactive effect. If you do not wish to continue using affected features, you can stop using them and request account deletion while retaining your legal rights."
                    ]
                },
                {
                    "title": "Applicable law, courts and contact",
                    "paragraphs": [
                        "Portuguese law applies without depriving consumers of mandatory protections under the law applicable to them, including their habitual-residence country where European rules provide for it. Jurisdiction follows applicable law; we do not impose an exclusive forum that removes a consumer’s right to use the competent courts where they reside.",
                        "For questions about these Terms, your account or content, contact contact@deepmap.cc. The Privacy Policy explains personal-data processing and is separate from acceptance of these Terms."
                    ]
                }
            ]
        },
        "pt": {
            "title": "Termos de Utilização",
            "description": "Regras para utilizar mapas, contas, perfis e contribuições da comunidade DeepMap.",
            "language": "Idioma",
            "eyebrow": "JOGO LIMPO",
            "subtitle": "Explora livremente. Respeita a jornada.",
            "updated": "Última atualização: 18 de outubro de 2026",
            "intro": "Estes Termos regulam o acesso ao DeepMap e às funcionalidades disponíveis. Consulta-os antes de criar conta ou enviar conteúdo. A Política de Privacidade explica separadamente o tratamento de dados; não é um pedido de consentimento genérico.",
            "contactLabel": "Contacto",
            "asideTitle": "Conta DeepMap",
            "aside": "Protege as credenciais e comunica acessos suspeitos. Utiliza a conta de forma responsável e envia apenas conteúdo que tenhas o direito de partilhar.",
            "privacyLabel": "Política de Privacidade",
            "sections": [
                {
                    "title": "O serviço DeepMap",
                    "paragraphs": [
                        "O DeepMap (deepmap.cc), operado por Rafael Silva em Portugal, é uma plataforma independente de mapas, exploração e conteúdo de videojogos, com contas, perfis e contribuições da comunidade. Os jogos podem disponibilizar funcionalidades diferentes. As ferramentas administrativas e de moderação são reservadas a pessoas autorizadas.",
                        "O DeepMap não é afiliado, patrocinado ou aprovado pelos editores, produtores ou titulares das marcas dos jogos apresentados, salvo indicação expressa."
                    ]
                },
                {
                    "title": "Conta, capacidade e segurança",
                    "paragraphs": [
                        "Algumas funcionalidades exigem conta por email/palavra-passe ou Google. Fornece os dados necessários de forma correta, protege o email e as credenciais e comunica acessos suspeitos a contact@deepmap.cc. Não partilhes credenciais, não te faças passar por outra pessoa e não contornes limitações de acesso.",
                        "Deves ter capacidade legal para aceitar estes Termos. Se fores menor, obtém a autorização ou intervenção do representante legal na medida exigida pela lei aplicável. As regras sobre consentimento para dados de crianças constam da Política de Privacidade e não equivalem a uma idade universal para celebrar contratos. Não existe verificação automática de idade na plataforma."
                    ]
                },
                {
                    "title": "Username e perfil",
                    "paragraphs": [
                        "O username pode ser inicialmente gerado e está sujeito às regras de formato, disponibilidade e alteração apresentadas na conta. Não uses nomes, avatares ou biografias ilegais, abusivos, enganosos ou que violem direitos de terceiros.",
                        "A visibilidade do perfil controla os seus detalhes, mas o username e o avatar ativo podem continuar públicos num perfil privado. Contribuições aprovadas e a atribuição de autoria não ficam privadas por essa escolha. O email de autenticação não é um campo público do perfil."
                    ]
                },
                {
                    "title": "Regras de utilização",
                    "paragraphs": [
                        "Utiliza o serviço de forma lícita e respeitadora. Não publiques conteúdo ilegal, ameaças, assédio, discriminação, dados pessoais de terceiros sem fundamento, spam, malware ou material que viole direitos de autor ou de imagem.",
                        "Não manipules submissões ou identidades para enganar a moderação, não explores falhas nem contornes suspensões. Não automatizes acessos ou extraias dados de modo a prejudicar a segurança, disponibilidade ou direitos de terceiros. Esta regra não afasta utilizações permitidas por lei."
                    ]
                },
                {
                    "title": "Submissões e responsabilidade pelo conteúdo",
                    "paragraphs": [
                        "As funcionalidades disponíveis permitem propor novos marcadores e correções, incluindo texto, coordenadas no jogo e referências de imagens ou vídeos. Podes sinalizar uma imagem pelo fluxo de correção. As opções apresentadas determinam o que podes submeter, editar ou cancelar; uma contribuição não dá acesso direto a editar o mapa publicado.",
                        "És responsável por ter os direitos, permissões e fundamento necessários para o conteúdo que envias, incluindo avatares e recursos externos que indicas. Não envies material de terceiros sem autorização ou outra utilização legalmente permitida, nem informação pessoal desnecessária. A existência de um URL público não significa que o conteúdo possa ser reutilizado livremente."
                    ]
                },
                {
                    "title": "Direitos sobre as contribuições e licença",
                    "paragraphs": [
                        "Manténs os direitos que efetivamente tenhas sobre o teu conteúdo. Ao submetê-lo, concedes ao DeepMap uma licença não exclusiva, gratuita e mundial para o alojar, reproduzir, mostrar e comunicar na plataforma, integrar nos mapas, formatar, traduzir e adaptar tecnicamente, corrigir e moderar na medida necessária à prestação do serviço. A licença abrange os prestadores que atuem por nossa conta apenas para essas finalidades, não uma autorização geral para exploração alheia ao DeepMap.",
                        "A licença vigora enquanto o conteúdo for legitimamente mantido no serviço. A eliminação da conta não retira automaticamente conteúdo já integrado nos mapas. Esta licença não substitui direitos de terceiros, não concede mais direitos do que possuis e não limita direitos de apagamento ou outras proteções legais. A plataforma pode apresentar a autoria nos termos da Política de Privacidade."
                    ]
                },
                {
                    "title": "Moderação e comunicação de problemas",
                    "paragraphs": [
                        "A equipa autorizada pode rever, aprovar, rejeitar ou corrigir submissões e remover ou restringir conteúdo por razões de legalidade, segurança, direitos de terceiros, qualidade ou cumprimento destes Termos. Podem ser conservadas versões e decisões. Submissões de moderadores podem ser aprovadas automaticamente; não prometemos revisão humana prévia de todos os conteúdos.",
                        "Não garantimos publicação ou manutenção de uma submissão. Para comunicar conteúdo ilegal, violação de direitos ou outro problema, usa contact@deepmap.cc, indicando o URL ou marcador, o motivo e informação suficiente para o avaliarmos. Podes também pedir reavaliação de uma decisão pelo mesmo contacto."
                    ]
                },
                {
                    "title": "Suspensão e restrições",
                    "paragraphs": [
                        "Podemos restringir interações, suspender contas ou retirar permissões quando necessário e proporcionado para lidar com infrações, abuso, risco de segurança ou obrigações legais. Uma suspensão de interações não impede necessariamente a consulta das áreas públicas.",
                        "Quando aplicável, comunicamos o motivo e a duração da medida através das funcionalidades de conta ou de outro meio adequado, salvo impedimento legal ou de segurança. Podes contactar-nos para esclarecer ou contestar a medida. Estas regras não afastam garantias legais aplicáveis."
                    ]
                },
                {
                    "title": "Eliminação de conta e conservação",
                    "paragraphs": [
                        "Podes pedir eliminação através de contact@deepmap.cc. Atualmente não existe um botão automático para esse efeito; poderemos verificar a identidade de forma proporcionada. Terminar sessão ou tornar o perfil privado não equivale a eliminar a conta.",
                        "A conta e o perfil são distintos de marcadores, contribuições incorporadas, versões e histórico de moderação/auditoria. Estes podem ser conservados quando legítimo, sem ligação pública a um perfil existente; certos identificadores históricos podem permanecer em registos internos. Avaliamos separadamente os dados pessoais, avatares e outros registos associados e os pedidos de apagamento. Não prometemos anonimização integral automática nem a eliminação de todas as cópias externas."
                    ]
                },
                {
                    "title": "Mapas e propriedade intelectual",
                    "paragraphs": [
                        "Os mapas e conteúdos podem estar incompletos, incorretos ou desatualizados e variar com a versão, atualização, plataforma ou partida do jogo. Não garantimos completude ou adequação a uma finalidade específica, sem prejuízo das garantias impostas por lei.",
                        "A marca, interface, código, gráficos e conteúdo original do DeepMap estão protegidos na medida prevista pela lei e pelas licenças aplicáveis. Os nomes, marcas, imagens, personagens e outros materiais dos jogos pertencem aos respetivos titulares. As contribuições permanecem sujeitas aos direitos dos seus autores. Não adquirimos a propriedade desses materiais pela sua apresentação na plataforma.",
                        "Não reutilizes partes protegidas do serviço sem autorização ou fundamento legal. Mantêm-se as exceções legais e os direitos concedidos por licenças de componentes ou materiais de terceiros."
                    ]
                },
                {
                    "title": "Serviços externos",
                    "paragraphs": [
                        "A autenticação, alojamento e outros componentes dependem de prestadores. Links, imagens e vídeos externos podem levar o navegador a contactar terceiros, sujeitos às respetivas regras, como explicado na Política de Privacidade.",
                        "Não controlamos o conteúdo ou disponibilidade de sites externos e a sua apresentação não significa aprovação. Isto não afasta a responsabilidade do DeepMap pela sua própria atuação nem as obrigações legais relativas aos prestadores que utiliza."
                    ]
                },
                {
                    "title": "Disponibilidade, alterações e responsabilidade",
                    "paragraphs": [
                        "O serviço está em desenvolvimento e pode sofrer manutenção, interrupções ou alterações de funcionalidades por razões técnicas, de segurança, legais ou de evolução do produto. Não garantimos disponibilidade contínua ou ausência de erros. Alterações materiais ou descontinuações serão comunicadas com antecedência razoável quando possível e legalmente exigido, respeitando os direitos aplicáveis.",
                        "A responsabilidade do DeepMap é determinada pela lei aplicável; estes Termos não estabelecem uma exclusão geral de responsabilidade. Não excluímos responsabilidade por dolo ou culpa grave, danos pessoais ou outras situações em que a lei o proíba. Não limitamos direitos imperativos de consumidores ou titulares de dados nem os meios de reação legalmente disponíveis."
                    ]
                },
                {
                    "title": "Versão e alterações aos Termos",
                    "paragraphs": [
                        "A versão e data atuais são publicadas nesta página. Alterações materiais serão comunicadas de forma adequada, com a antecedência e aceitação exigidas por lei, sem aplicação retroativa indevida. Se não quiseres continuar a usar as funcionalidades afetadas, podes deixar de as usar e pedir eliminação da conta, mantendo os teus direitos legais."
                    ]
                },
                {
                    "title": "Lei aplicável, tribunais e contacto",
                    "paragraphs": [
                        "Aplica-se a lei portuguesa, sem privar consumidores das proteções imperativas da lei que lhes seja aplicável, incluindo a do país de residência habitual quando previsto nas regras europeias. A competência dos tribunais segue as regras legais aplicáveis; não impomos um foro exclusivo que retire a um consumidor o direito de recorrer aos tribunais competentes da sua residência.",
                        "Para questões sobre estes Termos, conta ou conteúdo, contacta contact@deepmap.cc. A Política de Privacidade explica o tratamento de dados pessoais e é distinta da aceitação destes Termos."
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
    <link rel="canonical" href="https://deepmap.cc/terms" />
</svelte:head>

<main class="privacy-page">
    <div class="privacy-container">
        <div class="privacy-card">

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
    .contact-email { display: block; color: #e0c187; overflow-wrap: anywhere; text-decoration: none; margin: 10px 0 0; font-size: .91rem; }
    .contact-email:hover, .reference-link a:hover { text-decoration: underline; }
    .reference-link a { color: #d6b67a; text-decoration: none; }
    a:focus-visible, select:focus-visible { outline: 2px solid #d1ad6c; outline-offset: 3px; }
    @media (max-width: 790px) { .content-grid { grid-template-columns: 1fr; } .side-column { position: static; grid-row: 1; grid-template-columns: repeat(2, minmax(0,1fr)); } }
    @media (max-width: 590px) { .privacy-page { padding: 20px 12px 35px; } .privacy-card { padding: 15px; } .hero { padding: 23px 19px; } .side-column { grid-template-columns: 1fr; } .policy-section, .aside-card { padding: 18px; } .section-heading { gap: 10px; } .section-heading h2 { font-size: 1.03rem; } .hero::after { width: 180px; height: 180px; right: -90px; top: -90px; } }
</style>
