
import { redirect } from '@sveltejs/kit';

export const GET = async ({ url, locals }) => {
    const code = url.searchParams.get('code');
    const next = url.searchParams.get('next') ?? '/';

    // Permitir apenas destinos internos do DeepMap.
    const safeNext =
        next.startsWith('/') &&
        !next.startsWith('//') &&
        !next.includes('\\')
            ? next
            : '/';

    if (!code) {
        const providerError = url.searchParams.get('error_code');

        const reason = providerError
            ? `&reason=${encodeURIComponent(providerError)}`
            : '';

        redirect(303, `/login?auth_error=missing_code${reason}`);
    }

    const { error } =
        await locals.supabase.auth.exchangeCodeForSession(code);

    if (error) {
        console.error('Erro no callback Supabase:', {
            reason: error.code,
            status: error.status,
            message: error.message
        });

        // Mostramos apenas o tipo de erro, nunca o código de autenticação.
        const reason = encodeURIComponent(error.code ?? 'unknown');
        const status = encodeURIComponent(String(error.status ?? 'unknown'));

        redirect(
            303,
            `/login?auth_error=callback&reason=${reason}&status=${status}`
        );
    }

    redirect(303, safeNext);
};
