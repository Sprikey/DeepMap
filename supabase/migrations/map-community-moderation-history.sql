-- DeepMap — Community moderation pagination + duplicate pending correction guard
-- Adds server-side history pagination and prevents a user from keeping more than
-- one pending correction for the same marker.

begin;

create unique index if not exists marker_submissions_one_pending_correction_per_marker_idx
    on public.marker_submissions (game_id, marker_id, submitted_by)
    where status = 'pending'
      and submission_type = 'correction'
      and marker_id is not null;

create or replace function public.get_marker_submissions_page(
    p_game_id text,
    p_status text default 'pending',
    p_limit integer default 10,
    p_offset integer default 0
)
returns table (
    id bigint,
    game_id text,
    marker_id bigint,
    submission_type text,
    correction_kind text,
    status text,
    submitted_by uuid,
    submitted_username text,
    payload jsonb,
    note text,
    reviewed_by uuid,
    reviewed_username text,
    reviewed_at timestamptz,
    review_note text,
    created_at timestamptz,
    updated_at timestamptz,
    revision_count integer,
    total_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    if not private.is_deepmap_admin() then
        raise exception 'ADMIN_REQUIRED' using errcode = 'P0001';
    end if;

    if p_status not in ('pending', 'approved', 'rejected') then
        raise exception 'INVALID_STATUS' using errcode = 'P0001';
    end if;

    return query
    select
        s.id,
        s.game_id,
        s.marker_id,
        s.submission_type,
        s.correction_kind,
        s.status,
        s.submitted_by,
        submitter.username as submitted_username,
        s.payload,
        s.note,
        s.reviewed_by,
        reviewer.username as reviewed_username,
        s.reviewed_at,
        s.review_note,
        s.created_at,
        s.updated_at,
        (
            select count(*)::integer
            from private.marker_submission_revisions as r
            where r.submission_id = s.id
        ) as revision_count,
        count(*) over() as total_count
    from public.marker_submissions as s
    left join public.profiles as submitter
      on submitter.id = s.submitted_by
    left join public.profiles as reviewer
      on reviewer.id = s.reviewed_by
    where s.game_id = p_game_id
      and s.status = p_status
    order by
        case when p_status = 'pending' then s.updated_at else coalesce(s.reviewed_at, s.updated_at) end desc,
        s.id desc
    limit greatest(1, least(coalesce(p_limit, 10), 100))
    offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.get_marker_submissions_page(text, text, integer, integer)
from public, anon, authenticated;

grant execute on function public.get_marker_submissions_page(text, text, integer, integer)
to authenticated;

commit;
