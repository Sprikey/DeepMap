-- B7d3 DB contract only. Reviewed final baseline: map-community-contributions.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';
DO $migration$
DECLARE
 v_legacy oid := pg_catalog.to_regprocedure('public.get_marker_editor_audit(text)');
 v_new oid := pg_catalog.to_regprocedure('public.get_marker_editor_audit_by_game_uuid(uuid)');
 v_old jsonb; v_before jsonb; v_after jsonb; v_owner name; v_grantee name;
 v_rpc oid; v_is_new boolean; v_role record; v_relation record;
 v_body text := $legacy_body$
    select
        a.marker_id,
        a.created_by,
        pc.username as created_username,
        a.created_at,
        a.updated_by,
        pu.username as updated_username,
        a.updated_at,
        a.published_by,
        pp.username as published_username,
        a.published_at,
        a.approved_by,
        pa.username as approved_username,
        a.approved_at
    from private.marker_editor_audit as a
    join public.marcadores as m
      on m.id = a.marker_id
    left join public.profiles as pc
      on pc.id = a.created_by
    left join public.profiles as pu
      on pu.id = a.updated_by
    left join public.profiles as pp
      on pp.id = a.published_by
    left join public.profiles as pa
      on pa.id = a.approved_by
    where m.game_id = p_game_id
      and private.is_deepmap_admin();
$legacy_body$;
 v_uuid_body text;
 v_snapshot_sql text := $snapshot$SELECT pg_catalog.jsonb_build_object(
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
          AND NOT (n.nspname='public' AND p.proname='get_marker_editor_audit_by_game_uuid')),
    'dependencies', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.classid,d.objid,d.objsubid,d.refclassid,d.refobjid,d.refobjsubid,d.deptype)
 FROM pg_catalog.pg_depend d WHERE
 (d.classid='pg_catalog.pg_proc'::pg_catalog.regclass AND d.objid IN (SELECT p.oid FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private') AND NOT (n.nspname='public' AND p.proname='get_marker_editor_audit_by_game_uuid')))
 OR (d.classid='pg_catalog.pg_class'::pg_catalog.regclass AND d.objid IN (SELECT c.oid FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private')))),
 'schemas', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(n) ORDER BY n.oid)
        FROM pg_catalog.pg_namespace n WHERE n.nspname IN ('public','private'))
)$snapshot$;
BEGIN
 IF v_legacy IS NULL THEN RAISE EXCEPTION 'B7D3 missing legacy'; END IF;
 SELECT pg_catalog.to_jsonb(p),r.rolname INTO STRICT v_old,v_owner FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner WHERE p.oid=v_legacy;
 -- History leaves ownership to the creating role: validate its access and inherit it.
 IF v_owner IN ('anon','authenticated','service_role') THEN RAISE EXCEPTION 'B7D3 untrusted owner'; END IF;
 FOR v_relation IN SELECT c.* FROM pg_catalog.pg_class c WHERE c.oid IN ('public.marcadores'::pg_catalog.regclass,'private.marker_editor_audit'::pg_catalog.regclass,'public.profiles'::pg_catalog.regclass) LOOP
 IF v_relation.relkind<>'r' OR NOT pg_catalog.has_schema_privilege(v_owner,v_relation.relnamespace,'USAGE') OR NOT pg_catalog.has_table_privilege(v_owner,v_relation.oid,'SELECT')
 OR (v_relation.relrowsecurity AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname=v_owner AND (r.rolsuper OR r.rolbypassrls OR (r.oid=v_relation.relowner AND NOT v_relation.relforcerowsecurity)))) THEN RAISE EXCEPTION 'B7D3 owner access/RLS not guaranteed: %',v_relation.relname; END IF;
 END LOOP;
 IF NOT pg_catalog.has_function_privilege(v_owner,'private.is_deepmap_admin()','EXECUTE') THEN RAISE EXCEPTION 'B7D3 owner cannot execute Admin gate'; END IF;
 v_uuid_body := pg_catalog.replace(v_body,'m.game_id = p_game_id','m.game_uuid = p_game_uuid');
 v_rpc:=v_legacy; v_is_new:=false;

 IF (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace AND proname=CASE WHEN v_is_new THEN 'get_marker_editor_audit_by_game_uuid' ELSE 'get_marker_editor_audit' END)<>1 THEN
 RAISE EXCEPTION 'B7D3 missing/ambiguous RPC (new=%)',v_is_new; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
 WHERE p.oid=v_rpc AND p.prokind='f' AND p.pronargs=1
 AND p.proargtypes=CASE WHEN v_is_new THEN '2950'::pg_catalog.oidvector ELSE '25'::pg_catalog.oidvector END
 AND p.proallargtypes=CASE WHEN v_is_new THEN ARRAY['uuid'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid] ELSE ARRAY['text'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid] END
 AND p.proargnames=CASE WHEN v_is_new THEN ARRAY['p_game_uuid','marker_id','created_by','created_username','created_at','updated_by','updated_username','updated_at','published_by','published_username','published_at','approved_by','approved_username','approved_at'] ELSE ARRAY['p_game_id','marker_id','created_by','created_username','created_at','updated_by','updated_username','updated_at','published_by','published_username','published_at','approved_by','approved_username','approved_at'] END
 AND p.proargmodes=ARRAY['i','t','t','t','t','t','t','t','t','t','t','t','t','t']::"char"[]
 AND p.prorettype='record'::pg_catalog.regtype AND p.proretset AND p.provariadic=0
 AND p.pronargdefaults=0 AND p.proargdefaults IS NULL
 AND l.lanname='sql' AND p.prosecdef AND p.provolatile='s'
 AND p.proconfig=ARRAY['search_path=""']::text[]
 AND p.proowner=(v_old->>'proowner')::oid
 AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u'
 AND p.procost=100 AND p.prorows=1000 AND p.prosupport=0
 AND p.probin IS NULL AND p.prosqlbody IS NULL
 AND pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')=pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(CASE WHEN v_is_new THEN v_uuid_body ELSE v_body END,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')
 ) THEN RAISE EXCEPTION 'B7D3 exact shape/body/security/owner contract drift (new=%)',v_is_new; END IF;
 -- Explicit permanent UUID authority checks, in addition to exact reviewed body equality.
 IF v_is_new AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_rpc AND
 (pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),'m.game_uuid = p_game_uuid')=0
 OR p.prosrc ~ 'm[.]game_id' OR p.prosrc ~ 'private[.]game_legacy_identifiers'
 OR p.prosrc ~ 'slug' OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),'and private.is_deepmap_admin()')=0))
 THEN RAISE EXCEPTION 'B7D3 UUID authority/Admin gate drift'; END IF;
 -- Exact direct ACL: owner + authenticated + service_role, no grant option, owner is grantor.
 IF (SELECT count(*) FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a WHERE p.oid=v_rpc)<>3
 OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
 LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_rpc AND
 (a.grantor<>p.proowner OR a.privilege_type<>'EXECUTE' OR a.is_grantable OR (a.grantee<>p.proowner AND (a.grantee=0 OR (r.rolname IS DISTINCT FROM 'authenticated' AND r.rolname IS DISTINCT FROM 'service_role')))))
 -- Require each direct grantee explicitly; effective privileges alone are insufficient.
 OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc AND a.grantee=p.proowner AND a.privilege_type='EXECUTE')
 OR EXISTS (SELECT 1 FROM (VALUES ('authenticated'),('service_role')) expected(role_name)
 WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_rpc AND r.rolname=expected.role_name AND a.privilege_type='EXECUTE'))
 OR NOT pg_catalog.has_function_privilege('authenticated',v_rpc,'EXECUTE')
 OR NOT pg_catalog.has_function_privilege('service_role',v_rpc,'EXECUTE')
 OR pg_catalog.has_function_privilege('anon',v_rpc,'EXECUTE')
 THEN RAISE EXCEPTION 'B7D3 direct/effective ACL drift (new=%)',v_is_new; END IF;

 -- Public/browser roles must have no direct table OR column privileges.
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE c.oid='private.marker_editor_audit'::pg_catalog.regclass AND (a.grantee=0 OR r.rolname IN ('anon','authenticated')))
 OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute c CROSS JOIN LATERAL pg_catalog.aclexplode(c.attacl) a LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE c.attrelid='private.marker_editor_audit'::pg_catalog.regclass AND (a.grantee=0 OR r.rolname IN ('anon','authenticated')))
 THEN RAISE EXCEPTION 'B7D3 private audit direct grant'; END IF;

 EXECUTE v_snapshot_sql INTO v_before;
 IF v_new IS NULL THEN
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace AND proname='get_marker_editor_audit_by_game_uuid') THEN RAISE EXCEPTION 'B7D3 UUID overload drift'; END IF;
 EXECUTE pg_catalog.format('CREATE FUNCTION public.get_marker_editor_audit_by_game_uuid(p_game_uuid uuid) RETURNS TABLE (
    marker_id bigint,
    created_by uuid,
    created_username text,
    created_at timestamptz,
    updated_by uuid,
    updated_username text,
    updated_at timestamptz,
    published_by uuid,
    published_username text,
    published_at timestamptz,
    approved_by uuid,
    approved_username text,
    approved_at timestamptz
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = %L AS %L','',v_uuid_body);
 EXECUTE pg_catalog.format('ALTER FUNCTION public.get_marker_editor_audit_by_game_uuid(uuid) OWNER TO %I',v_owner);
 v_new:=pg_catalog.to_regprocedure('public.get_marker_editor_audit_by_game_uuid(uuid)');
 -- Remove unexpected default grants ONLY on the newly created function.
 FOR v_grantee IN SELECT DISTINCT r.rolname FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_new AND a.grantee<>p.proowner LOOP
 EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION public.get_marker_editor_audit_by_game_uuid(uuid) FROM %I',v_grantee);
 END LOOP;
 REVOKE ALL ON FUNCTION public.get_marker_editor_audit_by_game_uuid(uuid) FROM PUBLIC, anon, authenticated, service_role;
 GRANT EXECUTE ON FUNCTION public.get_marker_editor_audit_by_game_uuid(uuid) TO authenticated, service_role;
 END IF;
 v_rpc:=v_new; v_is_new:=true;

 IF (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='public'::pg_catalog.regnamespace AND proname=CASE WHEN v_is_new THEN 'get_marker_editor_audit_by_game_uuid' ELSE 'get_marker_editor_audit' END)<>1 THEN
 RAISE EXCEPTION 'B7D3 missing/ambiguous RPC (new=%)',v_is_new; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
 WHERE p.oid=v_rpc AND p.prokind='f' AND p.pronargs=1
 AND p.proargtypes=CASE WHEN v_is_new THEN '2950'::pg_catalog.oidvector ELSE '25'::pg_catalog.oidvector END
 AND p.proallargtypes=CASE WHEN v_is_new THEN ARRAY['uuid'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid] ELSE ARRAY['text'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid,'uuid'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,'timestamptz'::pg_catalog.regtype::oid] END
 AND p.proargnames=CASE WHEN v_is_new THEN ARRAY['p_game_uuid','marker_id','created_by','created_username','created_at','updated_by','updated_username','updated_at','published_by','published_username','published_at','approved_by','approved_username','approved_at'] ELSE ARRAY['p_game_id','marker_id','created_by','created_username','created_at','updated_by','updated_username','updated_at','published_by','published_username','published_at','approved_by','approved_username','approved_at'] END
 AND p.proargmodes=ARRAY['i','t','t','t','t','t','t','t','t','t','t','t','t','t']::"char"[]
 AND p.prorettype='record'::pg_catalog.regtype AND p.proretset AND p.provariadic=0
 AND p.pronargdefaults=0 AND p.proargdefaults IS NULL
 AND l.lanname='sql' AND p.prosecdef AND p.provolatile='s'
 AND p.proconfig=ARRAY['search_path=""']::text[]
 AND p.proowner=(v_old->>'proowner')::oid
 AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u'
 AND p.procost=100 AND p.prorows=1000 AND p.prosupport=0
 AND p.probin IS NULL AND p.prosqlbody IS NULL
 AND pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')=pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(CASE WHEN v_is_new THEN v_uuid_body ELSE v_body END,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g')
 ) THEN RAISE EXCEPTION 'B7D3 exact shape/body/security/owner contract drift (new=%)',v_is_new; END IF;
 -- Explicit permanent UUID authority checks, in addition to exact reviewed body equality.
 IF v_is_new AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_rpc AND
 (pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),'m.game_uuid = p_game_uuid')=0
 OR p.prosrc ~ 'm[.]game_id' OR p.prosrc ~ 'private[.]game_legacy_identifiers'
 OR p.prosrc ~ 'slug' OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),'[[:space:]]+',' ','g'),'and private.is_deepmap_admin()')=0))
 THEN RAISE EXCEPTION 'B7D3 UUID authority/Admin gate drift'; END IF;
 -- Exact direct ACL: owner + authenticated + service_role, no grant option, owner is grantor.
 IF (SELECT count(*) FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a WHERE p.oid=v_rpc)<>3
 OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
 LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_rpc AND
 (a.grantor<>p.proowner OR a.privilege_type<>'EXECUTE' OR a.is_grantable OR (a.grantee<>p.proowner AND (a.grantee=0 OR (r.rolname IS DISTINCT FROM 'authenticated' AND r.rolname IS DISTINCT FROM 'service_role')))))
 -- Require each direct grantee explicitly; effective privileges alone are insufficient.
 OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_rpc AND a.grantee=p.proowner AND a.privilege_type='EXECUTE')
 OR EXISTS (SELECT 1 FROM (VALUES ('authenticated'),('service_role')) expected(role_name)
 WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_rpc AND r.rolname=expected.role_name AND a.privilege_type='EXECUTE'))
 OR NOT pg_catalog.has_function_privilege('authenticated',v_rpc,'EXECUTE')
 OR NOT pg_catalog.has_function_privilege('service_role',v_rpc,'EXECUTE')
 OR pg_catalog.has_function_privilege('anon',v_rpc,'EXECUTE')
 THEN RAISE EXCEPTION 'B7D3 direct/effective ACL drift (new=%)',v_is_new; END IF;

 -- Compare effective execution for EVERY existing role, including inherited grants.
 FOR v_role IN SELECT rolname FROM pg_catalog.pg_roles LOOP
 IF pg_catalog.has_function_privilege(v_role.rolname,v_legacy,'EXECUTE') IS DISTINCT FROM pg_catalog.has_function_privilege(v_role.rolname,v_new,'EXECUTE') THEN RAISE EXCEPTION 'B7D3 effective execution mismatch: %',v_role.rolname; END IF;
 END LOOP;
 IF (SELECT pg_catalog.to_jsonb(p) FROM pg_catalog.pg_proc p WHERE p.oid=v_legacy) IS DISTINCT FROM v_old THEN RAISE EXCEPTION 'B7D3 complete legacy pg_proc changed'; END IF;

 EXECUTE v_snapshot_sql INTO v_after;
 IF v_before IS DISTINCT FROM v_after THEN RAISE EXCEPTION 'B7D3 protected catalog changed'; END IF;
 RAISE NOTICE 'PASS B7D3 exact legacy preservation and UUID contract';
 RAISE NOTICE 'INFO B7D3 preservation fingerprint = %',pg_catalog.md5(v_before::text);
END;
$migration$;
COMMIT;
