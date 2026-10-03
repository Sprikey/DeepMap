-- DeepMap Map Editor 2.0 — Marker audit / publisher attribution
-- Keeps editor/moderator identity outside public.marcadores.
-- Public users cannot query this table; admins access it through a narrow RPC.

begin;

create schema if not exists private;

create table if not exists private.marker_editor_audit (
    marker_id bigint primary key
        references public.marcadores(id)
        on delete cascade,

    created_by uuid,
    created_at timestamptz,

    updated_by uuid,
    updated_at timestamptz,

    published_by uuid,
    published_at timestamptz
);

alter table private.marker_editor_audit enable row level security;

revoke all on table private.marker_editor_audit
from public, anon, authenticated;

create or replace function private.deepmap_stamp_marker_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := (select auth.uid());
begin
    if tg_op = 'INSERT' then
        insert into private.marker_editor_audit as audit (
            marker_id,
            created_by,
            created_at,
            updated_by,
            updated_at,
            published_by,
            published_at
        )
        values (
            new.id,
            v_user_id,
            now(),
            v_user_id,
            now(),
            case when new.is_published then v_user_id else null end,
            case when new.is_published then now() else null end
        )
        on conflict (marker_id) do update
        set
            updated_by = excluded.updated_by,
            updated_at = excluded.updated_at,
            published_by = case
                when new.is_published then coalesce(audit.published_by, excluded.published_by)
                else audit.published_by
            end,
            published_at = case
                when new.is_published then coalesce(audit.published_at, excluded.published_at)
                else audit.published_at
            end;

        return new;
    end if;

    insert into private.marker_editor_audit as audit (
        marker_id,
        created_by,
        created_at,
        updated_by,
        updated_at,
        published_by,
        published_at
    )
    values (
        new.id,
        null,
        null,
        v_user_id,
        now(),
        case when new.is_published then v_user_id else null end,
        case when new.is_published then now() else null end
    )
    on conflict (marker_id) do update
    set
        updated_by = v_user_id,
        updated_at = now(),
        published_by = case
            when new.is_published
                 and (
                     old.is_published = false
                     or old.is_published is null
                     or audit.published_by is null
                 )
                then v_user_id
            else audit.published_by
        end,
        published_at = case
            when new.is_published
                 and (
                     old.is_published = false
                     or old.is_published is null
                     or audit.published_at is null
                 )
                then now()
            else audit.published_at
        end;

    return new;
end;
$$;

revoke all on function private.deepmap_stamp_marker_audit()
from public, anon, authenticated;

-- AFTER trigger: new.id already exists for identity-generated markers.
drop trigger if exists deepmap_marker_editor_audit
on public.marcadores;

create trigger deepmap_marker_editor_audit
after insert or update on public.marcadores
for each row
execute function private.deepmap_stamp_marker_audit();

-- Admin-only audit read. Usernames are resolved from immutable profile UUIDs,
-- so changing @username never makes an old handle point at the wrong account.
create or replace function public.get_marker_editor_audit(p_game_id text)
returns table (
    marker_id bigint,
    created_by uuid,
    created_username text,
    created_at timestamptz,
    updated_by uuid,
    updated_username text,
    updated_at timestamptz,
    published_by uuid,
    published_username text,
    published_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        a.marker_id,
        a.created_by,
        pc.username as created_username,
        a.created_at,
        a.updated_by,
        pu.username as updated_username,
        a.updated_at,
        a.published_by,
        pp.username as published_username,
        a.published_at
    from private.marker_editor_audit as a
    join public.marcadores as m
      on m.id = a.marker_id
    left join public.profiles as pc
      on pc.id = a.created_by
    left join public.profiles as pu
      on pu.id = a.updated_by
    left join public.profiles as pp
      on pp.id = a.published_by
    where m.game_id = p_game_id
      and private.is_deepmap_admin();
$$;

revoke all on function public.get_marker_editor_audit(text)
from public, anon, authenticated;

grant execute on function public.get_marker_editor_audit(text)
to authenticated;

commit;
