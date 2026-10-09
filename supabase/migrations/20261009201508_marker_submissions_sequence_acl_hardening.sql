-- DeepMap: harden ONLY the marker_submissions identity sequence ACL.
-- No sequence value consumption/read/reset, ownership/configuration change or row DML.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = pg_catalog;
DO $hardening$
DECLARE
    v_table oid;
    v_seq oid;
    v_id smallint;
    v_owner oid;
    v_anon oid;
    v_auth oid;
    v_service oid;
    v_before jsonb;
    v_after jsonb;
BEGIN
    v_table := pg_catalog.to_regclass('public.marker_submissions');
    v_seq := pg_catalog.to_regclass(pg_catalog.pg_get_serial_sequence('public.marker_submissions','id'));
    v_anon := pg_catalog.to_regrole('anon');
    v_auth := pg_catalog.to_regrole('authenticated');
    v_service := pg_catalog.to_regrole('service_role');
    IF v_table IS NULL OR v_seq IS NULL
       OR v_seq IS DISTINCT FROM pg_catalog.to_regclass('public.marker_submissions_id_seq')
       OR v_anon IS NULL OR v_auth IS NULL OR v_service IS NULL THEN
        RAISE EXCEPTION 'SUBMISSION_SEQUENCE_OBJECT_OR_ROLE_MISSING';
    END IF;
    SELECT a.attnum INTO v_id FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=v_table AND a.attname='id' AND a.attnum>0 AND NOT a.attisdropped
          AND a.atttypid='bigint'::pg_catalog.regtype AND a.attnotnull AND a.attidentity='d' AND a.attgenerated='';
    SELECT c.relowner INTO v_owner FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE c.oid=v_seq AND c.relkind='S' AND n.nspname='public' AND c.relname='marker_submissions_id_seq';
    IF v_id IS NULL OR v_owner IS NULL OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE oid=v_owner)
       OR v_owner IN (v_anon,v_auth)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class WHERE oid=v_table AND relkind='r')
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_sequence WHERE seqrelid=v_seq)
       OR (SELECT count(*) FROM pg_catalog.pg_depend d WHERE d.classid='pg_catalog.pg_class'::pg_catalog.regclass
            AND d.objid=v_seq AND d.deptype='i')<>1
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_depend d WHERE d.classid='pg_catalog.pg_class'::pg_catalog.regclass
            AND d.objid=v_seq AND d.objsubid=0 AND d.refclassid='pg_catalog.pg_class'::pg_catalog.regclass
            AND d.refobjid=v_table AND d.refobjsubid=v_id AND d.deptype='i') THEN
        RAISE EXCEPTION 'SUBMISSION_SEQUENCE_IDENTITY_OR_OWNER_DRIFT';
    END IF;
    -- Fail before ACL writes unless the effective session can act as the owner.
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname=CURRENT_USER
        AND (r.rolsuper OR pg_catalog.pg_has_role(r.oid,v_owner,'USAGE'))) THEN
        RAISE EXCEPTION 'SUBMISSION_SEQUENCE_EFFECTIVE_OWNERSHIP_REQUIRED';
    END IF;
    SELECT pg_catalog.jsonb_build_object(
        'sequence_class',(SELECT pg_catalog.to_jsonb(c)-'relacl' FROM pg_catalog.pg_class c WHERE c.oid=v_seq),
        'configuration',(SELECT pg_catalog.to_jsonb(s) FROM pg_catalog.pg_sequence s WHERE s.seqrelid=v_seq),
        'dependencies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.classid,d.objid,d.objsubid,d.refclassid,d.refobjid,d.refobjsubid,d.deptype)
            FROM pg_catalog.pg_depend d WHERE (d.classid='pg_catalog.pg_class'::pg_catalog.regclass AND d.objid=v_seq)
              OR (d.refclassid='pg_catalog.pg_class'::pg_catalog.regclass AND d.refobjid=v_seq)),
        'table_class',(SELECT pg_catalog.to_jsonb(c) FROM pg_catalog.pg_class c WHERE c.oid=v_table),
        'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attnum) FROM pg_catalog.pg_attribute a WHERE a.attrelid=v_table),
        'defaults',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.adnum) FROM pg_catalog.pg_attrdef d WHERE d.adrelid=v_table),
        'constraints',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid) FROM pg_catalog.pg_constraint c WHERE c.conrelid=v_table),
        'indexes',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.indexrelid) FROM pg_catalog.pg_index i WHERE i.indrelid=v_table),
        'triggers',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY t.oid) FROM pg_catalog.pg_trigger t WHERE t.tgrelid=v_table),
        'policies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid) FROM pg_catalog.pg_policy p WHERE p.polrelid=v_table),
        'unaffected_acl',(SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable),'[]'::jsonb)
            FROM pg_catalog.pg_class c CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('s',c.relowner))) a
            WHERE c.oid=v_seq AND a.grantee NOT IN (0,v_anon,v_auth)),
        'service_effective',ARRAY[pg_catalog.has_sequence_privilege(v_service,v_seq,'USAGE'),
            pg_catalog.has_sequence_privilege(v_service,v_seq,'SELECT'),pg_catalog.has_sequence_privilege(v_service,v_seq,'UPDATE')],
        'owner_effective',ARRAY[pg_catalog.has_sequence_privilege(v_owner,v_seq,'USAGE'),
            pg_catalog.has_sequence_privilege(v_owner,v_seq,'SELECT'),pg_catalog.has_sequence_privilege(v_owner,v_seq,'UPDATE')]
    ) INTO v_before;

    REVOKE ALL PRIVILEGES ON SEQUENCE public.marker_submissions_id_seq FROM anon;
    REVOKE UPDATE ON SEQUENCE public.marker_submissions_id_seq FROM authenticated;
    GRANT USAGE, SELECT ON SEQUENCE public.marker_submissions_id_seq TO authenticated;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c
        CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('s',c.relowner))) a
        WHERE c.oid=v_seq AND a.grantee=0 AND a.privilege_type IN ('USAGE','SELECT','UPDATE')) THEN
        REVOKE ALL PRIVILEGES ON SEQUENCE public.marker_submissions_id_seq FROM PUBLIC;
    END IF;
    SELECT pg_catalog.jsonb_build_object(
        'sequence_class',(SELECT pg_catalog.to_jsonb(c)-'relacl' FROM pg_catalog.pg_class c WHERE c.oid=v_seq),
        'configuration',(SELECT pg_catalog.to_jsonb(s) FROM pg_catalog.pg_sequence s WHERE s.seqrelid=v_seq),
        'dependencies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.classid,d.objid,d.objsubid,d.refclassid,d.refobjid,d.refobjsubid,d.deptype)
            FROM pg_catalog.pg_depend d WHERE (d.classid='pg_catalog.pg_class'::pg_catalog.regclass AND d.objid=v_seq)
              OR (d.refclassid='pg_catalog.pg_class'::pg_catalog.regclass AND d.refobjid=v_seq)),
        'table_class',(SELECT pg_catalog.to_jsonb(c) FROM pg_catalog.pg_class c WHERE c.oid=v_table),
        'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attnum) FROM pg_catalog.pg_attribute a WHERE a.attrelid=v_table),
        'defaults',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.adnum) FROM pg_catalog.pg_attrdef d WHERE d.adrelid=v_table),
        'constraints',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid) FROM pg_catalog.pg_constraint c WHERE c.conrelid=v_table),
        'indexes',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.indexrelid) FROM pg_catalog.pg_index i WHERE i.indrelid=v_table),
        'triggers',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY t.oid) FROM pg_catalog.pg_trigger t WHERE t.tgrelid=v_table),
        'policies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid) FROM pg_catalog.pg_policy p WHERE p.polrelid=v_table),
        'unaffected_acl',(SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable),'[]'::jsonb)
            FROM pg_catalog.pg_class c CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('s',c.relowner))) a
            WHERE c.oid=v_seq AND a.grantee NOT IN (0,v_anon,v_auth)),
        'service_effective',ARRAY[pg_catalog.has_sequence_privilege(v_service,v_seq,'USAGE'),
            pg_catalog.has_sequence_privilege(v_service,v_seq,'SELECT'),pg_catalog.has_sequence_privilege(v_service,v_seq,'UPDATE')],
        'owner_effective',ARRAY[pg_catalog.has_sequence_privilege(v_owner,v_seq,'USAGE'),
            pg_catalog.has_sequence_privilege(v_owner,v_seq,'SELECT'),pg_catalog.has_sequence_privilege(v_owner,v_seq,'UPDATE')]
    ) INTO v_after;

    IF v_after IS DISTINCT FROM v_before
       OR pg_catalog.to_regclass(pg_catalog.pg_get_serial_sequence('public.marker_submissions','id')) IS DISTINCT FROM v_seq THEN
        RAISE EXCEPTION 'SUBMISSION_SEQUENCE_CONFIGURATION_DEPENDENCY_OWNER_OR_UNRELATED_ACL_CHANGED';
    END IF;
    IF pg_catalog.has_sequence_privilege(v_anon,v_seq,'USAGE')
       OR pg_catalog.has_sequence_privilege(v_anon,v_seq,'SELECT')
       OR pg_catalog.has_sequence_privilege(v_anon,v_seq,'UPDATE')
       OR NOT pg_catalog.has_sequence_privilege(v_auth,v_seq,'USAGE')
       OR NOT pg_catalog.has_sequence_privilege(v_auth,v_seq,'SELECT')
       OR pg_catalog.has_sequence_privilege(v_auth,v_seq,'UPDATE')
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c
            CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('s',c.relowner))) a
            WHERE c.oid=v_seq AND a.grantee=0 AND a.privilege_type IN ('USAGE','SELECT','UPDATE')) THEN
        RAISE EXCEPTION 'SUBMISSION_SEQUENCE_FINAL_EFFECTIVE_ACL_INVALID';
    END IF;
    -- No nextval/setval/restart is executed. Concurrent identity use is not frozen;
    -- no historical equality of last_value is claimed by this ACL-only migration.
END;
$hardening$;
COMMIT;
