import { redirect } from '@sveltejs/kit';

export const GET = async ({ url, locals }) => {
    const code = url.searchParams.get('code');
    const tokenHash = url.searchParams.get('token_hash');
    const type = url.searchParams.get('type');
    const next = url.searchParams.get('next') ?? '/';

    // Permitir apenas destinos internos do DeepMap para o fluxo normal.
    const safeNext =
        next.startsWith('/') &&
        !next.startsWith('//') &&
        !next.includes('\\')
            ? next
            : '/';

    // Recuperação entre navegadores: mantém o fluxo já testado.
    if (type === 'recovery') {
        if (!tokenHash) {
            redirect(303, '/login?auth_error=missing_code&reason=invalid_recovery_link');
        }

        const { error } = await locals.supabase.auth.verifyOtp({
            token_hash: tokenHash,
            type: 'recovery'
        });

        if (error) {
            console.error('Erro na recuperação Supabase:', {
                reason: error.code,
                status: error.status,
                message: error.message
            });

            redirect(303, '/login?auth_error=callback&reason=recovery_failed');
        }

        redirect(303, '/reset-password');
    }

    // Confirmação de conta, mesmo que o email seja aberto noutro navegador.
    if (type === 'email') {
        if (!tokenHash) {
            redirect(303, '/login?email_error=invalid_link');
        }

        const { error } = await locals.supabase.auth.verifyOtp({
            token_hash: tokenHash,
            type: 'email'
        });

        if (error) {
            console.error('Erro na confirmação de email Supabase:', {
                reason: error.code,
                status: error.status,
                message: error.message
            });

            redirect(303, '/login?email_error=confirmation_failed');
        }

        redirect(303, '/login?email_confirmed=1');
    }

    // Rejeitar tipos de token desconhecidos.
    if (tokenHash) {
        redirect(303, '/login?auth_error=missing_code&reason=invalid_link_type');
    }

    // Fluxo PKCE existente: Google e links antigos no mesmo navegador.
    if (!code) {
        const providerError = url.searchParams.get('error_code');
        const reason = providerError
            ? `&reason=${encodeURIComponent(providerError)}`
            : '';

        redirect(303, `/login?auth_error=missing_code${reason}`);
    }

    const { error } = await locals.supabase.auth.exchangeCodeForSession(code);

    if (error) {
        console.error('Erro no callback Supabase:', {
            reason: error.code,
            status: error.status,
            message: error.message
        });

        // Nunca incluir tokens ou códigos nos URLs de erro.
        const reason = encodeURIComponent(error.code ?? 'unknown');
        const status = encodeURIComponent(String(error.status ?? 'unknown'));

        redirect(303, `/login?auth_error=callback&reason=${reason}&status=${status}`);
    }

    redirect(303, safeNext);
};