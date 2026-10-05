-- DeepMap — Round 10A: guaranteed usernames, admin search semantics and contribution identity guard
-- Apply directly in Supabase SQL Editor after Round 9/current schema.
-- This file remains in the existing supabase/migrations folder as the record of the deployed change.

begin;

create schema if not exists private;

-- =========================================================
-- 1. EVERY AUTH ACCOUNT GETS A SAFE GENERATED @USERNAME
-- =========================================================

alter table public.profiles
    add column if not exists username_changed_at timestamptz,
    add column if not exists username_is_generated boolean not null default false;

create table if not exists private.deepmap_username_reservations (
    username text primary key,
    reserved_for uuid,
    reserved_until timestamptz not null
);

alter table private.deepmap_username_reservations enable row level security;
revoke all on table private.deepmap_username_reservations from public, anon, authenticated;

create or replace function private.deepmap_generated_username()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_candidate text;
    v_attempt integer := 0;
begin
    loop
        v_attempt := v_attempt + 1;
        -- 10 random digits keeps the generated handle inside the existing 20-char limit
        -- while avoiding useful human-picked handles.
        v_candidate := 'explorer_' || lpad((floor(random() * 10000000000))::bigint::text, 10, '0');

        if not exists (
            select 1 from public.profiles p where p.username = v_candidate
        ) and not exists (
            select 1
              from private.deepmap_username_reservations r
             where r.username = v_candidate
               and r.reserved_until > now()
        ) then
            return v_candidate;
        end if;

        if v_attempt >= 50 then
            raise exception 'USERNAME_GENERATION_FAILED' using errcode = 'P0001';
        end if;
    end loop;
end;
$$;

revoke all on function private.deepmap_generated_username() from public, anon, authenticated;

create or replace function private.deepmap_create_profile_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not exists (select 1 from public.profiles p where p.id = new.id) then
        insert into public.profiles (id, username, username_is_generated)
        values (new.id, private.deepmap_generated_username(), true);
    end if;
    return new;
end;
$$;

revoke all on function private.deepmap_create_profile_for_auth_user() from public, anon, authenticated;

drop trigger if exists deepmap_auth_create_profile on auth.users;
create trigger deepmap_auth_create_profile
after insert on auth.users
for each row
execute function private.deepmap_create_profile_for_auth_user();

-- Backfill every account that predates automatic profile creation.
do $$
declare
    v_user record;
begin
    for v_user in
        select u.id
          from auth.users u
          left join public.profiles p on p.id = u.id
         where p.id is null
         order by u.created_at, u.id
    loop
        insert into public.profiles (id, username, username_is_generated)
        values (v_user.id, private.deepmap_generated_username(), true)
        on conflict (id) do nothing;
    end loop;
end;
$$;

-- Self-healing entry point used before community writes. It never accepts a
-- foreign user id: the authenticated account can only ensure its own profile.
create or replace function public.ensure_deepmap_profile()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := (select auth.uid());
    v_username text;
begin
    if v_user_id is null then
        raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
    end if;

    select p.username into v_username
      from public.profiles p
     where p.id = v_user_id;

    if v_username is null then
        insert into public.profiles (id, username, username_is_generated)
        values (v_user_id, private.deepmap_generated_username(), true)
        on conflict (id) do nothing;

        select p.username into v_username
          from public.profiles p
         where p.id = v_user_id;
    end if;

    if v_username is null then
        raise exception 'USERNAME_REQUIRED' using errcode = 'P0001';
    end if;

    return v_username;
end;
$$;

revoke all on function public.ensure_deepmap_profile() from public, anon, authenticated;
grant execute on function public.ensure_deepmap_profile() to authenticated;

-- =========================================================
-- 2. GENERATED HANDLE DOES NOT COUNT AS THE USER'S FIRST CHOICE
--    + KEEP THE EXISTING 30-DAY / 1-HOUR RULE SERVER-SIDE
-- =========================================================

create or replace function private.deepmap_username_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_candidate text := lower(btrim(new.username));
begin
    if new.username is not distinct from old.username then
        return new;
    end if;

    if v_candidate !~ '^[a-z0-9_]{3,20}$' then
        raise exception 'username_format' using errcode = 'P0001';
    end if;

    if v_candidate in (
        'admin','administrator','deepmap','official','moderator','support',
        'staff','system','root','contact','help'
    ) then
        raise exception 'username_reserved' using errcode = 'P0001';
    end if;

    delete from private.deepmap_username_reservations
     where reserved_until <= now();

    if exists (
        select 1
          from private.deepmap_username_reservations r
         where r.username = v_candidate
           and r.reserved_until > now()
           and r.reserved_for is distinct from old.id
    ) then
        raise exception 'username_temporarily_reserved' using errcode = 'P0001';
    end if;

    new.username := v_candidate;
    new.username_is_generated := false;

    if coalesce(old.username_is_generated, false) then
        -- explorer_########## is only a placeholder. The first human-picked
        -- handle remains the initial choice and starts no cooldown.
        new.username_changed_at := null;
    else
        if old.username_changed_at is not null
           and old.username_changed_at > now() - interval '30 days' then
            raise exception 'username_cooldown' using errcode = 'P0001';
        end if;

        insert into private.deepmap_username_reservations (username, reserved_for, reserved_until)
        values (old.username, old.id, now() + interval '1 hour')
        on conflict (username) do update
        set reserved_for = excluded.reserved_for,
            reserved_until = excluded.reserved_until;

        new.username_changed_at := now();
    end if;

    return new;
end;
$$;

revoke all on function private.deepmap_username_guard() from public, anon, authenticated;

-- Prefix zz_ intentionally makes this guard run after older BEFORE UPDATE
-- username triggers, so the generated first-choice exception wins cleanly.
drop trigger if exists zz_deepmap_username_guard on public.profiles;
create trigger zz_deepmap_username_guard
before update of username on public.profiles
for each row
execute function private.deepmap_username_guard();

create or replace function public.username_availability(p_username text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_candidate text := lower(btrim(coalesce(p_username, '')));
    v_user_id uuid := (select auth.uid());
begin
    if v_candidate !~ '^[a-z0-9_]{3,20}$' then
        return 'taken';
    end if;

    if exists (
        select 1
          from public.profiles p
         where p.username = v_candidate
           and p.id is distinct from v_user_id
    ) then
        return 'taken';
    end if;

    if exists (
        select 1
          from private.deepmap_username_reservations r
         where r.username = v_candidate
           and r.reserved_until > now()
           and r.reserved_for is distinct from v_user_id
    ) then
        return 'held';
    end if;

    return 'available';
end;
$$;

revoke all on function public.username_availability(text) from public, anon, authenticated;
grant execute on function public.username_availability(text) to authenticated;

create or replace function public.set_deepmap_username(p_username text)
returns table (
    username text,
    username_changed_at timestamptz,
    username_is_generated boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := (select auth.uid());
    v_candidate text := lower(btrim(coalesce(p_username, '')));
begin
    if v_user_id is null then
        raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
    end if;

    perform public.ensure_deepmap_profile();

    if v_candidate !~ '^[a-z0-9_]{3,20}$' then
        raise exception 'username_format' using errcode = 'P0001';
    end if;

    -- The table trigger is the authoritative validator/cooldown guard.
    update public.profiles p
       set username = v_candidate
     where p.id = v_user_id;

    return query
    select p.username, p.username_changed_at, p.username_is_generated
      from public.profiles p
     where p.id = v_user_id;
end;
$$;

revoke all on function public.set_deepmap_username(text) from public, anon, authenticated;
grant execute on function public.set_deepmap_username(text) to authenticated;

-- =========================================================
-- 3. COMMUNITY WRITES REQUIRE A REAL PROFILE/@USERNAME
-- =========================================================

drop policy if exists "marker_submissions_insert_own" on public.marker_submissions;
create policy "marker_submissions_insert_own"
on public.marker_submissions
for insert
to authenticated
with check (
    public.can_deepmap_interact()
    and submitted_by = (select auth.uid())
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
    and review_note is null
    and exists (
        select 1
          from public.profiles p
         where p.id = (select auth.uid())
           and nullif(btrim(p.username), '') is not null
    )
);

-- =========================================================
-- 4. ADMIN USER SEARCH
--    @handle => exact username
--    text    => contains username OR public display name
-- =========================================================

drop function if exists public.get_deepmap_users(text, text, integer, integer);
create function public.get_deepmap_users(
    p_role_filter text default 'all',
    p_search text default null,
    p_limit integer default 20,
    p_offset integer default 0
)
returns table (
    user_id uuid,
    username text,
    display_name text,
    joined_at timestamptz,
    role text,
    contribution_count bigint,
    pending_count bigint,
    approved_count bigint,
    rejected_count bigint,
    is_banned boolean,
    ban_reason text,
    ban_expires_at timestamptz,
    total_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_search text := lower(btrim(coalesce(p_search, '')));
    v_exact_username boolean := left(v_search, 1) = '@';
    v_term text := case when left(v_search, 1) = '@' then substring(v_search from 2) else v_search end;
begin
    if not private.is_deepmap_admin() then
        raise exception 'ADMIN_REQUIRED' using errcode = 'P0001';
    end if;
    if p_role_filter not in ('all','user','moderator') then
        raise exception 'INVALID_ROLE_FILTER' using errcode = 'P0001';
    end if;

    return query
    select
        p.id,
        p.username,
        p.public_display_name,
        p.joined_at,
        case when a.user_id is not null then 'admin' when m.user_id is not null then 'moderator' else 'user' end,
        count(s.id)::bigint,
        count(s.id) filter (where s.status='pending')::bigint,
        count(s.id) filter (where s.status='approved')::bigint,
        count(s.id) filter (where s.status='rejected')::bigint,
        (b.user_id is not null),
        b.reason,
        b.expires_at,
        count(*) over()
    from public.profiles p
    left join private.deepmap_admins a on a.user_id=p.id
    left join private.deepmap_moderators m on m.user_id=p.id
    left join public.marker_submissions s on s.submitted_by=p.id
    left join private.deepmap_bans b
      on b.user_id=p.id
     and b.lifted_at is null
     and (b.expires_at is null or b.expires_at > now())
    where (
        v_term = ''
        or (
            v_exact_username
            and lower(p.username) = v_term
        )
        or (
            not v_exact_username
            and (
                lower(p.username) like '%' || v_term || '%'
                or lower(coalesce(p.public_display_name, '')) like '%' || v_term || '%'
            )
        )
    ) and (
        p_role_filter='all'
        or (p_role_filter='user' and a.user_id is null and m.user_id is null)
        or (p_role_filter='moderator' and a.user_id is null and m.user_id is not null)
    )
    group by p.id,p.username,p.public_display_name,p.joined_at,a.user_id,m.user_id,b.user_id,b.reason,b.expires_at
    order by case when a.user_id is not null then 0 when m.user_id is not null then 1 else 2 end, p.username asc
    limit greatest(1,least(coalesce(p_limit,20),100))
    offset greatest(coalesce(p_offset,0),0);
end;
$$;

revoke all on function public.get_deepmap_users(text, text, integer, integer) from public, anon, authenticated;
grant execute on function public.get_deepmap_users(text, text, integer, integer) to authenticated;


-- =========================================================
-- 5. MODERATION HISTORY — LOAD REVISIONS ONLY WHEN EXPANDED
-- =========================================================

create or replace function public.get_marker_submission_revisions(p_submission_id bigint)
returns table (
    revision_no integer,
    edited_by uuid,
    edited_username text,
    payload jsonb,
    note text,
    created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    if not private.can_moderate_deepmap() then
        raise exception 'MODERATOR_REQUIRED' using errcode = 'P0001';
    end if;

    if not exists (
        select 1 from public.marker_submissions s where s.id = p_submission_id
    ) then
        raise exception 'SUBMISSION_NOT_FOUND' using errcode = 'P0001';
    end if;

    return query
    select
        r.revision_no,
        r.edited_by,
        p.username,
        r.payload,
        r.note,
        r.created_at
    from private.marker_submission_revisions r
    left join public.profiles p on p.id = r.edited_by
    where r.submission_id = p_submission_id
    order by r.revision_no asc;
end;
$$;

revoke all on function public.get_marker_submission_revisions(bigint) from public, anon, authenticated;
grant execute on function public.get_marker_submission_revisions(bigint) to authenticated;

commit;
