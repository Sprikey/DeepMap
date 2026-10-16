-- B7g3a additive Admin Audit read contract; no writers are executed.
-- game_id is legacy display metadata ONLY. No alias lookup authorizes routes.
-- Event set matches get_deepmap_admin_audit; marker editor audit is separate.
-- NULL scope includes global events; UUID scope includes resolved current games only.
-- Missing marker: live submission UUID. Conflicting parents: NULL route context.
-- Missing game: all route fields NULL. Deleted submission: no event, as in legacy.
-- Timestamp ties use unique event_id in C collation DESC.
-- All public/private catalog, table data and sequences are protected.
-- Use a quiet maintenance window: sequence state is not MVCC transactional.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL TimeZone = 'UTC';
DO $verify$
DECLARE
    v_baseline oid := pg_catalog.to_regprocedure('public.get_deepmap_admin_audit(integer,integer)');
    v_rpc oid := pg_catalog.to_regprocedure('public.get_admin_audit_log_by_game_uuid(uuid,integer,integer)');
    v_owner name; v_grantee name; v_relation record; v_item record; v_role record;
    v_before jsonb; v_after jsonb; v_state jsonb; v_data jsonb; v_sequences jsonb; v_actual jsonb;
    v_acl_baseline jsonb; v_acl_rpc jsonb; v_service_direct boolean;
    v_body text := $route_body$
begin
    if not private.is_deepmap_admin() then
        raise exception 'ADMIN_REQUIRED' using errcode = 'P0001';
    end if;

    return query
    with events as (
        select
            'role-' || r.id::text as event_id,
            r.action,
            actor.username as actor_username,
            target.username as target_username,
            null::text as game_id,
            null::bigint as submission_id,
            null::bigint as marker_id, null::uuid as context_game_uuid,
            null::text as detail,
            r.created_at
        from private.deepmap_role_audit r
        left join public.profiles actor on actor.id=r.actor_id
        left join public.profiles target on target.id=r.target_user_id

        union all

        select
            'ban-' || b.id::text,
            b.action,
            actor.username,
            target.username,
            null::text,
            null::bigint,
            null::bigint, null::uuid,
            case
                when b.action='user_banned' then coalesce(b.reason,'') || case when b.expires_at is null then ' · permanent' else ' · until ' || b.expires_at::text end
                else coalesce(b.reason,'')
            end,
            b.created_at
        from private.deepmap_ban_audit b
        left join public.profiles actor on actor.id=b.actor_id
        left join public.profiles target on target.id=b.target_user_id

        union all

        select
            'submission-' || s.id::text || '-' || s.status,
            case when s.status='approved' then 'submission_approved' else 'submission_rejected' end,
            reviewer.username,
            submitter.username,
            s.game_id,
            s.id,
            s.marker_id,
            CASE WHEN m.id IS NOT NULL THEN
                CASE WHEN s.game_uuid = m.game_uuid THEN s.game_uuid ELSE NULL::uuid END
                ELSE s.game_uuid END,
            nullif(s.review_note,''),
            coalesce(s.reviewed_at,s.updated_at)
        from public.marker_submissions s
        left join public.marcadores m on m.id=s.marker_id
        left join public.profiles reviewer on reviewer.id=s.reviewed_by
        left join public.profiles submitter on submitter.id=s.submitted_by
        where s.status in ('approved','rejected')
    )
    select
        e.event_id,e.action,e.actor_username,e.target_username,e.game_id,e.submission_id,e.detail,e.created_at,
        count(*) over(),e.marker_id,
        g.id as route_game_uuid,g.slug as route_game_slug,g.name as route_game_name
    from events e
    left join public.games g on g.id=e.context_game_uuid
    where p_game_uuid is null or g.id=p_game_uuid
    order by e.created_at desc,e.event_id collate pg_catalog."C" desc
    limit greatest(1,least(coalesce(p_limit,25),100))
    offset greatest(coalesce(p_offset,0),0);
end;
$route_body$;
    v_baseline_body text := $baseline_body$
begin
    if not private.is_deepmap_admin() then
        raise exception 'ADMIN_REQUIRED' using errcode = 'P0001';
    end if;

    return query
    with events as (
        select
            'role-' || r.id::text as event_id,
            r.action,
            actor.username as actor_username,
            target.username as target_username,
            null::text as game_id,
            null::bigint as submission_id,
            null::text as detail,
            r.created_at
        from private.deepmap_role_audit r
        left join public.profiles actor on actor.id=r.actor_id
        left join public.profiles target on target.id=r.target_user_id

        union all

        select
            'ban-' || b.id::text,
            b.action,
            actor.username,
            target.username,
            null::text,
            null::bigint,
            case
                when b.action='user_banned' then coalesce(b.reason,'') || case when b.expires_at is null then ' · permanent' else ' · until ' || b.expires_at::text end
                else coalesce(b.reason,'')
            end,
            b.created_at
        from private.deepmap_ban_audit b
        left join public.profiles actor on actor.id=b.actor_id
        left join public.profiles target on target.id=b.target_user_id

        union all

        select
            'submission-' || s.id::text || '-' || s.status,
            case when s.status='approved' then 'submission_approved' else 'submission_rejected' end,
            reviewer.username,
            submitter.username,
            s.game_id,
            s.id,
            nullif(s.review_note,''),
            coalesce(s.reviewed_at,s.updated_at)
        from public.marker_submissions s
        left join public.profiles reviewer on reviewer.id=s.reviewed_by
        left join public.profiles submitter on submitter.id=s.submitted_by
        where s.status in ('approved','rejected')
    )
    select
        e.event_id,e.action,e.actor_username,e.target_username,e.game_id,e.submission_id,e.detail,e.created_at,
        count(*) over()
    from events e
    order by e.created_at desc
    limit greatest(1,least(coalesce(p_limit,25),100))
    offset greatest(coalesce(p_offset,0),0);
end;
$baseline_body$;
    v_snapshot_sql text := $snapshot$WITH excluded AS (SELECT p.oid FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='public' AND p.proname='get_admin_audit_log_by_game_uuid' AND p.proargtypes='2950 23 23'::pg_catalog.oidvector)),
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
          AND NOT (n.nspname='public' AND p.proname='get_admin_audit_log_by_game_uuid' AND p.proargtypes='2950 23 23'::pg_catalog.oidvector)),
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
    v_expected_preservation_md5 text := NULL;
    v_fixture_failed boolean;
BEGIN
    IF v_expected_preservation_md5 IS NULL THEN
        RAISE EXCEPTION 'B7G3A_EXPECTED_PRODUCTION_PRESERVATION_FINGERPRINT_REQUIRED';
    END IF;
    -- BEGIN PRESERVATION CAPTURE
    EXECUTE v_snapshot_sql INTO v_state;
    v_data := '{}'::jsonb;
    FOR v_relation IN SELECT n.nspname,c.relname FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p') ORDER BY c.oid LOOP
        EXECUTE pg_catalog.format('SELECT pg_catalog.jsonb_build_object(''count'',pg_catalog.count(*),''md5'',pg_catalog.md5(coalesce(pg_catalog.string_agg(pg_catalog.md5(pg_catalog.to_jsonb(t)::text),'''' ORDER BY pg_catalog.to_jsonb(t)::text),''''))) FROM %I.%I t',v_relation.nspname,v_relation.relname) INTO v_actual;
        v_data := v_data || pg_catalog.jsonb_build_object(v_relation.nspname||'.'||v_relation.relname,v_actual);
    END LOOP;
    v_sequences := '{}'::jsonb;
    FOR v_relation IN SELECT n.nspname,c.relname FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('public','private') AND c.relkind='S' ORDER BY c.oid LOOP
        EXECUTE pg_catalog.format('SELECT pg_catalog.jsonb_build_object(''last_value'',last_value,''is_called'',is_called) FROM %I.%I',v_relation.nspname,v_relation.relname) INTO v_actual;
        v_sequences := v_sequences || pg_catalog.jsonb_build_object(v_relation.nspname||'.'||v_relation.relname,v_actual);
    END LOOP;
    v_state := v_state || pg_catalog.jsonb_build_object('protected_data',v_data,'sequence_state',v_sequences);
    -- END PRESERVATION CAPTURE
    v_before := v_state;
    IF pg_catalog.md5(v_before::text) IS DISTINCT FROM v_expected_preservation_md5 THEN
        RAISE EXCEPTION 'B7G3A_PRODUCTION_PRESERVATION_FINGERPRINT_MISMATCH'; END IF;
    IF v_baseline IS NULL OR (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace AND proname='get_deepmap_admin_audit')<>1 THEN
        RAISE EXCEPTION 'B7G3A_LEGACY_RPC_MISSING_OR_OVERLOADED'; END IF;
    SELECT pg_catalog.pg_get_userbyid(proowner) INTO v_owner FROM pg_catalog.pg_proc WHERE oid=v_baseline;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname=v_owner AND (rolsuper OR rolbypassrls))
        OR pg_catalog.pg_has_role('anon',v_owner,'MEMBER') OR pg_catalog.pg_has_role('authenticated',v_owner,'MEMBER') THEN
        RAISE EXCEPTION 'B7G3A_UNTRUSTED_OWNER'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=v_baseline AND p.prokind='f' AND p.pronargs=2 AND p.proargtypes='23 23'::pg_catalog.oidvector
          AND p.proargnames=ARRAY['p_limit','p_offset','event_id','action','actor_username','target_username','game_id','submission_id','detail','created_at','total_count']::text[]
          AND p.proallargtypes=ARRAY['integer'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid]
          AND p.proargmodes=ARRAY['i','i','t','t','t','t','t','t','t','t','t']::"char"[]
          AND p.proretset AND p.prorettype='record'::pg_catalog.regtype AND p.provariadic=0
          AND p.pronargdefaults=2 AND pg_catalog.pg_get_expr(p.proargdefaults,0)='25, 0'
          AND l.lanname='plpgsql' AND p.prosecdef AND p.provolatile='s'
          AND p.proconfig=ARRAY['search_path=""']::text[] AND p.proowner=pg_catalog.to_regrole(v_owner)
          AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u'
          AND p.prosupport=0 AND p.procost=100 AND p.prorows=1000 AND p.probin IS NULL AND p.prosqlbody IS NULL
          AND pg_catalog.regexp_replace(pg_catalog.btrim(p.prosrc),'[[:space:]]+',' ','g')=
              pg_catalog.regexp_replace(pg_catalog.btrim(v_baseline_body),'[[:space:]]+',' ','g')) THEN
        RAISE EXCEPTION 'B7G3A_EXACT_CONTRACT_DRIFT: %',v_baseline::pg_catalog.regprocedure;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE oid='private.is_deepmap_admin()'::pg_catalog.regprocedure
        AND prolang=(SELECT oid FROM pg_catalog.pg_language WHERE lanname='sql')
        AND prosecdef AND provolatile='s' AND proconfig=ARRAY['search_path=""']::text[]
        AND pg_catalog.btrim(pg_catalog.regexp_replace(prosrc,'[[:space:]]+',' ','g'))=
        'select exists ( select 1 from private.deepmap_admins as a where a.user_id = (select auth.uid()) );') THEN
        RAISE EXCEPTION 'B7G3A_ADMIN_GATE_DRIFT'; END IF;
    FOR v_item IN SELECT * FROM (VALUES
        ('public.games','id','uuid'),('public.games','slug','text'),('public.games','name','text'),
        ('public.marker_submissions','id','bigint'),('public.marker_submissions','game_uuid','uuid'),
        ('public.marker_submissions','marker_id','bigint'),('public.marcadores','id','bigint'),
        ('public.marcadores','game_uuid','uuid')) e(rel,col,typ) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=v_item.rel::pg_catalog.regclass
            AND attname=v_item.col AND atttypid=v_item.typ::pg_catalog.regtype AND attnum>0 AND NOT attisdropped) THEN
            RAISE EXCEPTION 'B7G3A_PARENT_COLUMN_DRIFT: %.%',v_item.rel,v_item.col; END IF;
    END LOOP;
    FOR v_item IN SELECT * FROM (VALUES ('public.games'),('public.marcadores'),('public.marker_submissions'),
        ('private.deepmap_role_audit'),('private.deepmap_ban_audit'),('public.profiles')) e(rel) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_attribute a
            ON a.attrelid=c.conrelid AND a.attname='id'
            WHERE c.conrelid=v_item.rel::pg_catalog.regclass AND c.contype='p' AND c.conkey=ARRAY[a.attnum]::smallint[]) THEN
            RAISE EXCEPTION 'B7G3A_SINGLETON_KEY_DRIFT: %',v_item.rel; END IF;
        IF NOT pg_catalog.has_table_privilege(v_owner,v_item.rel,'SELECT') THEN
            RAISE EXCEPTION 'B7G3A_OWNER_SELECT_REQUIRED: %',v_item.rel; END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM public.marker_submissions s LEFT JOIN public.games g ON g.id=s.game_uuid WHERE g.id IS NULL)
        OR EXISTS (SELECT 1 FROM public.marcadores m LEFT JOIN public.games g ON g.id=m.game_uuid WHERE g.id IS NULL) THEN
        RAISE EXCEPTION 'B7G3A_LIVE_PARENT_GAME_ORPHAN'; END IF;
    IF EXISTS (SELECT 1 FROM public.marker_submissions s JOIN public.marcadores m ON m.id=s.marker_id
        WHERE s.game_uuid IS DISTINCT FROM m.game_uuid) THEN
        RAISE EXCEPTION 'B7G3A_LIVE_PARENT_GAME_CONFLICT'; END IF;
    FOR v_item IN SELECT * FROM (VALUES
        ('public.set_deepmap_moderator(uuid,boolean)','8536cffacb8ab9ce38c7a2ccb789c3a4'),
        ('public.set_deepmap_user_ban(uuid,text,timestamptz)','81e9ed304a86d3b7622d9e1a28496d4c'),
        ('public.clear_deepmap_user_ban(uuid)','e17dc0dbb71b850efc69b689a718071f'),
        ('private.deepmap_capture_submission_revision()','d3ff5f69ceb1cd15cf09cf72b26f55ce'),
        ('private.deepmap_autoapprove_moderator_submission()','9c7c5a38258ea603f205fcddb5b48861'),
        ('private.deepmap_notify_submission_review()','a423d83f1c880b7fcb81217d99e8c96d'),
        ('private.deepmap_notify_admin_submission_received()','c0ec4567cd4efa473e393a5e1e3f6016'),
        ('private.deepmap_materialize_submission_content()','09fdd39ed4b0565d21b1f51e6494c4eb'),
        ('public.review_marker_submission(bigint,text,text)','c2d611f6339f023f3c2b43891f56af29'),
        ('public.review_marker_submission_v2(bigint,text,text,jsonb)','10327cfdf171ec2e3ba17380a909d644'),
        ('private.deepmap_stamp_marker_audit()','5ccb0483cc83a23ca899a758d91e6ce8')) e(signature,digest) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(v_item.signature)
            AND CASE WHEN v_item.signature IN ('public.set_deepmap_moderator(uuid,boolean)',
                'public.set_deepmap_user_ban(uuid,text,timestamptz)','public.clear_deepmap_user_ban(uuid)',
                'private.deepmap_stamp_marker_audit()')
                THEN pg_catalog.md5(pg_catalog.btrim(pg_catalog.regexp_replace(prosrc,'[[:space:]]+',' ','g')))
                ELSE pg_catalog.md5(pg_catalog.replace(prosrc,pg_catalog.chr(13),'')) END=v_item.digest) THEN
            RAISE EXCEPTION 'B7G3A_FROZEN_WRITER_SOURCE_DRIFT: %',v_item.signature; END IF;
    END LOOP;
    -- Expected audit/review hooks are inspected only, never fired.
    FOR v_item IN SELECT * FROM (VALUES
        ('public.marcadores','deepmap_marker_editor_audit','private.deepmap_stamp_marker_audit()',21),
        ('public.marker_submissions','deepmap_marker_submission_revision','private.deepmap_capture_submission_revision()',21),
        ('public.marker_submissions','deepmap_marker_submissions_touch_updated_at','private.deepmap_touch_submission_updated_at()',19),
        ('public.marker_submissions','deepmap_notify_admin_submission_received','private.deepmap_notify_admin_submission_received()',5),
        ('public.marker_submissions','deepmap_notify_submission_review','private.deepmap_notify_submission_review()',17),
        ('public.marker_submissions','marker_submissions_autoapprove_moderator_insert','private.deepmap_autoapprove_moderator_submission()',5),
        ('public.marker_submissions','marker_submissions_autoapprove_moderator_update','private.deepmap_autoapprove_moderator_submission()',17),
        ('public.marker_submissions','deepmap_materialize_submission_content','private.deepmap_materialize_submission_content()',17)
    ) e(rel,nm,signature,bits) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgrelid=v_item.rel::pg_catalog.regclass
            AND tgname=v_item.nm AND tgfoid=pg_catalog.to_regprocedure(v_item.signature)
            AND tgtype=v_item.bits AND tgenabled='O' AND NOT tgisinternal) THEN
            RAISE EXCEPTION 'B7G3A_FROZEN_TRIGGER_DRIFT: %',v_item.nm; END IF;
    END LOOP;
    -- Exact pg_trigger rows (including column lists/WHEN), function metadata/ACLs
    -- and all legacy RPCs are additionally frozen by the full preservation capture.
    IF NOT pg_catalog.has_schema_privilege(v_owner,'private','USAGE')
        OR NOT pg_catalog.has_schema_privilege(v_owner,'public','USAGE')
        OR NOT pg_catalog.has_schema_privilege('authenticated','public','USAGE')
        OR NOT pg_catalog.has_function_privilege(v_owner,'private.is_deepmap_admin()','EXECUTE') THEN
        RAISE EXCEPTION 'B7G3A_OWNER_AUTH_SCHEMA_ACCESS_DRIFT'; END IF;
    IF v_rpc IS NULL OR (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace
        AND proname='get_admin_audit_log_by_game_uuid')<>1 THEN RAISE EXCEPTION 'B7G3A_RPC_MISSING_OR_OVERLOADED'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=v_rpc AND p.prokind='f' AND p.pronargs=3 AND p.proargtypes='2950 23 23'::pg_catalog.oidvector
          AND p.proargnames=ARRAY['p_game_uuid','p_limit','p_offset','event_id','action','actor_username','target_username','game_id','submission_id','detail','created_at','total_count','marker_id','route_game_uuid','route_game_slug','route_game_name']::text[]
          AND p.proallargtypes=ARRAY['uuid'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid]
          AND p.proargmodes=ARRAY['i','i','i','t','t','t','t','t','t','t','t','t','t','t','t','t']::"char"[]
          AND p.proretset AND p.prorettype='record'::pg_catalog.regtype AND p.provariadic=0
          AND p.pronargdefaults=3 AND pg_catalog.pg_get_expr(p.proargdefaults,0)='NULL::uuid, 25, 0'
          AND l.lanname='plpgsql' AND p.prosecdef AND p.provolatile='s'
          AND p.proconfig=ARRAY['search_path=""']::text[] AND p.proowner=pg_catalog.to_regrole(v_owner)
          AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u'
          AND p.prosupport=0 AND p.procost=100 AND p.prorows=1000 AND p.probin IS NULL AND p.prosqlbody IS NULL
          AND pg_catalog.regexp_replace(pg_catalog.btrim(p.prosrc),'[[:space:]]+',' ','g')=
              pg_catalog.regexp_replace(pg_catalog.btrim(v_body),'[[:space:]]+',' ','g')) THEN
        RAISE EXCEPTION 'B7G3A_EXACT_CONTRACT_DRIFT: %',v_rpc::pg_catalog.regprocedure;
    END IF;
    FOR v_item IN SELECT v_baseline AS rpc UNION ALL SELECT v_rpc LOOP
        IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
            LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_item.rpc AND
            (a.grantor<>p.proowner OR a.privilege_type<>'EXECUTE' OR a.is_grantable
                OR (a.grantee<>p.proowner AND (a.grantee=0 OR r.rolname IS NULL OR r.rolname NOT IN ('authenticated','service_role')))))
            OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_item.rpc AND a.grantee=p.proowner)
            OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_item.rpc AND a.grantee='authenticated'::pg_catalog.regrole::oid)
            OR NOT pg_catalog.has_function_privilege('authenticated',v_item.rpc,'EXECUTE')
            OR pg_catalog.has_function_privilege('anon',v_item.rpc,'EXECUTE') THEN RAISE EXCEPTION 'B7G3A_RPC_ACL_DRIFT'; END IF;
    END LOOP;
    SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_baseline
        FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_baseline;
    SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_rpc
        FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc;
    IF v_acl_rpc IS DISTINCT FROM v_acl_baseline THEN RAISE EXCEPTION 'B7G3A_DIRECT_ACL_PARITY_DRIFT'; END IF;
    FOR v_role IN SELECT rolname FROM pg_catalog.pg_roles LOOP
        IF pg_catalog.has_function_privilege(v_role.rolname,v_rpc,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege(v_role.rolname,v_baseline,'EXECUTE') THEN
            RAISE EXCEPTION 'B7G3A_ALL_ROLE_EXECUTE_PARITY_DRIFT: %',v_role.rolname; END IF;
    END LOOP;
    -- Pure fixtures: same CASE and games join as the exact pinned RPC body.
    -- UUIDs, slug renames, deleted parents and legacy alias text are independent.
    WITH games(id,slug,name) AS (VALUES
        ('00000000-0000-0000-0000-000000000001'::uuid,'current-slug'::text,'Current name'::text),
        ('00000000-0000-0000-0000-000000000002'::uuid,'second-slug','Second name')),
    cases(label,submission_live,submission_uuid,marker_live,marker_uuid,legacy_game_id,expected_uuid) AS (VALUES
        ('submission only',true,1,false,NULL::integer,'old-alias',1),
        ('matching parents',true,1,true,1,'different-historical-alias',1),
        ('conflicting parents',true,1,true,2,'current-slug',NULL),
        ('missing marker',true,1,false,2,'old-alias',1),
        ('missing game',true,3,false,NULL,'current-slug',NULL),
        ('missing submission',false,1,true,1,'current-slug',NULL),
        ('global role',false,NULL,false,NULL,'current-slug',NULL),
        ('global suspension',false,NULL,false,NULL,'old-alias',NULL),
        ('null submission UUID with live marker',true,NULL,true,1,'current-slug',NULL),
        ('null marker UUID',true,1,true,NULL,'current-slug',NULL),
        ('both parent UUIDs NULL',true,NULL,true,NULL,'current-slug',NULL),
        ('second game',true,2,true,2,'old-alias',2)),
    fixture AS (SELECT c.*,s.game_uuid AS s_uuid,m.game_uuid AS m_uuid,g.id,g.slug,g.name
        FROM cases c
        LEFT JOIN LATERAL (SELECT 9007199254740993::bigint AS id,
            CASE c.submission_uuid WHEN 1 THEN '00000000-0000-0000-0000-000000000001'::uuid
                WHEN 2 THEN '00000000-0000-0000-0000-000000000002'::uuid
                WHEN 3 THEN '00000000-0000-0000-0000-000000000003'::uuid END AS game_uuid
            WHERE c.submission_live) s ON true
        LEFT JOIN LATERAL (SELECT 9007199254740995::bigint AS id,
            CASE c.marker_uuid WHEN 1 THEN '00000000-0000-0000-0000-000000000001'::uuid
                WHEN 2 THEN '00000000-0000-0000-0000-000000000002'::uuid END AS game_uuid
            WHERE c.marker_live) m ON true
        LEFT JOIN games g ON g.id=CASE WHEN s.id IS NULL THEN NULL::uuid ELSE
            CASE WHEN m.id IS NOT NULL THEN
                CASE WHEN s.game_uuid = m.game_uuid THEN s.game_uuid ELSE NULL::uuid END
                ELSE s.game_uuid END END)
    SELECT EXISTS (SELECT 1 FROM fixture f WHERE
        f.id IS DISTINCT FROM CASE f.expected_uuid
            WHEN 1 THEN '00000000-0000-0000-0000-000000000001'::uuid
            WHEN 2 THEN '00000000-0000-0000-0000-000000000002'::uuid END
        OR f.slug IS DISTINCT FROM CASE f.expected_uuid WHEN 1 THEN 'current-slug' WHEN 2 THEN 'second-slug' END
        OR f.name IS DISTINCT FROM CASE f.expected_uuid WHEN 1 THEN 'Current name' WHEN 2 THEN 'Second name' END)
    INTO v_fixture_failed;
    IF v_fixture_failed THEN RAISE EXCEPTION 'B7G3A_ROUTE_FIXTURE_FAILED'; END IF;

    -- Scope includes globals only for NULL; count is after scope and before pagination.
    WITH events(event_id,created_at,game_uuid) AS (VALUES
        ('role-1'::text,'2026-01-01 UTC'::timestamptz,NULL::uuid),
        ('submission-2-approved','2026-01-01 UTC','00000000-0000-0000-0000-000000000001'::uuid),
        ('submission-1-approved','2026-01-01 UTC','00000000-0000-0000-0000-000000000002'::uuid)),
    scopes(p_game_uuid,expected_total) AS (VALUES
        (NULL::uuid,3::bigint),('00000000-0000-0000-0000-000000000001'::uuid,1),
        ('00000000-0000-0000-0000-000000000002'::uuid,1),('00000000-0000-0000-0000-000000000003'::uuid,0))
    SELECT EXISTS (SELECT 1 FROM scopes s WHERE
        (SELECT count(*) FROM events g WHERE s.p_game_uuid IS NULL OR g.game_uuid=s.p_game_uuid)<>s.expected_total)
        OR (SELECT pg_catalog.array_agg(event_id ORDER BY created_at DESC,event_id COLLATE pg_catalog."C" DESC) FROM events)
            IS DISTINCT FROM ARRAY['submission-2-approved','submission-1-approved','role-1']::text[]
    INTO v_fixture_failed;
    IF v_fixture_failed THEN RAISE EXCEPTION 'B7G3A_SCOPE_ORDER_FIXTURE_FAILED'; END IF;

    WITH cases(p_limit,p_offset,want_limit,want_offset) AS (VALUES
        (NULL::integer,NULL::integer,25,0),(-1,-1,1,0),(0,0,1,0),(1,2,1,2),
        (10,0,10,0),(20,0,20,0),(50,0,50,0),(101,0,100,0),(2147483647,2147483647,100,2147483647))
    SELECT EXISTS (SELECT 1 FROM cases WHERE greatest(1,least(coalesce(p_limit,25),100))<>want_limit
        OR greatest(coalesce(p_offset,0),0)<>want_offset)
    INTO v_fixture_failed;
    IF v_fixture_failed THEN RAISE EXCEPTION 'B7G3A_CLAMP_FIXTURE_FAILED'; END IF;
    WITH events(id) AS (VALUES (9007199254740993::bigint),(9007199254740995::bigint),(9007199254740997::bigint)),
    page AS (SELECT id,count(*) OVER() AS total_count FROM events ORDER BY id DESC LIMIT 1 OFFSET 1),
    empty_page AS (SELECT id,count(*) OVER() AS total_count FROM events ORDER BY id DESC LIMIT 1 OFFSET 3)
    SELECT (SELECT count(*) FROM page)<>1 OR (SELECT total_count FROM page) IS DISTINCT FROM 3::bigint
        OR (SELECT id FROM page) IS DISTINCT FROM 9007199254740995::bigint
        OR EXISTS (SELECT 1 FROM empty_page) INTO v_fixture_failed;
    IF v_fixture_failed THEN RAISE EXCEPTION 'B7G3A_BIGINT_PAGINATION_TOTAL_FIXTURE_FAILED'; END IF;

    -- Runtime-positive authorization only with an existing admin JWT; no auth manipulation.
    IF auth.uid() IS NULL OR NOT private.is_deepmap_admin() THEN
        BEGIN
            PERFORM * FROM public.get_admin_audit_log_by_game_uuid(NULL,1,0);
            RAISE EXCEPTION 'B7G3A_UNAUTHORIZED_CALL_ACCEPTED';
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ADMIN_REQUIRED' THEN RAISE; END IF;
        END;
        RAISE NOTICE 'SKIP runtime-positive admin branch: caller has no admin JWT; source, ACL and fixtures remain mandatory';
    ELSE
        IF EXISTS (SELECT 1 FROM public.get_admin_audit_log_by_game_uuid(NULL,1,0) WHERE total_count<1) THEN
            RAISE EXCEPTION 'B7G3A_RUNTIME_TOTAL_INVALID'; END IF;
    END IF;
    -- BEGIN PRESERVATION CAPTURE
    EXECUTE v_snapshot_sql INTO v_state;
    v_data := '{}'::jsonb;
    FOR v_relation IN SELECT n.nspname,c.relname FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p') ORDER BY c.oid LOOP
        EXECUTE pg_catalog.format('SELECT pg_catalog.jsonb_build_object(''count'',pg_catalog.count(*),''md5'',pg_catalog.md5(coalesce(pg_catalog.string_agg(pg_catalog.md5(pg_catalog.to_jsonb(t)::text),'''' ORDER BY pg_catalog.to_jsonb(t)::text),''''))) FROM %I.%I t',v_relation.nspname,v_relation.relname) INTO v_actual;
        v_data := v_data || pg_catalog.jsonb_build_object(v_relation.nspname||'.'||v_relation.relname,v_actual);
    END LOOP;
    v_sequences := '{}'::jsonb;
    FOR v_relation IN SELECT n.nspname,c.relname FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('public','private') AND c.relkind='S' ORDER BY c.oid LOOP
        EXECUTE pg_catalog.format('SELECT pg_catalog.jsonb_build_object(''last_value'',last_value,''is_called'',is_called) FROM %I.%I',v_relation.nspname,v_relation.relname) INTO v_actual;
        v_sequences := v_sequences || pg_catalog.jsonb_build_object(v_relation.nspname||'.'||v_relation.relname,v_actual);
    END LOOP;
    v_state := v_state || pg_catalog.jsonb_build_object('protected_data',v_data,'sequence_state',v_sequences);
    -- END PRESERVATION CAPTURE
    v_after := v_state;
    IF v_after IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'B7G3A_PRESERVATION_FAILED'; END IF;
    RAISE NOTICE 'PASS B7g3a verifier; production fingerprint matched; protected state unchanged';
END;
$verify$;
ROLLBACK;
