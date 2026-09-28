import { error } from '@sveltejs/kit';
import { PUBLIC_SUPABASE_URL } from '$env/static/public';
import { AVATAR_PRESETS } from '$lib/avatar/avatars.js';

// A rota nunca consulta auth.users nem expõe os metadados de autenticação.
const USERNAME_PATTERN = /^[a-z0-9_]{3,20}$/;
const CUSTOM_PATH_PATTERN = /^[0-9a-f-]{36}\/avatar-[0-9a-f-]{36}\.webp$/i;
const GOOGLE_PHOTO_PATTERN = /^https:\/\/lh[0-9]+\.googleusercontent\.com\//i;

function avatarFromSafeFields(row, ownerId = null) {
    const preset = AVATAR_PRESETS.find((item) => item.id === row.public_avatar_choice);
    if (preset) return preset.image;

    if (row.public_avatar_choice === 'custom') {
        const path = row.public_avatar_path;
        // A RPC já valida o caminho, mas voltamos a validar à saída do servidor.
        if (typeof path === 'string' && CUSTOM_PATH_PATTERN.test(path) &&
            (!ownerId || path.startsWith(`${ownerId}/`))) {
            const escaped = path.split('/').map(encodeURIComponent).join('/');
            return `${PUBLIC_SUPABASE_URL}/storage/v1/object/public/avatars/${escaped}`;
        }
    }

    if (row.public_avatar_choice === 'google' &&
        typeof row.public_google_avatar_url === 'string' &&
        GOOGLE_PHOTO_PATTERN.test(row.public_google_avatar_url)) {
        return row.public_google_avatar_url;
    }

    return null;
}

/** @type {import('./$types').PageServerLoad} */
export const load = async ({ params, url, locals, setHeaders }) => {
    // Uma resposta diferente por sessão nunca deve ser guardada em cache partilhada.
    setHeaders({ 'cache-control': 'private, no-store' });

    const username = params.username;
    if (!USERNAME_PATTERN.test(username)) {
        return { kind: 'not_found', profile: null, isOwner: false, isVisitorPreview: false };
    }

    const wantsVisitorPreview = url.searchParams.get('view') === 'visitor';
    const { data: { user }, error: authError } = await locals.supabase.auth.getUser();
    if (authError && authError.name !== 'AuthSessionMissingError') {
        console.error('DeepMap public profile: unable to verify session:', authError.code);
        throw error(503, 'Unable to verify the current session.');
    }

    // O RLS permite ler o registo completo apenas se for público ou do proprietário.
    const { data: row, error: rowError } = await locals.supabase
        .from('profiles')
        .select('id, username, is_public, public_display_name, public_bio, public_avatar_choice, public_avatar_path, public_google_avatar_url, joined_at')
        .eq('username', username)
        .maybeSingle();

    if (rowError) {
        console.error('DeepMap public profile: select failed:', rowError.code);
        throw error(503, 'Unable to load this profile.');
    }

    const isOwner = !!row && !!user && row.id === user.id;
    const isVisitorPreview = isOwner && wantsVisitorPreview;

    // Perfil público OU proprietário a consultar o seu perfil privado normalmente.
    if (row && (row.is_public || (isOwner && !isVisitorPreview))) {
        return {
            kind: 'public',
            isOwner,
            isVisitorPreview,
            profile: {
                username: row.username,
                displayName: row.public_display_name || 'Explorer',
                bio: row.public_bio || '',
                avatarUrl: avatarFromSafeFields(row, row.id),
                joinedYear: row.joined_at && !Number.isNaN(Date.parse(row.joined_at))
                    ? new Date(row.joined_at).getUTCFullYear()
                    : null,
                isPublic: row.is_public
            }
        };
    }

    // Perfil não encontrado pelo RLS, ou pré-visualização de proprietário privado:
    // consultar APENAS identidade mínima pela RPC da query 05 (avatar, @ e visibilidade).
    const { data: identities, error: identityError } = await locals.supabase
        .rpc('get_profile_identity', { p_username: username });

    if (identityError) {
        console.error('DeepMap public profile: identity lookup failed:', identityError.code);
        throw error(503, 'Unable to load profile identity.');
    }

    const identity = Array.isArray(identities) ? identities[0] : identities;
    if (!identity) {
        return { kind: 'not_found', profile: null, isOwner: false, isVisitorPreview: false };
    }

    // Um perfil público invisível na consulta RLS indica falha de acesso; não classificá-lo
    // erradamente como privado, nem fornecer uma rota alternativa para os dados completos.
    if (identity.is_public && !row) {
        console.error('DeepMap public profile: inconsistent public profile visibility');
        throw error(503, 'Unable to load this profile.');
    }

    if (identity.is_public && row) {
        // Defesa adicional; a condição normal foi tratada acima.
        throw error(503, 'Unable to load this profile.');
    }

    return {
        kind: 'private',
        isOwner,
        isVisitorPreview,
        profile: {
            username: identity.username,
            avatarUrl: avatarFromSafeFields(identity)
        }
    };
};
