/**
 * Transitional browser-compatible adapter: uses only the caller's RLS-bound
 * client. Session/operation guards and cleanup decisions remain with the caller.
 * @param {Pick<import('@supabase/supabase-js').SupabaseClient, 'storage'>} supabase
 * @param {string} path
 * @param {File} file
 */
export function uploadLegacyAvatar(supabase, path, file) {
    return supabase.storage.from('avatars').upload(path, file, {
        contentType: 'image/webp', cacheControl: '3600', upsert: false
    });
}

/**
 * Delete exactly the captured object path, never a URL or a current-session
 * reconstruction. The caller retains ownership and stale-operation guards.
 * @param {Pick<import('@supabase/supabase-js').SupabaseClient, 'storage'>} supabase
 * @param {string} path
 */
export function deleteLegacyAvatar(supabase, path) {
    return supabase.storage.from('avatars').remove([path]);
}
