/**
 * Own browser work by mounted lifetime and account UUID.
 * onChange is synchronous invalidation only; start SDK work in an effect/task.
 * @param {() => void} onChange
 */
export function createSessionScope(onChange) {
    let mounted = false;
    let epoch = 0;
    let accountId = /** @type {string | null} */ (null);
    return {
        get accountId() { return accountId; },
        capture() {
            const actor = accountId;
            const generation = epoch;
            return () => mounted && actor !== null && actor === accountId && generation === epoch;
        },
        /** @param {import('@supabase/supabase-js').SupabaseClient} supabase */
        start(supabase) {
            mounted = true;
            let initialized = false;
            const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
                if (!mounted) return;
                const nextAccountId = event === 'SIGNED_OUT' ? null : session?.user?.id ?? null;
                // Token renewal/reconfirmation preserves work owned by the same actor.
                if (initialized && nextAccountId === accountId && event !== 'SIGNED_OUT') return;
                initialized = true;
                ++epoch;
                accountId = nextAccountId;
                onChange();
            });
            return () => {
                mounted = false;
                ++epoch;
                accountId = null;
                subscription.unsubscribe();
            };
        }
    };
}
