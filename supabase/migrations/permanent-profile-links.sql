-- DeepMap v1.0.31 — 06 | Permanent Profile Links
-- Prerequisites: 03 Profile Visibility, 04 Public Profile Data, 05 Private Profile Identity.
-- Only returns the CURRENT @username for an immutable profile UUID.
-- A private profile's minimal public identity is already allowed by query 05.
-- Does not expose email, auth.users, bio, settings or other private fields.

begin;

create schema if not exists private;

-- Privileged implementation in a schema NOT exposed by the Data API.
create or replace function private.current_profile_username_by_id(p_profile_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
    select p.username
      from public.profiles as p
     where p.id = p_profile_id
     limit 1;
$$;

-- Narrow public entry point; only returns a username or null.
create or replace function public.get_profile_username_by_id(p_profile_id uuid)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
    select private.current_profile_username_by_id(p_profile_id);
$$;

revoke all on function private.current_profile_username_by_id(uuid)
    from public, anon, authenticated;
revoke all on function public.get_profile_username_by_id(uuid)
    from public, anon, authenticated;

grant usage on schema private to anon, authenticated;
grant execute on function private.current_profile_username_by_id(uuid)
    to anon, authenticated;
grant execute on function public.get_profile_username_by_id(uuid)
    to anon, authenticated;

commit;
