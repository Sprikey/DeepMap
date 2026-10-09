-- DeepMap B5a: timestamp compatibility only; no UUID columns/backfill yet.
-- UUID-only updates cannot reach the other known UPDATE OF / INSERT triggers.
-- Future B5 bridge MUST reject arbitrary UUID-only mutations.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = pg_catalog;

-- Serializes submission writers while checking rows/catalog and replacing touch.
-- SHARE ROW EXCLUSIVE allows ordinary reads; no locks on side-effect tables.
LOCK TABLE public.marker_submissions IN SHARE ROW EXCLUSIVE MODE;

DO $migration$
DECLARE
    v_expected text := pg_catalog.replace($legacy_body$
begin
    new.updated_at := now();
    return new;
end;
$legacy_body$,pg_catalog.chr(13),'');
    v_guard text := pg_catalog.replace($guard$    -- Only a real UUID-shadow change may bypass the legacy timestamp touch.
    -- Safe before expand: JSONB subtraction tolerates an absent game_uuid key.
    if tg_op = 'UPDATE'
       and to_jsonb(new) is distinct from to_jsonb(old)
       and (to_jsonb(new) - 'game_uuid') is not distinct from
           (to_jsonb(old) - 'game_uuid') then
        new.updated_at := old.updated_at;
        return new;
    end if;

$guard$,pg_catalog.chr(13),'');
    v_new_body text;
    v_oid oid;
    v_function_before jsonb;
    v_functions_before jsonb;
    v_catalog_before jsonb;
    v_catalog_after jsonb;
    v_rows_before jsonb;
    v_rows_after jsonb;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
        WHERE c.oid=pg_catalog.to_regclass('public.marker_submissions') AND c.relkind='r' AND c.relrowsecurity
          AND pg_catalog.has_table_privilege(c.oid,'SELECT') AND pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
          AND (r.rolsuper OR r.rolbypassrls OR (r.oid=c.relowner AND NOT c.relforcerowsecurity))) THEN
        RAISE EXCEPTION 'B5A_FULL_MAINTENANCE_VISIBILITY_REQUIRED';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.marker_submissions'::pg_catalog.regclass
        AND a.attnum>0 AND NOT a.attisdropped)<>14 OR EXISTS (
        SELECT 1 FROM (VALUES
            ('id','bigint',true,'d',NULL::text),
            ('game_id','text',true,'',NULL),('marker_id','bigint',false,'',NULL),
            ('submission_type','text',true,'',NULL),('correction_kind','text',false,'',NULL),
            ('status','text',true,'','''pending''::text'),('submitted_by','uuid',true,'',NULL),
            ('payload','jsonb',true,'','''{}''::jsonb'),('note','text',false,'',NULL),
            ('reviewed_by','uuid',false,'',NULL),('reviewed_at','timestamp with time zone',false,'',NULL),
            ('review_note','text',false,'',NULL),
            ('created_at','timestamp with time zone',true,'','now()'),
            ('updated_at','timestamp with time zone',true,'','now()')
        ) e(name,type_name,nn,identity_kind,default_expr)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
            LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
            WHERE a.attrelid='public.marker_submissions'::pg_catalog.regclass AND a.attname=e.name
              AND a.attnum>0 AND NOT a.attisdropped AND a.atttypid=pg_catalog.to_regtype(e.type_name)
              AND a.attnotnull=e.nn AND a.attidentity::text=e.identity_kind AND a.attgenerated=''
              AND a.atthasdef=(e.default_expr IS NOT NULL)
              AND pg_catalog.pg_get_expr(d.adbin,d.adrelid) IS NOT DISTINCT FROM e.default_expr)) THEN
        RAISE EXCEPTION 'B5A_SUBMISSION_COLUMN_CONTRACT_DRIFT';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid='public.marker_submissions'::pg_catalog.regclass AND a.attnum>0 AND NOT a.attisdropped
          AND a.attname IN ('game_uuid','layer_uuid','category_uuid','group_uuid','game_map_id'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='private' AND p.proname='deepmap_resolve_submission_identity') THEN
        RAISE EXCEPTION 'B5A_PARTIAL_BRIDGE_OR_UNEXPECTED_UUID_STATE';
    END IF;
    IF EXISTS (SELECT 1 FROM (VALUES ('game_uuid'),('layer_uuid')) e(name)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
            WHERE a.attrelid=pg_catalog.to_regclass('public.marcadores') AND a.attname=e.name
              AND a.attnum>0 AND NOT a.attisdropped AND a.atttypid='uuid'::pg_catalog.regtype AND a.attnotnull))
       OR pg_catalog.to_regprocedure('private.deepmap_resolve_marker_identity()') IS NULL
       OR (SELECT count(*) FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass('public.marcadores')
            AND c.conname IN ('marcadores_legacy_game_uuid_fk','marcadores_legacy_uuid_layer_fk')
            AND c.contype='f' AND c.convalidated AND NOT c.condeferrable)<>2 THEN
        RAISE EXCEPTION 'B5A_B4B_DEPENDENCY_MISSING';
    END IF;
    v_oid := pg_catalog.to_regprocedure('private.deepmap_touch_submission_updated_at()');
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=v_oid AND p.pronargs=0 AND p.prokind='f' AND NOT p.proretset
          AND p.prorettype='trigger'::pg_catalog.regtype AND l.lanname='plpgsql' AND NOT p.prosecdef
          AND p.proconfig=ARRAY['search_path=""']::text[] AND p.provolatile='v' AND p.proparallel='u'
          AND NOT p.proleakproof AND NOT p.proisstrict AND p.procost=100 AND p.prorows=0
          AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=v_expected)
       OR (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='private' AND p.proname='deepmap_touch_submission_updated_at')<>1 THEN
        RAISE EXCEPTION 'B5A_TOUCH_BODY_OR_ATTRIBUTES_DRIFT';
    END IF;

    -- Exact timing/events, target, UPDATE OF list and WHEN contract.
    IF (SELECT count(*) FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.marker_submissions'::pg_catalog.regclass
        AND NOT t.tgisinternal)<>7 OR EXISTS (
        SELECT 1 FROM (VALUES
            ('deepmap_marker_submissions_touch_updated_at','private.deepmap_touch_submission_updated_at()',19,ARRAY[]::text[],NULL::text),
            ('deepmap_marker_submission_revision','private.deepmap_capture_submission_revision()',21,ARRAY['payload','note','correction_kind'],NULL),
            ('deepmap_materialize_submission_content','private.deepmap_materialize_submission_content()',17,ARRAY['status'],'old.statusisdistinctfromnew.status'),
            ('deepmap_notify_admin_submission_received','private.deepmap_notify_admin_submission_received()',5,ARRAY[]::text[],NULL),
            ('deepmap_notify_submission_review','private.deepmap_notify_submission_review()',17,ARRAY['status','marker_id','review_note','reviewed_by'],'old.statusisdistinctfromnew.status'),
            ('marker_submissions_autoapprove_moderator_insert','private.deepmap_autoapprove_moderator_submission()',5,ARRAY[]::text[],NULL),
            ('marker_submissions_autoapprove_moderator_update','private.deepmap_autoapprove_moderator_submission()',17,ARRAY['payload','note','correction_kind'],'new.status=''pending''::text')
        ) e(name,signature,bits,columns,condition)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
            WHERE t.tgrelid='public.marker_submissions'::pg_catalog.regclass AND t.tgname=e.name
              AND t.tgfoid=pg_catalog.to_regprocedure(e.signature) AND t.tgtype=e.bits
              AND NOT t.tgisinternal AND t.tgenabled='O' AND t.tgnargs=0
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(t.tgattr::smallint[]) WITH ORDINALITY k(num,ord)
                  JOIN pg_catalog.pg_attribute a ON a.attrelid=t.tgrelid AND a.attnum=k.num ORDER BY k.ord)=e.columns
              AND pg_catalog.lower(pg_catalog.regexp_replace(pg_catalog.substring(pg_catalog.pg_get_triggerdef(t.oid,true),
                  ' WHEN [(](.*)[)] EXECUTE FUNCTION '),
                  '[[:space:]()]','','g')) IS NOT DISTINCT FROM e.condition)) THEN
        RAISE EXCEPTION 'B5A_SUBMISSION_TRIGGER_CONTRACT_DRIFT';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgfoid=v_oid AND NOT tgisinternal)<>1
       OR EXISTS (SELECT 1 FROM (VALUES
           ('private.deepmap_replace_quick_marker_content(bigint,jsonb)'),
           ('public.review_marker_submission(bigint,text,text)'),
           ('public.review_marker_submission_v2(bigint,text,text,jsonb)')) e(signature)
           WHERE pg_catalog.to_regprocedure(e.signature) IS NULL) THEN
        RAISE EXCEPTION 'B5A_UNKNOWN_TOUCH_USAGE_OR_MISSING_REVIEW_CONTRACT';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_rewrite r
        WHERE r.ev_class='public.marker_submissions'::pg_catalog.regclass)
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_inherits i WHERE i.inhrelid='public.marker_submissions'::pg_catalog.regclass
            OR i.inhparent='public.marker_submissions'::pg_catalog.regclass) THEN
        RAISE EXCEPTION 'B5A_UNEXPECTED_RULE_OR_INHERITANCE';
    END IF;

    SELECT pg_catalog.to_jsonb(p)-'prosrc' INTO STRICT v_function_before FROM pg_catalog.pg_proc p WHERE p.oid=v_oid;
    SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid) INTO v_functions_before
        FROM pg_catalog.pg_proc p WHERE p.oid IN (
            pg_catalog.to_regprocedure('private.deepmap_capture_submission_revision()'),
            pg_catalog.to_regprocedure('private.deepmap_autoapprove_moderator_submission()'),
            pg_catalog.to_regprocedure('private.deepmap_notify_admin_submission_received()'),
            pg_catalog.to_regprocedure('private.deepmap_notify_submission_review()'),
            pg_catalog.to_regprocedure('private.deepmap_materialize_submission_content()'),
            pg_catalog.to_regprocedure('private.deepmap_replace_quick_marker_content(bigint,jsonb)'),
            pg_catalog.to_regprocedure('public.review_marker_submission(bigint,text,text)'),
            pg_catalog.to_regprocedure('public.review_marker_submission_v2(bigint,text,text,jsonb)'));
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(s) ORDER BY s.id),'[]'::jsonb)
        INTO v_rows_before FROM public.marker_submissions s;

    -- Catalog snapshot: no exclusions; no table/trigger/ACL/policy change permitted.
    SELECT pg_catalog.jsonb_build_object(
        'relation',(SELECT pg_catalog.to_jsonb(c) FROM pg_catalog.pg_class c WHERE c.oid='public.marker_submissions'::pg_catalog.regclass),
        'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attnum) FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.marker_submissions'::pg_catalog.regclass),
        'defaults',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.adnum) FROM pg_catalog.pg_attrdef d WHERE d.adrelid='public.marker_submissions'::pg_catalog.regclass),
        'constraints',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid) FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.marker_submissions'::pg_catalog.regclass),
        'indexes',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.indexrelid) FROM pg_catalog.pg_index i WHERE i.indrelid='public.marker_submissions'::pg_catalog.regclass),
        'triggers',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY t.oid) FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.marker_submissions'::pg_catalog.regclass),
        'policies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid) FROM pg_catalog.pg_policy p WHERE p.polrelid='public.marker_submissions'::pg_catalog.regclass)
    ) INTO v_catalog_before;

    v_new_body := pg_catalog.replace(v_expected,'begin'||pg_catalog.chr(10),'begin'||pg_catalog.chr(10)||v_guard);
    IF v_new_body=v_expected OR pg_catalog.strpos(v_new_body,v_guard)=0 THEN
        RAISE EXCEPTION 'B5A_BODY_TRANSFORMATION_FAILED';
    END IF;
    EXECUTE pg_catalog.format(
        'CREATE OR REPLACE FUNCTION private.deepmap_touch_submission_updated_at() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER VOLATILE PARALLEL UNSAFE CALLED ON NULL INPUT COST 100 SET search_path = %L AS %L',
        '',v_new_body);

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_oid
        AND pg_catalog.to_jsonb(p)-'prosrc'=v_function_before
        AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=v_new_body) THEN
        RAISE EXCEPTION 'B5A_FUNCTION_POSTCONDITION_FAILED';
    END IF;
    IF (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid) FROM pg_catalog.pg_proc p WHERE p.oid IN (
            pg_catalog.to_regprocedure('private.deepmap_capture_submission_revision()'),
            pg_catalog.to_regprocedure('private.deepmap_autoapprove_moderator_submission()'),
            pg_catalog.to_regprocedure('private.deepmap_notify_admin_submission_received()'),
            pg_catalog.to_regprocedure('private.deepmap_notify_submission_review()'),
            pg_catalog.to_regprocedure('private.deepmap_materialize_submission_content()'),
            pg_catalog.to_regprocedure('private.deepmap_replace_quick_marker_content(bigint,jsonb)'),
            pg_catalog.to_regprocedure('public.review_marker_submission(bigint,text,text)'),
            pg_catalog.to_regprocedure('public.review_marker_submission_v2(bigint,text,text,jsonb)'))) IS DISTINCT FROM v_functions_before THEN
        RAISE EXCEPTION 'B5A_SIDE_EFFECT_FUNCTION_CHANGED';
    END IF;
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(s) ORDER BY s.id),'[]'::jsonb)
        INTO v_rows_after FROM public.marker_submissions s;
    IF v_rows_after IS DISTINCT FROM v_rows_before THEN
        RAISE EXCEPTION 'B5A_SUBMISSION_ROWS_CHANGED';
    END IF;
    SELECT pg_catalog.jsonb_build_object(
        'relation',(SELECT pg_catalog.to_jsonb(c) FROM pg_catalog.pg_class c WHERE c.oid='public.marker_submissions'::pg_catalog.regclass),
        'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attnum) FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.marker_submissions'::pg_catalog.regclass),
        'defaults',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.adnum) FROM pg_catalog.pg_attrdef d WHERE d.adrelid='public.marker_submissions'::pg_catalog.regclass),
        'constraints',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid) FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.marker_submissions'::pg_catalog.regclass),
        'indexes',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.indexrelid) FROM pg_catalog.pg_index i WHERE i.indrelid='public.marker_submissions'::pg_catalog.regclass),
        'triggers',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY t.oid) FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.marker_submissions'::pg_catalog.regclass),
        'policies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid) FROM pg_catalog.pg_policy p WHERE p.polrelid='public.marker_submissions'::pg_catalog.regclass)
    ) INTO v_catalog_after;
    IF v_catalog_after IS DISTINCT FROM v_catalog_before THEN
        RAISE EXCEPTION 'B5A_SUBMISSION_SCHEMA_SECURITY_OR_TRIGGERS_CHANGED';
    END IF;
    -- No DML is issued and no trigger/RPC is invoked: adjacent rows are untouched
    -- by this migration. Full side-effect data snapshots belong to future B5 fill.
END;
$migration$;
COMMIT;
