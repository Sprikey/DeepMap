-- DeepMap v1.0.31 — 04 | Public Profile Data
-- Public fields only. No email, auth provider or private account settings.
-- Profiles remain governed by the existing is_public RLS policy.

begin;

create schema if not exists private;

alter table public.profiles
    add column if not exists public_display_name text not null default 'Explorer',
    add column if not exists public_bio text not null default '',
    add column if not exists public_avatar_choice text not null default 'initial',
    add column if not exists public_avatar_path text,
    add column if not exists public_google_avatar_url text,
    add column if not exists joined_at timestamptz;

-- Build a limited, non-sensitive snapshot of user_metadata. Never use email
-- as a fallback public name and never copy user_metadata wholesale.
create or replace function private.profile_public_snapshot(
    p_user_id uuid,
    p_metadata jsonb
)
returns jsonb
language sql
stable
set search_path = ''
as $$
    select pg_catalog.jsonb_build_object(
        'display_name',
            pg_catalog.left(
                coalesce(
                    nullif(pg_catalog.btrim(p_metadata ->> 'display_name'), ''),
                    nullif(pg_catalog.btrim(p_metadata ->> 'full_name'), ''),
                    nullif(pg_catalog.btrim(p_metadata ->> 'name'), ''),
                    'Explorer'
                ),
                40
            ),
        'bio', pg_catalog.left(coalesce(p_metadata ->> 'bio', ''), 200),
        'avatar_choice',
            case
                when p_metadata ->> 'avatar_choice' in (
                    'explorador', 'cartografo', 'cavaleiro',
                    'feiticeiro', 'ladino', 'errante',
                    'custom', 'google', 'initial'
                ) then p_metadata ->> 'avatar_choice'
                when coalesce(p_metadata ->> 'avatar_url', p_metadata ->> 'picture')
                    ~ '^https://lh[0-9]+[.]googleusercontent[.]com/' then 'google'
                else 'initial'
            end,
        'avatar_path',
            case
                when p_metadata ->> 'avatar_custom_path' ~
                    ('^' || p_user_id::text || '/avatar-[0-9a-f-]{36}[.]webp$')
                then p_metadata ->> 'avatar_custom_path'
                else null
            end,
        'google_avatar_url',
            case
                when coalesce(p_metadata ->> 'avatar_url', p_metadata ->> 'picture')
                    ~ '^https://lh[0-9]+[.]googleusercontent[.]com/'
                then coalesce(p_metadata ->> 'avatar_url', p_metadata ->> 'picture')
                else null
            end
    );
$$;

-- Populate the public fields when a user picks a username for the first time.
create or replace function private.fill_public_profile_on_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    snapshot jsonb;
    account_created_at timestamptz;
begin
    select private.profile_public_snapshot(u.id, coalesce(u.raw_user_meta_data, '{}'::jsonb)),
           u.created_at
      into snapshot, account_created_at
      from auth.users u
     where u.id = new.id;

    if not found then
        raise exception 'profile_account_missing';
    end if;

    new.public_display_name := snapshot ->> 'display_name';
    new.public_bio := snapshot ->> 'bio';
    new.public_avatar_choice := snapshot ->> 'avatar_choice';
    new.public_avatar_path := snapshot ->> 'avatar_path';
    new.public_google_avatar_url := snapshot ->> 'google_avatar_url';
    new.joined_at := account_created_at;
    return new;
end;
$$;

drop trigger if exists deepmap_public_profile_insert on public.profiles;
create trigger deepmap_public_profile_insert
before insert on public.profiles
for each row
execute function private.fill_public_profile_on_insert();

-- Keep name, bio and avatar in sync when the owner edits their Auth metadata.
create or replace function private.sync_auth_public_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    snapshot jsonb;
begin
    snapshot := private.profile_public_snapshot(
        new.id,
        coalesce(new.raw_user_meta_data, '{}'::jsonb)
    );

    update public.profiles
       set public_display_name = snapshot ->> 'display_name',
           public_bio = snapshot ->> 'bio',
           public_avatar_choice = snapshot ->> 'avatar_choice',
           public_avatar_path = snapshot ->> 'avatar_path',
           public_google_avatar_url = snapshot ->> 'google_avatar_url'
     where id = new.id;

    return new;
end;
$$;

drop trigger if exists deepmap_auth_public_profile_sync on auth.users;
create trigger deepmap_auth_public_profile_sync
after update of raw_user_meta_data on auth.users
for each row
when (old.raw_user_meta_data is distinct from new.raw_user_meta_data)
execute function private.sync_auth_public_profile();

-- Backfill profiles that already exist. Does not change username or is_public.
update public.profiles p
   set public_display_name = snapshot.data ->> 'display_name',
       public_bio = snapshot.data ->> 'bio',
       public_avatar_choice = snapshot.data ->> 'avatar_choice',
       public_avatar_path = snapshot.data ->> 'avatar_path',
       public_google_avatar_url = snapshot.data ->> 'google_avatar_url',
       joined_at = u.created_at
  from auth.users u
  cross join lateral (
      select private.profile_public_snapshot(
          u.id, coalesce(u.raw_user_meta_data, '{}'::jsonb)
      ) as data
  ) snapshot
 where p.id = u.id;

-- Only the established owner-controlled fields may be edited by clients.
revoke update on table public.profiles from public, anon, authenticated;
grant update (username, is_public) on table public.profiles to authenticated;

-- No direct Data API access to the privileged trigger functions.
revoke all on function private.profile_public_snapshot(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.fill_public_profile_on_insert() from public, anon, authenticated;
revoke all on function private.sync_auth_public_profile() from public, anon, authenticated;

commit;
