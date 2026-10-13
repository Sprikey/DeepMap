-- Set trusted fingerprint ONLY in a temporary SQL Editor copy.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
DO $verify$
DECLARE
 v_old_global jsonb; v_old_mine jsonb; v_before jsonb; v_after jsonb;
 v_kind integer; v_pass integer; v_legacy oid; v_new oid; v_rpc oid;
 v_old jsonb; v_owner name; v_grantee name; v_name text; v_signature text;
 v_input_types oid[]; v_input_names text[]; v_output_types oid[]; v_output_names text[];
 v_defaults text; v_default_count integer; v_expected_body text;
 v_service_direct boolean; v_acl_legacy jsonb; v_acl_new jsonb; v_role record; v_relation record; v_dependency record;
 v_global_body text := $global_legacy$
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
        count(*) over()
    from public.marker_submissions s
    left join public.profiles submitter on submitter.id=s.submitted_by
    left join public.profiles reviewer on reviewer.id=s.reviewed_by
    where (p_game_id is null or p_game_id='' or s.game_id=p_game_id)
      and s.status=p_status
    order by case when p_status='pending' then s.updated_at else coalesce(s.reviewed_at,s.updated_at) end desc, s.id desc
    limit greatest(1,least(coalesce(p_limit,10),100))
    offset greatest(coalesce(p_offset,0),0);
end;
$global_legacy$;
 v_mine_body text := $mine_legacy$
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
        count(*) over() as total_count
    from public.marker_submissions as s
    left join public.profiles as submitter
      on submitter.id = s.submitted_by
    left join public.profiles as reviewer
      on reviewer.id = s.reviewed_by
    where s.game_id = p_game_id
      and s.submitted_by = (select auth.uid())
    order by
        case s.status when 'pending' then 0 else 1 end,
        s.updated_at desc,
        s.id desc
    limit greatest(1, least(coalesce(p_limit, 20), 50))
    offset greatest(coalesce(p_offset, 0), 0);
end;
$mine_legacy$;
 v_global_uuid_body text := $global_uuid$
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
$global_uuid$;
 v_mine_uuid_body text := $mine_uuid$
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
$mine_uuid$;
 v_snapshot_sql text := $snapshot$WITH excluded AS (SELECT p.oid FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='public' AND ((p.proname='get_marker_submissions_page_by_game_uuid' AND p.proargtypes='2950 25 23 23'::pg_catalog.oidvector) OR (p.proname='get_my_marker_submissions_page_by_game_uuid' AND p.proargtypes='2950 23 23'::pg_catalog.oidvector)))),
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
          AND NOT (n.nspname='public' AND ((p.proname='get_marker_submissions_page_by_game_uuid' AND p.proargtypes='2950 25 23 23'::pg_catalog.oidvector) OR (p.proname='get_my_marker_submissions_page_by_game_uuid' AND p.proargtypes='2950 23 23'::pg_catalog.oidvector)))),
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
 v_fail integer := 0;
 v_structural_ok boolean := true;
 v_uid uuid := auth.uid();
 v_staff boolean := private.can_moderate_deepmap();
 v_unknown uuid := '00000000-0000-0000-0000-000000000000'::uuid;
 v_game record; v_alias record; v_case record; v_status text;
 v_cap integer; v_default_limit integer; v_normal_limit integer; v_normal_offset integer; v_alias_offset integer;
 v_alias_total bigint; v_total bigint; v_direct_total bigint; v_beyond integer;
 v_raw jsonb; v_union jsonb; v_page jsonb; v_actual jsonb; v_expected jsonb;
 v_games integer := 0; v_aliases integer; v_coverage bigint;
 v_rows jsonb; v_item jsonb; v_metadata jsonb; v_statuses text[];
BEGIN
 BEGIN
   IF EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated'),('service_role')) expected(name) WHERE pg_catalog.to_regrole(expected.name) IS NULL) THEN RAISE EXCEPTION 'B7E1_REQUIRED_ROLE_MISSING'; END IF;
 SELECT pg_catalog.to_jsonb(p) INTO v_old_global FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_marker_submissions_page(text,text,integer,integer)');
 SELECT pg_catalog.to_jsonb(p) INTO v_old_mine FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_my_marker_submissions_page(text,integer,integer)');
 IF v_old_global IS NULL OR v_old_mine IS NULL THEN RAISE EXCEPTION 'B7E1_REQUIRED_LEGACY_RPC_MISSING'; END IF;
   FOR v_dependency IN SELECT * FROM (VALUES
 ('public.marker_submissions','id','bigint',true),('public.marker_submissions','game_id','text',true),('public.marker_submissions','game_uuid','uuid',true),('public.marker_submissions','marker_id','bigint',false),
 ('public.marker_submissions','submission_type','text',true),('public.marker_submissions','correction_kind','text',false),('public.marker_submissions','status','text',true),('public.marker_submissions','submitted_by','uuid',true),
 ('public.marker_submissions','payload','jsonb',true),('public.marker_submissions','note','text',false),('public.marker_submissions','reviewed_by','uuid',false),('public.marker_submissions','reviewed_at','timestamptz',false),
 ('public.marker_submissions','review_note','text',false),('public.marker_submissions','created_at','timestamptz',true),('public.marker_submissions','updated_at','timestamptz',true),
 ('public.games','id','uuid',true),('public.games','slug','text',true),('public.games','name','text',true),('public.profiles','id','uuid',true),('public.profiles','username','text',true),('private.marker_submission_revisions','submission_id','bigint',true)
 ) expected(relation_name,column_name,type_name,not_null) LOOP
   IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid=pg_catalog.to_regclass(v_dependency.relation_name) AND a.attname=v_dependency.column_name AND a.attnum>0 AND NOT a.attisdropped AND a.atttypid=pg_catalog.to_regtype(v_dependency.type_name) AND a.attnotnull=v_dependency.not_null) THEN RAISE EXCEPTION 'B7E1_SCHEMA_DEPENDENCY_DRIFT: %.%',v_dependency.relation_name,v_dependency.column_name; END IF;
 END LOOP;
 IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.games'::pg_catalog.regclass AND c.contype='p' AND c.convalidated AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=c.conrelid AND attname='id')]::smallint[]) THEN RAISE EXCEPTION 'B7E1_GAMES_UUID_PK_REQUIRED'; END IF;
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_class WHERE oid IN ('public.marker_submissions'::pg_catalog.regclass,'private.marker_submission_revisions'::pg_catalog.regclass) AND NOT relrowsecurity) THEN RAISE EXCEPTION 'B7E1_SUBMISSION_RLS_DRIFT'; END IF;
 -- Private revisions retain no direct browser table/column grants.
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE c.oid='private.marker_submission_revisions'::pg_catalog.regclass AND (a.grantee=0 OR r.rolname IN ('anon','authenticated')))
   OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute c CROSS JOIN LATERAL pg_catalog.aclexplode(c.attacl) a LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE c.attrelid='private.marker_submission_revisions'::pg_catalog.regclass AND (a.grantee=0 OR r.rolname IN ('anon','authenticated'))) THEN RAISE EXCEPTION 'B7E1_PRIVATE_REVISION_DIRECT_GRANT_DRIFT'; END IF;
 EXCEPTION WHEN OTHERS THEN v_fail:=v_fail+1; v_structural_ok:=false; RAISE NOTICE 'FAIL B7E1 prerequisites: %',SQLERRM;
 END;
 FOR v_kind IN 1..2 LOOP
   BEGIN
     v_legacy:=pg_catalog.to_regprocedure(CASE WHEN v_kind=1 THEN 'public.get_marker_submissions_page(text,text,integer,integer)' ELSE 'public.get_my_marker_submissions_page(text,integer,integer)' END);
 v_new:=pg_catalog.to_regprocedure(CASE WHEN v_kind=1 THEN 'public.get_marker_submissions_page_by_game_uuid(uuid,text,integer,integer)' ELSE 'public.get_my_marker_submissions_page_by_game_uuid(uuid,integer,integer)' END);
 v_old:=CASE WHEN v_kind=1 THEN v_old_global ELSE v_old_mine END;
 SELECT rolname INTO STRICT v_owner FROM pg_catalog.pg_roles WHERE oid=(v_old->>'proowner')::oid;
     IF v_owner IN ('anon','authenticated','service_role') OR pg_catalog.pg_has_role('anon',v_owner,'MEMBER') OR pg_catalog.pg_has_role('authenticated',v_owner,'MEMBER') THEN RAISE EXCEPTION 'B7E1_UNTRUSTED_OWNER: %',v_owner; END IF;
 FOR v_relation IN SELECT c.* FROM pg_catalog.pg_class c WHERE c.oid IN ('public.marker_submissions'::pg_catalog.regclass,'private.marker_submission_revisions'::pg_catalog.regclass,'public.profiles'::pg_catalog.regclass,'public.games'::pg_catalog.regclass) LOOP
   IF v_relation.relkind<>'r' OR NOT pg_catalog.has_schema_privilege(v_owner,v_relation.relnamespace,'USAGE') OR NOT pg_catalog.has_table_privilege(v_owner,v_relation.oid,'SELECT')
     OR (v_relation.relrowsecurity AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname=v_owner AND (r.rolsuper OR r.rolbypassrls OR (r.oid=v_relation.relowner AND NOT v_relation.relforcerowsecurity)))) THEN RAISE EXCEPTION 'B7E1_OWNER_READ_RLS_ACCESS_NOT_GUARANTEED: %.%',v_owner,v_relation.relname; END IF;
 END LOOP;
 IF NOT pg_catalog.has_schema_privilege(v_owner,'auth','USAGE') OR NOT pg_catalog.has_function_privilege(v_owner,'auth.uid()','EXECUTE') OR (v_kind=1 AND NOT pg_catalog.has_function_privilege(v_owner,'private.can_moderate_deepmap()','EXECUTE')) THEN RAISE EXCEPTION 'B7E1_OWNER_GATE_ACCESS_DRIFT'; END IF;
     FOR v_pass IN 1..2 LOOP
       v_rpc:=CASE WHEN v_pass=1 THEN v_legacy ELSE v_new END;
 v_name:=CASE WHEN v_kind=1 THEN CASE WHEN v_pass=1 THEN 'get_marker_submissions_page' ELSE 'get_marker_submissions_page_by_game_uuid' END ELSE CASE WHEN v_pass=1 THEN 'get_my_marker_submissions_page' ELSE 'get_my_marker_submissions_page_by_game_uuid' END END;
 v_input_types:=CASE WHEN v_kind=1 THEN CASE WHEN v_pass=1 THEN ARRAY['text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid] ELSE ARRAY['uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid] END ELSE CASE WHEN v_pass=1 THEN ARRAY['text'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid] ELSE ARRAY['uuid'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid] END END;
 v_input_names:=ARRAY[CASE WHEN v_pass=1 THEN 'p_game_id' ELSE 'p_game_uuid' END] || CASE WHEN v_kind=1 THEN ARRAY['p_status','p_limit','p_offset'] ELSE ARRAY['p_limit','p_offset'] END;
 v_output_types:=ARRAY['bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'jsonb'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'integer'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid];
 v_output_names:=ARRAY['id','game_id','marker_id','submission_type','correction_kind','status','submitted_by','submitted_username','payload','note','reviewed_by','reviewed_username','reviewed_at','review_note','created_at','updated_at','revision_count','total_count'];
 IF v_pass=2 THEN
   v_output_types:=v_output_types || CASE WHEN v_kind=1 THEN ARRAY['uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid] ELSE ARRAY['uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid] END;
   v_output_names:=v_output_names || CASE WHEN v_kind=1 THEN ARRAY['game_uuid','game_slug','game_name'] ELSE ARRAY['game_uuid','game_slug'] END;
 END IF;
 v_default_count:=CASE WHEN v_kind=1 THEN CASE WHEN v_pass=1 THEN 3 ELSE 4 END ELSE 2 END;
 v_defaults:=CASE WHEN v_kind=1 THEN CASE WHEN v_pass=1 THEN '''pending''::text, 10, 0' ELSE 'NULL::uuid, ''pending''::text, 10, 0' END ELSE '20, 0' END;
 v_expected_body:=CASE WHEN v_kind=1 THEN CASE WHEN v_pass=1 THEN v_global_body ELSE v_global_uuid_body END ELSE CASE WHEN v_pass=1 THEN v_mine_body ELSE v_mine_uuid_body END END;
 IF v_rpc IS NULL OR (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace AND proname=v_name)<>1 THEN RAISE EXCEPTION 'B7E1_MISSING_OR_AMBIGUOUS_RPC: %',v_name; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang WHERE p.oid=v_rpc
   AND p.prokind='f' AND p.pronargs=pg_catalog.cardinality(v_input_types) AND ARRAY(SELECT pg_catalog.unnest(p.proargtypes::oid[]))=v_input_types
   AND p.proallargtypes=v_input_types||v_output_types AND p.proargnames=v_input_names||v_output_names
   AND p.proargmodes=pg_catalog.array_fill('i'::"char",ARRAY[pg_catalog.cardinality(v_input_types)])||pg_catalog.array_fill('t'::"char",ARRAY[pg_catalog.cardinality(v_output_types)])
   AND p.prorettype='record'::pg_catalog.regtype AND p.proretset AND p.provariadic=0
   AND p.pronargdefaults=v_default_count AND pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(pg_catalog.pg_get_expr(p.proargdefaults,0),pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')=pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(v_defaults,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')
   AND l.lanname='plpgsql' AND p.prosecdef AND p.provolatile='s' AND p.proconfig=ARRAY['search_path=""']::text[] AND p.proowner=(v_old->>'proowner')::oid
   AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u' AND p.prosupport=0 AND p.procost=100 AND p.prorows=1000 AND p.probin IS NULL AND p.prosqlbody IS NULL
   AND pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')=pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(v_expected_body,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')) THEN RAISE EXCEPTION 'B7E1_EXACT_BODY_SHAPE_DEFAULTS_SECURITY_OWNER_DRIFT: %',v_name; END IF;
 -- Allow only direct owner + authenticated, optionally legitimate service_role.
 -- Historical GRANT text alone does not describe Supabase default privileges.
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_rpc AND
   (a.grantor<>p.proowner OR a.privilege_type<>'EXECUTE' OR a.is_grantable OR (a.grantee<>p.proowner AND (a.grantee=0 OR r.rolname IS NULL OR r.rolname NOT IN ('authenticated','service_role')))))
   OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc AND a.grantee=p.proowner)
   OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_rpc AND r.rolname='authenticated')
   OR (SELECT count(*) FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc) NOT IN (2,3)
   OR (SELECT count(DISTINCT a.grantee) FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc) IS DISTINCT FROM (SELECT count(*) FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc)
   OR NOT pg_catalog.has_function_privilege('authenticated',v_rpc,'EXECUTE') OR pg_catalog.has_function_privilege('anon',v_rpc,'EXECUTE') THEN
   RAISE EXCEPTION 'B7E1_ACL_REQUIRES_REVIEW: %, allow=owner/authenticated/optional service_role, actual=%',v_name,(SELECT proacl FROM pg_catalog.pg_proc WHERE oid=v_rpc); END IF;
 IF v_pass=2 AND (v_expected_body ~ 'private[.]game_legacy_identifiers' OR v_expected_body ~ 's[.]game_id[[:space:]]*=' OR v_expected_body ~ 'p_game_id'
   OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(v_expected_body,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),CASE WHEN v_kind=1 THEN '(p_game_uuid is null or s.game_uuid=p_game_uuid)' ELSE 's.game_uuid = p_game_uuid' END)=0) THEN RAISE EXCEPTION 'B7E1_UUID_AUTHORITY_DRIFT: %',v_name; END IF;
     END LOOP;
     SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_legacy FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_legacy;
 SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_new FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_new;
 IF v_acl_legacy IS DISTINCT FROM v_acl_new THEN RAISE EXCEPTION 'B7E1_DIRECT_ACL_PARITY_DRIFT: pair %',v_kind; END IF;
 IF pg_catalog.has_function_privilege('authenticated',v_legacy,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege('authenticated',v_new,'EXECUTE')
   OR pg_catalog.has_function_privilege('service_role',v_legacy,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege('service_role',v_new,'EXECUTE')
   OR pg_catalog.has_function_privilege('anon',v_new,'EXECUTE') THEN RAISE EXCEPTION 'B7E1_CALLER_EFFECTIVE_EXECUTE_DRIFT'; END IF;
 FOR v_role IN SELECT rolname FROM pg_catalog.pg_roles LOOP
   IF pg_catalog.has_function_privilege(v_role.rolname,v_legacy,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege(v_role.rolname,v_new,'EXECUTE') THEN RAISE EXCEPTION 'B7E1_ALL_ROLE_EXECUTE_PARITY_DRIFT: pair %, role %',v_kind,v_role.rolname; END IF;
 END LOOP;
     RAISE NOTICE 'PASS B7E1 pair % exact signatures/defaults/returns/body/gates/clamps/order/count/security/owner/ACL and all-role parity',v_kind;
   EXCEPTION WHEN OTHERS THEN v_fail:=v_fail+1; v_structural_ok:=false; RAISE NOTICE 'FAIL B7E1 pair % structural: %',v_kind,SQLERRM;
   END;
 END LOOP;
 BEGIN
   IF (SELECT pg_catalog.to_jsonb(p) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_marker_submissions_page(text,text,integer,integer)')) IS DISTINCT FROM v_old_global
   OR (SELECT pg_catalog.to_jsonb(p) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_my_marker_submissions_page(text,integer,integer)')) IS DISTINCT FROM v_old_mine THEN RAISE EXCEPTION 'B7E1_COMPLETE_LEGACY_PG_PROC_CHANGED'; END IF;
   EXECUTE v_snapshot_sql INTO v_after;
   RAISE NOTICE 'INFO B7E1 preservation fingerprint = %',pg_catalog.md5(v_after::text);
   IF v_expected_preservation_md5 IS NULL OR v_expected_preservation_md5 IS DISTINCT FROM pg_catalog.md5(v_after::text) THEN
     v_fail:=v_fail+1; RAISE NOTICE 'FAIL B7E1 missing/mismatched trusted preservation fingerprint';
   ELSE RAISE NOTICE 'PASS B7E1 protected snapshot including BOTH complete legacy pg_proc rows matches trusted pre-migration fingerprint'; END IF;
 EXCEPTION WHEN OTHERS THEN v_fail:=v_fail+1; RAISE NOTICE 'FAIL B7E1 preservation: %',SQLERRM;
 END;
 IF NOT v_structural_ok THEN
   RAISE NOTICE 'INFO SKIP B7E1 behavior until structural contracts pass';
 ELSE
   BEGIN
     -- Mapping is verification-only. Production UUID RPCs never reference it.
     IF EXISTS (SELECT 1 FROM public.marker_submissions s LEFT JOIN public.games g ON g.id=s.game_uuid
       LEFT JOIN private.game_legacy_identifiers i ON i.legacy_identifier=s.game_id AND i.game_id=s.game_uuid
       WHERE s.game_uuid IS NULL OR g.id IS NULL OR i.game_id IS NULL)
       OR EXISTS (SELECT legacy_identifier FROM private.game_legacy_identifiers GROUP BY legacy_identifier HAVING count(*)<>1) THEN
       RAISE EXCEPTION 'B7E1_SUBMISSION_GAME_RELATIONSHIP_DRIFT'; END IF;
     IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
       WHERE c.conrelid='public.marker_submissions'::pg_catalog.regclass AND c.conname='marker_submissions_legacy_game_uuid_fk'
       AND c.contype='f' AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
       AND c.confrelid='private.game_legacy_identifiers'::pg_catalog.regclass
       AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=ARRAY['game_id','game_uuid']::text[]
       AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)=ARRAY['legacy_identifier','game_id']::text[]) THEN
       RAISE EXCEPTION 'B7E1_COMPOSITE_ALIAS_UUID_FK_DRIFT'; END IF;
     RAISE NOTICE 'PASS B7E1 UUID NOT NULL/games relationships and multi-alias identity consistency';
     RAISE NOTICE 'INFO B7E1 current dataset: submissions=%, games=%, multi-alias games=%, nullable marker targets=%, missing submitter profiles=%, missing reviewer profiles=%',
       (SELECT count(*) FROM public.marker_submissions),
       (SELECT count(DISTINCT game_uuid) FROM public.marker_submissions),
       (SELECT count(*) FROM (SELECT game_uuid FROM public.marker_submissions GROUP BY game_uuid HAVING count(DISTINCT game_id)>1) multi),
       (SELECT count(*) FROM public.marker_submissions WHERE marker_id IS NULL),
       (SELECT count(*) FROM public.marker_submissions s LEFT JOIN public.profiles p ON p.id=s.submitted_by WHERE p.id IS NULL),
       (SELECT count(*) FROM public.marker_submissions s LEFT JOIN public.profiles p ON p.id=s.reviewed_by WHERE s.reviewed_by IS NOT NULL AND p.id IS NULL);
     -- This is merely an unused UUID test probe, never a global scope sentinel.
     WHILE EXISTS (SELECT 1 FROM public.games WHERE id=v_unknown) OR EXISTS (SELECT 1 FROM public.marker_submissions WHERE game_uuid=v_unknown) LOOP
       v_unknown:=pg_catalog.md5(v_unknown::text)::uuid;
     END LOOP;

     IF v_staff IS NOT TRUE THEN
       BEGIN
         PERFORM * FROM public.get_marker_submissions_page(NULL::text);
         RAISE EXCEPTION 'B7E1_LEGACY_STAFF_GATE_DID_NOT_REJECT';
       EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'MODERATOR_REQUIRED' THEN RAISE; END IF;
       END;
       BEGIN
         PERFORM * FROM public.get_marker_submissions_page_by_game_uuid();
         RAISE EXCEPTION 'B7E1_UUID_STAFF_GATE_DID_NOT_REJECT';
       EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'MODERATOR_REQUIRED' THEN RAISE; END IF;
       END;
       RAISE NOTICE 'PASS B7E1 non-staff legacy/UUID gate rejects with MODERATOR_REQUIRED';
       RAISE NOTICE 'INFO SKIP B7E1 positive staff calls: current auth context cannot moderate; no role/session mutation';
     ELSE
       IF EXISTS (SELECT 1 FROM public.get_marker_submissions_page_by_game_uuid(v_unknown)) THEN RAISE EXCEPTION 'B7E1_UNKNOWN_UUID_STAFF_LEAK'; END IF;
       IF EXISTS (SELECT 1 FROM public.get_marker_submissions_page_by_game_uuid(NULL::uuid,NULL::text))
         OR EXISTS (SELECT 1 FROM public.get_marker_submissions_page(NULL::text,NULL::text)) THEN RAISE EXCEPTION 'B7E1_NULL_STATUS_NOT_EMPTY'; END IF;
       FOREACH v_status IN ARRAY ARRAY['cancelled','invalid','']::text[] LOOP
         BEGIN
           PERFORM * FROM public.get_marker_submissions_page(NULL::text,v_status);
           RAISE EXCEPTION 'B7E1_LEGACY_INVALID_STATUS_NOT_REJECTED';
         EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'INVALID_STATUS' THEN RAISE; END IF;
         END;
         BEGIN
           PERFORM * FROM public.get_marker_submissions_page_by_game_uuid(NULL::uuid,v_status);
           RAISE EXCEPTION 'B7E1_UUID_INVALID_STATUS_NOT_REJECTED';
         EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'INVALID_STATUS' THEN RAISE; END IF;
         END;
       END LOOP;
       RAISE NOTICE 'PASS B7E1 unknown UUID empty, NULL status empty, cancelled/invalid/empty status rejected';
       -- All-game semantics can compare legacy global directly: no alias merge.
       FOREACH v_status IN ARRAY ARRAY['pending','approved','rejected']::text[] LOOP
         SELECT count(*) INTO v_direct_total FROM public.marker_submissions WHERE status=v_status;
         FOR v_case IN SELECT * FROM (VALUES
           (NULL::integer,NULL::integer,true),(NULL,NULL,false),(-5,-5,false),(1,0,false),(1000,0,false),(1000,3,false),(10,3,false)
         ) cases(limit_value,offset_value,use_defaults) LOOP
           IF v_case.use_defaults THEN
             SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)-'ordinality' ORDER BY a.ordinality),'[]'::jsonb) INTO v_actual
               FROM public.get_marker_submissions_page_by_game_uuid(NULL::uuid,v_status) WITH ORDINALITY a;
             SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)-'ordinality' ORDER BY a.ordinality),'[]'::jsonb) INTO v_expected
               FROM public.get_marker_submissions_page(NULL::text,v_status) WITH ORDINALITY a;
           ELSE
             SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)-'ordinality' ORDER BY a.ordinality),'[]'::jsonb) INTO v_actual
               FROM public.get_marker_submissions_page_by_game_uuid(NULL::uuid,v_status,v_case.limit_value,v_case.offset_value) WITH ORDINALITY a;
             SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)-'ordinality' ORDER BY a.ordinality),'[]'::jsonb) INTO v_expected
               FROM public.get_marker_submissions_page(NULL::text,v_status,v_case.limit_value,v_case.offset_value) WITH ORDINALITY a;
           END IF;
           SELECT COALESCE(pg_catalog.jsonb_agg(e.value-ARRAY['game_uuid','game_slug','game_name']::text[] ORDER BY e.pos),'[]'::jsonb) INTO v_rows FROM pg_catalog.jsonb_array_elements(v_actual) WITH ORDINALITY e(value,pos);
           IF v_rows IS DISTINCT FROM v_expected THEN RAISE EXCEPTION 'B7E1_GLOBAL_NULL_PAGE_EQUIVALENCE: status %, case %',v_status,v_case; END IF;
           FOR v_item IN SELECT value FROM pg_catalog.jsonb_array_elements(v_actual) LOOP
             SELECT pg_catalog.jsonb_build_object('game_uuid',s.game_uuid,'game_slug',g.slug,'game_name',g.name) INTO v_metadata
               FROM public.marker_submissions s JOIN public.games g ON g.id=s.game_uuid WHERE s.id=(v_item->>'id')::bigint;
             IF v_metadata IS NULL OR v_item->'game_uuid' IS DISTINCT FROM v_metadata->'game_uuid' OR v_item->'game_slug' IS DISTINCT FROM v_metadata->'game_slug'
               OR v_item->'game_name' IS DISTINCT FROM v_metadata->'game_name' OR (v_item->>'total_count')::bigint IS DISTINCT FROM v_direct_total THEN RAISE EXCEPTION 'B7E1_GLOBAL_METADATA_OR_TOTAL_COUNT_DRIFT'; END IF;
           END LOOP;
         END LOOP;
         -- Legacy empty-string global matches NULL global; UUID has no empty value.
         SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.id),'[]'::jsonb) INTO v_actual FROM public.get_marker_submissions_page(''::text,v_status) a;
         SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.id),'[]'::jsonb) INTO v_expected FROM public.get_marker_submissions_page(NULL::text,v_status) a;
         IF v_actual IS DISTINCT FROM v_expected THEN RAISE EXCEPTION 'B7E1_LEGACY_EMPTY_NULL_GLOBAL_DRIFT'; END IF;
         RAISE NOTICE 'PASS B7E1 NULL global status %: defaults/clamps/order/offset/count/all fields and routing metadata',v_status;
       END LOOP;
       -- No-argument UUID invocation specifically tests the added NULL default.
       SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)-ARRAY['ordinality','game_uuid','game_slug','game_name']::text[] ORDER BY a.ordinality),'[]'::jsonb) INTO v_actual FROM public.get_marker_submissions_page_by_game_uuid() WITH ORDINALITY a;
       SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)-'ordinality' ORDER BY a.ordinality),'[]'::jsonb) INTO v_expected FROM public.get_marker_submissions_page(NULL::text) WITH ORDINALITY a;
       IF v_actual IS DISTINCT FROM v_expected THEN RAISE EXCEPTION 'B7E1_GLOBAL_DEFAULT_ARGUMENT_DRIFT'; END IF;
     END IF;

     IF v_uid IS NULL THEN
       BEGIN
         PERFORM * FROM public.get_my_marker_submissions_page(NULL::text);
         RAISE EXCEPTION 'B7E1_LEGACY_MINE_GATE_DID_NOT_REJECT';
       EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'AUTH_REQUIRED' THEN RAISE; END IF;
       END;
       BEGIN
         PERFORM * FROM public.get_my_marker_submissions_page_by_game_uuid(NULL::uuid);
         RAISE EXCEPTION 'B7E1_UUID_MINE_GATE_DID_NOT_REJECT';
       EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'AUTH_REQUIRED' THEN RAISE; END IF;
       END;
       RAISE NOTICE 'PASS B7E1 unauthenticated legacy/UUID mine gate rejects with AUTH_REQUIRED';
       RAISE NOTICE 'INFO SKIP B7E1 positive own-user calls: auth.uid is NULL; no auth/session mutation';
     ELSE
       IF EXISTS (SELECT 1 FROM public.get_my_marker_submissions_page_by_game_uuid(v_unknown))
         OR EXISTS (SELECT 1 FROM public.get_my_marker_submissions_page_by_game_uuid(NULL::uuid))
         OR EXISTS (SELECT 1 FROM public.get_my_marker_submissions_page(NULL::text)) THEN RAISE EXCEPTION 'B7E1_MINE_NULL_UNKNOWN_NOT_EMPTY'; END IF;
       RAISE NOTICE 'PASS B7E1 own NULL/unknown UUID empty after auth gate';
       RAISE NOTICE 'INFO B7E1 mine preserves existing auth-only gate even for banned sessions (current banned=%)',private.is_deepmap_banned();
     END IF;

     -- Per-UUID comparison across ALL aliases actually used in submissions.
     -- Fetch at least the needed cap+3 prefix from EACH nonempty alias
     -- in capped pages (at most two pages per alias). This is
     -- sufficient for every tested merged offset <=3 and limit <=cap; counts
     -- come from the full legacy window, never from the fetched prefix length.
     FOR v_kind IN 1..2 LOOP
       IF (v_kind=1 AND v_staff IS NOT TRUE) OR (v_kind=2 AND v_uid IS NULL) THEN CONTINUE; END IF;
       v_cap:=CASE WHEN v_kind=1 THEN 100 ELSE 50 END;
       v_default_limit:=CASE WHEN v_kind=1 THEN 10 ELSE 20 END;
       v_statuses:=CASE WHEN v_kind=1 THEN ARRAY['pending','approved','rejected']::text[] ELSE ARRAY[NULL::text] END;
       v_games:=0;
       FOR v_game IN SELECT DISTINCT game_uuid FROM public.marker_submissions ORDER BY game_uuid LOOP
         v_games:=v_games+1;
         FOREACH v_status IN ARRAY v_statuses LOOP
           v_raw:='[]'::jsonb; v_total:=0; v_aliases:=0;
           FOR v_alias IN SELECT DISTINCT s.game_id FROM public.marker_submissions s
             JOIN private.game_legacy_identifiers i ON i.legacy_identifier=s.game_id AND i.game_id=s.game_uuid
             WHERE s.game_uuid=v_game.game_uuid ORDER BY s.game_id LOOP
             v_aliases:=v_aliases+1; v_alias_offset:=0; v_alias_total:=0;
             WHILE v_alias_offset<v_cap+3 LOOP
               IF v_kind=1 THEN
                 SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)-'ordinality' ORDER BY a.ordinality),'[]'::jsonb) INTO v_page FROM public.get_marker_submissions_page(v_alias.game_id,v_status,v_cap,v_alias_offset) WITH ORDINALITY a;
               ELSE
                 SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)-'ordinality' ORDER BY a.ordinality),'[]'::jsonb) INTO v_page FROM public.get_my_marker_submissions_page(v_alias.game_id,v_cap,v_alias_offset) WITH ORDINALITY a;
               END IF;
               IF v_alias_offset=0 THEN v_alias_total:=COALESCE((v_page->0->>'total_count')::bigint,0); END IF;
               IF EXISTS (SELECT 1 FROM pg_catalog.jsonb_array_elements(v_page) p WHERE (p.value->>'total_count')::bigint IS DISTINCT FROM v_alias_total) THEN RAISE EXCEPTION 'B7E1_ALIAS_TOTAL_COUNT_DRIFT'; END IF;
               SELECT COALESCE(pg_catalog.jsonb_agg(e.value-'total_count' ORDER BY e.pos),'[]'::jsonb) INTO v_rows FROM pg_catalog.jsonb_array_elements(v_page) WITH ORDINALITY e(value,pos);
               v_raw:=v_raw||v_rows;
               EXIT WHEN pg_catalog.jsonb_array_length(v_page)<v_cap;
               v_alias_offset:=v_alias_offset+v_cap;
             END LOOP;
             SELECT count(*) INTO v_direct_total FROM public.marker_submissions s WHERE s.game_uuid=v_game.game_uuid AND s.game_id=v_alias.game_id
               AND (v_kind=2 OR s.status=v_status) AND (v_kind=1 OR s.submitted_by=v_uid);
             IF v_alias_total IS DISTINCT FROM v_direct_total THEN RAISE EXCEPTION 'B7E1_ALIAS_EXACT_TOTAL_DRIFT: %',v_alias.game_id; END IF;
             v_total:=v_total+v_alias_total;
           END LOOP;
           -- Unique aliases/composite FK make legacy result sets disjoint;
           -- DISTINCT handles repeated identical rows; conflicting IDs fail.
           SELECT COALESCE(pg_catalog.jsonb_agg(d.value ORDER BY (d.value->>'id')::bigint),'[]'::jsonb) INTO v_union FROM (SELECT DISTINCT value FROM pg_catalog.jsonb_array_elements(v_raw)) d;
           IF (SELECT count(DISTINCT (value->>'id')::bigint) FROM pg_catalog.jsonb_array_elements(v_union))<>pg_catalog.jsonb_array_length(v_union) THEN RAISE EXCEPTION 'B7E1_CONFLICTING_DUPLICATE_SUBMISSION_ID'; END IF;
           SELECT count(*) INTO v_direct_total FROM public.marker_submissions s WHERE s.game_uuid=v_game.game_uuid AND (v_kind=2 OR s.status=v_status) AND (v_kind=1 OR s.submitted_by=v_uid);
           IF v_total IS DISTINCT FROM v_direct_total THEN RAISE EXCEPTION 'B7E1_UUID_EXACT_TOTAL_DRIFT'; END IF;
           FOR v_case IN SELECT * FROM (VALUES (NULL::integer,NULL::integer,true),(NULL,NULL,false),(-5,-5,false),(1,0,false),(1000,0,false),(1000,3,false),(10,3,false)) cases(limit_value,offset_value,use_defaults) LOOP
             v_normal_limit:=greatest(1,least(coalesce(v_case.limit_value,v_default_limit),v_cap));
             v_normal_offset:=greatest(coalesce(v_case.offset_value,0),0);
             SELECT COALESCE(pg_catalog.jsonb_agg(x.row_data ORDER BY x.pos),'[]'::jsonb) INTO v_expected FROM (
               SELECT e.value||pg_catalog.jsonb_build_object('total_count',v_total) AS row_data,
                 row_number() OVER (ORDER BY CASE WHEN v_kind=2 THEN CASE e.value->>'status' WHEN 'pending' THEN 0 ELSE 1 END ELSE 0 END,
                   CASE WHEN v_kind=2 OR v_status='pending' THEN (e.value->>'updated_at')::timestamptz ELSE coalesce((e.value->>'reviewed_at')::timestamptz,(e.value->>'updated_at')::timestamptz) END DESC,(e.value->>'id')::bigint DESC) AS pos
               FROM pg_catalog.jsonb_array_elements(v_union) e
               ORDER BY pos LIMIT v_normal_limit OFFSET v_normal_offset
             ) x;
             IF v_kind=1 THEN
               IF v_case.use_defaults THEN
                 SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)-'ordinality' ORDER BY a.ordinality),'[]'::jsonb) INTO v_actual FROM public.get_marker_submissions_page_by_game_uuid(v_game.game_uuid,v_status) WITH ORDINALITY a;
               ELSE
                 SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)-'ordinality' ORDER BY a.ordinality),'[]'::jsonb) INTO v_actual FROM public.get_marker_submissions_page_by_game_uuid(v_game.game_uuid,v_status,v_case.limit_value,v_case.offset_value) WITH ORDINALITY a;
               END IF;
             ELSE
               IF v_case.use_defaults THEN
                 SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)-'ordinality' ORDER BY a.ordinality),'[]'::jsonb) INTO v_actual FROM public.get_my_marker_submissions_page_by_game_uuid(v_game.game_uuid) WITH ORDINALITY a;
               ELSE
                 SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)-'ordinality' ORDER BY a.ordinality),'[]'::jsonb) INTO v_actual FROM public.get_my_marker_submissions_page_by_game_uuid(v_game.game_uuid,v_case.limit_value,v_case.offset_value) WITH ORDINALITY a;
               END IF;
             END IF;
             SELECT COALESCE(pg_catalog.jsonb_agg(e.value-ARRAY['game_uuid','game_slug','game_name']::text[] ORDER BY e.pos),'[]'::jsonb) INTO v_rows FROM pg_catalog.jsonb_array_elements(v_actual) WITH ORDINALITY e(value,pos);
             IF v_rows IS DISTINCT FROM v_expected THEN RAISE EXCEPTION 'B7E1_MULTI_ALIAS_PAGE_EQUIVALENCE: pair %, game %, status %, case %',v_kind,v_game.game_uuid,v_status,v_case; END IF;
             FOR v_item IN SELECT value FROM pg_catalog.jsonb_array_elements(v_actual) LOOP
               SELECT pg_catalog.jsonb_build_object('game_uuid',g.id,'game_slug',g.slug,'game_name',g.name) INTO v_metadata FROM public.games g WHERE g.id=v_game.game_uuid;
               IF v_item->'game_uuid' IS DISTINCT FROM v_metadata->'game_uuid' OR v_item->'game_slug' IS DISTINCT FROM v_metadata->'game_slug'
                 OR (v_kind=1 AND v_item->'game_name' IS DISTINCT FROM v_metadata->'game_name')
                 OR (v_kind=2 AND (v_item->>'submitted_by')::uuid IS DISTINCT FROM v_uid) THEN RAISE EXCEPTION 'B7E1_UUID_ROUTING_OR_OWNERSHIP_LEAK'; END IF;
             END LOOP;
           END LOOP;
           -- Beyond-end pages carry neither rows nor a synthesized total_count.
           IF v_total<2147483647 THEN
             v_beyond:=(v_total+1)::integer;
             IF v_kind=1 THEN
               IF EXISTS (SELECT 1 FROM public.get_marker_submissions_page_by_game_uuid(v_game.game_uuid,v_status,10,v_beyond)) THEN RAISE EXCEPTION 'B7E1_STAFF_BEYOND_END_NOT_EMPTY'; END IF;
             ELSE
               IF EXISTS (SELECT 1 FROM public.get_my_marker_submissions_page_by_game_uuid(v_game.game_uuid,20,v_beyond)) THEN RAISE EXCEPTION 'B7E1_MINE_BEYOND_END_NOT_EMPTY'; END IF;
             END IF;
           ELSE RAISE NOTICE 'INFO SKIP B7E1 beyond-end INTEGER offset unavailable for count %',v_total; END IF;
           RAISE NOTICE 'PASS B7E1 pair % game % status %: aliases=%, total=%, 7 pagination cases, all fields/NULLs/revision counts/BIGINTs/UUID routing',v_kind,v_game.game_uuid,v_status,v_aliases,v_total;
         END LOOP;
       END LOOP;
       IF v_games=0 THEN RAISE NOTICE 'INFO SKIP B7E1 positive dataset coverage: no submissions'; END IF;
       IF v_games<2 THEN RAISE NOTICE 'INFO SKIP B7E1 multiple-game coverage: % games',v_games; END IF;
     END LOOP;
     FOREACH v_status IN ARRAY ARRAY['pending','approved','rejected','cancelled']::text[] LOOP
       SELECT count(*) INTO v_coverage FROM public.marker_submissions WHERE status=v_status;
       IF v_coverage=0 THEN RAISE NOTICE 'INFO SKIP B7E1 status % row coverage: absent from dataset',v_status;
       ELSE RAISE NOTICE 'INFO B7E1 status % rows=% (positive tests depend on matching staff/own auth context)',v_status,v_coverage; END IF;
     END LOOP;
     IF NOT EXISTS (SELECT 1 FROM public.marker_submissions GROUP BY game_uuid HAVING count(DISTINCT game_id)>1) THEN RAISE NOTICE 'INFO SKIP B7E1 multi-alias row coverage: no UUID currently has multiple used aliases'; END IF;
     IF NOT EXISTS (SELECT 1 FROM public.marker_submissions WHERE marker_id IS NULL) THEN RAISE NOTICE 'INFO SKIP B7E1 nullable marker_id row coverage: absent'; END IF;
     IF NOT EXISTS (SELECT 1 FROM public.marker_submissions WHERE reviewed_by IS NULL OR reviewed_at IS NULL OR review_note IS NULL) THEN RAISE NOTICE 'INFO SKIP B7E1 nullable review row coverage: absent'; END IF;
     IF NOT EXISTS (SELECT 1 FROM public.marker_submissions s LEFT JOIN public.profiles p ON p.id=s.submitted_by WHERE p.id IS NULL)
       AND NOT EXISTS (SELECT 1 FROM public.marker_submissions s LEFT JOIN public.profiles p ON p.id=s.reviewed_by WHERE s.reviewed_by IS NOT NULL AND p.id IS NULL) THEN RAISE NOTICE 'INFO SKIP B7E1 deleted optional profile row coverage: absent'; END IF;
     IF v_uid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.marker_submissions WHERE submitted_by=v_uid) THEN RAISE NOTICE 'INFO SKIP B7E1 own positive row coverage: current user has no submissions (empty-result calls still checked)'; END IF;
     RAISE NOTICE 'INFO SKIP B7E1 role impersonation/banned-session synthesis: no role/auth/session/data mutation; exact gates and ACL are verified structurally';
   EXCEPTION WHEN OTHERS THEN v_fail:=v_fail+1; RAISE NOTICE 'FAIL B7E1 behavior: %',SQLERRM;
   END;
 END IF;
 RAISE NOTICE 'INFO B7E1 TOTAL FAIL = %',v_fail;
 IF v_fail<>0 THEN RAISE EXCEPTION 'B7E1 verification failed: % failure(s)',v_fail; END IF;
 RAISE NOTICE 'PASS B7E1 verifier';
END;
$verify$;
ROLLBACK;
