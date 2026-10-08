-- DeepMap: additive multi-game foundation.
-- Apply manually only after review. This file does not replay older migrations.
-- Existing text game_id columns, layers, application RPCs and policies stay intact.
-- The DDL deliberately fails if a target relation already exists: never silently
-- adopt an unknown schema with IF NOT EXISTS. The seed itself preserves existing
-- identities/configuration and can be repeated independently on this schema.

begin;

-- Fail before creating anything if the audited authorization/trigger dependencies
-- are unavailable. No existing function is created or replaced here.
do $preflight$
begin
    if to_regprocedure('public.get_deepmap_role()') is null then
        raise exception 'MULTIGAME_REQUIRES_GET_DEEPMAP_ROLE';
    end if;
    if not has_function_privilege('authenticated', 'public.get_deepmap_role()', 'EXECUTE') then
        raise exception 'MULTIGAME_REQUIRES_AUTHENTICATED_ROLE_EXECUTE';
    end if;
    if to_regprocedure('private.deepmap_touch_updated_at()') is null then
        raise exception 'MULTIGAME_REQUIRES_TOUCH_UPDATED_AT';
    end if;
    if to_regprocedure('pg_catalog.gen_random_uuid()') is null then
        raise exception 'MULTIGAME_REQUIRES_GEN_RANDOM_UUID';
    end if;
end;
$preflight$;

-- 1. Stable identities; slugs are independently editable presentation/URL keys.
create table public.games (
    id uuid primary key default pg_catalog.gen_random_uuid(),
    slug text not null,
    name text not null,
    status text not null default 'draft',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint games_slug_unique unique (slug),
    constraint games_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
    constraint games_name_not_blank check (nullif(btrim(name), '') is not null),
    constraint games_status_valid check (status in ('draft', 'coming_soon', 'published'))
);

-- 2. Open-ended module keys: future modules need no schema change.
-- settings is PUBLIC configuration when the row is publicly readable; no secrets.
create table public.game_modules (
    id uuid primary key default pg_catalog.gen_random_uuid(),
    game_id uuid not null references public.games(id) on delete restrict,
    module_key text not null,
    enabled boolean not null default false,
    position integer not null default 0,
    settings jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint game_modules_game_key_unique unique (game_id, module_key),
    constraint game_modules_key_format check (module_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
    constraint game_modules_admin_areas_excluded check (module_key not in ('overview', 'settings')),
    constraint game_modules_position_valid check (position >= 0),
    constraint game_modules_settings_object check (jsonb_typeof(settings) = 'object')
);

create index game_modules_game_position_idx
    on public.game_modules (game_id, position, module_key);

-- 3. Conceptual maps, not layers. Existing layers are deliberately not linked yet.
-- A game can temporarily have no default; at most one default is allowed.
-- settings is PUBLIC map configuration, never private credentials or storage keys.
create table public.game_maps (
    id uuid primary key default pg_catalog.gen_random_uuid(),
    game_id uuid not null references public.games(id) on delete restrict,
    slug text not null,
    name text not null,
    status text not null default 'draft',
    position integer not null default 0,
    is_default boolean not null default false,
    settings jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint game_maps_game_slug_unique unique (game_id, slug),
    constraint game_maps_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
    constraint game_maps_name_not_blank check (nullif(btrim(name), '') is not null),
    constraint game_maps_status_valid check (status in ('draft', 'published')),
    constraint game_maps_position_valid check (position >= 0),
    constraint game_maps_settings_object check (jsonb_typeof(settings) = 'object')
);

create unique index game_maps_one_default_per_game_idx
    on public.game_maps (game_id) where is_default;

create index game_maps_game_position_idx
    on public.game_maps (game_id, position, slug);

-- 4. Private compatibility mapping. legacy_identifier is not the current slug.
-- Multiple historical identifiers can point to the same permanent game UUID.
-- Normal authenticated clients cannot edit or remove a recorded correspondence.
create table private.game_legacy_identifiers (
    id uuid primary key default pg_catalog.gen_random_uuid(),
    legacy_identifier text not null,
    game_id uuid not null references public.games(id) on delete restrict,
    created_at timestamptz not null default now(),
    constraint game_legacy_identifiers_identifier_unique unique (legacy_identifier),
    constraint game_legacy_identifiers_identifier_not_blank
        check (legacy_identifier = btrim(legacy_identifier) and legacy_identifier <> '')
);

create index game_legacy_identifiers_game_idx
    on private.game_legacy_identifiers (game_id);

-- Reuse the existing invoker trigger function, without changing its definition.
create trigger deepmap_games_touch_updated_at
before update on public.games
for each row execute function private.deepmap_touch_updated_at();

create trigger deepmap_game_modules_touch_updated_at
before update on public.game_modules
for each row execute function private.deepmap_touch_updated_at();

create trigger deepmap_game_maps_touch_updated_at
before update on public.game_maps
for each row execute function private.deepmap_touch_updated_at();

-- 5. Privileges and RLS apply exclusively to the four new tables.
alter table public.games enable row level security;
alter table public.game_modules enable row level security;
alter table public.game_maps enable row level security;
alter table private.game_legacy_identifiers enable row level security;

revoke all on table public.games, public.game_modules, public.game_maps,
    private.game_legacy_identifiers from public, anon, authenticated;

grant select on table public.games, public.game_modules, public.game_maps
    to anon, authenticated;

grant insert, delete on table public.games, public.game_modules, public.game_maps
    to authenticated;

-- Permanent IDs/ownership and created_at cannot be changed through these grants.
-- updated_at is maintained by the triggers, not supplied by application clients.
grant update (slug, name, status) on public.games to authenticated;
grant update (enabled, position, settings) on public.game_modules to authenticated;
grant update (slug, name, status, position, is_default, settings)
    on public.game_maps to authenticated;

grant select, insert on table private.game_legacy_identifiers to authenticated;

-- Public games include coming-soon catalogue entries, but never drafts.
create policy games_public_read on public.games
for select to anon, authenticated
using (status in ('coming_soon', 'published'));

-- Use the existing role RPC instead of checking admin membership alone:
-- get_deepmap_role() also excludes suspended admins. Moderators do not qualify.
create policy games_admin_all on public.games
for all to authenticated
using ((select public.get_deepmap_role()) = 'admin')
with check ((select public.get_deepmap_role()) = 'admin');

create policy game_modules_public_read on public.game_modules
for select to anon, authenticated
using (
    enabled
    and exists (
        select 1 from public.games g
        where g.id = game_modules.game_id and g.status = 'published'
    )
);

create policy game_modules_admin_all on public.game_modules
for all to authenticated
using ((select public.get_deepmap_role()) = 'admin')
with check ((select public.get_deepmap_role()) = 'admin');

create policy game_maps_public_read on public.game_maps
for select to anon, authenticated
using (
    status = 'published'
    and exists (
        select 1 from public.games g
        where g.id = game_maps.game_id and g.status = 'published'
    )
    and exists (
        select 1 from public.game_modules m
        where m.game_id = game_maps.game_id and m.module_key = 'map' and m.enabled
    )
);

create policy game_maps_admin_all on public.game_maps
for all to authenticated
using ((select public.get_deepmap_role()) = 'admin')
with check ((select public.get_deepmap_role()) = 'admin');

create policy game_legacy_identifiers_admin_read on private.game_legacy_identifiers
for select to authenticated
using ((select public.get_deepmap_role()) = 'admin');

create policy game_legacy_identifiers_admin_insert on private.game_legacy_identifiers
for insert to authenticated
with check ((select public.get_deepmap_role()) = 'admin');

-- 6. Seed only new entities. No existing text references or layers are touched.
-- Prefer the stable legacy correspondence on a seed replay, even after a rename.
-- Never overwrite a configured game, module or map with ON CONFLICT DO UPDATE.
do $seed$
declare
    v_game_id uuid;
    v_alias_game_id uuid;
begin
    select game_id into v_game_id
    from private.game_legacy_identifiers
    where legacy_identifier = 'elden-ring';

    if v_game_id is null then
        insert into public.games (slug, name, status)
        values ('elden-ring', 'Elden Ring', 'published')
        on conflict (slug) do nothing
        returning id into v_game_id;

        if v_game_id is null then
            select id into v_game_id from public.games where slug = 'elden-ring';
        end if;

        if v_game_id is null then
            raise exception 'MULTIGAME_ELDEN_RING_ID_NOT_RESOLVED';
        end if;

        insert into private.game_legacy_identifiers (legacy_identifier, game_id)
        values ('elden-ring', v_game_id)
        on conflict (legacy_identifier) do nothing;

        select game_id into v_alias_game_id
        from private.game_legacy_identifiers
        where legacy_identifier = 'elden-ring';

        if v_alias_game_id is distinct from v_game_id then
            raise exception 'MULTIGAME_ELDEN_RING_LEGACY_MAPPING_CONFLICT';
        end if;
    end if;

    insert into public.game_modules (game_id, module_key, enabled, position)
    values
        (v_game_id, 'hub', true, 10),
        (v_game_id, 'map', true, 20),
        (v_game_id, 'content', true, 30),
        (v_game_id, 'playtime', false, 40),
        (v_game_id, 'community', false, 50)
    on conflict (game_id, module_key) do nothing;

    insert into public.game_maps (game_id, slug, name, status, position, is_default)
    values (v_game_id, 'world', 'World Map', 'published', 10, true)
    on conflict (game_id, slug) do nothing;
end;
$seed$;

commit;
