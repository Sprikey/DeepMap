// Allowlisted route templates: unknown paths never reach Analytics verbatim.
const staticPaths = new Set([
    '/', '/login', '/profile', '/reset-password', '/terms', '/privacy',
    '/admin', '/moderation', '/notifications', '/suspended', '/onboarding',
    '/auth/callback', '/auth/confirm'
]);

/** @param {string} pathname */
export function analyticsPath(pathname) {
    const path = pathname.replace(/\/+$/, '') || '/';
    if (staticPaths.has(path)) return path;
    if (/^\/u\/[^/]+$/.test(path)) return '/u/[username]';
    if (/^\/p\/[^/]+$/.test(path)) return '/p/[id]';
    if (/^\/games\/[^/]+\/map$/.test(path)) return '/games/[game]/map';
    return '/[unmatched]';
}

/** @param {import('@vercel/analytics').BeforeSendEvent} event */
export function redactAnalyticsEvent(event) {
    try {
        const url = new URL(event.url);
        // Drop all query/hash data, including OAuth codes, return paths and map IDs.
        return { ...event, url: url.origin + analyticsPath(url.pathname) };
    } catch {
        return null;
    }
}
