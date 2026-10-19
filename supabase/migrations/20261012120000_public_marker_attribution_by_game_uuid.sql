-- B7c5 DB only. No data/schema/table-policy/writer changes.
-- Final legacy baseline: map-moderation-notifications-v2.sql.
-- Exact existing UUID contract is accepted; divergent/partial state rolls back.
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $migration$
DECLARE
    v_legacy oid := pg_catalog.to_regprocedure('public.get_public_marker_attribution(text)');
    v_new oid := pg_catalog.to_regprocedure('public.get_public_marker_attribution_by_game_uuid(uuid)');
    v_old jsonb;
    v_before jsonb;
    v_after jsonb;
    v_owner name;
    v_grantee name;
    v_relation record;
    v_expected record;
    v_body text := $legacy_body$
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
$legacy_body$;
    v_uuid_body text;
    v_snapshot_sql text := $snapshot$SELECT pg_catalog.jsonb_build_object(
    'relations', (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_array(
        c.oid,c.relname,c.relnamespace,c.relkind,c.relowner,c.relacl,c.relrowsecurity,
        c.relforcerowsecurity,c.reloptions,c.relreplident) ORDER BY c.oid)
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
          AND NOT (n.nspname='public' AND p.proname='get_public_marker_attribution_by_game_uuid')),
    'schemas', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(n) ORDER BY n.oid)
        FROM pg_catalog.pg_namespace n WHERE n.nspname IN ('public','private'))
)$snapshot$;
BEGIN
    IF v_legacy IS NULL THEN RAISE EXCEPTION 'B7C5_MISSING_LEGACY_RPC'; END IF;
    SELECT pg_catalog.to_jsonb(p),r.rolname INTO STRICT v_old,v_owner
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner WHERE p.oid=v_legacy;
    IF v_owner IN ('anon','authenticated') THEN
        RAISE EXCEPTION 'B7C5_OWNER_MUST_NOT_BE_PUBLIC_CALLER';
    END IF;
    v_uuid_body := pg_catalog.replace(v_body,'m.game_id = p_game_id','m.game_uuid = p_game_uuid');

    -- Guard exact final shape/execution attributes; recognize the reviewed
    -- body with whitespace-only normalization. Preservation stays exact.
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=v_legacy AND p.prokind='f' AND p.pronargs=1
          AND p.proargtypes='25'::pg_catalog.oidvector AND p.provariadic=0
          AND p.proallargtypes=ARRAY['text'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid]
          AND p.proargmodes=ARRAY['i','t','t']::"char"[]
          AND p.proargnames=ARRAY['p_game_id','marker_id','published_username']::text[]
          AND p.prorettype='record'::pg_catalog.regtype AND p.proretset
          AND p.pronargdefaults=0 AND p.proargdefaults IS NULL
          AND l.lanname='sql' AND p.prosecdef AND p.provolatile='s'
          AND p.proconfig=ARRAY['search_path=""']::text[]
          AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u'
          AND p.prosupport=0 AND p.probin IS NULL AND p.prosqlbody IS NULL
          AND pg_catalog.regexp_replace(
              pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),
              '[[:space:]]+',' ','g')=pg_catalog.regexp_replace(
              pg_catalog.btrim(pg_catalog.replace(v_body,pg_catalog.chr(13),'')),
              '[[:space:]]+',' ','g')
    ) THEN RAISE EXCEPTION 'B7C5_LEGACY_FINAL_CONTRACT_DRIFT'; END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_proc p
        WHERE p.pronamespace='public'::pg_catalog.regnamespace
          AND p.proname='get_public_marker_attribution')<>1 THEN
        RAISE EXCEPTION 'B7C5_LEGACY_OVERLOAD_DRIFT';
    END IF;

    FOR v_expected IN SELECT * FROM (VALUES
        ('public.marcadores','id','bigint',true),
        ('public.marcadores','game_uuid','uuid',true),
        ('public.marcadores','is_published','boolean',true),
        ('private.marker_editor_audit','marker_id','bigint',true),
        ('private.marker_editor_audit','created_by','uuid',false),
        ('public.profiles','id','uuid',true),
        ('public.profiles','username','text',true)
    ) e(relation_name,column_name,type_name,not_null) LOOP
        IF pg_catalog.to_regclass(v_expected.relation_name) IS NULL
           OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
            WHERE a.attrelid=pg_catalog.to_regclass(v_expected.relation_name)
              AND a.attname=v_expected.column_name AND a.attnum>0 AND NOT a.attisdropped
              AND a.atttypid=pg_catalog.to_regtype(v_expected.type_name)
              AND a.attnotnull=v_expected.not_null) THEN
            RAISE EXCEPTION 'B7C5_DEPENDENCY_DRIFT: %.%',v_expected.relation_name,v_expected.column_name;
        END IF;
    END LOOP;
    -- Require the same owner to have real access, including a safe RLS bypass.
    -- Fail closed for unfamiliar owner/policy arrangements rather than guessing.
    FOR v_relation IN SELECT c.*,n.nspname FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE c.oid IN ('public.marcadores'::pg_catalog.regclass,
            'private.marker_editor_audit'::pg_catalog.regclass,'public.profiles'::pg_catalog.regclass) LOOP
        IF v_relation.relkind<>'r'
           OR NOT pg_catalog.has_schema_privilege(v_owner,v_relation.relnamespace,'USAGE')
           OR NOT pg_catalog.has_table_privilege(v_owner,v_relation.oid,'SELECT')
           OR (v_relation.relrowsecurity AND NOT EXISTS (
               SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname=v_owner
                 AND (r.rolsuper OR r.rolbypassrls
                   OR (r.oid=v_relation.relowner AND NOT v_relation.relforcerowsecurity)))) THEN
            RAISE EXCEPTION 'B7C5_OWNER_PRIVATE_ACCESS_NOT_GUARANTEED: %',v_relation.relname;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated')) e(role_name)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname=e.role_name)
          OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
            CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
            JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
            WHERE p.oid=v_legacy AND r.rolname=e.role_name AND a.privilege_type='EXECUTE'
              AND NOT a.is_grantable)) OR EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p
        CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
        WHERE p.oid=v_legacy AND a.grantee=0 AND a.privilege_type='EXECUTE'
    ) THEN RAISE EXCEPTION 'B7C5_LEGACY_PUBLIC_CALLER_ACL_DRIFT'; END IF;
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_class c
        CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
        LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
        WHERE c.oid='private.marker_editor_audit'::pg_catalog.regclass
          AND (a.grantee=0 OR r.rolname IN ('anon','authenticated'))
    ) OR EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute c
        CROSS JOIN LATERAL pg_catalog.aclexplode(c.attacl) a
        LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
        WHERE c.attrelid='private.marker_editor_audit'::pg_catalog.regclass
          AND (a.grantee=0 OR r.rolname IN ('anon','authenticated'))
    ) THEN RAISE EXCEPTION 'B7C5_PRIVATE_AUDIT_DIRECT_GRANT_DRIFT'; END IF;
    EXECUTE v_snapshot_sql INTO v_before;

    IF v_new IS NULL THEN
        IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
            WHERE p.pronamespace='public'::pg_catalog.regnamespace
              AND p.proname='get_public_marker_attribution_by_game_uuid') THEN
            RAISE EXCEPTION 'B7C5_UUID_RPC_UNEXPECTED_SIGNATURE';
        END IF;
        EXECUTE pg_catalog.format(
            'CREATE FUNCTION public.get_public_marker_attribution_by_game_uuid(p_game_uuid uuid)
             RETURNS TABLE (marker_id bigint, published_username text)
             LANGUAGE sql STABLE SECURITY DEFINER SET search_path = %L AS %L','',v_uuid_body);
        EXECUTE pg_catalog.format(
            'ALTER FUNCTION public.get_public_marker_attribution_by_game_uuid(uuid) OWNER TO %I',v_owner);
        -- Only for the function just created: remove caller grants inherited
        -- from database default privileges, without changing those defaults.
        -- Existing RPC state never reaches this cleanup branch.
        FOR v_grantee IN SELECT DISTINCT r.rolname
            FROM pg_catalog.pg_proc p
            CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a
            JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
            WHERE p.oid=pg_catalog.to_regprocedure('public.get_public_marker_attribution_by_game_uuid(uuid)')
              AND a.grantee<>p.proowner AND r.rolname NOT IN ('anon','authenticated') LOOP
            EXECUTE pg_catalog.format(
                'REVOKE ALL ON FUNCTION public.get_public_marker_attribution_by_game_uuid(uuid) FROM %I',v_grantee);
        END LOOP;
        REVOKE ALL ON FUNCTION public.get_public_marker_attribution_by_game_uuid(uuid) FROM PUBLIC, anon, authenticated;
        GRANT EXECUTE ON FUNCTION public.get_public_marker_attribution_by_game_uuid(uuid) TO anon, authenticated;
        v_new := pg_catalog.to_regprocedure('public.get_public_marker_attribution_by_game_uuid(uuid)');
    END IF;
    -- No replace/regrant on existing state: inspect and accept only the exact contract.
    IF (SELECT count(*) FROM pg_catalog.pg_proc p
        WHERE p.pronamespace='public'::pg_catalog.regnamespace
          AND p.proname='get_public_marker_attribution_by_game_uuid')<>1
       OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=v_new AND p.prokind='f' AND p.pronargs=1
          AND p.proargtypes='2950'::pg_catalog.oidvector AND p.provariadic=0
          AND p.proallargtypes=ARRAY['uuid'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid]
          AND p.proargmodes=ARRAY['i','t','t']::"char"[]
          AND p.proargnames=ARRAY['p_game_uuid','marker_id','published_username']::text[]
          AND p.prorettype='record'::pg_catalog.regtype AND p.proretset
          AND p.pronargdefaults=0 AND p.proargdefaults IS NULL
          AND l.lanname='sql' AND p.prosecdef AND p.provolatile='s'
          AND p.proconfig=ARRAY['search_path=""']::text[]
          AND p.proowner=(v_old->>'proowner')::oid
          AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u'
          AND p.procost=100 AND p.prorows=1000
          AND p.prosupport=0 AND p.probin IS NULL AND p.prosqlbody IS NULL
          AND pg_catalog.regexp_replace(
              pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),
              '[[:space:]]+',' ','g')=pg_catalog.regexp_replace(
              pg_catalog.btrim(pg_catalog.replace(v_uuid_body,pg_catalog.chr(13),'')),
              '[[:space:]]+',' ','g')
    ) THEN RAISE EXCEPTION 'B7C5_UUID_RPC_CONTRACT_OR_OWNER_DRIFT'; END IF;
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p
        CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
        LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
        WHERE p.oid=v_new AND (a.grantor<>p.proowner
          OR a.privilege_type<>'EXECUTE' OR a.is_grantable
          OR (a.grantee<>p.proowner AND (a.grantee=0 OR r.rolname NOT IN ('anon','authenticated'))))
    ) OR (SELECT count(*) FROM pg_catalog.pg_proc p
        CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_new)<>3
      OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a
        WHERE p.oid=v_new AND a.grantee=p.proowner AND a.privilege_type='EXECUTE')
      OR EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated')) e(role_name)
        WHERE NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc p
            CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a
            JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
            WHERE p.oid=v_new AND r.rolname=e.role_name
              AND a.privilege_type='EXECUTE' AND NOT a.is_grantable)
    ) THEN RAISE EXCEPTION 'B7C5_UUID_RPC_ACL_DRIFT'; END IF;

    IF (SELECT pg_catalog.to_jsonb(p) FROM pg_catalog.pg_proc p WHERE p.oid=v_legacy)
        IS DISTINCT FROM v_old THEN RAISE EXCEPTION 'B7C5_LEGACY_RPC_CHANGED'; END IF;
    EXECUTE v_snapshot_sql INTO v_after;
    IF v_after IS DISTINCT FROM v_before THEN
        RAISE EXCEPTION 'B7C5_PROTECTED_CATALOG_CHANGED';
    END IF;
    RAISE NOTICE 'PASS legacy OID/owner/ACL/signature/return/security/config/volatility/body unchanged';
    RAISE NOTICE 'PASS protected tables/columns/constraints/indexes/triggers/policies/grants/schemas/writers/review RPCs unchanged';
    RAISE NOTICE 'INFO B7C5 preservation fingerprint = %',pg_catalog.md5(v_before::text);
    RAISE NOTICE 'PASS UUID RPC exact contract, same owner, anon/authenticated EXECUTE only (plus owner)';
END;
$migration$;

COMMIT;
