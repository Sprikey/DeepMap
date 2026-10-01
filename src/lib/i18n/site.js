// DeepMap: língua comum a todas as páginas.
// O valor fica persistido no localStorage e é sincronizado em tempo real
// entre o header global e as páginas que subscrevem alterações de idioma.
export const LANGUAGE_STORAGE_KEY = 'deepmap-language';
export const LANGUAGE_CHANGE_EVENT = 'deepmap:language-change';

export const siteHeaderTranslations = {
    en: {
        language: 'Language',
        navigationLabel: 'DeepMap navigation',
        navJourney: 'Our first world',
        navVision: 'Our vision',
        navFollow: 'Follow us',
        openMenu: 'Open navigation menu',
        closeMenu: 'Close navigation menu'
    },
    pt: {
        language: 'Idioma',
        navigationLabel: 'Navegação DeepMap',
        navJourney: 'Primeiro mundo',
        navVision: 'A nossa visão',
        navFollow: 'Segue-nos',
        openMenu: 'Abrir menu de navegação',
        closeMenu: 'Fechar menu de navegação'
    }
};



export const siteFooterTranslations = {
    en: {
        navigationLabel: 'DeepMap footer',
        copyright: 'Built for explorers.',
        privacy: 'Privacy Policy',
        terms: 'Terms of Use',
        contact: 'Contact'
    },
    pt: {
        navigationLabel: 'Rodapé DeepMap',
        copyright: 'Criado para exploradores.',
        privacy: 'Política de Privacidade',
        terms: 'Termos de Utilização',
        contact: 'Contacto'
    }
};

export function normaliseLanguage(value) {
    return value === 'pt' ? 'pt' : 'en';
}

export function getSiteLanguage() {
    if (typeof window === 'undefined') return 'en';

    try {
        return normaliseLanguage(window.localStorage.getItem(LANGUAGE_STORAGE_KEY));
    } catch {
        return 'en';
    }
}

export function setSiteLanguage(value) {
    const language = normaliseLanguage(value);

    if (typeof window !== 'undefined') {
        try {
            window.localStorage.setItem(LANGUAGE_STORAGE_KEY, language);
        } catch {
            // O idioma continua funcional mesmo com storage bloqueado.
        }

        document.documentElement.lang = language === 'pt' ? 'pt-PT' : 'en';

        window.dispatchEvent(new CustomEvent(LANGUAGE_CHANGE_EVENT, {
            detail: { language }
        }));
    }

    return language;
}

export function subscribeSiteLanguage(callback) {
    if (typeof window === 'undefined') return () => {};

    const handleLanguageChange = (event) => {
        callback(normaliseLanguage(event?.detail?.language));
    };

    const handleStorage = (event) => {
        if (event.key !== LANGUAGE_STORAGE_KEY) return;
        callback(normaliseLanguage(event.newValue));
    };

    window.addEventListener(LANGUAGE_CHANGE_EVENT, handleLanguageChange);
    window.addEventListener('storage', handleStorage);

    return () => {
        window.removeEventListener(LANGUAGE_CHANGE_EVENT, handleLanguageChange);
        window.removeEventListener('storage', handleStorage);
    };
}
