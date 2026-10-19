import { fail, redirect } from '@sveltejs/kit';
import { TERMS_VERSION, PRIVACY_VERSION } from '$lib/auth/legal.js';
import { safeAccountPath } from '$lib/auth/account-path.js';
import { authenticatedAccountPath } from '$lib/server/legal-onboarding.js';

export const load = async ({ locals, url }) => {
    const { data: { user } } = await locals.supabase.auth.getUser();
    if (!user) redirect(303, `/login?next=${encodeURIComponent(safeAccountPath(url.searchParams.get('next'), url.origin))}`);
    const destination = await authenticatedAccountPath(locals.supabase, url.searchParams.get('next'), url.origin);
    // Existing and already accepted accounts never see another acceptance form.
    if (!destination.startsWith('/onboarding?')) redirect(303, destination);
    return {};
};

export const actions = {
    default: async ({ request, locals, url }) => {
        const { data: { user } } = await locals.supabase.auth.getUser();
        if (!user) redirect(303, '/login');
        const next = safeAccountPath(url.searchParams.get('next'), url.origin);
        // Recheck the cohort/state on POST too, including stale accepted tabs.
        const { data: required, error: legalError } = await locals.supabase.rpc('requires_legal_acceptance');
        if (legalError || typeof required !== 'boolean') return fail(503, { error: 'save' });
        if (!required) redirect(303, next);
        const form = await request.formData();
        if (form.get('accepted') !== 'yes') return fail(400, { error: 'required' });
        // Validate the version actually displayed, including stale browser tabs.
        if (form.get('terms_version') !== TERMS_VERSION || form.get('privacy_version') !== PRIVACY_VERSION) {
            return fail(409, { error: 'version' });
        }
        const { error } = await locals.supabase.rpc('accept_legal_documents', {
            p_terms_version: TERMS_VERSION, p_privacy_version: PRIVACY_VERSION
        });
        if (error) return fail(503, { error: 'save' });
        redirect(303, next);
    }
};
