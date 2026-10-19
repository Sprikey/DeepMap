import { error } from '@sveltejs/kit';
import { safeAccountPath } from '../auth/account-path.js';

/** Single destination contract for authenticated email and OAuth sessions.
 * @param {import('@supabase/supabase-js').SupabaseClient} supabase
 * @param {unknown} candidate
 * @param {string} origin
 */
export async function authenticatedAccountPath(supabase, candidate, origin) {
    const next = safeAccountPath(candidate, origin);
    const { data: required, error: legalError } = await supabase.rpc('requires_legal_acceptance');
    if (legalError || typeof required !== 'boolean') error(503, 'Account onboarding is temporarily unavailable.');
    return required ? `/onboarding?next=${encodeURIComponent(next)}` : next;
}
