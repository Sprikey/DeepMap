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

    // Recuperação por token_hash: não depende do navegador onde foi pedido o email.
    // A sessão é criada no servidor e guardada nos cookies pelo cliente SSR.
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

        // Destino fixo: um link de recuperação nunca deve terminar no mapa.
        redirect(303, '/reset-password');
    }

    // Não aceitar outros tipos de token neste callback.
    // A confirmação de email continua em /auth/confirm.
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
