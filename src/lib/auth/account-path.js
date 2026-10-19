import { safeInternalPath } from './internal-path.js';

/** Internal post-auth destination, excluding routes that restart authentication.
 * @param {unknown} candidate
 * @param {string} origin
 */
export function safeAccountPath(candidate, origin) {
    const path = safeInternalPath(candidate, origin, '/profile');
    let pathname = new URL(path, origin).pathname;
    for (let depth = 0; depth < 8; depth++) {
        if (/^\/(?:login|onboarding|auth|reset-password)(?:\/|$)/i.test(pathname)) return '/profile';
        try {
            const decoded = decodeURIComponent(pathname);
            if (decoded === pathname) break;
            pathname = decoded;
        } catch { return '/profile'; }
    }
    return path;
}
