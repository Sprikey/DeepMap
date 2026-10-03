-- DeepMap — Map Editor 2.0 | Admin status RPC
-- Expõe ao frontend apenas um booleano seguro (true/false).
-- As permissões reais continuam a ser impostas pelas policies RLS que usam
-- private.is_deepmap_admin(). Esta função NÃO expõe a lista nem os UUIDs de admins.

begin;

create or replace function public.is_deepmap_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select private.is_deepmap_admin();
$$;

revoke all on function public.is_deepmap_admin()
from public, anon, authenticated;

grant execute on function public.is_deepmap_admin()
to authenticated;

comment on function public.is_deepmap_admin()
is 'Returns true only when the authenticated user is registered in private.deepmap_admins.';

commit;
