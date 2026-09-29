-- DeepMap v1.0.31 — 05 | Private Profile Identity
-- Permite distinguir perfis privados de usernames inexistentes.
-- Só devolve @username, estado de visibilidade e avatar ativo.
-- A política RLS de public.profiles mantém-se inalterada.

begin;

create schema if not exists private;

-- A consulta privilegiada vive num schema não exposto pela Data API.
-- Nunca devolve email, nome de apresentação, bio ou dados de autenticação.
create or replace function private.profile_identity_lookup(p_username text)
returns table (
    username text,
    is_public boolean,
    public_avatar_choice text,
    public_avatar_path text,
    public_google_avatar_url text
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        p.username,
        p.is_public,
        p.public_avatar_choice,
        case
            when p.public_avatar_choice = 'custom'
                and p.public_avatar_path ~
                    ('^' || p.id::text || '/avatar-[0-9a-f-]{36}[.]webp$')
                then p.public_avatar_path
            else null
        end,
        case
            when p.public_avatar_choice = 'google'
                and p.public_google_avatar_url ~ '^https://lh[0-9]+[.]googleusercontent[.]com/'
                then p.public_google_avatar_url
            else null
        end
    from public.profiles as p
    where p.username = p_username
      and p_username ~ '^[a-z0-9_]{3,20}$'
    limit 1;
$$;

-- Entrada pública com permissões do chamador; delega apenas nesta função.
create or replace function public.get_profile_identity(p_username text)
returns table (
    username text,
    is_public boolean,
    public_avatar_choice text,
    public_avatar_path text,
    public_google_avatar_url text
)
language sql
stable
security invoker
set search_path = ''
as $$
    select * from private.profile_identity_lookup(p_username);
$$;

-- Restringir explicitamente quem pode executar cada função.
revoke all on function private.profile_identity_lookup(text) from public, anon, authenticated;
revoke all on function public.get_profile_identity(text) from public, anon, authenticated;
grant usage on schema private to anon, authenticated;
grant execute on function private.profile_identity_lookup(text) to anon, authenticated;
grant execute on function public.get_profile_identity(text) to anon, authenticated;

commit;
