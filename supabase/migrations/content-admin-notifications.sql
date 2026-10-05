-- DeepMap — Round 9: optional Portuguese content + admin operational notifications
-- Apply this file directly in Supabase SQL Editor after Round 8/current schema.
-- This file is part of the existing supabase/migrations history.

begin;

-- =========================================================
-- 1. PORTUGUESE MARKER TITLE IS OPTIONAL
-- =========================================================

alter table public.marcadores
    alter column title_pt drop not null;

-- Existing English copies created only to satisfy the old NOT NULL rule are
-- intentionally left untouched: we cannot safely distinguish them from valid
-- titles that genuinely match in both languages. They can be cleaned manually
-- later while editing content.

-- =========================================================
-- 2. MODERATION FUNCTIONS PRESERVE OPTIONAL PT
-- =========================================================

create or replace function public.review_marker_submission(
    p_submission_id bigint,
    p_decision text,
    p_review_note text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_submission public.marker_submissions%rowtype;
    v_admin uuid := (select auth.uid());
    v_marker_id bigint;
    v_slug text;
    v_image_url text;
    v_sort_order integer;
begin
    if not private.can_moderate_deepmap() then
        raise exception 'ADMIN_REQUIRED' using errcode = 'P0001';
    end if;

    if p_decision not in ('approved', 'rejected') then
        raise exception 'INVALID_DECISION' using errcode = 'P0001';
    end if;

    select *
      into v_submission
      from public.marker_submissions
     where id = p_submission_id
     for update;

    if not found then
        raise exception 'SUBMISSION_NOT_FOUND' using errcode = 'P0001';
    end if;

    if v_submission.status <> 'pending' then
        raise exception 'SUBMISSION_NOT_PENDING' using errcode = 'P0001';
    end if;

    if p_decision = 'rejected' then
        update public.marker_submissions
           set status = 'rejected',
               reviewed_by = v_admin,
               reviewed_at = now(),
               review_note = nullif(btrim(p_review_note), '')
         where id = p_submission_id;
        return v_submission.marker_id;
    end if;

    if v_submission.submission_type = 'create' then
        if nullif(btrim(v_submission.payload->>'category_id'), '') is null
           or nullif(btrim(v_submission.payload->>'title_en'), '') is null
           or (v_submission.payload->>'coordinate_x') is null
           or (v_submission.payload->>'coordinate_y') is null then
            raise exception 'SUBMISSION_INCOMPLETE' using errcode = 'P0001';
        end if;

        v_slug := private.deepmap_unique_marker_slug(
            v_submission.game_id,
            v_submission.payload->>'title_en'
        );

        insert into public.marcadores (
            game_id,
            map_layer,
            slug,
            category_id,
            region_id,
            title_en,
            title_pt,
            coordinate_x,
            coordinate_y,
            description_en,
            description_pt,
            video_url,
            is_published
        ) values (
            v_submission.game_id,
            coalesce(nullif(btrim(v_submission.payload->>'map_layer'), ''), 'surface'),
            v_slug,
            btrim(v_submission.payload->>'category_id'),
            nullif(btrim(v_submission.payload->>'region_id'), ''),
            btrim(v_submission.payload->>'title_en'),
            nullif(btrim(v_submission.payload->>'title_pt'), ''),
            (v_submission.payload->>'coordinate_x')::double precision,
            (v_submission.payload->>'coordinate_y')::double precision,
            nullif(btrim(v_submission.payload->>'description_en'), ''),
            nullif(btrim(v_submission.payload->>'description_pt'), ''),
            nullif(btrim(v_submission.payload->>'video_url'), ''),
            true
        )
        returning id into v_marker_id;

        -- Replace trigger attribution with the community author + current approver.
        insert into private.marker_editor_audit as audit (
            marker_id,
            created_by,
            created_at,
            updated_by,
            updated_at,
            published_by,
            published_at,
            approved_by,
            approved_at
        ) values (
            v_marker_id,
            v_submission.submitted_by,
            now(),
            v_submission.submitted_by,
            now(),
            v_admin,
            now(),
            v_admin,
            now()
        )
        on conflict (marker_id) do update
        set
            created_by = excluded.created_by,
            created_at = coalesce(audit.created_at, excluded.created_at),
            updated_by = excluded.updated_by,
            updated_at = excluded.updated_at,
            published_by = excluded.published_by,
            published_at = coalesce(audit.published_at, excluded.published_at),
            approved_by = excluded.approved_by,
            approved_at = excluded.approved_at;

        v_image_url := nullif(btrim(v_submission.payload->>'image_url'), '');
        if v_image_url is not null then
            insert into public.marker_images (
                marker_id,
                source,
                image_ref,
                sort_order,
                is_cover
            ) values (
                v_marker_id,
                case when v_image_url like '/%' then 'static' else 'external' end,
                v_image_url,
                10,
                true
            );
        end if;

        update public.marker_submissions
           set marker_id = v_marker_id
         where id = p_submission_id;

    else
        v_marker_id := v_submission.marker_id;

        if not exists (
            select 1 from public.marcadores as m
            where m.id = v_marker_id
              and m.game_id = v_submission.game_id
        ) then
            raise exception 'TARGET_MARKER_NOT_FOUND' using errcode = 'P0001';
        end if;

        if v_submission.correction_kind = 'text' then
            update public.marcadores
               set title_en = case when v_submission.payload ? 'title_en' then coalesce(nullif(btrim(v_submission.payload->>'title_en'), ''), title_en) else title_en end,
                   title_pt = case when v_submission.payload ? 'title_pt' then nullif(btrim(v_submission.payload->>'title_pt'), '') else title_pt end,
                   region_id = case when v_submission.payload ? 'region_id' then nullif(btrim(v_submission.payload->>'region_id'), '') else region_id end,
                   description_en = case when v_submission.payload ? 'description_en' then nullif(btrim(v_submission.payload->>'description_en'), '') else description_en end,
                   description_pt = case when v_submission.payload ? 'description_pt' then nullif(btrim(v_submission.payload->>'description_pt'), '') else description_pt end,
                   video_url = case when v_submission.payload ? 'video_url' then nullif(btrim(v_submission.payload->>'video_url'), '') else video_url end
             where id = v_marker_id;

        elsif v_submission.correction_kind = 'location' then
            update public.marcadores
               set coordinate_x = coalesce(nullif(v_submission.payload->>'coordinate_x', '')::double precision, coordinate_x),
                   coordinate_y = coalesce(nullif(v_submission.payload->>'coordinate_y', '')::double precision, coordinate_y)
             where id = v_marker_id;

        elsif v_submission.correction_kind = 'image' then
            v_image_url := nullif(btrim(v_submission.payload->>'image_url'), '');

            if coalesce(v_submission.payload->>'image_action', 'add') = 'report' then
                if nullif(v_submission.payload->>'target_image_id', '') is null then
                    raise exception 'IMAGE_TARGET_REQUIRED' using errcode = 'P0001';
                end if;

                delete from public.marker_images
                 where id = (v_submission.payload->>'target_image_id')::bigint
                   and marker_id = v_marker_id;
            elsif v_image_url is not null then
                select coalesce(max(mi.sort_order), 0) + 10
                  into v_sort_order
                  from public.marker_images as mi
                 where mi.marker_id = v_marker_id;

                insert into public.marker_images (
                    marker_id,
                    source,
                    image_ref,
                    sort_order,
                    is_cover
                ) values (
                    v_marker_id,
                    case when v_image_url like '/%' then 'static' else 'external' end,
                    v_image_url,
                    v_sort_order,
                    false
                );
            end if;
        end if;

        -- Only accepted content changes renew public modification/approval attribution.
        if v_submission.correction_kind in ('text', 'location', 'image') then
            insert into private.marker_editor_audit as audit (
                marker_id,
                updated_by,
                updated_at,
                approved_by,
                approved_at
            ) values (
                v_marker_id,
                v_submission.submitted_by,
                now(),
                v_admin,
                now()
            )
            on conflict (marker_id) do update
            set
                updated_by = excluded.updated_by,
                updated_at = excluded.updated_at,
                approved_by = excluded.approved_by,
                approved_at = excluded.approved_at;
        end if;
    end if;

    update public.marker_submissions
       set status = 'approved',
           reviewed_by = v_admin,
           reviewed_at = now(),
           review_note = nullif(btrim(p_review_note), '')
     where id = p_submission_id;

    return v_marker_id;
end;
$$;

create or replace function public.review_marker_submission_v2(
    p_submission_id bigint,
    p_decision text,
    p_review_note text default null,
    p_payload_override jsonb default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_admin uuid := (select auth.uid());
    v_marker_id bigint;
    v_payload jsonb;
begin
    if not private.can_moderate_deepmap() then
        raise exception 'ADMIN_REQUIRED' using errcode = 'P0001';
    end if;

    if p_decision not in ('approved', 'rejected') then
        raise exception 'INVALID_DECISION' using errcode = 'P0001';
    end if;

    if p_decision = 'approved' and p_payload_override is not null then
        update public.marker_submissions
           set payload = p_payload_override
         where id = p_submission_id
           and status = 'pending';

        if not found then
            raise exception 'SUBMISSION_NOT_PENDING' using errcode = 'P0001';
        end if;
    end if;

    v_marker_id := public.review_marker_submission(
        p_submission_id,
        p_decision,
        p_review_note
    );

    if p_decision <> 'approved' or p_payload_override is null or v_marker_id is null then
        return v_marker_id;
    end if;

    v_payload := p_payload_override;

    if nullif(btrim(v_payload->>'category_id'), '') is null
       or nullif(btrim(v_payload->>'title_en'), '') is null
       or (v_payload->>'coordinate_x') is null
       or (v_payload->>'coordinate_y') is null then
        raise exception 'SUBMISSION_INCOMPLETE' using errcode = 'P0001';
    end if;

    -- Apply the moderator's final reviewed version as one complete marker state.
    update public.marcadores
       set map_layer = coalesce(nullif(btrim(v_payload->>'map_layer'), ''), map_layer),
           category_id = btrim(v_payload->>'category_id'),
           region_id = nullif(btrim(v_payload->>'region_id'), ''),
           title_en = btrim(v_payload->>'title_en'),
           title_pt = nullif(btrim(v_payload->>'title_pt'), ''),
           coordinate_x = (v_payload->>'coordinate_x')::double precision,
           coordinate_y = (v_payload->>'coordinate_y')::double precision,
           description_en = nullif(btrim(v_payload->>'description_en'), ''),
           description_pt = nullif(btrim(v_payload->>'description_pt'), ''),
           video_url = nullif(btrim(v_payload->>'video_url'), '')
     where id = v_marker_id;

    perform private.deepmap_replace_quick_marker_content(
        v_marker_id,
        v_payload->'content_items'
    );

    -- The marker audit trigger records the moderator as last editor when the
    -- reviewed version differs from the submitted one. Re-stamp approval after
    -- that update so the admin audit remains complete.
    update private.marker_editor_audit
       set approved_by = v_admin,
           approved_at = now()
     where marker_id = v_marker_id;

    return v_marker_id;
end;
$$;



revoke all on function public.review_marker_submission(bigint, text, text)
from public, anon, authenticated;
grant execute on function public.review_marker_submission(bigint, text, text)
to authenticated;

revoke all on function public.review_marker_submission_v2(bigint, text, text, jsonb)
from public, anon, authenticated;
grant execute on function public.review_marker_submission_v2(bigint, text, text, jsonb)
to authenticated;

-- =========================================================
-- 3. ADMIN OPERATIONAL NOTIFICATIONS
-- =========================================================

alter table public.user_notifications
    drop constraint if exists user_notifications_kind_check;

alter table public.user_notifications
    add constraint user_notifications_kind_check check (
        (kind = 'submission_review'
            and submission_type in ('create','correction')
            and decision in ('approved','rejected'))
        or (kind in ('moderator_granted','moderator_revoked','account_suspended','account_reinstated')
            and submission_type is null
            and decision is null)
        or (kind = 'admin_submission_received'
            and submission_type in ('create','correction')
            and decision is null)
        or (kind = 'admin_moderation_decision'
            and submission_type in ('create','correction')
            and decision in ('approved','rejected'))
    );

create unique index if not exists user_notifications_user_submission_kind_uidx
    on public.user_notifications (user_id, submission_id, kind)
    where submission_id is not null;

create or replace function private.deepmap_notify_admin_submission_received()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_submitted_username text;
begin
    -- Staff submissions do not need a "waiting for moderation" admin alert.
    -- Moderators self-approve and admins use the map editor.
    if exists (
        select 1 from private.deepmap_admins a where a.user_id = new.submitted_by
    ) or exists (
        select 1 from private.deepmap_moderators m where m.user_id = new.submitted_by
    ) then
        return new;
    end if;

    select p.username
      into v_submitted_username
      from public.profiles p
     where p.id = new.submitted_by;

    insert into public.user_notifications (
        user_id,
        kind,
        game_id,
        submission_id,
        marker_id,
        submission_type,
        metadata
    )
    select
        a.user_id,
        'admin_submission_received',
        new.game_id,
        new.id,
        new.marker_id,
        new.submission_type,
        jsonb_build_object(
            'submitted_by', new.submitted_by,
            'submitted_username', v_submitted_username
        )
    from private.deepmap_admins a
    where a.user_id is distinct from new.submitted_by
    on conflict (user_id, submission_id, kind)
    where submission_id is not null
    do update set
        game_id = excluded.game_id,
        marker_id = excluded.marker_id,
        submission_type = excluded.submission_type,
        metadata = excluded.metadata,
        created_at = now(),
        is_read = false;

    return new;
end;
$$;

revoke all on function private.deepmap_notify_admin_submission_received()
from public, anon, authenticated;

drop trigger if exists deepmap_notify_admin_submission_received
on public.marker_submissions;

create trigger deepmap_notify_admin_submission_received
after insert on public.marker_submissions
for each row
execute function private.deepmap_notify_admin_submission_received();

-- Keep the contributor notification and add an operational notification for
-- admins whenever a moderator (not an admin) makes the decision.
create or replace function private.deepmap_notify_submission_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_reviewer_username text;
begin
    if old.status = 'pending'
       and new.status in ('approved', 'rejected') then

        -- Contributor result notification. A moderator whose own submission
        -- auto-approved does not need a notification about their own action.
        if new.submitted_by is distinct from new.reviewed_by then
            insert into public.user_notifications (
                user_id,
                kind,
                game_id,
                submission_id,
                marker_id,
                submission_type,
                decision,
                review_note
            ) values (
                new.submitted_by,
                'submission_review',
                new.game_id,
                new.id,
                new.marker_id,
                new.submission_type,
                new.status,
                new.review_note
            )
            on conflict (user_id, submission_id, decision)
            where submission_id is not null
            do update set
                marker_id = excluded.marker_id,
                review_note = excluded.review_note,
                created_at = now(),
                is_read = false;
        end if;

        -- Admin operational notification only when a moderator performed the
        -- decision. Admins do not receive notifications for their own reviews.
        if new.reviewed_by is not null
           and exists (
               select 1
                 from private.deepmap_moderators m
                where m.user_id = new.reviewed_by
           )
           and not exists (
               select 1
                 from private.deepmap_admins a
                where a.user_id = new.reviewed_by
           ) then

            select p.username
              into v_reviewer_username
              from public.profiles p
             where p.id = new.reviewed_by;

            insert into public.user_notifications (
                user_id,
                kind,
                game_id,
                submission_id,
                marker_id,
                submission_type,
                decision,
                review_note,
                metadata
            )
            select
                a.user_id,
                'admin_moderation_decision',
                new.game_id,
                new.id,
                new.marker_id,
                new.submission_type,
                new.status,
                new.review_note,
                jsonb_build_object(
                    'reviewed_by', new.reviewed_by,
                    'reviewed_username', v_reviewer_username,
                    'submitted_by', new.submitted_by
                )
            from private.deepmap_admins a
            where a.user_id is distinct from new.reviewed_by
              and a.user_id is distinct from new.submitted_by
            on conflict (user_id, submission_id, decision)
            where submission_id is not null
            do update set
                marker_id = excluded.marker_id,
                review_note = excluded.review_note,
                metadata = excluded.metadata,
                created_at = now(),
                is_read = false;
        end if;
    end if;

    return new;
end;
$$;

revoke all on function private.deepmap_notify_submission_review()
from public, anon, authenticated;

drop trigger if exists deepmap_notify_submission_review
on public.marker_submissions;

create trigger deepmap_notify_submission_review
after update of status, marker_id, review_note, reviewed_by
on public.marker_submissions
for each row
when (old.status is distinct from new.status)
execute function private.deepmap_notify_submission_review();

commit;
