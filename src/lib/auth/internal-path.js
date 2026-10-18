/**
 * Return a normalized, root-relative path at the supplied HTTP(S) origin.
 * Invalid candidates use a separately validated fallback (ultimately `/`).
 * No browser globals; encoded representations are checked, never returned decoded.
 * @param {unknown} candidate
 * @param {string} origin
 * @param {unknown} [fallback]
 * @returns {string}
 */
export function safeInternalPath(candidate, origin, fallback = '/') {
    /** @type {URL} */
    let base;
    try {
        base = new URL(origin);
        if (!['http:', 'https:'].includes(base.protocol)) return '/';
    } catch {
        return '/';
    }

    /** @param {unknown} value */
    function validate(value) {
        if (typeof value !== 'string' || !value) return null;
        let representation = value;
        let normalized = '';
        // Bound repeated decoding; excessive nesting is invalid rather than unchecked.
        for (let depth = 0; depth < 8; depth += 1) {
            if (!representation.startsWith('/') || representation.startsWith('//') ||
                /[\\\u0000-\u001f\u007f-\u009f]/.test(representation)) return null;
            try {
                const target = new URL(representation, base.origin);
                const path = target.pathname + target.search + target.hash;
                // Dot-segment removal can itself produce a protocol-relative pathname.
                if (target.origin !== base.origin || path.startsWith('//') ||
                    new URL(path, base.origin).origin !== base.origin) return null;
                if (depth === 0) normalized = path;
                // Decoded literal percent signs needn't be decoded again.
                if (depth > 0 && !/%[0-9a-f]{2}/i.test(representation)) return normalized;
                const decoded = decodeURIComponent(representation);
                if (decoded === representation) return normalized;
                representation = decoded;
            } catch {
                return null;
            }
        }
        return null;
    }

    return validate(candidate) ?? validate(fallback) ?? '/';
}
