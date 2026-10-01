-- DeepMap v1.0.31 — 01 | Username Profiles
-- Cria a tabela public.profiles para @usernames e define as permissões/RLS base.

begin;

-- Cada conta tem um único @username.
-- Não guardamos emails nesta tabela.

create table public.profiles (
    id uuid primary key
        references auth.users(id)
        on delete cascade,

    username text not null unique,

    constraint profiles_username_format
        check (username ~ '^[a-z0-9_]{3,20}$'),

    constraint profiles_username_reserved
        check (
            username not in (
                'admin',
                'administrator',
                'deepmap',
                'official',
                'moderator',
                'support',
                'staff',
                'system',
                'root',
                'contact',
                'help'
            )
        )
);

-- Ativar segurança por utilizador.
alter table public.profiles enable row level security;

-- Remover permissões genéricas.
revoke all on table public.profiles
from public, anon, authenticated;

-- Todos podem consultar os @usernames públicos.
grant select on table public.profiles
to anon, authenticated;

-- Cada utilizador pode criar o seu registo.
grant insert (id, username) on table public.profiles
to authenticated;

-- Só permitimos editar a coluna username.
grant update (username) on table public.profiles
to authenticated;

-- Leitura pública.
create policy "profiles_public_read"
on public.profiles
for select
to anon, authenticated
using (true);

-- Criar apenas o próprio perfil.
create policy "profiles_insert_own"
on public.profiles
for insert
to authenticated
with check (
    (select auth.uid()) = id
);

-- Alterar apenas o próprio perfil.
create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using (
    (select auth.uid()) = id
)
with check (
    (select auth.uid()) = id
);

commit;
