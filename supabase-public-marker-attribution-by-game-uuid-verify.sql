-- B7c5 DB verifier. READ ONLY: no fixtures, DDL, DML, grants or persisted state.
-- Run manually as a maintenance role able to inspect private data/catalogs.
-- Paste the INFO B7C5 preservation fingerprint from the successful migration
-- into v_expected_preservation_md5 below. It is its BEFORE=AFTER baseline.
-- Alternatively capture this verifier's INFO fingerprint before migration.
-- Without a baseline, historical preservation is FAIL, never a fabricated PASS.
-- Before migration, missing UUID RPC is expected to FAIL; fingerprint is still printed.
-- Compare within the same database/catalog version, without intervening schema changes.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

DO $verify$
DECLARE
    v_expected_preservation_md5 text := NULL; -- REQUIRED: paste trusted baseline here.
    v_legacy oid := pg_catalog.to_regprocedure('public.get_public_marker_attribution(text)');
    v_new oid := pg_catalog.to_regprocedure('public.get_public_marker_attribution_by_game_uuid(uuid)');
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
    v_snapshot jsonb;
    v_check record;
    v_context record;
    v_legacy_rows jsonb;
    v_uuid_rows jsonb;
    v_expected_rows jsonb;
    v_absent uuid;
    v_probe integer := 0;
    v_pass integer := 0;
    v_fail integer := 0;
    v_context_count integer := 0;
    v_equivalence_count integer := 0;
    v_bad integer := 0;
    v_published bigint;
    v_unpublished bigint;
    v_can_call boolean := false;
    v_ok boolean;
BEGIN
    EXECUTE v_snapshot_sql INTO v_snapshot;
    RAISE NOTICE 'INFO B7C5 preservation fingerprint = %',pg_catalog.md5(v_snapshot::text);
    -- The snapshot protects complete public/private routine catalog rows,
    -- table schemas/ACL/column ACL, constraints/indexes, triggers, policies and schemas.
    -- It excludes ONLY the newly introduced RPC, by distinct name.
    IF v_expected_preservation_md5 IS NULL THEN
        v_fail := v_fail+1;
        RAISE NOTICE 'FAIL historical preservation baseline missing: paste trusted fingerprint before certifying legacy OID/owner/ACL and protected catalog immutability';
    ELSIF v_expected_preservation_md5=pg_catalog.md5(v_snapshot::text) THEN
        v_pass := v_pass+1;
        RAISE NOTICE 'PASS historical preservation: legacy full catalog row; marcadores/audit/profiles schema and grants; marker triggers/policies; all existing writers/review RPCs unchanged';
    ELSE
        v_fail := v_fail+1;
        RAISE NOTICE 'FAIL protected catalog fingerprint differs from baseline';
    END IF;

    v_uuid_body := pg_catalog.replace(v_body,'m.game_id = p_game_id','m.game_uuid = p_game_uuid');
    FOR v_check IN SELECT * FROM (VALUES
        ('A legacy TEXT RPC exists',v_legacy IS NOT NULL),
        ('B distinct UUID RPC exists',v_new IS NOT NULL),
        ('C no attribution overload ambiguity',
            (SELECT count(*)=1 FROM pg_catalog.pg_proc p
             WHERE p.pronamespace='public'::pg_catalog.regnamespace AND p.proname='get_public_marker_attribution')
            AND (SELECT count(*)=1 FROM pg_catalog.pg_proc p
             WHERE p.pronamespace='public'::pg_catalog.regnamespace AND p.proname='get_public_marker_attribution_by_game_uuid')),
        ('D UUID input and public output contain only marker_id bigint + published_username text',
            EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_new
                AND p.prokind='f' AND p.pronargs=1 AND p.proargtypes='2950'::pg_catalog.oidvector
                AND p.proallargtypes=ARRAY['uuid'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid]
                AND p.proargmodes=ARRAY['i','t','t']::"char"[]
                AND p.proargnames=ARRAY['p_game_uuid','marker_id','published_username']::text[]
                AND p.prorettype='record'::pg_catalog.regtype AND p.proretset)),
        ('E legacy final TEXT input and two-column public output',
            EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_legacy
                AND p.prokind='f' AND p.pronargs=1 AND p.proargtypes='25'::pg_catalog.oidvector
                AND p.proallargtypes=ARRAY['text'::pg_catalog.regtype::oid,'bigint'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid]
                AND p.proargmodes=ARRAY['i','t','t']::"char"[]
                AND p.proargnames=ARRAY['p_game_id','marker_id','published_username']::text[]
                AND p.prorettype='record'::pg_catalog.regtype AND p.proretset)),
        ('F both RPCs SECURITY DEFINER',EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc n JOIN pg_catalog.pg_proc l ON l.oid=v_legacy
            WHERE n.oid=v_new AND n.prosecdef AND l.prosecdef)),
        ('G both RPCs empty search_path only',EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc n JOIN pg_catalog.pg_proc l ON l.oid=v_legacy
            WHERE n.oid=v_new AND n.proconfig=ARRAY['search_path=""']::text[]
              AND l.proconfig=ARRAY['search_path=""']::text[])),
        ('H same SQL STABLE volatility and compatible execution attributes',EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc n JOIN pg_catalog.pg_proc l ON l.oid=v_legacy
            JOIN pg_catalog.pg_language lang ON lang.oid=n.prolang
            WHERE n.oid=v_new AND n.provolatile='s' AND l.provolatile=n.provolatile
              AND n.prolang=l.prolang AND lang.lanname='sql'
              AND NOT n.proisstrict AND NOT l.proisstrict
              AND NOT n.proleakproof AND NOT l.proleakproof
              AND n.proparallel='u' AND l.proparallel='u'
              AND n.pronargdefaults=0 AND l.pronargdefaults=0
              AND n.proargdefaults IS NULL AND l.proargdefaults IS NULL
              AND n.provariadic=0 AND l.provariadic=0
              AND n.procost=100 AND n.prorows=1000
              AND n.prosupport=0 AND n.probin IS NULL AND n.prosqlbody IS NULL
              AND l.prosupport=0 AND l.probin IS NULL AND l.prosqlbody IS NULL)),
        ('I identical owner',EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc n JOIN pg_catalog.pg_proc l ON l.oid=v_legacy
            JOIN pg_catalog.pg_roles r ON r.oid=n.proowner
            WHERE n.oid=v_new AND n.proowner=l.proowner AND r.rolname NOT IN ('anon','authenticated'))),
        ('J UUID RPC PUBLIC has no EXECUTE',
            v_new IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(
                    COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
                WHERE p.oid=v_new AND a.grantee=0 AND a.privilege_type='EXECUTE')),
        ('K anon direct and effective EXECUTE without grant option',
            EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a
                JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_new AND r.rolname='anon'
                    AND a.privilege_type='EXECUTE' AND NOT a.is_grantable
                    AND pg_catalog.has_function_privilege(r.oid,p.oid,'EXECUTE'))),
        ('L authenticated direct and effective EXECUTE without grant option',
            EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a
                JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_new AND r.rolname='authenticated'
                    AND a.privilege_type='EXECUTE' AND NOT a.is_grantable
                    AND pg_catalog.has_function_privilege(r.oid,p.oid,'EXECUTE'))),
        ('ACL exact owner/anon/authenticated entries and owner grantor',v_new IS NOT NULL
            AND (SELECT count(*) FROM pg_catalog.pg_proc p
                CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a WHERE p.oid=v_new)=3
            AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
                CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a
                WHERE p.oid=v_new AND a.grantee=p.proowner AND a.privilege_type='EXECUTE')
            AND NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(
                COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
            LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.oid=v_new
                AND (a.grantor<>p.proowner OR a.privilege_type<>'EXECUTE' OR a.is_grantable
                    OR (a.grantee<>p.proowner AND (a.grantee=0 OR r.rolname NOT IN ('anon','authenticated')))))),
        ('N explicit UUID equality and published marker filter',EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_new
                AND pg_catalog.strpos(p.prosrc,'m.game_uuid = p_game_uuid')>0
                AND pg_catalog.strpos(p.prosrc,'m.is_published = true')>0)),
        ('O no private mapping dependency in UUID body',EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_new
                AND p.prosrc !~* 'game_legacy_identifiers')),
        ('P no slug or legacy marker scope in UUID body',EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_new
                AND p.prosrc !~* '(slug|m[.]game_id|p_game_id)')),
        ('Q legacy body equals FINAL repo baseline after whitespace normalization',EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_legacy
                AND pg_catalog.regexp_replace(
                    pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),
                    '[[:space:]]+',' ','g')=pg_catalog.regexp_replace(
                    pg_catalog.btrim(pg_catalog.replace(v_body,pg_catalog.chr(13),'')),
                    '[[:space:]]+',' ','g'))),
        ('V UUID body equals final creator logic with UUID scope substitution after whitespace normalization',EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_new
                AND pg_catalog.regexp_replace(
                    pg_catalog.btrim(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')),
                    '[[:space:]]+',' ','g')=pg_catalog.regexp_replace(
                    pg_catalog.btrim(pg_catalog.replace(v_uuid_body,pg_catalog.chr(13),'')),
                    '[[:space:]]+',' ','g')))
    ) e(label,ok) LOOP
        IF v_check.ok IS TRUE THEN v_pass:=v_pass+1; RAISE NOTICE 'PASS %',v_check.label;
        ELSE v_fail:=v_fail+1; RAISE NOTICE 'FAIL %',v_check.label; END IF;
    END LOOP;

    IF EXISTS (SELECT 1 FROM (VALUES ('public.marcadores'),('private.marker_editor_audit'),('public.profiles'))
        e(name) WHERE pg_catalog.to_regclass(e.name) IS NULL) THEN
        v_fail:=v_fail+1;
        RAISE NOTICE 'FAIL required relation missing; INFO SKIP dependency and behavioral checks';
    ELSE
        FOR v_check IN SELECT * FROM (VALUES
            ('game_uuid UUID NOT NULL final bridge',EXISTS (
                SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.marcadores'::pg_catalog.regclass
                  AND a.attname='game_uuid' AND a.atttypid='uuid'::pg_catalog.regtype
                  AND a.attnotnull AND a.attnum>0 AND NOT a.attisdropped)),
            ('M no direct audit table/column grants to PUBLIC/anon/authenticated',NOT EXISTS (
                SELECT 1 FROM pg_catalog.pg_class c CROSS JOIN LATERAL pg_catalog.aclexplode(
                    COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
                LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
                WHERE c.oid='private.marker_editor_audit'::pg_catalog.regclass
                  AND (a.grantee=0 OR r.rolname IN ('anon','authenticated'))
                UNION ALL
                SELECT 1 FROM pg_catalog.pg_attribute c CROSS JOIN LATERAL pg_catalog.aclexplode(c.attacl) a
                LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
                WHERE c.attrelid='private.marker_editor_audit'::pg_catalog.regclass
                  AND (a.grantee=0 OR r.rolname IN ('anon','authenticated')))),
            ('I owner has dependency SELECT/schema USAGE and guaranteed RLS access',
                v_new IS NOT NULL AND NOT EXISTS (
                    SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_proc p ON p.oid=v_new
                    JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
                    WHERE c.oid IN ('public.marcadores'::pg_catalog.regclass,
                        'private.marker_editor_audit'::pg_catalog.regclass,'public.profiles'::pg_catalog.regclass)
                      AND (c.relkind<>'r' OR NOT pg_catalog.has_table_privilege(r.oid,c.oid,'SELECT')
                        OR NOT pg_catalog.has_schema_privilege(r.oid,c.relnamespace,'USAGE')
                        OR (c.relrowsecurity AND NOT (r.rolsuper OR r.rolbypassrls
                            OR (r.oid=c.relowner AND NOT c.relforcerowsecurity)))))),
            ('legacy expected public caller ACL',
                v_legacy IS NOT NULL AND NOT EXISTS (
                    SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(
                        COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
                    WHERE p.oid=v_legacy AND a.grantee=0 AND a.privilege_type='EXECUTE')
                AND NOT EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated')) e(name)
                    WHERE NOT EXISTS (
                        SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) a
                        JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
                        WHERE p.oid=v_legacy AND r.rolname=e.name AND a.privilege_type='EXECUTE'
                          AND NOT a.is_grantable)))
        ) e(label,ok) LOOP
            IF v_check.ok IS TRUE THEN v_pass:=v_pass+1; RAISE NOTICE 'PASS %',v_check.label;
            ELSE v_fail:=v_fail+1; RAISE NOTICE 'FAIL %',v_check.label; END IF;
        END LOOP;

        -- Invoke only after whitespace-normalized body recognition and exact
        -- return/execution checks have all passed.
        -- Missing historical baseline does not prevent useful behavioral diagnostics.
        SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_proc n JOIN pg_catalog.pg_proc l ON l.oid=v_legacy
            WHERE n.oid=v_new AND pg_catalog.regexp_replace(
                pg_catalog.btrim(pg_catalog.replace(n.prosrc,pg_catalog.chr(13),'')),
                '[[:space:]]+',' ','g')=pg_catalog.regexp_replace(
                pg_catalog.btrim(pg_catalog.replace(v_uuid_body,pg_catalog.chr(13),'')),
                '[[:space:]]+',' ','g')
              AND pg_catalog.regexp_replace(
                pg_catalog.btrim(pg_catalog.replace(l.prosrc,pg_catalog.chr(13),'')),
                '[[:space:]]+',' ','g')=pg_catalog.regexp_replace(
                pg_catalog.btrim(pg_catalog.replace(v_body,pg_catalog.chr(13),'')),
                '[[:space:]]+',' ','g'))
        INTO v_can_call;
        IF v_can_call
           AND v_fail = (
               CASE
                   WHEN v_expected_preservation_md5 IS NULL
                     OR v_expected_preservation_md5 <> pg_catalog.md5(v_snapshot::text)
                   THEN 1
                   ELSE 0
               END
           )
        THEN
            LOOP
                v_absent:=pg_catalog.md5('DeepMap B7c5 absent UUID probe '||v_probe::text)::uuid;
                EXIT WHEN NOT EXISTS (SELECT 1 FROM public.marcadores m WHERE m.game_uuid=v_absent)
                    AND NOT EXISTS (SELECT 1 FROM public.games g WHERE g.id=v_absent);
                v_probe:=v_probe+1;
            END LOOP;
            SELECT NOT EXISTS (SELECT 1 FROM public.get_public_marker_attribution_by_game_uuid(v_absent)) INTO v_ok;
            IF v_ok THEN v_pass:=v_pass+1; RAISE NOTICE 'PASS R nonexistent game UUID returns zero rows';
            ELSE v_fail:=v_fail+1; RAISE NOTICE 'FAIL R nonexistent game UUID returned rows'; END IF;
            SELECT NOT EXISTS (SELECT 1 FROM public.get_public_marker_attribution_by_game_uuid(NULL::uuid)) INTO v_ok;
            IF v_ok THEN v_pass:=v_pass+1; RAISE NOTICE 'PASS NULL game UUID returns zero rows';
            ELSE v_fail:=v_fail+1; RAISE NOTICE 'FAIL NULL game UUID returned rows'; END IF;

            SELECT count(*) FILTER (WHERE is_published),count(*) FILTER (WHERE NOT is_published)
                INTO v_published,v_unpublished FROM public.marcadores;
            FOR v_context IN SELECT DISTINCT m.game_uuid FROM public.marcadores m ORDER BY m.game_uuid LOOP
                v_context_count:=v_context_count+1;
                SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r)
                    ORDER BY r.marker_id,r.published_username NULLS FIRST),'[]'::jsonb)
                INTO v_uuid_rows FROM public.get_public_marker_attribution_by_game_uuid(v_context.game_uuid) r;
                SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r)
                    ORDER BY r.marker_id,r.published_username NULLS FIRST),'[]'::jsonb)
                INTO v_expected_rows FROM (
                    SELECT a.marker_id,creator.username AS published_username
                    FROM private.marker_editor_audit a JOIN public.marcadores m ON m.id=a.marker_id
                    LEFT JOIN public.profiles creator ON creator.id=a.created_by
                    WHERE m.game_uuid=v_context.game_uuid AND m.is_published=true
                ) r;
                IF v_uuid_rows IS DISTINCT FROM v_expected_rows THEN v_bad:=v_bad+1; END IF;
                IF EXISTS (
                    SELECT 1 FROM public.get_public_marker_attribution_by_game_uuid(v_context.game_uuid) r
                    LEFT JOIN public.marcadores m ON m.id=r.marker_id
                    WHERE m.id IS NULL OR m.is_published IS DISTINCT FROM true
                        OR m.game_uuid IS DISTINCT FROM v_context.game_uuid
                ) THEN v_bad:=v_bad+1; END IF;
            END LOOP;
            IF v_bad>0 THEN
                v_fail:=v_fail+1; RAISE NOTICE 'FAIL creator/NULL/publication/isolation checks in % contexts',v_bad;
            ELSIF v_context_count=0 THEN
                RAISE NOTICE 'INFO SKIP published/unpublished/isolation/creator behavior: no markers';
            ELSE
                v_pass:=v_pass+1;
                RAISE NOTICE 'PASS exact creator/NULL output and published UUID scope for all % marker contexts',v_context_count;
            END IF;
            IF v_published=0 THEN RAISE NOTICE 'INFO SKIP published-marker positive coverage: no published markers';
            ELSE RAISE NOTICE 'INFO published-marker coverage: % existing markers',v_published; END IF;
            IF v_unpublished=0 THEN RAISE NOTICE 'INFO SKIP T unpublished-marker negative fixtures: no unpublished markers';
            ELSE RAISE NOTICE 'INFO T unpublished exclusion covered: % existing markers',v_unpublished; END IF;
            IF v_context_count<2 THEN RAISE NOTICE 'INFO SKIP U cross-game negative fixtures: fewer than two marker games';
            ELSE RAISE NOTICE 'INFO U cross-game exclusion covered across % games',v_context_count; END IF;

            IF pg_catalog.to_regclass('private.game_legacy_identifiers') IS NULL THEN
                v_fail:=v_fail+1; RAISE NOTICE 'FAIL S verifier-only mapping missing';
            ELSE
                v_bad:=0;
                -- Multiple aliases may map to one conceptual game. Compare
                -- once per UUID, combining every legacy alias for that UUID.
                FOR v_context IN SELECT DISTINCT m.game_uuid
                    FROM public.marcadores m
                    WHERE m.is_published=true
                    ORDER BY m.game_uuid LOOP
                    IF EXISTS (SELECT 1 FROM public.marcadores m WHERE m.game_uuid=v_context.game_uuid
                        AND (SELECT count(*) FROM private.game_legacy_identifiers i
                            WHERE i.legacy_identifier=m.game_id AND i.game_id=m.game_uuid)<>1) THEN
                        v_bad:=v_bad+1;
                        RAISE NOTICE 'FAIL S incompatible legacy/UUID bridge context';
                        CONTINUE;
                    END IF;
                    v_equivalence_count:=v_equivalence_count+1;
                    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r)
                        ORDER BY r.marker_id,r.published_username NULLS FIRST),'[]'::jsonb)
                        INTO v_legacy_rows FROM private.game_legacy_identifiers i
                        CROSS JOIN LATERAL public.get_public_marker_attribution(i.legacy_identifier) r
                        WHERE i.game_id=v_context.game_uuid;
                    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r)
                        ORDER BY r.marker_id,r.published_username NULLS FIRST),'[]'::jsonb)
                        INTO v_uuid_rows FROM public.get_public_marker_attribution_by_game_uuid(v_context.game_uuid) r;
                    IF v_legacy_rows IS DISTINCT FROM v_uuid_rows THEN
                        v_bad:=v_bad+1; RAISE NOTICE 'FAIL S combined legacy aliases/UUID ordered attribution results differ';
                    END IF;
                END LOOP;
                IF v_bad>0 THEN v_fail:=v_fail+1; RAISE NOTICE 'FAIL S % divergent/incompatible contexts',v_bad;
                ELSIF v_equivalence_count=0 THEN
                    RAISE NOTICE 'INFO SKIP S no mapped published-marker contexts; no fixtures invented';
                ELSE v_pass:=v_pass+1;
                    RAISE NOTICE 'PASS S combined legacy aliases/UUID ordered (marker_id,published_username) results identical for all % game UUID contexts',v_equivalence_count;
                END IF;
            END IF;
            RAISE NOTICE 'INFO V privacy proved by exact two-column return/body; no raw UUID/email/audit metadata output';
        ELSE
            RAISE NOTICE 'INFO SKIP behavioral RPC calls: structural/security contract failed or RPC absent';
        END IF;
    END IF;
    RAISE NOTICE 'TOTAL PASS = %',v_pass;
    RAISE NOTICE 'TOTAL FAIL = %',v_fail;
    RAISE NOTICE 'INFO success requires TOTAL FAIL = 0; INFO SKIP is not exercised behavioral coverage';
    IF v_fail <> 0 THEN
        RAISE EXCEPTION 'B7C5_VERIFICATION_FAILED: TOTAL FAIL = %', v_fail;
    END IF;
EXCEPTION WHEN OTHERS THEN
    v_fail:=v_fail+1;
    RAISE NOTICE 'FAIL verifier structural/permission/runtime error [%]: %',SQLSTATE,SQLERRM;
    RAISE NOTICE 'TOTAL PASS = %',v_pass;
    RAISE NOTICE 'TOTAL FAIL = %',v_fail;
    RAISE NOTICE 'INFO verification incomplete; resolve error and rerun';
    RAISE;
END;
$verify$;

ROLLBACK;
