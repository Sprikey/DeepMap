-- B7e1 READ contracts only. Final sources: deepmap-admin-global-moderation-v2.sql / list-pagination.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';
DO $migration$
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
 -- Both legacy contracts/existing new names are reviewed BEFORE mutation.
 FOR v_kind IN 1..2 LOOP
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
     IF v_pass=2 AND v_new IS NULL THEN
       IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace AND proname=CASE WHEN v_kind=1 THEN 'get_marker_submissions_page_by_game_uuid' ELSE 'get_my_marker_submissions_page_by_game_uuid' END) THEN RAISE EXCEPTION 'B7E1_UUID_NAME_COLLISION_REQUIRES_REVIEW'; END IF;
       CONTINUE;
     END IF;
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
   IF v_new IS NOT NULL THEN
     SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_legacy FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_legacy;
 SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_new FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_new;
 IF v_acl_legacy IS DISTINCT FROM v_acl_new THEN RAISE EXCEPTION 'B7E1_DIRECT_ACL_PARITY_DRIFT: pair %',v_kind; END IF;
 IF pg_catalog.has_function_privilege('authenticated',v_legacy,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege('authenticated',v_new,'EXECUTE')
   OR pg_catalog.has_function_privilege('service_role',v_legacy,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege('service_role',v_new,'EXECUTE')
   OR pg_catalog.has_function_privilege('anon',v_new,'EXECUTE') THEN RAISE EXCEPTION 'B7E1_CALLER_EFFECTIVE_EXECUTE_DRIFT'; END IF;
 FOR v_role IN SELECT rolname FROM pg_catalog.pg_roles LOOP
   IF pg_catalog.has_function_privilege(v_role.rolname,v_legacy,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege(v_role.rolname,v_new,'EXECUTE') THEN RAISE EXCEPTION 'B7E1_ALL_ROLE_EXECUTE_PARITY_DRIFT: pair %, role %',v_kind,v_role.rolname; END IF;
 END LOOP;
   END IF;
 END LOOP;
 EXECUTE v_snapshot_sql INTO v_before;
 FOR v_kind IN 1..2 LOOP
   v_legacy:=pg_catalog.to_regprocedure(CASE WHEN v_kind=1 THEN 'public.get_marker_submissions_page(text,text,integer,integer)' ELSE 'public.get_my_marker_submissions_page(text,integer,integer)' END);
 v_new:=pg_catalog.to_regprocedure(CASE WHEN v_kind=1 THEN 'public.get_marker_submissions_page_by_game_uuid(uuid,text,integer,integer)' ELSE 'public.get_my_marker_submissions_page_by_game_uuid(uuid,integer,integer)' END);
 v_old:=CASE WHEN v_kind=1 THEN v_old_global ELSE v_old_mine END;
 SELECT rolname INTO STRICT v_owner FROM pg_catalog.pg_roles WHERE oid=(v_old->>'proowner')::oid;
   IF v_new IS NULL THEN
   v_signature:=CASE WHEN v_kind=1 THEN 'public.get_marker_submissions_page_by_game_uuid(uuid,text,integer,integer)' ELSE 'public.get_my_marker_submissions_page_by_game_uuid(uuid,integer,integer)' END;
   IF v_kind=1 THEN
     EXECUTE pg_catalog.format('CREATE FUNCTION public.get_marker_submissions_page_by_game_uuid(p_game_uuid uuid DEFAULT NULL, p_status text DEFAULT ''pending'', p_limit integer DEFAULT 10, p_offset integer DEFAULT 0)
       RETURNS TABLE (id bigint,
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
    total_count bigint, game_uuid uuid, game_slug text, game_name text)
       LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = %L AS %L','',v_global_uuid_body);
   ELSE
     EXECUTE pg_catalog.format('CREATE FUNCTION public.get_my_marker_submissions_page_by_game_uuid(p_game_uuid uuid, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
       RETURNS TABLE (id bigint,
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
    total_count bigint, game_uuid uuid, game_slug text)
       LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = %L AS %L','',v_mine_uuid_body);
   END IF;
   EXECUTE pg_catalog.format('ALTER FUNCTION %s OWNER TO %I',v_signature,v_owner);
   v_new:=pg_catalog.to_regprocedure(v_signature);
   -- Remove default grants ONLY on the freshly created RPC.
   FOR v_grantee IN SELECT DISTINCT r.rolname FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_new AND a.grantee<>p.proowner LOOP
     EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION %s FROM %I',v_signature,v_grantee);
   END LOOP;
   EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',v_signature);
   EXECUTE pg_catalog.format('GRANT EXECUTE ON FUNCTION %s TO authenticated',v_signature);
   SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_legacy AND r.rolname='service_role') INTO v_service_direct;
   IF v_service_direct THEN EXECUTE pg_catalog.format('GRANT EXECUTE ON FUNCTION %s TO service_role',v_signature); END IF;
 END IF;
   v_pass:=2;
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
   SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_legacy FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_legacy;
 SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable) INTO v_acl_new FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_new;
 IF v_acl_legacy IS DISTINCT FROM v_acl_new THEN RAISE EXCEPTION 'B7E1_DIRECT_ACL_PARITY_DRIFT: pair %',v_kind; END IF;
 IF pg_catalog.has_function_privilege('authenticated',v_legacy,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege('authenticated',v_new,'EXECUTE')
   OR pg_catalog.has_function_privilege('service_role',v_legacy,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege('service_role',v_new,'EXECUTE')
   OR pg_catalog.has_function_privilege('anon',v_new,'EXECUTE') THEN RAISE EXCEPTION 'B7E1_CALLER_EFFECTIVE_EXECUTE_DRIFT'; END IF;
 FOR v_role IN SELECT rolname FROM pg_catalog.pg_roles LOOP
   IF pg_catalog.has_function_privilege(v_role.rolname,v_legacy,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege(v_role.rolname,v_new,'EXECUTE') THEN RAISE EXCEPTION 'B7E1_ALL_ROLE_EXECUTE_PARITY_DRIFT: pair %, role %',v_kind,v_role.rolname; END IF;
 END LOOP;
 END LOOP;
 IF (SELECT pg_catalog.to_jsonb(p) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_marker_submissions_page(text,text,integer,integer)')) IS DISTINCT FROM v_old_global
   OR (SELECT pg_catalog.to_jsonb(p) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_my_marker_submissions_page(text,integer,integer)')) IS DISTINCT FROM v_old_mine THEN RAISE EXCEPTION 'B7E1_COMPLETE_LEGACY_PG_PROC_CHANGED'; END IF;
 EXECUTE v_snapshot_sql INTO v_after;
 IF v_after IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'B7E1_PROTECTED_CATALOG_CHANGED'; END IF;
 RAISE NOTICE 'PASS B7E1 complete legacy pg_proc and protected catalog unchanged';
 RAISE NOTICE 'PASS B7E1 exact UUID contracts, inherited owners, narrow ACL and every-role parity';
 RAISE NOTICE 'INFO B7E1 preservation fingerprint = %',pg_catalog.md5(v_before::text);
END;
$migration$;
COMMIT;
