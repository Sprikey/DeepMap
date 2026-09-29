import { error } from '@sveltejs/kit';

// Permanent profile URL: /p/<immutable account UUID>.
// Never derive the destination from a historical username.
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const USERNAME_PATTERN = /^[a-z0-9_]{3,20}$/;

/** @type {import('./$types').RequestHandler} */
export const GET = async ({ params, url, locals }) => {

    if (!UUID_PATTERN.test(params.id)) {
        throw error(404, 'Explorer not found.');
    }

    const { data: username, error: lookupError } = await locals.supabase
        .rpc('get_profile_username_by_id', { p_profile_id: params.id });

    if (lookupError) {
        console.error('DeepMap permanent profile lookup failed:', lookupError.code);
        throw error(503, 'Unable to load this explorer.');
    }

    if (typeof username !== 'string' || !USERNAME_PATTERN.test(username)) {
        throw error(404, 'Explorer not found.');
    }

    const destination = `/u/${username}${url.searchParams.get('view') === 'visitor' ? '?view=visitor' : ''}`;
    return new Response(null, {
        status: 302,
        headers: {
            location: destination,
            'cache-control': 'private, no-store'
        }
    });
};
