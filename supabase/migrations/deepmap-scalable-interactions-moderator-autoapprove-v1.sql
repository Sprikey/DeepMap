-- DeepMap — scalable interaction gate + moderator self-approval
-- Run after deepmap-admin-global-moderation-v2.sql.

begin;

-- One reusable permission check for every future interactive feature
-- (markers, comments, guides, follows, uploads, reports, etc.).
create or replace function public.can_deepmap_interact()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select (select auth.uid()) is not null
       and not private.is_deepmap_banned();
$$;

revoke all on function public.can_deepmap_interact() from public, anon, authenticated;
grant execute on function public.can_deepmap_interact() to authenticated;

-- Moderators are trusted reviewers. Their own marker submissions are therefore
-- approved immediately instead of entering the queue they themselves moderate.
create or replace function private.deepmap_autoapprove_moderator_submission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.status = 'pending'
       and new.submitted_by = (select auth.uid())
       and private.is_deepmap_moderator()
       and private.can_moderate_deepmap()
       and pg_trigger_depth() = 1 then
        if new.submission_type = 'create' then
            -- v2 applies the full reviewed payload, including quick content rows.
            perform public.review_marker_submission_v2(new.id, 'approved', null, new.payload);
        else
            -- Corrections deliberately use the scoped payload handled by v1.
            perform public.review_marker_submission(new.id, 'approved', null);
        end if;
    end if;

    return new;
end;
$$;

revoke all on function private.deepmap_autoapprove_moderator_submission()
from public, anon, authenticated;

drop trigger if exists marker_submissions_autoapprove_moderator_insert
on public.marker_submissions;

create trigger marker_submissions_autoapprove_moderator_insert
after insert on public.marker_submissions
for each row
execute function private.deepmap_autoapprove_moderator_submission();

-- Covers a moderator editing one of their older pending submissions created
-- before this migration. Status-only updates made by the review function do
-- not retrigger this trigger.
drop trigger if exists marker_submissions_autoapprove_moderator_update
on public.marker_submissions;

create trigger marker_submissions_autoapprove_moderator_update
after update of payload, note, correction_kind on public.marker_submissions
for each row
when (new.status = 'pending')
execute function private.deepmap_autoapprove_moderator_submission();

commit;
