
import { redirect } from '@sveltejs/kit';

export const GET = async ({ url, locals }) => {
    const token_hash = url.searchParams.get('token_hash');
    const type = url.searchParams.get('type');

    if (!token_hash || type !== 'email') {
        redirect(303, '/login?email_error=invalid_link');
    }

    const { error } = await locals.supabase.auth.verifyOtp({
        token_hash,
        type: 'email'
    });

    if (error) {
        console.error('Erro ao confirmar email:', error.message);
        redirect(303, '/login?email_error=confirmation_failed');
    }

    redirect(303, '/login?email_confirmed=1');
};
