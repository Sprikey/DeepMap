import { redirect } from '@sveltejs/kit';
import { safeAccountPath } from '$lib/auth/account-path.js';
import { authenticatedAccountPath } from '$lib/server/legal-onboarding.js';

export const GET = async ({ locals, url }) => {
    const next = safeAccountPath(url.searchParams.get('next'), url.origin);
    const { data: { user } } = await locals.supabase.auth.getUser();
    if (!user) redirect(303, `/login?next=${encodeURIComponent(next)}`);
    redirect(303, await authenticatedAccountPath(locals.supabase, next, url.origin));
};
