-- B7e2 DB-only READ context. Baseline: verified B7e1 staff UUID listing.
-- Frozen B6c sources/digests are inert literals, NEVER invoked.
BEGIN;
SET LOCAL lock_timeout = '5s';
DO $migration$
DECLARE
 v_baseline oid := pg_catalog.to_regprocedure('public.get_marker_submissions_page_by_game_uuid(uuid,text,integer,integer)');
 v_new oid := pg_catalog.to_regprocedure('public.get_marker_review_context_by_game_uuid(uuid,bigint)');
 v_rpc oid; v_owner name; v_baseline_old jsonb; v_before jsonb; v_after jsonb;
 v_frozen_before jsonb; v_frozen_after jsonb; v_frozen_signatures text[] := ARRAY[]::text[];
 v_writer record; v_relation record; v_role record; v_grantee name;
 v_acl_baseline jsonb; v_acl_new jsonb; v_service_direct boolean;
 v_input_types oid[]; v_input_names text[]; v_output_types oid[]; v_output_names text[];
 v_expected_body text; v_default_count integer; v_defaults text;
 v_expected_names text[] := ARRAY['submission_id','game_uuid','game_id','game_slug','game_name','submission_type','correction_kind','status','marker_id','payload','target_id','target_game_uuid','target_title_en','target_title_pt','target_region_id','target_description_en','target_description_pt','target_video_url','target_coordinate_x','target_coordinate_y','target_is_published','target_content_items','target_image_count','current_layer_uuid','current_layer_id','current_game_map_uuid','current_layer_name_en','current_layer_name_pt','current_layer_is_active','current_category_uuid','current_category_id','current_category_name_en','current_category_name_pt','current_category_is_active','current_group_uuid','current_group_id','current_group_name_en','current_group_name_pt','current_group_is_active','submitted_layer_uuid','submitted_layer_id','submitted_game_map_uuid','submitted_layer_name_en','submitted_layer_name_pt','submitted_layer_is_active','submitted_category_uuid','submitted_category_id','submitted_category_name_en','submitted_category_name_pt','submitted_category_is_active','submitted_group_uuid','submitted_group_id','submitted_group_name_en','submitted_group_name_pt','submitted_group_is_active'];
 v_expected_types oid[] := ARRAY['bigint'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'jsonb'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'double precision'::pg_catalog.regtype::oid,'double precision'::pg_catalog.regtype::oid,'boolean'::pg_catalog.regtype::oid,'jsonb'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'boolean'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'boolean'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'boolean'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'boolean'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'boolean'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'boolean'::pg_catalog.regtype::oid];
 v_body text := $review_context$DECLARE
    v_submission public.marker_submissions%ROWTYPE;
    v_game public.games%ROWTYPE;
    v_target public.marcadores%ROWTYPE;
    v_current_layer public.map_layers%ROWTYPE;
    v_current_category public.marker_categories%ROWTYPE;
    v_current_group public.marker_category_groups%ROWTYPE;
    v_submitted_layer public.map_layers%ROWTYPE;
    v_submitted_category public.marker_categories%ROWTYPE;
    v_submitted_group public.marker_category_groups%ROWTYPE;
    v_content_items jsonb;
    v_image_count bigint;
BEGIN
    -- Authorization precedes every lookup, including invalid/NULL identifiers.
    IF private.can_moderate_deepmap() IS NOT TRUE THEN
        RAISE EXCEPTION 'MODERATOR_REQUIRED' USING ERRCODE = 'P0001';
    END IF;
    SELECT s.* INTO v_submission FROM public.marker_submissions s
    WHERE s.id = p_submission_id AND s.game_uuid = p_game_uuid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'REVIEW_CONTEXT_NOT_FOUND' USING ERRCODE = 'P0001';
    END IF;
    SELECT g.* INTO v_game FROM public.games g WHERE g.id = v_submission.game_uuid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'REVIEW_CONTEXT_PARENT_CONFLICT' USING ERRCODE = 'P0001';
    END IF;

    IF v_submission.submission_type = 'correction' AND v_submission.marker_id IS NULL THEN
        RAISE EXCEPTION 'REVIEW_CONTEXT_TARGET_NOT_FOUND' USING ERRCODE = 'P0001';
    END IF;
    -- Approved creates may have a marker_id; pending creates need not have one.
    IF v_submission.marker_id IS NOT NULL THEN
        SELECT m.* INTO v_target FROM public.marcadores m
        WHERE m.id = v_submission.marker_id AND m.game_uuid = v_submission.game_uuid;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'REVIEW_CONTEXT_TARGET_NOT_FOUND' USING ERRCODE = 'P0001';
        END IF;
        BEGIN
            SELECT l.* INTO STRICT v_current_layer FROM public.map_layers l
            WHERE l.layer_uuid = v_target.layer_uuid AND l.game_uuid = v_submission.game_uuid;
            SELECT c.* INTO STRICT v_current_category FROM public.marker_categories c
            WHERE c.category_uuid = v_target.category_uuid AND c.game_uuid = v_submission.game_uuid;
        EXCEPTION WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'REVIEW_CONTEXT_PARENT_CONFLICT' USING ERRCODE = 'P0001';
        END;
        IF v_current_layer.id IS DISTINCT FROM v_target.map_layer
            OR v_current_category.id IS DISTINCT FROM v_target.category_id
            OR NOT EXISTS (SELECT 1 FROM public.game_maps gm
                WHERE gm.id = v_current_layer.game_map_id AND gm.game_id = v_submission.game_uuid) THEN
            RAISE EXCEPTION 'REVIEW_CONTEXT_PARENT_CONFLICT' USING ERRCODE = 'P0001';
        END IF;
        IF v_current_category.group_uuid IS NOT NULL THEN
            BEGIN
                SELECT cg.* INTO STRICT v_current_group FROM public.marker_category_groups cg
                WHERE cg.group_uuid = v_current_category.group_uuid AND cg.game_uuid = v_submission.game_uuid;
            EXCEPTION WHEN no_data_found OR too_many_rows THEN
                RAISE EXCEPTION 'REVIEW_CONTEXT_PARENT_CONFLICT' USING ERRCODE = 'P0001';
            END;
            IF v_current_group.id IS DISTINCT FROM v_current_category.group_id THEN
                RAISE EXCEPTION 'REVIEW_CONTEXT_PARENT_CONFLICT' USING ERRCODE = 'P0001';
            END IF;
        ELSIF v_current_category.group_id IS NOT NULL THEN
            RAISE EXCEPTION 'REVIEW_CONTEXT_PARENT_CONFLICT' USING ERRCODE = 'P0001';
        END IF;

        -- Existing moderation compares only flattened text items and image count,
        -- not section metadata, private audit or an image/asset gallery.
        SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'type',sec.section_type,'text_en',r.text_en,'text_pt',r.text_pt)
            ORDER BY r.sort_order,r.id),'[]'::jsonb) INTO v_content_items
        FROM public.marker_sections sec JOIN public.marker_section_rows r ON r.section_id = sec.id
        JOIN public.marcadores m ON m.id = sec.marker_id AND m.game_uuid = v_submission.game_uuid
        WHERE sec.marker_id = v_target.id;
        SELECT count(*) INTO v_image_count FROM public.marker_images mi
        JOIN public.marcadores m ON m.id = mi.marker_id AND m.game_uuid = v_submission.game_uuid
        WHERE mi.marker_id = v_target.id;
    END IF;

    -- Exact legacy adapter within permanent game scope; no trim/default/alias map.
    -- UUID owns the context; submission.game_id disambiguates the historical adapter.
    -- Missing, JSON NULL, non-string or unknown exact-alias keys stay unresolved.
    IF pg_catalog.jsonb_typeof(v_submission.payload->'map_layer') = 'string' THEN
        BEGIN
            SELECT l.* INTO STRICT v_submitted_layer FROM public.map_layers l
            WHERE l.game_uuid = v_submission.game_uuid AND l.game_id = v_submission.game_id AND l.id = v_submission.payload->>'map_layer';
        EXCEPTION WHEN no_data_found THEN v_submitted_layer := NULL;
            WHEN too_many_rows THEN
                RAISE EXCEPTION 'REVIEW_CONTEXT_PARENT_CONFLICT' USING ERRCODE = 'P0001';
        END;
        IF v_submitted_layer.layer_uuid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.game_maps gm
            WHERE gm.id = v_submitted_layer.game_map_id AND gm.game_id = v_submission.game_uuid) THEN
            RAISE EXCEPTION 'REVIEW_CONTEXT_PARENT_CONFLICT' USING ERRCODE = 'P0001';
        END IF;
    END IF;
    IF pg_catalog.jsonb_typeof(v_submission.payload->'category_id') = 'string' THEN
        BEGIN
            SELECT c.* INTO STRICT v_submitted_category FROM public.marker_categories c
            WHERE c.game_uuid = v_submission.game_uuid AND c.game_id = v_submission.game_id AND c.id = v_submission.payload->>'category_id';
        EXCEPTION WHEN no_data_found THEN v_submitted_category := NULL;
            WHEN too_many_rows THEN
                RAISE EXCEPTION 'REVIEW_CONTEXT_PARENT_CONFLICT' USING ERRCODE = 'P0001';
        END;
        IF v_submitted_category.group_uuid IS NOT NULL THEN
            BEGIN
                SELECT cg.* INTO STRICT v_submitted_group FROM public.marker_category_groups cg
                WHERE cg.group_uuid = v_submitted_category.group_uuid AND cg.game_uuid = v_submission.game_uuid;
            EXCEPTION WHEN no_data_found OR too_many_rows THEN
                RAISE EXCEPTION 'REVIEW_CONTEXT_PARENT_CONFLICT' USING ERRCODE = 'P0001';
            END;
            IF v_submitted_group.id IS DISTINCT FROM v_submitted_category.group_id THEN
                RAISE EXCEPTION 'REVIEW_CONTEXT_PARENT_CONFLICT' USING ERRCODE = 'P0001';
            END IF;
        ELSIF v_submitted_category.group_id IS NOT NULL THEN
            RAISE EXCEPTION 'REVIEW_CONTEXT_PARENT_CONFLICT' USING ERRCODE = 'P0001';
        END IF;
    END IF;

    RETURN QUERY SELECT
        v_submission.id,v_submission.game_uuid,v_submission.game_id,v_game.slug,v_game.name,
        v_submission.submission_type,v_submission.correction_kind,v_submission.status,v_submission.marker_id,v_submission.payload,
        v_target.id,v_target.game_uuid,v_target.title_en,v_target.title_pt,v_target.region_id,
        v_target.description_en,v_target.description_pt,v_target.video_url,v_target.coordinate_x,v_target.coordinate_y,
        v_target.is_published,v_content_items,v_image_count,
        v_current_layer.layer_uuid,v_current_layer.id,v_current_layer.game_map_id,
        v_current_layer.name_en,v_current_layer.name_pt,v_current_layer.is_active,
        v_current_category.category_uuid,v_current_category.id,v_current_category.name_en,v_current_category.name_pt,v_current_category.is_active,
        v_current_group.group_uuid,v_current_group.id,v_current_group.name_en,v_current_group.name_pt,v_current_group.is_active,
        v_submitted_layer.layer_uuid,v_submitted_layer.id,v_submitted_layer.game_map_id,
        v_submitted_layer.name_en,v_submitted_layer.name_pt,v_submitted_layer.is_active,
        v_submitted_category.category_uuid,v_submitted_category.id,v_submitted_category.name_en,v_submitted_category.name_pt,v_submitted_category.is_active,
        v_submitted_group.group_uuid,v_submitted_group.id,v_submitted_group.name_en,v_submitted_group.name_pt,v_submitted_group.is_active;
END;
$review_context$;
 v_baseline_body text := $baseline_body$
begin
    if not private.can_moderate_deepmap() then
        raise exception 'MODERATOR_REQUIRED' using errcode = 'P0001';
    end if;
    if p_status not in ('pending','approved','rejected') then
        raise exception 'INVALID_STATUS' using errcode = 'P0001';
    end if;

    return query
    select
        s.id,s.game_id,s.marker_id,s.submission_type,s.correction_kind,s.status,s.submitted_by,
        submitter.username,s.payload,s.note,s.reviewed_by,reviewer.username,s.reviewed_at,s.review_note,s.created_at,s.updated_at,
        (select count(*)::integer from private.marker_submission_revisions r where r.submission_id=s.id),
        count(*) over(),
        s.game_uuid,g.slug,g.name
    from public.marker_submissions s
    left join public.games g on g.id=s.game_uuid
    left join public.profiles submitter on submitter.id=s.submitted_by
    left join public.profiles reviewer on reviewer.id=s.reviewed_by
    where (p_game_uuid is null or s.game_uuid=p_game_uuid)
      and s.status=p_status
    order by case when p_status='pending' then s.updated_at else coalesce(s.reviewed_at,s.updated_at) end desc, s.id desc
    limit greatest(1,least(coalesce(p_limit,10),100))
    offset greatest(coalesce(p_offset,0),0);
end;
$baseline_body$;
 v_gate_body text := $gate_body$
    select not private.is_deepmap_banned()
       and (private.is_deepmap_admin() or private.is_deepmap_moderator());
$gate_body$;
 v_revision_body text := $revision_body$
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
$revision_body$;
 v_writer_sql text := $b6_contracts$WITH sources(name,signature,definer,body) AS (VALUES
 ('marker','private.deepmap_resolve_marker_identity()',false,$marker_b6c$
    DECLARE
        v_game uuid;
        v_layer uuid;
        v_layer_game uuid;
        v_layer_changed boolean := false;
        v_category_uuid uuid;
        v_category_game_uuid uuid;
        v_category_changed boolean := false;
        v_category_hydrating boolean := false;
    BEGIN
        IF TG_OP='UPDATE' THEN
            IF OLD.game_uuid IS NULL AND OLD.layer_uuid IS NULL THEN
                IF (pg_catalog.to_jsonb(NEW)-ARRAY['game_uuid','layer_uuid']::text[])
                   IS DISTINCT FROM (pg_catalog.to_jsonb(OLD)-ARRAY['game_uuid','layer_uuid']::text[]) THEN
                    RAISE EXCEPTION 'B4B_HYDRATION_MUST_PRESERVE_LEGACY_FIELDS';
                END IF;
            ELSIF OLD.game_uuid IS NULL OR OLD.layer_uuid IS NULL THEN
                RAISE EXCEPTION 'B4B_PARTIAL_MARKER_IDENTITY';
            ELSE
                IF NEW.game_id IS DISTINCT FROM OLD.game_id OR NEW.game_uuid IS DISTINCT FROM OLD.game_uuid THEN
                    RAISE EXCEPTION 'B4B_MARKER_GAME_REASSIGNMENT_NOT_SUPPORTED';
                END IF;
                v_layer_changed := NEW.map_layer IS DISTINCT FROM OLD.map_layer;
                IF NOT v_layer_changed AND NEW.layer_uuid IS DISTINCT FROM OLD.layer_uuid THEN
                    RAISE EXCEPTION 'B4B_UUID_ONLY_LAYER_CHANGE_NOT_SUPPORTED';
                END IF;
            END IF;
        ELSIF TG_OP<>'INSERT' THEN
            RAISE EXCEPTION 'B4B_UNSUPPORTED_MARKER_TRIGGER_EVENT';
        END IF;
        BEGIN
            SELECT i.game_id INTO STRICT v_game FROM private.game_legacy_identifiers i
                WHERE i.legacy_identifier=NEW.game_id;
        EXCEPTION WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B4B_MARKER_MAPPING_NOT_EXACTLY_ONE_VISIBLE_ROW';
        END;
        BEGIN
            SELECT l.layer_uuid,l.game_uuid INTO STRICT v_layer,v_layer_game
                FROM public.map_layers l WHERE l.game_id=NEW.game_id AND l.id=NEW.map_layer;
        EXCEPTION WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B4B_MARKER_LAYER_NOT_EXACTLY_ONE_VISIBLE_ROW';
        END;
        IF v_layer IS NULL OR v_layer_game IS DISTINCT FROM v_game THEN
            RAISE EXCEPTION 'B4B_MARKER_LAYER_GAME_MAPPING_MISMATCH';
        END IF;
        IF NEW.game_uuid IS NULL THEN NEW.game_uuid := v_game;
        ELSIF NEW.game_uuid IS DISTINCT FROM v_game THEN
            RAISE EXCEPTION 'B4B_MARKER_LEGACY_GAME_UUID_MISMATCH';
        END IF;
        IF v_layer_changed THEN
            IF NEW.layer_uuid IS NOT NULL AND NEW.layer_uuid IS DISTINCT FROM OLD.layer_uuid
               AND NEW.layer_uuid IS DISTINCT FROM v_layer THEN
                RAISE EXCEPTION 'B4B_MARKER_EXPLICIT_NEW_LAYER_UUID_MISMATCH';
            END IF;
            NEW.layer_uuid := v_layer;
        ELSIF NEW.layer_uuid IS NULL THEN NEW.layer_uuid := v_layer;
        ELSIF NEW.layer_uuid IS DISTINCT FROM v_layer THEN
            RAISE EXCEPTION 'B4B_MARKER_LEGACY_LAYER_UUID_MISMATCH';
        END IF;
        IF TG_OP='UPDATE' THEN
            v_category_changed := NEW.category_id IS DISTINCT FROM OLD.category_id;
            v_category_hydrating := OLD.category_uuid IS NULL;
            IF v_category_hydrating THEN
                -- Identity BEFORE touch: every other key, even updated_at,
                -- must still be exactly OLD. NOT NULL ends this transition.
                IF (pg_catalog.to_jsonb(NEW)-'category_uuid') IS DISTINCT FROM
                   (pg_catalog.to_jsonb(OLD)-'category_uuid') THEN
                    RAISE EXCEPTION 'B6C_CATEGORY_HYDRATION_MUST_PRESERVE_OTHER_FIELDS';
                END IF;
            ELSIF NOT v_category_changed AND NEW.category_uuid IS DISTINCT FROM OLD.category_uuid THEN
                RAISE EXCEPTION 'B6C_UUID_ONLY_CATEGORY_CHANGE_NOT_SUPPORTED';
            END IF;
        END IF;
        BEGIN
            SELECT c.category_uuid,c.game_uuid INTO STRICT v_category_uuid,v_category_game_uuid
                FROM public.marker_categories c WHERE c.game_id=NEW.game_id AND c.id=NEW.category_id;
        EXCEPTION WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B6C_CATEGORY_NOT_EXACTLY_ONE_VISIBLE_ROW';
        END;
        IF v_category_uuid IS NULL OR v_category_game_uuid IS DISTINCT FROM NEW.game_uuid THEN
            RAISE EXCEPTION 'B6C_CATEGORY_GAME_CONTEXT_MISMATCH';
        END IF;
        IF TG_OP='UPDATE' THEN
            IF v_category_hydrating THEN
                IF NEW.category_uuid IS DISTINCT FROM v_category_uuid THEN
                    RAISE EXCEPTION 'B6C_CATEGORY_HYDRATION_REQUIRES_EXACT_UUID';
                END IF;
            ELSIF v_category_changed THEN
                -- Legacy callers transport OLD or NULL; correctly supplied
                -- destination UUID is also safe. Reject every other UUID.
                IF NEW.category_uuid IS NOT NULL AND NEW.category_uuid IS DISTINCT FROM OLD.category_uuid
                   AND NEW.category_uuid IS DISTINCT FROM v_category_uuid THEN
                    RAISE EXCEPTION 'B6C_EXPLICIT_NEW_CATEGORY_UUID_MISMATCH';
                END IF;
            ELSIF NEW.category_uuid IS DISTINCT FROM v_category_uuid THEN
                RAISE EXCEPTION 'B6C_EXISTING_CATEGORY_UUID_MISMATCH';
            END IF;
        END IF;
        -- INSERT callers never own category identity; always derive it.
        NEW.category_uuid := v_category_uuid;
        RETURN NEW;
    END;
    $marker_b6c$),
 ('audit','private.deepmap_stamp_marker_audit()',true,$audit_b6c$
declare
    v_user_id uuid := (select auth.uid());
    v_content_changed boolean := false;
begin
    if tg_op = 'INSERT' then
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
            new.id,
            v_user_id,
            now(),
            v_user_id,
            now(),
            case when new.is_published then v_user_id else null end,
            case when new.is_published then now() else null end,
            null,
            null
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
            end,
            approved_by = null,
            approved_at = null;

        return new;
    end if;

    -- B4a: only a genuine UUID-shadow-only UPDATE bypasses the audit UPSERT.
    -- is_published stays in both projections; missing JSONB keys are safe.
    if tg_op = 'UPDATE'
       and (pg_catalog.to_jsonb(new) - 'updated_at')
           is distinct from (pg_catalog.to_jsonb(old) - 'updated_at')
       and (pg_catalog.to_jsonb(new) - ARRAY['updated_at','game_uuid','layer_uuid','category_uuid']::text[])
           is not distinct from
           (pg_catalog.to_jsonb(old) - ARRAY['updated_at','game_uuid','layer_uuid','category_uuid']::text[]) then
        return new;
    end if;

    -- Publication toggles alone do not count as a content modification.
    v_content_changed :=
        (to_jsonb(new) - ARRAY['updated_at','is_published','game_uuid','layer_uuid','category_uuid']::text[])
        is distinct from
        (to_jsonb(old) - ARRAY['updated_at','is_published','game_uuid','layer_uuid','category_uuid']::text[]);

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
        new.id,
        null,
        null,
        case when v_content_changed then v_user_id else null end,
        case when v_content_changed then now() else null end,
        case when new.is_published then v_user_id else null end,
        case when new.is_published then now() else null end,
        null,
        null
    )
    on conflict (marker_id) do update
    set
        updated_by = case
            when v_content_changed then v_user_id
            else audit.updated_by
        end,
        updated_at = case
            when v_content_changed then now()
            else audit.updated_at
        end,
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
        end,
        -- Any direct content edit creates a new version that has not passed moderation.
        approved_by = case
            when v_content_changed then null
            else audit.approved_by
        end,
        approved_at = case
            when v_content_changed then null
            else audit.approved_at
        end;

    return new;
end;
$audit_b6c$),
 ('category','private.deepmap_resolve_category_identity()',false,$category_b6b$
DECLARE
    v_game_uuid uuid;
    v_group_uuid uuid;
    v_group_game_uuid uuid;
    v_group_changed boolean := false;
    v_hydrating boolean := false;
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.category_uuid := pg_catalog.gen_random_uuid();
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.category_uuid IS NULL OR NEW.category_uuid IS NULL
           OR NEW.category_uuid IS DISTINCT FROM OLD.category_uuid THEN
            RAISE EXCEPTION 'B6B_CATEGORY_UUID_IS_IMMUTABLE';
        END IF;
        v_group_changed := NEW.group_id IS DISTINCT FROM OLD.group_id;
        -- Technical transition exists only before the validated pair CHECK.
        v_hydrating := OLD.group_id IS NOT NULL AND OLD.group_uuid IS NULL;
        IF v_hydrating THEN
            IF (pg_catalog.to_jsonb(NEW)-'group_uuid') IS DISTINCT FROM
               (pg_catalog.to_jsonb(OLD)-'group_uuid') THEN
                RAISE EXCEPTION 'B6B_GROUP_HYDRATION_MUST_PRESERVE_OTHER_FIELDS';
            END IF;
        ELSIF NOT v_group_changed AND NEW.group_uuid IS DISTINCT FROM OLD.group_uuid THEN
            RAISE EXCEPTION 'B6B_UUID_ONLY_GROUP_CHANGE_NOT_SUPPORTED';
        END IF;
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF OLD.game_uuid IS NULL THEN
            -- Only technical hydration, before the later touch trigger.
            -- Final NOT NULL prevents this old-row state after COMMIT.
            IF (pg_catalog.to_jsonb(NEW) - 'game_uuid')
               IS DISTINCT FROM (pg_catalog.to_jsonb(OLD) - 'game_uuid') THEN
                RAISE EXCEPTION 'B2B_HYDRATION_MUST_PRESERVE_LEGACY_FIELDS';
            END IF;
        ELSIF NEW.game_id IS DISTINCT FROM OLD.game_id
           OR NEW.game_uuid IS DISTINCT FROM OLD.game_uuid THEN
            RAISE EXCEPTION 'B2B_CATEGORY_GAME_IDENTITY_IS_IMMUTABLE';
        END IF;
    ELSIF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'B2B_UNSUPPORTED_CATEGORY_TRIGGER_EVENT';
    END IF;

    BEGIN
        SELECT i.game_id INTO STRICT v_game_uuid
        FROM private.game_legacy_identifiers AS i
        WHERE i.legacy_identifier = NEW.game_id;
    EXCEPTION
        WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B2B_CATEGORY_MAPPING_NOT_EXACTLY_ONE_VISIBLE_ROW';
    END;

    IF NEW.game_uuid IS NULL THEN
        NEW.game_uuid := v_game_uuid;
    ELSIF NEW.game_uuid IS DISTINCT FROM v_game_uuid THEN
        RAISE EXCEPTION 'B2B_CATEGORY_LEGACY_GAME_UUID_MISMATCH';
    END IF;
    IF NEW.group_id IS NULL THEN
        NEW.group_uuid := NULL;
    ELSE
        BEGIN
            SELECT g.group_uuid,g.game_uuid INTO STRICT v_group_uuid,v_group_game_uuid
            FROM public.marker_category_groups AS g
            WHERE g.game_id=NEW.game_id AND g.id=NEW.group_id;
        EXCEPTION WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B6B_GROUP_NOT_EXACTLY_ONE_VISIBLE_ROW';
        END;
        IF v_group_uuid IS NULL OR v_group_game_uuid IS DISTINCT FROM v_game_uuid THEN
            RAISE EXCEPTION 'B6B_GROUP_GAME_CONTEXT_MISMATCH';
        END IF;
        IF TG_OP = 'UPDATE' THEN
            IF v_hydrating THEN
                IF NEW.group_uuid IS DISTINCT FROM v_group_uuid THEN
                    RAISE EXCEPTION 'B6B_GROUP_HYDRATION_REQUIRES_EXACT_UUID';
                END IF;
            ELSIF v_group_changed THEN
                IF NEW.group_uuid IS NOT NULL AND NEW.group_uuid IS DISTINCT FROM OLD.group_uuid
                   AND NEW.group_uuid IS DISTINCT FROM v_group_uuid THEN
                    RAISE EXCEPTION 'B6B_EXPLICIT_NEW_GROUP_UUID_MISMATCH';
                END IF;
            ELSIF NEW.group_uuid IS DISTINCT FROM v_group_uuid THEN
                RAISE EXCEPTION 'B6B_EXISTING_GROUP_UUID_MISMATCH';
            END IF;
        END IF;
        NEW.group_uuid := v_group_uuid;
    END IF;
    RETURN NEW;
END;
$category_b6b$),
 ('group','private.deepmap_resolve_category_group_identity()',false,$group_b6a$
DECLARE
    v_game_uuid uuid;
BEGIN
    -- Table-wide legacy INSERT grants must not let callers choose entity identity.
    -- Default fills rewritten old rows; the INSERT trigger owns new-row identity.
    IF TG_OP = 'INSERT' THEN
        NEW.group_uuid := pg_catalog.gen_random_uuid();
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.group_uuid IS NULL OR NEW.group_uuid IS NULL
           OR NEW.group_uuid IS DISTINCT FROM OLD.group_uuid THEN
            RAISE EXCEPTION 'B6A_GROUP_UUID_IS_IMMUTABLE';
        END IF;
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF OLD.game_uuid IS NULL THEN
            -- Only technical hydration, before the later touch trigger.
            -- Final NOT NULL prevents this old-row state after COMMIT.
            IF (pg_catalog.to_jsonb(NEW) - 'game_uuid')
               IS DISTINCT FROM (pg_catalog.to_jsonb(OLD) - 'game_uuid') THEN
                RAISE EXCEPTION 'B2A_HYDRATION_MUST_PRESERVE_LEGACY_FIELDS';
            END IF;
        ELSIF NEW.game_id IS DISTINCT FROM OLD.game_id
           OR NEW.game_uuid IS DISTINCT FROM OLD.game_uuid THEN
            RAISE EXCEPTION 'B2A_GROUP_GAME_IDENTITY_IS_IMMUTABLE';
        END IF;
    ELSIF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'B2A_UNSUPPORTED_GROUP_TRIGGER_EVENT';
    END IF;

    BEGIN
        SELECT i.game_id INTO STRICT v_game_uuid
        FROM private.game_legacy_identifiers AS i
        WHERE i.legacy_identifier = NEW.game_id;
    EXCEPTION
        WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B2A_GROUP_MAPPING_NOT_EXACTLY_ONE_VISIBLE_ROW';
    END;

    IF NEW.game_uuid IS NULL THEN
        NEW.game_uuid := v_game_uuid;
    ELSIF NEW.game_uuid IS DISTINCT FROM v_game_uuid THEN
        RAISE EXCEPTION 'B2A_GROUP_LEGACY_GAME_UUID_MISMATCH';
    END IF;
    RETURN NEW;
END;
$group_b6a$),
 ('touch','private.deepmap_touch_updated_at()',false,$touch_body$
begin
    new.updated_at := now();
    return new;
end;
$touch_body$)
), expected_side_bodies(signature,digest) AS (VALUES
 ('public.cancel_marker_submission(bigint)','32db8c8d8de026e6ef2220c752544a06'),
        ('private.deepmap_capture_submission_revision()','d3ff5f69ceb1cd15cf09cf72b26f55ce'),
        ('private.deepmap_autoapprove_moderator_submission()','9c7c5a38258ea603f205fcddb5b48861'),
        ('private.deepmap_notify_admin_submission_received()','c0ec4567cd4efa473e393a5e1e3f6016'),
        ('private.deepmap_notify_submission_review()','a423d83f1c880b7fcb81217d99e8c96d'),
        ('private.deepmap_materialize_submission_content()','09fdd39ed4b0565d21b1f51e6494c4eb'),
        ('private.deepmap_replace_quick_marker_content(bigint,jsonb)','74c611df1824cd9e78d76b98ca6f9920'),
        ('public.review_marker_submission(bigint,text,text)','c2d611f6339f023f3c2b43891f56af29'),
        ('public.review_marker_submission_v2(bigint,text,text,jsonb)','10327cfdf171ec2e3ba17380a909d644')
)
 SELECT signature,definer,body,NULL::text AS digest FROM sources
 UNION ALL SELECT signature,true,NULL::text,digest FROM expected_side_bodies$b6_contracts$;
 v_snapshot_sql text := $snapshot$WITH excluded AS (SELECT p.oid FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='public' AND p.proname='get_marker_review_context_by_game_uuid' AND p.proargtypes='2950 20'::pg_catalog.oidvector)),
 protected_objects(classid,objid) AS (
 SELECT 'pg_catalog.pg_namespace'::pg_catalog.regclass::oid,n.oid FROM pg_catalog.pg_namespace n WHERE n.nspname IN ('public','private')
 UNION ALL SELECT 'pg_catalog.pg_class'::pg_catalog.regclass::oid,c.oid FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private')
 UNION ALL SELECT 'pg_catalog.pg_proc'::pg_catalog.regclass::oid,p.oid FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private') AND p.oid NOT IN (SELECT oid FROM excluded)
 UNION ALL SELECT 'pg_catalog.pg_type'::pg_catalog.regclass::oid,t.oid FROM pg_catalog.pg_type t JOIN pg_catalog.pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname IN ('public','private')
 UNION ALL SELECT 'pg_catalog.pg_constraint'::pg_catalog.regclass::oid,c.oid FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_namespace n ON n.oid=c.connamespace WHERE n.nspname IN ('public','private')
 UNION ALL SELECT 'pg_catalog.pg_attrdef'::pg_catalog.regclass::oid,d.oid FROM pg_catalog.pg_attrdef d JOIN pg_catalog.pg_class c ON c.oid=d.adrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private')
 UNION ALL SELECT 'pg_catalog.pg_trigger'::pg_catalog.regclass::oid,t.oid FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private')
 UNION ALL SELECT 'pg_catalog.pg_policy'::pg_catalog.regclass::oid,p.oid FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_class c ON c.oid=p.polrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private')
 UNION ALL SELECT 'pg_catalog.pg_rewrite'::pg_catalog.regclass::oid,r.oid FROM pg_catalog.pg_rewrite r JOIN pg_catalog.pg_class c ON c.oid=r.ev_class JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private'))
SELECT pg_catalog.jsonb_build_object(
    'relations', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid)
        FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('public','private')),
    'columns', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attrelid,a.attnum)
        FROM pg_catalog.pg_attribute a JOIN pg_catalog.pg_class c ON c.oid=a.attrelid
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private')),
    'defaults', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.oid)
        FROM pg_catalog.pg_attrdef d JOIN pg_catalog.pg_class c ON c.oid=d.adrelid
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private')),
    'constraints', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid)
        FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_namespace n ON n.oid=c.connamespace
        WHERE n.nspname IN ('public','private')),
    'indexes', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.indexrelid)
        FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indrelid
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private')),
    'triggers', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY t.oid)
        FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private')),
    'policies', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid)
        FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_class c ON c.oid=p.polrelid
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private')),
    'routines', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid)
        FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname IN ('public','private')
          AND NOT (n.nspname='public' AND p.proname='get_marker_review_context_by_game_uuid' AND p.proargtypes='2950 20'::pg_catalog.oidvector)),
    'dependencies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.classid,d.objid,d.objsubid,d.refclassid,d.refobjid,d.refobjsubid,d.deptype) FROM pg_catalog.pg_depend d
 WHERE NOT (d.classid='pg_catalog.pg_proc'::pg_catalog.regclass AND d.objid IN (SELECT oid FROM excluded))
 AND (EXISTS (SELECT 1 FROM protected_objects o WHERE o.classid=d.classid AND o.objid=d.objid) OR EXISTS (SELECT 1 FROM protected_objects o WHERE o.classid=d.refclassid AND o.objid=d.refobjid))),
 'shared_dependencies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.dbid,d.classid,d.objid,d.objsubid,d.refclassid,d.refobjid,d.deptype) FROM pg_catalog.pg_shdepend d
 WHERE d.dbid=(SELECT oid FROM pg_catalog.pg_database WHERE datname=pg_catalog.current_database()) AND EXISTS (SELECT 1 FROM protected_objects o WHERE o.classid=d.classid AND o.objid=d.objid)),
 'schemas', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(n) ORDER BY n.oid)
        FROM pg_catalog.pg_namespace n WHERE n.nspname IN ('public','private')),
 'types',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY t.oid) FROM pg_catalog.pg_type t JOIN pg_catalog.pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname IN ('public','private')),
 'enums',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(e) ORDER BY e.oid) FROM pg_catalog.pg_enum e JOIN pg_catalog.pg_type t ON t.oid=e.enumtypid JOIN pg_catalog.pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname IN ('public','private')),
 'sequences',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(s) ORDER BY s.seqrelid) FROM pg_catalog.pg_sequence s JOIN pg_catalog.pg_class c ON c.oid=s.seqrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private')),
 'rules',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) ORDER BY r.oid) FROM pg_catalog.pg_rewrite r JOIN pg_catalog.pg_class c ON c.oid=r.ev_class JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private'))
)$snapshot$;
BEGIN
 IF EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated'),('service_role')) expected(name) WHERE pg_catalog.to_regrole(expected.name) IS NULL) THEN RAISE EXCEPTION 'B7E2_REQUIRED_ROLE_MISSING'; END IF;
 IF v_baseline IS NULL THEN RAISE EXCEPTION 'B7E2_VERIFIED_B7E1_BASELINE_REQUIRED'; END IF;
 SELECT pg_catalog.to_jsonb(p),r.rolname INTO STRICT v_baseline_old,v_owner FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner WHERE p.oid=v_baseline;
 IF v_owner IN ('anon','authenticated','service_role') OR pg_catalog.pg_has_role('anon',v_owner,'MEMBER') OR pg_catalog.pg_has_role('authenticated',v_owner,'MEMBER') THEN RAISE EXCEPTION 'B7E2_UNTRUSTED_OWNER: %',v_owner; END IF;
 FOR v_relation IN SELECT c.* FROM pg_catalog.pg_class c WHERE c.oid IN (
   'public.marker_submissions'::pg_catalog.regclass,'public.marcadores'::pg_catalog.regclass,'public.map_layers'::pg_catalog.regclass,
   'public.marker_categories'::pg_catalog.regclass,'public.marker_category_groups'::pg_catalog.regclass,'public.game_maps'::pg_catalog.regclass,'public.games'::pg_catalog.regclass,
   'public.marker_images'::pg_catalog.regclass,'public.marker_sections'::pg_catalog.regclass,'public.marker_section_rows'::pg_catalog.regclass,
   'public.profiles'::pg_catalog.regclass,'private.marker_submission_revisions'::pg_catalog.regclass) LOOP
   IF v_relation.relkind<>'r' OR NOT pg_catalog.has_schema_privilege(v_owner,v_relation.relnamespace,'USAGE') OR NOT pg_catalog.has_table_privilege(v_owner,v_relation.oid,'SELECT')
     OR (v_relation.relrowsecurity AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname=v_owner AND (r.rolsuper OR r.rolbypassrls OR (r.oid=v_relation.relowner AND NOT v_relation.relforcerowsecurity)))) THEN RAISE EXCEPTION 'B7E2_OWNER_READ_RLS_ACCESS_NOT_GUARANTEED: %',v_relation.relname; END IF;
 END LOOP;
 IF NOT pg_catalog.has_schema_privilege(v_owner,'auth','USAGE') OR NOT pg_catalog.has_function_privilege(v_owner,'auth.uid()','EXECUTE') OR NOT pg_catalog.has_function_privilege(v_owner,'private.can_moderate_deepmap()','EXECUTE') THEN RAISE EXCEPTION 'B7E2_OWNER_GATE_ACCESS_DRIFT'; END IF;
 v_rpc:=v_baseline;
 v_input_types:=ARRAY['uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid]; v_input_names:=ARRAY['p_game_uuid','p_status','p_limit','p_offset'];
 v_output_names:=ARRAY['id','game_id','marker_id','submission_type','correction_kind','status','submitted_by','submitted_username','payload','note','reviewed_by','reviewed_username','reviewed_at','review_note','created_at','updated_at','revision_count','total_count','game_uuid','game_slug','game_name']; v_output_types:=ARRAY['bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'jsonb'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid];
 v_default_count:=4; v_defaults:='NULL::uuid, ''pending''::text, 10, 0'; v_expected_body:=v_baseline_body;
 IF v_rpc IS NULL OR (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace AND proname=CASE WHEN v_rpc=v_baseline THEN 'get_marker_submissions_page_by_game_uuid' ELSE 'get_marker_review_context_by_game_uuid' END)<>1 THEN RAISE EXCEPTION 'B7E2_MISSING_OR_AMBIGUOUS_RPC'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang WHERE p.oid=v_rpc
   AND p.prokind='f' AND p.pronargs=pg_catalog.cardinality(v_input_types) AND ARRAY(SELECT pg_catalog.unnest(p.proargtypes::oid[]))=v_input_types
   AND p.proallargtypes=v_input_types||v_output_types AND p.proargnames=v_input_names||v_output_names
   AND p.proargmodes=pg_catalog.array_fill('i'::"char",ARRAY[pg_catalog.cardinality(v_input_types)])||pg_catalog.array_fill('t'::"char",ARRAY[pg_catalog.cardinality(v_output_types)])
   AND p.prorettype='record'::pg_catalog.regtype AND p.proretset AND p.provariadic=0 AND p.pronargdefaults=v_default_count AND (v_default_count<>0 OR p.proargdefaults IS NULL)
   AND pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(pg_catalog.pg_get_expr(p.proargdefaults,0),pg_catalog.chr(13),'')),'[[:space:]]+',' ','g') IS NOT DISTINCT FROM pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(v_defaults,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')
   AND l.lanname='plpgsql' AND p.prosecdef AND p.provolatile='s' AND p.proconfig=ARRAY['search_path=""']::text[] AND p.proowner=(v_baseline_old->>'proowner')::oid
   AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u' AND p.prosupport=0 AND p.procost=100 AND p.prorows=1000 AND p.probin IS NULL AND p.prosqlbody IS NULL
   AND pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')=pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(v_expected_body,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')) THEN RAISE EXCEPTION 'B7E2_EXACT_BODY_SHAPE_DEFAULTS_SECURITY_OWNER_DRIFT: %',v_rpc::pg_catalog.regprocedure; END IF;
 -- Mandatory owner/authenticated and optional legitimate service_role, not arbitrary ACL copying.
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_rpc AND
   (a.grantor<>p.proowner OR a.privilege_type<>'EXECUTE' OR a.is_grantable OR (a.grantee<>p.proowner AND (a.grantee=0 OR r.rolname IS NULL OR r.rolname NOT IN ('authenticated','service_role')))))
   OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc AND a.grantee=p.proowner)
   OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_rpc AND r.rolname='authenticated')
   OR (SELECT count(*) FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc) NOT IN (2,3)
   OR (SELECT count(DISTINCT a.grantee) FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc) IS DISTINCT FROM (SELECT count(*) FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc)
   OR NOT pg_catalog.has_function_privilege('authenticated',v_rpc,'EXECUTE') OR pg_catalog.has_function_privilege('anon',v_rpc,'EXECUTE') THEN RAISE EXCEPTION 'B7E2_ACL_REQUIRES_REVIEW: %, actual=%',v_rpc::pg_catalog.regprocedure,(SELECT proacl FROM pg_catalog.pg_proc WHERE oid=v_rpc); END IF;
 -- Existing staff readers/gate may not acquire hidden defaulted overloads.
 IF (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace AND proname='get_marker_submission_revisions')<>1
   OR (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='private'::pg_catalog.regnamespace AND proname='can_moderate_deepmap')<>1 THEN RAISE EXCEPTION 'B7E2_STAFF_READ_OR_GATE_OVERLOAD_DRIFT'; END IF;
 -- Exact reviewed staff gate, including ban behavior; no helper invocation here.
 IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang WHERE p.oid=pg_catalog.to_regprocedure('private.can_moderate_deepmap()') AND p.pronargs=0 AND p.prorettype='boolean'::pg_catalog.regtype AND NOT p.proretset AND p.prosecdef AND p.provolatile='s' AND l.lanname='sql' AND p.proconfig=ARRAY['search_path=""']::text[] AND pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')=pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(v_gate_body,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')) THEN RAISE EXCEPTION 'B7E2_FINAL_STAFF_GATE_DRIFT'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang WHERE p.oid=pg_catalog.to_regprocedure('public.get_marker_submission_revisions(bigint)')
   AND p.proargtypes='20'::pg_catalog.oidvector AND p.pronargs=1 AND p.pronargdefaults=0 AND p.proargdefaults IS NULL
   AND p.proallargtypes=ARRAY['bigint'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'jsonb'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid]
   AND p.proargnames=ARRAY['p_submission_id','revision_no','edited_by','edited_username','payload','note','created_at']
   AND p.proargmodes=ARRAY['i','t','t','t','t','t','t']::"char"[] AND p.proretset AND p.prorettype='record'::pg_catalog.regtype
   AND l.lanname='plpgsql' AND p.prosecdef AND p.provolatile='s' AND p.proconfig=ARRAY['search_path=""']::text[] AND pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')=pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(v_revision_body,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')) THEN RAISE EXCEPTION 'B7E2_REVIEWED_REVISION_READ_CONTRACT_DRIFT'; END IF;
 -- Reuse all 5 final B6c source literals and all 9 B6c side-effect digests.
 -- They are only inspected in pg_proc, NEVER called.
 FOR v_writer IN EXECUTE v_writer_sql LOOP
   IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure(v_writer.signature) AND p.prosecdef=v_writer.definer AND p.proconfig=ARRAY['search_path=""']::text[]
     AND CASE WHEN v_writer.body IS NOT NULL THEN pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=pg_catalog.replace(v_writer.body,pg_catalog.chr(13),'') ELSE pg_catalog.md5(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),''))=v_writer.digest END)
     OR (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private') AND p.proname=pg_catalog.split_part(pg_catalog.split_part(v_writer.signature,'.',2),'(',1))<>1 THEN RAISE EXCEPTION 'B7E2_FROZEN_B6C_WRITER_DRIFT: %',v_writer.signature; END IF;
   v_frozen_signatures:=pg_catalog.array_append(v_frozen_signatures,v_writer.signature);
 END LOOP;
 -- Review writer signatures/defaults/volatility/return types are also explicit.
 IF EXISTS (SELECT 1 FROM (VALUES ('public.review_marker_submission(bigint,text,text)',ARRAY['p_submission_id','p_decision','p_review_note']::text[],1,'NULL::text'),
   ('public.review_marker_submission_v2(bigint,text,text,jsonb)',ARRAY['p_submission_id','p_decision','p_review_note','p_payload_override']::text[],2,'NULL::text, NULL::jsonb')) expected(signature,argnames,defaults,default_expr)
   WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang WHERE p.oid=pg_catalog.to_regprocedure(expected.signature) AND p.prokind='f' AND p.pronargs=pg_catalog.cardinality(expected.argnames) AND p.proargnames=expected.argnames AND p.prorettype='bigint'::pg_catalog.regtype AND NOT p.proretset AND p.provolatile='v' AND p.prosecdef AND l.lanname='plpgsql' AND p.pronargdefaults=expected.defaults AND pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(pg_catalog.pg_get_expr(p.proargdefaults,0),pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')=pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(expected.default_expr,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'))) THEN RAISE EXCEPTION 'B7E2_FINAL_REVIEW_SIGNATURE_DRIFT'; END IF;
 v_frozen_signatures:=v_frozen_signatures||ARRAY['public.get_marker_submissions_page_by_game_uuid(uuid,text,integer,integer)','public.get_marker_submission_revisions(bigint)','private.can_moderate_deepmap()'];
 SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid) INTO v_frozen_before FROM pg_catalog.pg_proc p WHERE p.oid IN (SELECT pg_catalog.to_regprocedure(signature) FROM pg_catalog.unnest(v_frozen_signatures) e(signature));
 FOR v_writer IN SELECT * FROM (VALUES
 ('public.marker_submissions','id','bigint',true),
 ('public.marker_submissions','game_uuid','uuid',true),
 ('public.marker_submissions','game_id','text',true),
 ('public.marker_submissions','marker_id','bigint',false),
 ('public.marker_submissions','submission_type','text',true),
 ('public.marker_submissions','correction_kind','text',false),
 ('public.marker_submissions','status','text',true),
 ('public.marker_submissions','payload','jsonb',true),
 ('public.games','id','uuid',true),
 ('public.games','slug','text',true),
 ('public.games','name','text',true),
 ('public.game_maps','id','uuid',true),
 ('public.game_maps','game_id','uuid',true),
 ('public.marcadores','id','bigint',true),
 ('public.marcadores','game_uuid','uuid',true),
 ('public.marcadores','layer_uuid','uuid',true),
 ('public.marcadores','map_layer','text',true),
 ('public.marcadores','category_uuid','uuid',true),
 ('public.marcadores','category_id','text',true),
 ('public.marcadores','title_en','text',true),
 ('public.marcadores','title_pt','text',false),
 ('public.marcadores','region_id','text',false),
 ('public.marcadores','description_en','text',false),
 ('public.marcadores','description_pt','text',false),
 ('public.marcadores','video_url','text',false),
 ('public.marcadores','coordinate_x','double precision',true),
 ('public.marcadores','coordinate_y','double precision',true),
 ('public.marcadores','is_published','boolean',true),
 ('public.map_layers','layer_uuid','uuid',true),
 ('public.map_layers','game_uuid','uuid',true),
 ('public.map_layers','game_map_id','uuid',true),
 ('public.map_layers','id','text',true),
 ('public.map_layers','name_en','text',true),
 ('public.map_layers','name_pt','text',true),
 ('public.map_layers','is_active','boolean',true),
 ('public.marker_categories','category_uuid','uuid',true),
 ('public.marker_categories','game_uuid','uuid',true),
 ('public.marker_categories','id','text',true),
 ('public.marker_categories','group_uuid','uuid',false),
 ('public.marker_categories','group_id','text',false),
 ('public.marker_categories','name_en','text',true),
 ('public.marker_categories','name_pt','text',true),
 ('public.marker_categories','is_active','boolean',true),
 ('public.marker_category_groups','group_uuid','uuid',true),
 ('public.marker_category_groups','game_uuid','uuid',true),
 ('public.marker_category_groups','id','text',true),
 ('public.marker_category_groups','name_en','text',true),
 ('public.marker_category_groups','name_pt','text',true),
 ('public.marker_category_groups','is_active','boolean',true),
 ('public.marker_sections','id','bigint',true),
 ('public.marker_sections','marker_id','bigint',true),
 ('public.marker_sections','section_type','text',true),
 ('public.marker_section_rows','id','bigint',true),
 ('public.marker_section_rows','section_id','bigint',true),
 ('public.marker_section_rows','text_en','text',false),
 ('public.marker_section_rows','text_pt','text',false),
 ('public.marker_section_rows','sort_order','integer',true),
 ('public.marker_images','marker_id','bigint',true)
 ) expected(relation_name,column_name,type_name,not_null) LOOP
   IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid=pg_catalog.to_regclass(v_writer.relation_name) AND a.attname=v_writer.column_name AND a.attnum>0 AND NOT a.attisdropped AND a.atttypid=pg_catalog.to_regtype(v_writer.type_name) AND a.attnotnull=v_writer.not_null) THEN RAISE EXCEPTION 'B7E2_SCHEMA_DEPENDENCY_DRIFT: %.%',v_writer.relation_name,v_writer.column_name; END IF;
 END LOOP;
 -- UUID/marker/submission singleton lookup authority must be backed by keys.
 FOR v_writer IN SELECT * FROM (VALUES
   ('public.marker_submissions','id','p'),('public.marcadores','id','p'),('public.games','id','p'),('public.game_maps','id','p'),
   ('public.map_layers','layer_uuid','u'),('public.marker_categories','category_uuid','u'),('public.marker_category_groups','group_uuid','u')
 ) expected(relation_name,column_name,kind) LOOP
   IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid WHERE c.conrelid=pg_catalog.to_regclass(v_writer.relation_name) AND c.contype::text=v_writer.kind AND c.convalidated AND NOT c.condeferrable
     AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.conrelid AND a.attname=v_writer.column_name)]::smallint[] AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive AND i.indpred IS NULL AND i.indexprs IS NULL) THEN RAISE EXCEPTION 'B7E2_REQUIRED_SINGLETON_KEY_DRIFT: %.%',v_writer.relation_name,v_writer.column_name; END IF;
 END LOOP;
 -- Validate existing UUID contract before any catalog mutation.
 IF v_new IS NOT NULL THEN
   v_rpc:=v_new; v_input_types:=ARRAY['uuid'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid]; v_input_names:=ARRAY['p_game_uuid','p_submission_id'];
 v_output_names:=v_expected_names; v_output_types:=v_expected_types;
 v_default_count:=0; v_defaults:=NULL; v_expected_body:=v_body;
 IF v_rpc IS NULL OR (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace AND proname=CASE WHEN v_rpc=v_baseline THEN 'get_marker_submissions_page_by_game_uuid' ELSE 'get_marker_review_context_by_game_uuid' END)<>1 THEN RAISE EXCEPTION 'B7E2_MISSING_OR_AMBIGUOUS_RPC'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang WHERE p.oid=v_rpc
   AND p.prokind='f' AND p.pronargs=pg_catalog.cardinality(v_input_types) AND ARRAY(SELECT pg_catalog.unnest(p.proargtypes::oid[]))=v_input_types
   AND p.proallargtypes=v_input_types||v_output_types AND p.proargnames=v_input_names||v_output_names
   AND p.proargmodes=pg_catalog.array_fill('i'::"char",ARRAY[pg_catalog.cardinality(v_input_types)])||pg_catalog.array_fill('t'::"char",ARRAY[pg_catalog.cardinality(v_output_types)])
   AND p.prorettype='record'::pg_catalog.regtype AND p.proretset AND p.provariadic=0 AND p.pronargdefaults=v_default_count AND (v_default_count<>0 OR p.proargdefaults IS NULL)
   AND pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(pg_catalog.pg_get_expr(p.proargdefaults,0),pg_catalog.chr(13),'')),'[[:space:]]+',' ','g') IS NOT DISTINCT FROM pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(v_defaults,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')
   AND l.lanname='plpgsql' AND p.prosecdef AND p.provolatile='s' AND p.proconfig=ARRAY['search_path=""']::text[] AND p.proowner=(v_baseline_old->>'proowner')::oid
   AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u' AND p.prosupport=0 AND p.procost=100 AND p.prorows=1000 AND p.probin IS NULL AND p.prosqlbody IS NULL
   AND pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')=pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(v_expected_body,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')) THEN RAISE EXCEPTION 'B7E2_EXACT_BODY_SHAPE_DEFAULTS_SECURITY_OWNER_DRIFT: %',v_rpc::pg_catalog.regprocedure; END IF;
 -- Mandatory owner/authenticated and optional legitimate service_role, not arbitrary ACL copying.
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_rpc AND
   (a.grantor<>p.proowner OR a.privilege_type<>'EXECUTE' OR a.is_grantable OR (a.grantee<>p.proowner AND (a.grantee=0 OR r.rolname IS NULL OR r.rolname NOT IN ('authenticated','service_role')))))
   OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc AND a.grantee=p.proowner)
   OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_rpc AND r.rolname='authenticated')
   OR (SELECT count(*) FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc) NOT IN (2,3)
   OR (SELECT count(DISTINCT a.grantee) FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc) IS DISTINCT FROM (SELECT count(*) FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc)
   OR NOT pg_catalog.has_function_privilege('authenticated',v_rpc,'EXECUTE') OR pg_catalog.has_function_privilege('anon',v_rpc,'EXECUTE') THEN RAISE EXCEPTION 'B7E2_ACL_REQUIRES_REVIEW: %, actual=%',v_rpc::pg_catalog.regprocedure,(SELECT proacl FROM pg_catalog.pg_proc WHERE oid=v_rpc); END IF;
 -- Exact body matching above implies all joins/scopes and no broader returned fields.
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_new AND
   (p.prosrc ~ 'private[.]game_legacy_identifiers' OR p.prosrc ~ '(^|[[:space:]])(s|m)[.]game_id[[:space:]]*='
   OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),'s.id = p_submission_id AND s.game_uuid = p_game_uuid')=0
   OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),'m.id = v_submission.marker_id AND m.game_uuid = v_submission.game_uuid')=0
   OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),'l.game_uuid = v_submission.game_uuid AND l.game_id = v_submission.game_id AND l.id = v_submission.payload->>''map_layer''')=0
   OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),'c.game_uuid = v_submission.game_uuid AND c.game_id = v_submission.game_id AND c.id = v_submission.payload->>''category_id''')=0
   OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),'IF private.can_moderate_deepmap() IS NOT TRUE THEN')=0)) THEN RAISE EXCEPTION 'B7E2_EXACT_STAFF_UUID_SCOPE_DRIFT'; END IF;
   SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_baseline FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_baseline;
 SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_new FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_new;
 IF v_acl_baseline IS DISTINCT FROM v_acl_new THEN RAISE EXCEPTION 'B7E2_DIRECT_ACL_PARITY_DRIFT'; END IF;
 IF pg_catalog.has_function_privilege('authenticated',v_baseline,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege('authenticated',v_new,'EXECUTE')
   OR pg_catalog.has_function_privilege('service_role',v_baseline,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege('service_role',v_new,'EXECUTE')
   OR pg_catalog.has_function_privilege('anon',v_new,'EXECUTE') THEN RAISE EXCEPTION 'B7E2_CALLER_EFFECTIVE_EXECUTE_DRIFT'; END IF;
 FOR v_role IN SELECT rolname FROM pg_catalog.pg_roles LOOP
   IF pg_catalog.has_function_privilege(v_role.rolname,v_baseline,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege(v_role.rolname,v_new,'EXECUTE') THEN RAISE EXCEPTION 'B7E2_ALL_ROLE_EXECUTE_PARITY_DRIFT: %',v_role.rolname; END IF;
 END LOOP;
 ELSIF EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace AND proname='get_marker_review_context_by_game_uuid') THEN
   RAISE EXCEPTION 'B7E2_UUID_NAME_COLLISION_REQUIRES_REVIEW';
 END IF;
 EXECUTE v_snapshot_sql INTO v_before;
 IF v_new IS NULL THEN
   EXECUTE pg_catalog.format('CREATE FUNCTION public.get_marker_review_context_by_game_uuid(p_game_uuid uuid,p_submission_id bigint)
     RETURNS TABLE (
       submission_id bigint,
       game_uuid uuid,
       game_id text,
       game_slug text,
       game_name text,
       submission_type text,
       correction_kind text,
       status text,
       marker_id bigint,
       payload jsonb,
       target_id bigint,
       target_game_uuid uuid,
       target_title_en text,
       target_title_pt text,
       target_region_id text,
       target_description_en text,
       target_description_pt text,
       target_video_url text,
       target_coordinate_x double precision,
       target_coordinate_y double precision,
       target_is_published boolean,
       target_content_items jsonb,
       target_image_count bigint,
       current_layer_uuid uuid,
       current_layer_id text,
       current_game_map_uuid uuid,
       current_layer_name_en text,
       current_layer_name_pt text,
       current_layer_is_active boolean,
       current_category_uuid uuid,
       current_category_id text,
       current_category_name_en text,
       current_category_name_pt text,
       current_category_is_active boolean,
       current_group_uuid uuid,
       current_group_id text,
       current_group_name_en text,
       current_group_name_pt text,
       current_group_is_active boolean,
       submitted_layer_uuid uuid,
       submitted_layer_id text,
       submitted_game_map_uuid uuid,
       submitted_layer_name_en text,
       submitted_layer_name_pt text,
       submitted_layer_is_active boolean,
       submitted_category_uuid uuid,
       submitted_category_id text,
       submitted_category_name_en text,
       submitted_category_name_pt text,
       submitted_category_is_active boolean,
       submitted_group_uuid uuid,
       submitted_group_id text,
       submitted_group_name_en text,
       submitted_group_name_pt text,
       submitted_group_is_active boolean
     ) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = %L AS %L','',v_body);
   EXECUTE pg_catalog.format('ALTER FUNCTION public.get_marker_review_context_by_game_uuid(uuid,bigint) OWNER TO %I',v_owner);
   v_new:=pg_catalog.to_regprocedure('public.get_marker_review_context_by_game_uuid(uuid,bigint)');
   -- Only a freshly created RPC may have inherited default grants removed.
   FOR v_grantee IN SELECT DISTINCT r.rolname FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_new AND a.grantee<>p.proowner LOOP
     EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION public.get_marker_review_context_by_game_uuid(uuid,bigint) FROM %I',v_grantee);
   END LOOP;
   REVOKE ALL ON FUNCTION public.get_marker_review_context_by_game_uuid(uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
   GRANT EXECUTE ON FUNCTION public.get_marker_review_context_by_game_uuid(uuid,bigint) TO authenticated;
   SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_baseline AND r.rolname='service_role') INTO v_service_direct;
   IF v_service_direct THEN GRANT EXECUTE ON FUNCTION public.get_marker_review_context_by_game_uuid(uuid,bigint) TO service_role; END IF;
 END IF;
 v_rpc:=v_new; v_input_types:=ARRAY['uuid'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid]; v_input_names:=ARRAY['p_game_uuid','p_submission_id'];
 v_output_names:=v_expected_names; v_output_types:=v_expected_types;
 v_default_count:=0; v_defaults:=NULL; v_expected_body:=v_body;
 IF v_rpc IS NULL OR (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace AND proname=CASE WHEN v_rpc=v_baseline THEN 'get_marker_submissions_page_by_game_uuid' ELSE 'get_marker_review_context_by_game_uuid' END)<>1 THEN RAISE EXCEPTION 'B7E2_MISSING_OR_AMBIGUOUS_RPC'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang WHERE p.oid=v_rpc
   AND p.prokind='f' AND p.pronargs=pg_catalog.cardinality(v_input_types) AND ARRAY(SELECT pg_catalog.unnest(p.proargtypes::oid[]))=v_input_types
   AND p.proallargtypes=v_input_types||v_output_types AND p.proargnames=v_input_names||v_output_names
   AND p.proargmodes=pg_catalog.array_fill('i'::"char",ARRAY[pg_catalog.cardinality(v_input_types)])||pg_catalog.array_fill('t'::"char",ARRAY[pg_catalog.cardinality(v_output_types)])
   AND p.prorettype='record'::pg_catalog.regtype AND p.proretset AND p.provariadic=0 AND p.pronargdefaults=v_default_count AND (v_default_count<>0 OR p.proargdefaults IS NULL)
   AND pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(pg_catalog.pg_get_expr(p.proargdefaults,0),pg_catalog.chr(13),'')),'[[:space:]]+',' ','g') IS NOT DISTINCT FROM pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(v_defaults,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')
   AND l.lanname='plpgsql' AND p.prosecdef AND p.provolatile='s' AND p.proconfig=ARRAY['search_path=""']::text[] AND p.proowner=(v_baseline_old->>'proowner')::oid
   AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u' AND p.prosupport=0 AND p.procost=100 AND p.prorows=1000 AND p.probin IS NULL AND p.prosqlbody IS NULL
   AND pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')=pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(v_expected_body,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')) THEN RAISE EXCEPTION 'B7E2_EXACT_BODY_SHAPE_DEFAULTS_SECURITY_OWNER_DRIFT: %',v_rpc::pg_catalog.regprocedure; END IF;
 -- Mandatory owner/authenticated and optional legitimate service_role, not arbitrary ACL copying.
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_rpc AND
   (a.grantor<>p.proowner OR a.privilege_type<>'EXECUTE' OR a.is_grantable OR (a.grantee<>p.proowner AND (a.grantee=0 OR r.rolname IS NULL OR r.rolname NOT IN ('authenticated','service_role')))))
   OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc AND a.grantee=p.proowner)
   OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_rpc AND r.rolname='authenticated')
   OR (SELECT count(*) FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc) NOT IN (2,3)
   OR (SELECT count(DISTINCT a.grantee) FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc) IS DISTINCT FROM (SELECT count(*) FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc)
   OR NOT pg_catalog.has_function_privilege('authenticated',v_rpc,'EXECUTE') OR pg_catalog.has_function_privilege('anon',v_rpc,'EXECUTE') THEN RAISE EXCEPTION 'B7E2_ACL_REQUIRES_REVIEW: %, actual=%',v_rpc::pg_catalog.regprocedure,(SELECT proacl FROM pg_catalog.pg_proc WHERE oid=v_rpc); END IF;
 -- Exact body matching above implies all joins/scopes and no broader returned fields.
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_new AND
   (p.prosrc ~ 'private[.]game_legacy_identifiers' OR p.prosrc ~ '(^|[[:space:]])(s|m)[.]game_id[[:space:]]*='
   OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),'s.id = p_submission_id AND s.game_uuid = p_game_uuid')=0
   OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),'m.id = v_submission.marker_id AND m.game_uuid = v_submission.game_uuid')=0
   OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),'l.game_uuid = v_submission.game_uuid AND l.game_id = v_submission.game_id AND l.id = v_submission.payload->>''map_layer''')=0
   OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),'c.game_uuid = v_submission.game_uuid AND c.game_id = v_submission.game_id AND c.id = v_submission.payload->>''category_id''')=0
   OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),'IF private.can_moderate_deepmap() IS NOT TRUE THEN')=0)) THEN RAISE EXCEPTION 'B7E2_EXACT_STAFF_UUID_SCOPE_DRIFT'; END IF;
 SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_baseline FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_baseline;
 SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_new FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_new;
 IF v_acl_baseline IS DISTINCT FROM v_acl_new THEN RAISE EXCEPTION 'B7E2_DIRECT_ACL_PARITY_DRIFT'; END IF;
 IF pg_catalog.has_function_privilege('authenticated',v_baseline,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege('authenticated',v_new,'EXECUTE')
   OR pg_catalog.has_function_privilege('service_role',v_baseline,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege('service_role',v_new,'EXECUTE')
   OR pg_catalog.has_function_privilege('anon',v_new,'EXECUTE') THEN RAISE EXCEPTION 'B7E2_CALLER_EFFECTIVE_EXECUTE_DRIFT'; END IF;
 FOR v_role IN SELECT rolname FROM pg_catalog.pg_roles LOOP
   IF pg_catalog.has_function_privilege(v_role.rolname,v_baseline,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege(v_role.rolname,v_new,'EXECUTE') THEN RAISE EXCEPTION 'B7E2_ALL_ROLE_EXECUTE_PARITY_DRIFT: %',v_role.rolname; END IF;
 END LOOP;
 SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid) INTO v_frozen_after FROM pg_catalog.pg_proc p WHERE p.oid IN (SELECT pg_catalog.to_regprocedure(signature) FROM pg_catalog.unnest(v_frozen_signatures) e(signature));
 IF v_frozen_after IS DISTINCT FROM v_frozen_before OR (SELECT pg_catalog.to_jsonb(p) FROM pg_catalog.pg_proc p WHERE p.oid=v_baseline) IS DISTINCT FROM v_baseline_old THEN RAISE EXCEPTION 'B7E2_COMPLETE_FROZEN_PG_PROC_CHANGED'; END IF;
 EXECUTE v_snapshot_sql INTO v_after;
 IF v_after IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'B7E2_PROTECTED_CATALOG_CHANGED'; END IF;
 RAISE NOTICE 'PASS B7E2 context exact contract/owner/ACL, complete frozen pg_proc and protected catalog preservation';
 RAISE NOTICE 'INFO B7E2 preservation fingerprint = %',pg_catalog.md5(v_before::text);
END;
$migration$;
COMMIT;
