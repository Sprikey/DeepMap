import { PUBLIC_SUPABASE_URL } from '$env/static/public';

// Os IDs antigos mantêm-se para preservar as escolhas já guardadas nas contas.
export const AVATAR_PRESETS = [
    { id: 'explorador', label: 'Avatar 1', symbol: '01', image: '/avatars/official/avatar-01.webp' },
    { id: 'cartografo', label: 'Avatar 2', symbol: '02', image: '/avatars/official/avatar-02.webp' },
    { id: 'cavaleiro', label: 'Avatar 3', symbol: '03', image: '/avatars/official/avatar-03.webp' },
    { id: 'feiticeiro', label: 'Avatar 4', symbol: '04', image: '/avatars/official/avatar-04.webp' },
    { id: 'ladino', label: 'Avatar 5', symbol: '05', image: '/avatars/official/avatar-05.webp' },
    { id: 'errante', label: 'Avatar 6', symbol: '06', image: '/avatars/official/avatar-06.webp' }
];

export function getDisplayName(user) {
    const name =
        user?.user_metadata?.display_name ||
        user?.user_metadata?.full_name ||
        user?.user_metadata?.name ||
        user?.email?.split('@')[0] ||
        'Explorador';

    return String(name).trim() || 'Explorador';
}

export function getGoogleAvatarUrl(user) {
    const avatar = user?.user_metadata?.avatar_url || user?.user_metadata?.picture;
    return typeof avatar === 'string' && /^https:\/\//i.test(avatar) ? avatar : null;
}

// Nunca usar URLs arbitrários vindos de user_metadata como avatar personalizado.
// Guardamos apenas o caminho e reconstruímos a URL do nosso bucket público.
export function getCustomAvatarPath(user) {
    const path = user?.user_metadata?.avatar_custom_path;
    if (!user?.id || typeof path !== 'string') return null;

    const prefix = `${user.id}/`;
    if (!path.startsWith(prefix)) return null;

    const filename = path.slice(prefix.length);
    return /^avatar-[0-9a-f-]{36}\.webp$/i.test(filename) ? path : null;
}

export function getCustomAvatarUrl(user) {
    const path = getCustomAvatarPath(user);
    if (!path) return null;
    const segments = path.split('/').map(encodeURIComponent).join('/');
    return `${PUBLIC_SUPABASE_URL}/storage/v1/object/public/avatars/${segments}`;
}

export function getAvatarPresentation(user) {
    const selection = user?.user_metadata?.avatar_choice;
    const preset = AVATAR_PRESETS.find((item) => item.id === selection);
    const initial = getDisplayName(user).charAt(0).toLocaleUpperCase('pt-PT');

    if (preset) {
        return {
            choice: preset.id,
            image: preset.image,
            symbol: preset.symbol,
            label: preset.label
        };
    }

    const customImage = getCustomAvatarUrl(user);
    if (selection === 'custom' && customImage) {
        return { choice: 'custom', image: customImage, symbol: initial, label: 'Custom avatar' };
    }

    const googleImage = getGoogleAvatarUrl(user);
    if (googleImage && selection !== 'initial') {
        return { choice: 'google', image: googleImage, symbol: initial, label: 'Google photo' };
    }

    return { choice: 'initial', image: null, symbol: initial, label: 'Name initial' };
}
