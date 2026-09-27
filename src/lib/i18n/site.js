// DeepMap: língua comum a todas as páginas.
// Acesso ao storage apenas no browser (não há estado global partilhado no SSR).
export const LANGUAGE_STORAGE_KEY = 'deepmap-language';

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
    }

    return language;
}
