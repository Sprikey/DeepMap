import { dev } from '$app/environment';
import { injectAnalytics } from '@vercel/analytics/sveltekit';
import { redactAnalyticsEvent } from '$lib/analytics/redact.js';

injectAnalytics({
    mode: dev ? 'development' : 'production',
    beforeSend: redactAnalyticsEvent
});
