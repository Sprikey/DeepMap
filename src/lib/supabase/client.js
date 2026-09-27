
import { createBrowserClient } from '@supabase/ssr';

import {
    PUBLIC_SUPABASE_URL,
    PUBLIC_SUPABASE_PUBLISHABLE_KEY
} from '$env/static/public';

/* Cliente Supabase utilizado no browser. */

export function getSupabaseBrowserClient() {
    return createBrowserClient(
        PUBLIC_SUPABASE_URL,
        PUBLIC_SUPABASE_PUBLISHABLE_KEY
    );
}
