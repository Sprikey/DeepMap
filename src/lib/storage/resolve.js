/**
 * Pure public URL resolution. No network, credentials or authorization decisions.
 * Legacy avatar paths must first pass the calling feature's existing validation.
 * @param {import('./references.js').FileReference | null | undefined} reference
 * @param {{ supabaseUrl?: string }} [config]
 * @returns {string | null}
 */
export function resolveFileUrl(reference, config = {}) {
    if (!reference || typeof reference.value !== 'string' || !reference.value) return null;
    switch (reference.kind) {
        case 'static':
        case 'external':
        case 'google':
            return reference.value;
        case 'legacy-supabase-avatar': {
            if (typeof config.supabaseUrl !== 'string') return null;
            const segments = reference.value.split('/').map(encodeURIComponent).join('/');
            return `${config.supabaseUrl}/storage/v1/object/public/avatars/${segments}`;
        }
        case 'r2':
        default:
            return null;
    }
}
