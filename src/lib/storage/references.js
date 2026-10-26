/**
 * In-memory compatibility references, not database records or upload permissions.
 * Callers retain their existing path/URL allowlists before normalizing a value.
 * @typedef {{ kind: 'static' | 'external' | 'google' | 'legacy-supabase-avatar' | 'r2', value: string }} FileReference
 */

/**
 * Keep legacy strings byte-for-byte, including unknown/absent source labels that
 * existing marker readers treated as external references. This is deliberately
 * not URL validation: tightening an existing consumer's allowlist is separate work.
 * @param {unknown} source
 * @param {unknown} value
 * @returns {FileReference | null}
 */
export function normalizeFileReference(source, value) {
    if (typeof value !== 'string' || !value) return null;
    switch (source) {
        case 'static':
        case 'google':
        case 'legacy-supabase-avatar':
        case 'r2':
            return { kind: source, value };
        default:
            return { kind: 'external', value };
    }
}
