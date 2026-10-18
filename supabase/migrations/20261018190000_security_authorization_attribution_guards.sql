-- DeepMap B7h2e: forward-only authorization and public attribution guards.
-- MANUAL REVIEW/APPLICATION ONLY, after B7h2c. No business DML or schema removal.
-- Preserves owners, ACLs, signatures, policies, bridges and all historical migrations.
BEGIN;
SET LOCAL search_path = pg_catalog;
SET LOCAL lock_timeout = '5s';

DO $b7h2e$
DECLARE
    v record;
    v_oid oid;
    v_before jsonb;
    v_after jsonb;
BEGIN
    -- Require the reviewed dependencies; do not silently bless a divergent helper.
    FOR v IN SELECT * FROM (VALUES
        ('private.marker_is_public(bigint)', $dep0$
    select exists (
        select 1
        from public.marcadores as m
        join public.map_layers as l
          on l.layer_uuid = m.layer_uuid and l.game_uuid = m.game_uuid
        join public.game_maps as gm
          on gm.id = l.game_map_id and gm.game_id = m.game_uuid
        join public.games as g on g.id = m.game_uuid
        where m.id = p_marker_id
          and m.is_published = true
          and l.is_active = true
          and gm.status = 'published'
          and g.status = 'published'
          and exists (
              select 1 from public.game_modules as mod
              where mod.game_id = g.id and mod.module_key = 'map' and mod.enabled
          )
    );
$dep0$),
        ('public.can_deepmap_interact()', $dep1$
    select (select auth.uid()) is not null
       and not private.is_deepmap_banned();
$dep1$),
        ('private.is_deepmap_banned(uuid)', $dep2$
    select exists (
        select 1
          from private.deepmap_bans as b
         where b.user_id = p_user_id
           and b.lifted_at is null
           and (b.expires_at is null or b.expires_at > now())
    );
$dep2$),
        ('private.is_deepmap_banned()', $dep3$
    select private.is_deepmap_banned((select auth.uid()));
$dep3$)
    ) e(signature, body) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
            WHERE p.oid=pg_catalog.to_regprocedure(v.signature)
              AND p.prosecdef AND p.proconfig=ARRAY['search_path=""']::text[]
              AND (r.rolsuper OR r.rolbypassrls)
              AND pg_catalog.regexp_replace(p.prosrc,'[[:space:]]','','g')
                  =pg_catalog.regexp_replace(v.body,'[[:space:]]','','g')
        ) THEN RAISE EXCEPTION 'B7H2E_DEPENDENCY_DRIFT: %',v.signature; END IF;
    END LOOP;

    FOR v IN SELECT * FROM (VALUES
        ('private.is_deepmap_admin()', 'CREATE OR REPLACE FUNCTION private.is_deepmap_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''''', $old0$
    select exists (
        select 1
        from private.deepmap_admins as a
        where a.user_id = (select auth.uid())
    );
$old0$, $new0$
    select (select auth.uid()) is not null
       and private.is_deepmap_banned() is false
       and exists (
        select 1
        from private.deepmap_admins as a
        where a.user_id = (select auth.uid())
    );
$new0$),
        ('public.cancel_marker_submission(bigint)', 'CREATE OR REPLACE FUNCTION public.cancel_marker_submission(p_submission_id bigint) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''''', $old1$
begin
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
$old1$, $new1$
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
$new1$),
        ('public.get_public_marker_attribution(text)', 'CREATE OR REPLACE FUNCTION public.get_public_marker_attribution(p_game_id text) RETURNS TABLE(marker_id bigint, published_username text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''''', $old2$
    select
        a.marker_id,
        creator.username as published_username
    from private.marker_editor_audit as a
    join public.marcadores as m
      on m.id = a.marker_id
    left join public.profiles as creator
      on creator.id = a.created_by
    where m.game_id = p_game_id
      and m.is_published = true;
$old2$, $new2$
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
$new2$),
        ('public.get_public_marker_attribution_by_game_uuid(uuid)', 'CREATE OR REPLACE FUNCTION public.get_public_marker_attribution_by_game_uuid(p_game_uuid uuid) RETURNS TABLE(marker_id bigint, published_username text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''''', $old3$
    select
        a.marker_id,
        creator.username as published_username
    from private.marker_editor_audit as a
    join public.marcadores as m
      on m.id = a.marker_id
    left join public.profiles as creator
      on creator.id = a.created_by
    where m.game_uuid = p_game_uuid
      and m.is_published = true;
$old3$, $new3$
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
$new3$)
    ) e(signature, header, old_body, new_body) LOOP
        v_oid := pg_catalog.to_regprocedure(v.signature);
        SELECT pg_catalog.to_jsonb(p) INTO v_before FROM pg_catalog.pg_proc p WHERE p.oid=v_oid;
        IF v_before IS NULL OR NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
            WHERE p.oid=v_oid AND p.prokind='f' AND p.prosecdef
              AND p.proconfig=ARRAY['search_path=""']::text[]
              AND (r.rolsuper OR r.rolbypassrls)
              AND NOT pg_catalog.pg_has_role('anon',r.oid,'MEMBER')
              AND NOT pg_catalog.pg_has_role('authenticated',r.oid,'MEMBER')
              AND (pg_catalog.regexp_replace(p.prosrc,'[[:space:]]','','g')
                     =pg_catalog.regexp_replace(v.old_body,'[[:space:]]','','g')
                   OR pg_catalog.regexp_replace(p.prosrc,'[[:space:]]','','g')
                     =pg_catalog.regexp_replace(v.new_body,'[[:space:]]','','g'))
        ) THEN RAISE EXCEPTION 'B7H2E_FUNCTION_DRIFT: %',v.signature; END IF;
        -- Never preserve an unexpected public/inherited privileged entry point.
        IF EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc p
            CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
            LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
            WHERE p.oid=v_oid AND a.privilege_type='EXECUTE'
              AND (a.grantee=0 OR (a.grantee<>p.proowner AND r.rolname NOT IN ('anon','authenticated','service_role'))
                   OR (r.rolname='anon' AND v.signature NOT LIKE 'public.get_public_marker_attribution%')
                   OR (r.rolname IN ('anon','authenticated') AND a.is_grantable))
        ) OR (v.signature NOT LIKE 'public.get_public_marker_attribution%'
               AND pg_catalog.has_function_privilege('anon',v_oid,'EXECUTE'))
          OR NOT pg_catalog.has_function_privilege('authenticated',v_oid,'EXECUTE')
        THEN RAISE EXCEPTION 'B7H2E_EXECUTE_ACL_DRIFT: %',v.signature; END IF;

        EXECUTE pg_catalog.format('%s AS %L',v.header,v.new_body);
        SELECT pg_catalog.to_jsonb(p) INTO v_after FROM pg_catalog.pg_proc p WHERE p.oid=v_oid;
        -- CREATE OR REPLACE may change ONLY the body, including on a safe re-run.
        IF v_after IS DISTINCT FROM pg_catalog.jsonb_set(v_before,'{prosrc}',pg_catalog.to_jsonb(v.new_body)) THEN
            RAISE EXCEPTION 'B7H2E_UNEXPECTED_FUNCTION_METADATA_CHANGE: %',v.signature;
        END IF;
    END LOOP;
END;
$b7h2e$;
COMMIT;
