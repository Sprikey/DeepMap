-- B7g1a: additive own-notifications READ contract only.
-- Empty TABLE results intentionally carry no total_count. B7g1b recovery uses
-- THIS SAME RPC at offset 0, reads total, clamps and reloads the corrected page.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL TimeZone = 'UTC';
DO $migration$
DECLARE
    v_baseline oid := pg_catalog.to_regprocedure('public.get_my_marker_submissions_page_by_game_uuid(uuid,integer,integer)');
    v_rpc oid := pg_catalog.to_regprocedure('public.get_my_notifications_with_route_context(integer,integer)');
    v_owner name; v_grantee name; v_relation record; v_item record; v_role record;
    v_before jsonb; v_after jsonb; v_state jsonb; v_data jsonb; v_sequences jsonb; v_actual jsonb;
    v_acl_baseline jsonb; v_acl_rpc jsonb; v_service_direct boolean;
    v_count bigint;
    v_body text := $route_body$DECLARE
    v_user_id uuid := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = 'P0001';
    END IF;
    RETURN QUERY
    SELECT n.id,n.kind,n.game_id,n.submission_id,n.marker_id,
        n.submission_type,n.decision,n.review_note,n.is_read,n.created_at,n.metadata,
        g.id AS route_game_uuid,g.slug AS route_game_slug,
        m.is_published AS route_marker_is_published,pg_catalog.count(*) OVER () AS total_count
    FROM public.user_notifications n
    LEFT JOIN public.marker_submissions s ON s.id = n.submission_id
    LEFT JOIN public.marcadores m ON m.id = n.marker_id
    LEFT JOIN public.games g ON g.id = CASE
        WHEN s.id IS NOT NULL AND m.id IS NOT NULL THEN
            CASE WHEN s.game_uuid = m.game_uuid THEN s.game_uuid ELSE NULL::uuid END
        WHEN s.id IS NOT NULL THEN s.game_uuid
        WHEN m.id IS NOT NULL THEN m.game_uuid
        ELSE NULL::uuid
    END
    WHERE n.user_id = v_user_id
    ORDER BY n.created_at DESC,n.id DESC
    LIMIT greatest(1,least(coalesce(p_limit,20),100))
    OFFSET greatest(coalesce(p_offset,0),0);
END;
$route_body$;
    v_baseline_body text := $baseline_body$
begin
    if (select auth.uid()) is null then
        raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
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
        count(*) over() as total_count,
        s.game_uuid,
        g.slug
    from public.marker_submissions as s
    left join public.games as g on g.id = s.game_uuid
    left join public.profiles as submitter
      on submitter.id = s.submitted_by
    left join public.profiles as reviewer
      on reviewer.id = s.reviewed_by
    where s.game_uuid = p_game_uuid
      and s.submitted_by = (select auth.uid())
    order by
        case s.status when 'pending' then 0 else 1 end,
        s.updated_at desc,
        s.id desc
    limit greatest(1, least(coalesce(p_limit, 20), 50))
    offset greatest(coalesce(p_offset, 0), 0);
end;
$baseline_body$;
    v_snapshot_sql text := $snapshot$WITH excluded AS (SELECT p.oid FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='public' AND p.proname='get_my_notifications_with_route_context' AND p.proargtypes='23 23'::pg_catalog.oidvector)),
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
          AND NOT (n.nspname='public' AND p.proname='get_my_notifications_with_route_context' AND p.proargtypes='23 23'::pg_catalog.oidvector)),
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
    LOCK TABLE public.user_notifications,public.marker_submissions,public.marcadores,public.games IN SHARE MODE;
    -- BEGIN SHARED PREFLIGHT: all checks precede the first mutation.
    IF v_baseline IS NULL OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=v_baseline AND p.prokind='f' AND p.prosecdef AND p.provolatile='s'
          AND l.lanname='plpgsql' AND p.proconfig=ARRAY['search_path=""']::text[]
          AND p.proargnames=ARRAY['p_game_uuid','p_limit','p_offset','id','game_id','marker_id','submission_type','correction_kind','status','submitted_by','submitted_username','payload','note','reviewed_by','reviewed_username','reviewed_at','review_note','created_at','updated_at','revision_count','total_count','game_uuid','game_slug']::text[]
          AND p.proallargtypes=ARRAY['uuid'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'jsonb'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid]
          AND p.proargmodes=ARRAY['i','i','i','t','t','t','t','t','t','t','t','t','t','t','t','t','t','t','t','t','t','t','t']::"char"[]
          AND p.proretset AND p.prorettype='record'::pg_catalog.regtype AND p.provariadic=0
          AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u'
          AND p.prosupport=0 AND p.procost=100 AND p.prorows=1000 AND p.probin IS NULL AND p.prosqlbody IS NULL
          AND p.pronargdefaults=2 AND pg_catalog.pg_get_expr(p.proargdefaults,0)='20, 0'
          AND pg_catalog.regexp_replace(pg_catalog.btrim(p.prosrc),'[[:space:]]+',' ','g')=
              pg_catalog.regexp_replace(pg_catalog.btrim(v_baseline_body),'[[:space:]]+',' ','g'))
       OR (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace
           AND proname='get_my_marker_submissions_page_by_game_uuid')<>1
       OR pg_catalog.to_regprocedure('public.get_marker_review_context_by_game_uuid(uuid,bigint)') IS NULL THEN
        RAISE EXCEPTION 'B7G1A_B7E1_B7E2_BASELINE_DRIFT';
    END IF;
    SELECT r.rolname INTO STRICT v_owner FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner WHERE p.oid=v_baseline;
    IF EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated'),('service_role')) e(role_name)
        WHERE pg_catalog.to_regrole(e.role_name) IS NULL) THEN RAISE EXCEPTION 'B7G1A_ROLE_MISSING'; END IF;
    IF v_owner IN ('anon','authenticated','service_role') OR pg_catalog.pg_has_role('anon',v_owner,'MEMBER')
        OR pg_catalog.pg_has_role('authenticated',v_owner,'MEMBER') THEN RAISE EXCEPTION 'B7G1A_UNTRUSTED_OWNER'; END IF;
    FOR v_relation IN SELECT c.* FROM pg_catalog.pg_class c WHERE c.oid IN (
        'public.user_notifications'::pg_catalog.regclass,'public.marker_submissions'::pg_catalog.regclass,
        'public.marcadores'::pg_catalog.regclass,'public.games'::pg_catalog.regclass) LOOP
        -- Runner also needs full visibility, so real-data validation cannot silently pass under RLS.
        FOREACH v_grantee IN ARRAY ARRAY[v_owner,CURRENT_USER::name] LOOP
            IF v_relation.relkind<>'r' OR NOT pg_catalog.has_schema_privilege(v_grantee,v_relation.relnamespace,'USAGE')
                OR NOT pg_catalog.has_table_privilege(v_grantee,v_relation.oid,'SELECT')
                OR (v_relation.relrowsecurity AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname=v_grantee
                    AND (r.rolsuper OR r.rolbypassrls OR (r.oid=v_relation.relowner AND NOT v_relation.relforcerowsecurity)))) THEN
                RAISE EXCEPTION 'B7G1A_FULL_READ_RLS_ACCESS_REQUIRED: %, %',v_grantee,v_relation.relname;
            END IF;
        END LOOP;
    END LOOP;
    IF NOT pg_catalog.has_schema_privilege('authenticated','public','USAGE') THEN RAISE EXCEPTION 'B7G1A_AUTHENTICATED_PUBLIC_SCHEMA_USAGE_REQUIRED'; END IF;
    IF NOT pg_catalog.has_schema_privilege(v_owner,'auth','USAGE')
        OR NOT pg_catalog.has_function_privilege(v_owner,'auth.uid()','EXECUTE') THEN RAISE EXCEPTION 'B7G1A_OWNER_AUTH_ACCESS_DRIFT'; END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_attribute WHERE attrelid='public.user_notifications'::pg_catalog.regclass
        AND attnum>0 AND NOT attisdropped)<>12 THEN RAISE EXCEPTION 'B7G1A_NOTIFICATION_COLUMN_COUNT_DRIFT'; END IF;
    FOR v_item IN SELECT * FROM (VALUES
        ('id','bigint',true,'d',NULL::text),('user_id','uuid',true,'',NULL),('game_id','text',false,'',NULL),
        ('submission_id','bigint',false,'',NULL),('marker_id','bigint',false,'',NULL),('submission_type','text',false,'',NULL),
        ('decision','text',false,'',NULL),('review_note','text',false,'',NULL),('is_read','boolean',true,'','false'),
        ('created_at','timestamptz',true,'','now()'),('kind','text',true,'','''submission_review''::text'),('metadata','jsonb',true,'','''{}''::jsonb')
    ) e(col,typ,nn,identity_kind,default_expr) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
            WHERE a.attrelid='public.user_notifications'::pg_catalog.regclass AND a.attname=v_item.col AND a.attnum>0 AND NOT a.attisdropped
              AND a.atttypid=pg_catalog.to_regtype(v_item.typ) AND a.attnotnull=v_item.nn AND a.attidentity::text=v_item.identity_kind AND a.attgenerated=''
              AND pg_catalog.pg_get_expr(d.adbin,d.adrelid) IS NOT DISTINCT FROM v_item.default_expr) THEN
            RAISE EXCEPTION 'B7G1A_NOTIFICATION_COLUMN_DRIFT: %',v_item.col;
        END IF;
    END LOOP;
    FOR v_item IN SELECT * FROM (VALUES
        ('public.marker_submissions','id','bigint'),('public.marker_submissions','game_uuid','uuid'),
        ('public.marcadores','id','bigint'),('public.marcadores','game_uuid','uuid'),('public.marcadores','is_published','boolean'),
        ('public.games','id','uuid'),('public.games','slug','text')
    ) e(rel,col,typ) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid=pg_catalog.to_regclass(v_item.rel)
            AND a.attname=v_item.col AND a.attnum>0 AND NOT a.attisdropped AND a.attnotnull AND a.atttypid=pg_catalog.to_regtype(v_item.typ)) THEN
            RAISE EXCEPTION 'B7G1A_PARENT_COLUMN_DRIFT: %.%',v_item.rel,v_item.col;
        END IF;
    END LOOP;
    FOR v_item IN SELECT * FROM (VALUES ('public.user_notifications','id'),('public.marker_submissions','id'),('public.marcadores','id'),('public.games','id'),('public.games','slug')) e(rel,col) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
            WHERE c.conrelid=pg_catalog.to_regclass(v_item.rel) AND c.contype IN ('p','u') AND c.convalidated AND NOT c.condeferrable
              AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive AND i.indpred IS NULL AND i.indexprs IS NULL
              AND c.conkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.conrelid AND a.attname=v_item.col)]::smallint[]) THEN
            RAISE EXCEPTION 'B7G1A_SINGLETON_KEY_DRIFT: %.%',v_item.rel,v_item.col;
        END IF;
    END LOOP;
    IF (SELECT count(*) FROM pg_catalog.pg_constraint WHERE conrelid='public.user_notifications'::pg_catalog.regclass)<>4 THEN
        RAISE EXCEPTION 'B7G1A_NOTIFICATION_CONSTRAINT_COUNT_DRIFT'; END IF;
    FOR v_item IN SELECT * FROM (VALUES ('submission_id','public.marker_submissions'),('marker_id','public.marcadores')) e(col,target) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.user_notifications'::pg_catalog.regclass
            AND c.contype='f' AND c.confrelid=pg_catalog.to_regclass(v_item.target) AND c.convalidated AND NOT c.condeferrable
            AND c.confmatchtype='s' AND c.confupdtype='a' AND c.confdeltype='n'
            AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=c.conrelid AND attname=v_item.col)]::smallint[]
            AND c.confkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=c.confrelid AND attname='id')]::smallint[]) THEN
            RAISE EXCEPTION 'B7G1A_NOTIFICATION_FK_DRIFT: %',v_item.col;
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.user_notifications'::pg_catalog.regclass
        AND c.conname='user_notifications_kind_check' AND c.contype='c' AND c.convalidated AND NOT c.condeferrable
        AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(c.conbin,c.conrelid),'[[:space:]()]','','g')=$check$kind='submission_review'::textANDsubmission_type=ANYARRAY['create'::text,'correction'::text]ANDdecision=ANYARRAY['approved'::text,'rejected'::text]ORkind=ANYARRAY['moderator_granted'::text,'moderator_revoked'::text,'account_suspended'::text,'account_reinstated'::text]ANDsubmission_typeISNULLANDdecisionISNULLORkind='admin_submission_received'::textANDsubmission_type=ANYARRAY['create'::text,'correction'::text]ANDdecisionISNULLORkind='admin_moderation_decision'::textANDsubmission_type=ANYARRAY['create'::text,'correction'::text]ANDdecision=ANYARRAY['approved'::text,'rejected'::text]$check$) THEN
        RAISE EXCEPTION 'B7G1A_FINAL_KIND_CHECK_DRIFT'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class WHERE oid='public.user_notifications'::pg_catalog.regclass AND relrowsecurity AND NOT relforcerowsecurity)
        OR (SELECT count(*) FROM pg_catalog.pg_policy WHERE polrelid='public.user_notifications'::pg_catalog.regclass)<>2 THEN RAISE EXCEPTION 'B7G1A_NOTIFICATION_RLS_DRIFT'; END IF;
    FOR v_item IN SELECT * FROM (VALUES ('user_notifications_read_own','r'),('user_notifications_update_own','w')) e(nm,cmd) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.user_notifications'::pg_catalog.regclass
            AND p.polname=v_item.nm AND p.polcmd::text=v_item.cmd AND p.polpermissive AND p.polroles=ARRAY['authenticated'::pg_catalog.regrole::oid]
            AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'[[:space:]()]','','g')='user_id=SELECTauth.uidASuid'
            AND (CASE WHEN v_item.cmd='r' THEN p.polwithcheck IS NULL ELSE
                pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),'[[:space:]()]','','g')='user_id=SELECTauth.uidASuid' END)) THEN
            RAISE EXCEPTION 'B7G1A_NOTIFICATION_POLICY_DRIFT: %',v_item.nm; END IF;
    END LOOP;
    IF NOT pg_catalog.has_table_privilege('authenticated','public.user_notifications','SELECT')
        OR NOT pg_catalog.has_column_privilege('authenticated','public.user_notifications','is_read','UPDATE')
        OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.user_notifications'::pg_catalog.regclass AND a.attnum>0 AND NOT a.attisdropped
            AND a.attname<>'is_read' AND pg_catalog.has_column_privilege('authenticated',a.attrelid,a.attnum,'UPDATE'))
        OR pg_catalog.has_table_privilege('authenticated','public.user_notifications','INSERT,DELETE,TRUNCATE,REFERENCES,TRIGGER')
        OR pg_catalog.has_table_privilege('anon','public.user_notifications','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
        OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c CROSS JOIN LATERAL pg_catalog.aclexplode(c.relacl) a WHERE c.oid='public.user_notifications'::pg_catalog.regclass AND a.grantee=0)
        OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute c CROSS JOIN LATERAL pg_catalog.aclexplode(c.attacl) a WHERE c.attrelid='public.user_notifications'::pg_catalog.regclass AND a.grantee=0) THEN
        RAISE EXCEPTION 'B7G1A_NOTIFICATION_BROWSER_ACL_DRIFT'; END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_index WHERE indrelid='public.user_notifications'::pg_catalog.regclass)<>5 THEN RAISE EXCEPTION 'B7G1A_NOTIFICATION_INDEX_COUNT_DRIFT'; END IF;
    FOR v_item IN SELECT * FROM (VALUES
        ('user_notifications_pkey',true,ARRAY['id']::text[],NULL::text,ARRAY[0]::smallint[]),
        ('user_notifications_user_created_idx',false,ARRAY['user_id','created_at'],NULL,ARRAY[0,3]::smallint[]),
        ('user_notifications_user_unread_idx',false,ARRAY['user_id','created_at'],'is_read=false',ARRAY[0,3]::smallint[]),
        ('user_notifications_submission_decision_uidx',true,ARRAY['user_id','submission_id','decision'],'submission_idISNOTNULL',ARRAY[0,0,0]::smallint[]),
        ('user_notifications_user_submission_kind_uidx',true,ARRAY['user_id','submission_id','kind'],'submission_idISNOTNULL',ARRAY[0,0,0]::smallint[])
    ) e(nm,uniq,cols,predicate,options) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid JOIN pg_catalog.pg_am am ON am.oid=c.relam
            WHERE i.indrelid='public.user_notifications'::pg_catalog.regclass AND c.relname=v_item.nm AND am.amname='btree'
              AND i.indisunique=v_item.uniq AND i.indisvalid AND i.indisready AND i.indislive AND i.indexprs IS NULL
              AND i.indnkeyatts=pg_catalog.cardinality(v_item.cols) AND i.indnatts=i.indnkeyatts
              AND ARRAY(SELECT pg_catalog.unnest(i.indoption::smallint[]))=v_item.options
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(i.indkey::smallint[]) WITH ORDINALITY k(num,pos)
                  JOIN pg_catalog.pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.num ORDER BY k.pos)=v_item.cols
              AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(i.indpred,i.indrelid),'[[:space:]()]','','g') IS NOT DISTINCT FROM v_item.predicate) THEN
            RAISE EXCEPTION 'B7G1A_NOTIFICATION_INDEX_DRIFT: %',v_item.nm; END IF;
    END LOOP;
    IF pg_catalog.to_regclass(pg_catalog.pg_get_serial_sequence('public.user_notifications','id')) IS DISTINCT FROM pg_catalog.to_regclass('public.user_notifications_id_seq') THEN
        RAISE EXCEPTION 'B7G1A_NOTIFICATION_IDENTITY_SEQUENCE_DRIFT'; END IF;
    SELECT pg_catalog.count(*) INTO v_count FROM public.user_notifications n
        JOIN public.marker_submissions s ON s.id=n.submission_id JOIN public.marcadores m ON m.id=n.marker_id
        WHERE s.game_uuid IS DISTINCT FROM m.game_uuid;
    IF v_count<>0 THEN RAISE EXCEPTION 'B7G1A_LIVE_NOTIFICATION_PARENT_GAME_CONFLICT: %',v_count; END IF;
    RAISE NOTICE 'PASS live notification parent game mismatch count = 0';
    IF EXISTS (SELECT 1 FROM public.marker_submissions s LEFT JOIN public.games g ON g.id=s.game_uuid WHERE g.id IS NULL)
        OR EXISTS (SELECT 1 FROM public.marcadores m LEFT JOIN public.games g ON g.id=m.game_uuid WHERE g.id IS NULL) THEN
        RAISE EXCEPTION 'B7G1A_UUID_PARENT_ORPHAN'; END IF;
    FOR v_item IN SELECT * FROM (VALUES
        ('private.deepmap_notify_admin_submission_received()','c0ec4567cd4efa473e393a5e1e3f6016'),
        ('private.deepmap_notify_submission_review()','a423d83f1c880b7fcb81217d99e8c96d'),
        ('public.set_deepmap_user_ban(uuid,text,timestamptz)','a36d1157b8c8ed42797362a87d1d4758'),
        ('public.clear_deepmap_user_ban(uuid)','a9145db0007c4168759856a693fcf640'),
        ('public.set_deepmap_moderator(uuid,boolean)','6e56481a85adc4fd03a22070c0bc4601'),
        ('private.deepmap_autoapprove_moderator_submission()','9c7c5a38258ea603f205fcddb5b48861')
    ) e(signature,source_md5) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure(v_item.signature)
            AND p.prosecdef AND p.proconfig=ARRAY['search_path=""']::text[]
            AND pg_catalog.md5(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),''))=v_item.source_md5) THEN
            RAISE EXCEPTION 'B7G1A_FROZEN_NOTIFICATION_WRITER_DRIFT: %',v_item.signature; END IF;
    END LOOP;
    FOR v_item IN SELECT * FROM (VALUES
        ('deepmap_notify_admin_submission_received','private.deepmap_notify_admin_submission_received()',5,ARRAY[]::text[],NULL::text),
        ('deepmap_notify_submission_review','private.deepmap_notify_submission_review()',17,ARRAY['status','marker_id','review_note','reviewed_by'],'old.statusisdistinctfromnew.status'),
        ('marker_submissions_autoapprove_moderator_insert','private.deepmap_autoapprove_moderator_submission()',5,ARRAY[]::text[],NULL),
        ('marker_submissions_autoapprove_moderator_update','private.deepmap_autoapprove_moderator_submission()',17,ARRAY['payload','note','correction_kind'],$qual$new.status='pending'::text$qual$)
    ) e(nm,signature,event_type,attrs,qual) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.marker_submissions'::pg_catalog.regclass
            AND t.tgname=v_item.nm AND t.tgfoid=pg_catalog.to_regprocedure(v_item.signature) AND t.tgtype=v_item.event_type
            AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgnargs=0
            AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(t.tgattr::smallint[]) WITH ORDINALITY k(num,pos)
                JOIN pg_catalog.pg_attribute a ON a.attrelid=t.tgrelid AND a.attnum=k.num ORDER BY k.pos)=v_item.attrs
            AND pg_catalog.lower(pg_catalog.regexp_replace(pg_catalog.substring(pg_catalog.pg_get_triggerdef(t.oid,true),
                ' WHEN [(](.*)[)] EXECUTE FUNCTION '),'[[:space:]()]','','g')) IS NOT DISTINCT FROM v_item.qual) THEN
            RAISE EXCEPTION 'B7G1A_NOTIFICATION_TRIGGER_DRIFT: %',v_item.nm; END IF;
    END LOOP;
    -- UUID bridge dependencies are catalog-checked, never used as route lookups.
    FOR v_item IN SELECT * FROM (VALUES
        ('public.marker_submissions','marker_submissions_marker_game_uuid_fk',ARRAY['marker_id','game_id','game_uuid']::text[],
            'public.marcadores',ARRAY['id','game_id','game_uuid']::text[],'c'),
        ('public.marker_submissions','marker_submissions_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
            'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[],'r'),
        ('public.marcadores','marcadores_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
            'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[],'r')
    ) e(rel,nm,cols,target,target_cols,del) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass(v_item.rel)
            AND c.conname=v_item.nm AND c.contype='f' AND c.confrelid=pg_catalog.to_regclass(v_item.target)
            AND c.convalidated AND NOT c.condeferrable AND c.confmatchtype='s' AND c.confupdtype='a' AND c.confdeltype::text=v_item.del
            AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos)
                JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=v_item.cols
            AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num,pos)
                JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)=v_item.target_cols) THEN
            RAISE EXCEPTION 'B7G1A_UUID_BRIDGE_FK_DRIFT: %',v_item.nm; END IF;
    END LOOP;
    -- END SHARED PREFLIGHT
    FOR v_item IN SELECT v_baseline AS rpc LOOP
        IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
            LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_item.rpc AND
            (a.grantor<>p.proowner OR a.privilege_type<>'EXECUTE' OR a.is_grantable
                OR (a.grantee<>p.proowner AND (a.grantee=0 OR r.rolname IS NULL OR r.rolname NOT IN ('authenticated','service_role')))))
            OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_item.rpc AND a.grantee=p.proowner)
            OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_item.rpc AND a.grantee='authenticated'::pg_catalog.regrole::oid)
            OR NOT pg_catalog.has_function_privilege('authenticated',v_item.rpc,'EXECUTE')
            OR pg_catalog.has_function_privilege('anon',v_item.rpc,'EXECUTE') THEN RAISE EXCEPTION 'B7G1A_RPC_ACL_DRIFT'; END IF;
    END LOOP;
    IF v_rpc IS NOT NULL THEN
    -- BEGIN EXACT RPC CHECK
    IF v_rpc IS NULL OR (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace AND proname='get_my_notifications_with_route_context')<>1 THEN
        RAISE EXCEPTION 'B7G1A_RPC_MISSING_OR_OVERLOADED'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=v_rpc AND p.prokind='f' AND p.pronargs=2
          AND ARRAY(SELECT pg_catalog.unnest(p.proargtypes::oid[]))=ARRAY['integer'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid]
          AND p.proallargtypes=ARRAY['integer'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'boolean'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'jsonb'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'boolean'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid]
          AND p.proargnames=ARRAY['p_limit','p_offset','id','kind','game_id','submission_id','marker_id','submission_type','decision','review_note','is_read','created_at','metadata','route_game_uuid','route_game_slug','route_marker_is_published','total_count']::text[]
          AND p.proargmodes=ARRAY['i','i','t','t','t','t','t','t','t','t','t','t','t','t','t','t','t']::"char"[]
          AND p.prorettype='record'::pg_catalog.regtype AND p.proretset AND p.provariadic=0
          AND p.pronargdefaults=2 AND pg_catalog.pg_get_expr(p.proargdefaults,0)='20, 0'
          AND p.prosecdef AND p.provolatile='s' AND p.proconfig=ARRAY['search_path=""']::text[]
          AND l.lanname='plpgsql' AND p.proowner=pg_catalog.to_regrole(v_owner)
          AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u'
          AND p.prosupport=0 AND p.procost=100 AND p.prorows=1000 AND p.probin IS NULL AND p.prosqlbody IS NULL
          AND pg_catalog.regexp_replace(pg_catalog.btrim(p.prosrc),'[[:space:]]+',' ','g')=pg_catalog.regexp_replace(pg_catalog.btrim(v_body),'[[:space:]]+',' ','g')) THEN
        RAISE EXCEPTION 'B7G1A_EXACT_RPC_BODY_SIGNATURE_DEFAULTS_SECURITY_DRIFT'; END IF;
    -- Exact body equality above proves gate before reads, owner-only predicate,
    -- all route branches, no publication filter, ordering, clamps and narrow output.
    IF (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=v_rpc) ~ 'private[.]game_legacy_identifiers|/games/'
        OR (SELECT pg_catalog.regexp_count(p.prosrc,'n[.]game_id') FROM pg_catalog.pg_proc p WHERE p.oid=v_rpc)<>1 THEN
        RAISE EXCEPTION 'B7G1A_LEGACY_ROUTE_AUTHORITY_DRIFT'; END IF;
    FOR v_item IN SELECT v_baseline AS rpc UNION ALL SELECT v_rpc LOOP
        IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
            LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_item.rpc AND
            (a.grantor<>p.proowner OR a.privilege_type<>'EXECUTE' OR a.is_grantable
                OR (a.grantee<>p.proowner AND (a.grantee=0 OR r.rolname IS NULL OR r.rolname NOT IN ('authenticated','service_role')))))
            OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_item.rpc AND a.grantee=p.proowner)
            OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_item.rpc AND a.grantee='authenticated'::pg_catalog.regrole::oid)
            OR NOT pg_catalog.has_function_privilege('authenticated',v_item.rpc,'EXECUTE')
            OR pg_catalog.has_function_privilege('anon',v_item.rpc,'EXECUTE') THEN RAISE EXCEPTION 'B7G1A_RPC_ACL_DRIFT'; END IF;
    END LOOP;
    SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_baseline
        FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_baseline;
    SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_rpc
        FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc;
    IF v_acl_rpc IS DISTINCT FROM v_acl_baseline THEN RAISE EXCEPTION 'B7G1A_DIRECT_ACL_PARITY_DRIFT'; END IF;
    FOR v_role IN SELECT rolname FROM pg_catalog.pg_roles LOOP
        IF pg_catalog.has_function_privilege(v_role.rolname,v_rpc,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege(v_role.rolname,v_baseline,'EXECUTE') THEN
            RAISE EXCEPTION 'B7G1A_ALL_ROLE_EXECUTE_PARITY_DRIFT: %',v_role.rolname; END IF;
    END LOOP;
    -- END EXACT RPC CHECK
    ELSIF EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace AND proname='get_my_notifications_with_route_context') THEN
        RAISE EXCEPTION 'B7G1A_RPC_NAME_COLLISION'; END IF;
    -- BEGIN PRESERVATION CAPTURE
    EXECUTE v_snapshot_sql INTO v_state;
    v_data := '{}'::jsonb;
    FOREACH v_grantee IN ARRAY ARRAY['user_notifications','marker_submissions','marcadores','games']::name[] LOOP
        EXECUTE pg_catalog.format('SELECT pg_catalog.jsonb_build_object(''count'',pg_catalog.count(*),''md5'',pg_catalog.md5(coalesce(pg_catalog.string_agg(pg_catalog.md5(pg_catalog.to_jsonb(t)::text),'''' ORDER BY t.id),''''))) FROM public.%I t',v_grantee) INTO v_actual;
        v_data := v_data || pg_catalog.jsonb_build_object(v_grantee,v_actual);
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
    IF v_rpc IS NULL THEN
        EXECUTE pg_catalog.format('CREATE FUNCTION public.get_my_notifications_with_route_context(p_limit integer DEFAULT 20,p_offset integer DEFAULT 0)
            RETURNS TABLE (id bigint, kind text, game_id text, submission_id bigint, marker_id bigint, submission_type text, decision text, review_note text, is_read boolean, created_at timestamptz, metadata jsonb, route_game_uuid uuid, route_game_slug text, route_marker_is_published boolean, total_count bigint)
            LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = %L AS %L','',v_body);
        EXECUTE pg_catalog.format('ALTER FUNCTION public.get_my_notifications_with_route_context(integer,integer) OWNER TO %I',v_owner);
        v_rpc := pg_catalog.to_regprocedure('public.get_my_notifications_with_route_context(integer,integer)');
        -- Normalize inherited defaults ONLY on the freshly created RPC.
        FOR v_grantee IN SELECT DISTINCT r.rolname FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a
            JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_rpc AND a.grantee<>p.proowner LOOP
            EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION public.get_my_notifications_with_route_context(integer,integer) FROM %I',v_grantee);
        END LOOP;
        REVOKE ALL ON FUNCTION public.get_my_notifications_with_route_context(integer,integer) FROM PUBLIC,anon,authenticated,service_role;
        GRANT EXECUTE ON FUNCTION public.get_my_notifications_with_route_context(integer,integer) TO authenticated;
        SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a
            WHERE p.oid=v_baseline AND a.grantee='service_role'::pg_catalog.regrole::oid) INTO v_service_direct;
        IF v_service_direct THEN GRANT EXECUTE ON FUNCTION public.get_my_notifications_with_route_context(integer,integer) TO service_role; END IF;
    END IF;
    -- BEGIN EXACT RPC CHECK
    IF v_rpc IS NULL OR (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace AND proname='get_my_notifications_with_route_context')<>1 THEN
        RAISE EXCEPTION 'B7G1A_RPC_MISSING_OR_OVERLOADED'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=v_rpc AND p.prokind='f' AND p.pronargs=2
          AND ARRAY(SELECT pg_catalog.unnest(p.proargtypes::oid[]))=ARRAY['integer'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid]
          AND p.proallargtypes=ARRAY['integer'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'boolean'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'jsonb'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'boolean'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid]
          AND p.proargnames=ARRAY['p_limit','p_offset','id','kind','game_id','submission_id','marker_id','submission_type','decision','review_note','is_read','created_at','metadata','route_game_uuid','route_game_slug','route_marker_is_published','total_count']::text[]
          AND p.proargmodes=ARRAY['i','i','t','t','t','t','t','t','t','t','t','t','t','t','t','t','t']::"char"[]
          AND p.prorettype='record'::pg_catalog.regtype AND p.proretset AND p.provariadic=0
          AND p.pronargdefaults=2 AND pg_catalog.pg_get_expr(p.proargdefaults,0)='20, 0'
          AND p.prosecdef AND p.provolatile='s' AND p.proconfig=ARRAY['search_path=""']::text[]
          AND l.lanname='plpgsql' AND p.proowner=pg_catalog.to_regrole(v_owner)
          AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u'
          AND p.prosupport=0 AND p.procost=100 AND p.prorows=1000 AND p.probin IS NULL AND p.prosqlbody IS NULL
          AND pg_catalog.regexp_replace(pg_catalog.btrim(p.prosrc),'[[:space:]]+',' ','g')=pg_catalog.regexp_replace(pg_catalog.btrim(v_body),'[[:space:]]+',' ','g')) THEN
        RAISE EXCEPTION 'B7G1A_EXACT_RPC_BODY_SIGNATURE_DEFAULTS_SECURITY_DRIFT'; END IF;
    -- Exact body equality above proves gate before reads, owner-only predicate,
    -- all route branches, no publication filter, ordering, clamps and narrow output.
    IF (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=v_rpc) ~ 'private[.]game_legacy_identifiers|/games/'
        OR (SELECT pg_catalog.regexp_count(p.prosrc,'n[.]game_id') FROM pg_catalog.pg_proc p WHERE p.oid=v_rpc)<>1 THEN
        RAISE EXCEPTION 'B7G1A_LEGACY_ROUTE_AUTHORITY_DRIFT'; END IF;
    FOR v_item IN SELECT v_baseline AS rpc UNION ALL SELECT v_rpc LOOP
        IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
            LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_item.rpc AND
            (a.grantor<>p.proowner OR a.privilege_type<>'EXECUTE' OR a.is_grantable
                OR (a.grantee<>p.proowner AND (a.grantee=0 OR r.rolname IS NULL OR r.rolname NOT IN ('authenticated','service_role')))))
            OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_item.rpc AND a.grantee=p.proowner)
            OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_item.rpc AND a.grantee='authenticated'::pg_catalog.regrole::oid)
            OR NOT pg_catalog.has_function_privilege('authenticated',v_item.rpc,'EXECUTE')
            OR pg_catalog.has_function_privilege('anon',v_item.rpc,'EXECUTE') THEN RAISE EXCEPTION 'B7G1A_RPC_ACL_DRIFT'; END IF;
    END LOOP;
    SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_baseline
        FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_baseline;
    SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_rpc
        FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc;
    IF v_acl_rpc IS DISTINCT FROM v_acl_baseline THEN RAISE EXCEPTION 'B7G1A_DIRECT_ACL_PARITY_DRIFT'; END IF;
    FOR v_role IN SELECT rolname FROM pg_catalog.pg_roles LOOP
        IF pg_catalog.has_function_privilege(v_role.rolname,v_rpc,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege(v_role.rolname,v_baseline,'EXECUTE') THEN
            RAISE EXCEPTION 'B7G1A_ALL_ROLE_EXECUTE_PARITY_DRIFT: %',v_role.rolname; END IF;
    END LOOP;
    -- END EXACT RPC CHECK
    -- BEGIN PRESERVATION CAPTURE
    EXECUTE v_snapshot_sql INTO v_state;
    v_data := '{}'::jsonb;
    FOREACH v_grantee IN ARRAY ARRAY['user_notifications','marker_submissions','marcadores','games']::name[] LOOP
        EXECUTE pg_catalog.format('SELECT pg_catalog.jsonb_build_object(''count'',pg_catalog.count(*),''md5'',pg_catalog.md5(coalesce(pg_catalog.string_agg(pg_catalog.md5(pg_catalog.to_jsonb(t)::text),'''' ORDER BY t.id),''''))) FROM public.%I t',v_grantee) INTO v_actual;
        v_data := v_data || pg_catalog.jsonb_build_object(v_grantee,v_actual);
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
    IF v_after IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'B7G1A_PRESERVATION_FAILED'; END IF;
    RAISE NOTICE 'PASS B7g1a contract; existing catalog/data/sequence state unchanged';
    RAISE NOTICE 'INFO B7g1a preservation fingerprint = %',pg_catalog.md5(v_before::text);
END;
$migration$;
COMMIT;
