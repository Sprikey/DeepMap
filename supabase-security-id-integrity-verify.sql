-- DeepMap B7h2e temporary verifier. KEEP until final pre-R2 cleanup.
-- MANUAL ONLY; run AFTER the proposed migration, with maintenance visibility.
-- Read-only, counts/catalog checks only. No user rows, tokens or private identities.
-- This file is NOT a migration and has NOT been executed against remote Supabase.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE v record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname=CURRENT_USER AND (rolsuper OR rolbypassrls)) THEN
        RAISE EXCEPTION 'B7H2E_VERIFIER_REQUIRES_MAINTENANCE_VISIBILITY';
    END IF;
    FOR v IN SELECT * FROM (VALUES
        ('private.is_deepmap_admin()', $expected0$
    select (select auth.uid()) is not null
       and private.is_deepmap_banned() is false
       and exists (
        select 1
        from private.deepmap_admins as a
        where a.user_id = (select auth.uid())
    );
$expected0$),
        ('public.cancel_marker_submission(bigint)', $expected1$
begin
    if public.can_deepmap_interact() is distinct from true then
        raise exception 'INTERACTION_NOT_ALLOWED' using errcode = 'P0001';
    end if;

    update public.marker_submissions
       set status = 'cancelled',
           updated_at = now()
     where id = p_submission_id
       and submitted_by = (select auth.uid())
       and status = 'pending';

    if not found then
        raise exception 'SUBMISSION_NOT_CANCELLABLE' using errcode = 'P0001';
    end if;
end;
$expected1$),
        ('public.get_public_marker_attribution(text)', $expected2$
    select
        a.marker_id,
        creator.username as published_username
    from private.marker_editor_audit as a
    join public.marcadores as m
      on m.id = a.marker_id
    left join public.profiles as creator
      on creator.id = a.created_by
    where m.game_id = p_game_id
      and private.marker_is_public(m.id);
$expected2$),
        ('public.get_public_marker_attribution_by_game_uuid(uuid)', $expected3$
    select
        a.marker_id,
        creator.username as published_username
    from private.marker_editor_audit as a
    join public.marcadores as m
      on m.id = a.marker_id
    left join public.profiles as creator
      on creator.id = a.created_by
    where m.game_uuid = p_game_uuid
      and private.marker_is_public(m.id);
$expected3$)
    ) e(signature, body) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure(v.signature)
              AND p.prosecdef AND p.proconfig=ARRAY['search_path=""']::text[]
              AND pg_catalog.regexp_replace(p.prosrc,'[[:space:]]','','g')
                  =pg_catalog.regexp_replace(v.body,'[[:space:]]','','g')
        ) THEN RAISE EXCEPTION 'B7H2E_FINAL_BODY_DRIFT: %',v.signature; END IF;
        IF NOT pg_catalog.has_function_privilege('authenticated',v.signature,'EXECUTE')
           OR (v.signature NOT LIKE 'public.get_public_marker_attribution%'
               AND pg_catalog.has_function_privilege('anon',v.signature,'EXECUTE'))
           OR (v.signature LIKE 'public.get_public_marker_attribution%'
               AND NOT pg_catalog.has_function_privilege('anon',v.signature,'EXECUTE')) THEN
            RAISE EXCEPTION 'B7H2E_FINAL_EXECUTE_DRIFT: %',v.signature;
        END IF;
    END LOOP;
END;
$verify$;

-- Every count below must be zero. UUID + legacy pairs must identify ONE parent.
SELECT 'layer_game_map' AS relationship, count(*) AS inconsistent_rows
FROM public.map_layers l LEFT JOIN public.game_maps gm ON gm.id=l.game_map_id AND gm.game_id=l.game_uuid
WHERE gm.id IS NULL
UNION ALL
SELECT 'legacy_game_alias', count(*) FROM (
    SELECT game_id,game_uuid FROM public.map_layers
    UNION ALL SELECT game_id,game_uuid FROM public.marker_category_groups
    UNION ALL SELECT game_id,game_uuid FROM public.marker_categories
    UNION ALL SELECT game_id,game_uuid FROM public.marcadores
    UNION ALL SELECT game_id,game_uuid FROM public.map_labels
    UNION ALL SELECT game_id,game_uuid FROM public.marker_submissions
) r LEFT JOIN private.game_legacy_identifiers i ON i.legacy_identifier=r.game_id AND i.game_id=r.game_uuid
WHERE i.game_id IS NULL
UNION ALL
SELECT 'marker_layer', count(*) FROM public.marcadores m
LEFT JOIN public.map_layers l ON l.layer_uuid=m.layer_uuid AND l.game_uuid=m.game_uuid AND l.game_id=m.game_id AND l.id=m.map_layer
WHERE l.layer_uuid IS NULL
UNION ALL
SELECT 'marker_category', count(*) FROM public.marcadores m
LEFT JOIN public.marker_categories c ON c.category_uuid=m.category_uuid AND c.game_uuid=m.game_uuid AND c.game_id=m.game_id AND c.id=m.category_id
WHERE c.category_uuid IS NULL
UNION ALL
SELECT 'category_group', count(*) FROM public.marker_categories c
LEFT JOIN public.marker_category_groups g ON g.group_uuid=c.group_uuid AND g.game_uuid=c.game_uuid AND g.game_id=c.game_id AND g.id=c.group_id
WHERE (c.group_id IS NULL) IS DISTINCT FROM (c.group_uuid IS NULL) OR (c.group_id IS NOT NULL AND g.group_uuid IS NULL)
UNION ALL
SELECT 'label_layer', count(*) FROM public.map_labels m
LEFT JOIN public.map_layers l ON l.layer_uuid=m.layer_uuid AND l.game_uuid=m.game_uuid AND l.game_id=m.game_id AND l.id=m.map_layer
WHERE l.layer_uuid IS NULL
UNION ALL
SELECT 'submission_marker', count(*) FROM public.marker_submissions s
LEFT JOIN public.marcadores m ON m.id=s.marker_id AND m.game_id=s.game_id AND m.game_uuid=s.game_uuid
WHERE s.marker_id IS NOT NULL AND m.id IS NULL
UNION ALL
SELECT 'image_marker', count(*) FROM public.marker_images i LEFT JOIN public.marcadores m ON m.id=i.marker_id WHERE m.id IS NULL
UNION ALL
SELECT 'section_marker', count(*) FROM public.marker_sections s LEFT JOIN public.marcadores m ON m.id=s.marker_id WHERE m.id IS NULL
UNION ALL
SELECT 'row_section', count(*) FROM public.marker_section_rows r LEFT JOIN public.marker_sections s ON s.id=r.section_id WHERE s.id IS NULL;

-- Both entry points must match the authoritative visibility guard even for an
-- admin/maintenance caller: public attribution must never enumerate hidden maps.
SELECT 'uuid_attribution_visibility' AS contract, count(*) AS unexpected_rows
FROM public.games g
CROSS JOIN LATERAL public.get_public_marker_attribution_by_game_uuid(g.id) a
LEFT JOIN public.marcadores m ON m.id=a.marker_id AND m.game_uuid=g.id
WHERE m.id IS NULL OR NOT private.marker_is_public(a.marker_id)
UNION ALL
SELECT 'legacy_attribution_visibility', count(*)
FROM private.game_legacy_identifiers i
CROSS JOIN LATERAL public.get_public_marker_attribution(i.legacy_identifier) a
LEFT JOIN public.marcadores m ON m.id=a.marker_id AND m.game_id=i.legacy_identifier AND m.game_uuid=i.game_id
WHERE m.id IS NULL OR NOT private.marker_is_public(a.marker_id);

-- Permission matrix still needs real JWT tests in a disposable local/staging
-- fixture: anon/user/mod/admin/suspended; cancellation own vs another author;
-- direct REST writes with mismatched A/B game/layer/category/submission targets.
-- Never mutate production accounts or data merely to perform those tests.
ROLLBACK;
