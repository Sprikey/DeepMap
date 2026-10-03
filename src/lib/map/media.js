export function normaliseHttpUrl(value) {
    const raw = String(value ?? '').trim();
    if (!raw) return null;

    try {
        const url = new URL(raw);
        if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
        return url.toString();
    } catch {
        return null;
    }
}

export function getVideoEmbedUrl(value) {
    const normalised = normaliseHttpUrl(value);
    if (!normalised) return null;

    const url = new URL(normalised);
    const host = url.hostname.replace(/^www\./, '').toLowerCase();

    if (host === 'youtu.be') {
        const id = url.pathname.split('/').filter(Boolean)[0];
        return id ? `https://www.youtube.com/embed/${encodeURIComponent(id)}` : null;
    }

    if (host === 'youtube.com' || host === 'm.youtube.com') {
        if (url.pathname === '/watch') {
            const id = url.searchParams.get('v');
            return id ? `https://www.youtube.com/embed/${encodeURIComponent(id)}` : null;
        }

        const match = url.pathname.match(/^\/(?:embed|shorts|live)\/([^/?#]+)/);
        return match?.[1]
            ? `https://www.youtube.com/embed/${encodeURIComponent(match[1])}`
            : null;
    }

    if (host === 'vimeo.com' || host === 'player.vimeo.com') {
        const parts = url.pathname.split('/').filter(Boolean).reverse();
        const id = parts.find((part) => /^\d+$/.test(part));
        return id ? `https://player.vimeo.com/video/${encodeURIComponent(id)}` : null;
    }

    return null;
}
