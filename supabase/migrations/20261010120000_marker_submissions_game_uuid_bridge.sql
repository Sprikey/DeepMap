-- DeepMap B5b: permanent parallel game UUID identity, legacy writers preserved.
-- Manual review/application only. Requires B4b, B5a and sequence ACL hardening.
-- Marker coherence is declarative; neither new function reads markers.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = pg_catalog;

DO $dependencies$
BEGIN
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.games'),('private.game_legacy_identifiers'),('public.marcadores'),
        ('public.marker_submissions'),('private.marker_submission_revisions'),
        ('public.user_notifications'),('private.marker_editor_audit'),
        ('public.marker_images'),('public.marker_sections'),('public.marker_section_rows')) e(name)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
            WHERE c.oid=pg_catalog.to_regclass(e.name) AND c.relkind='r' AND c.relrowsecurity)) THEN
        RAISE EXCEPTION 'B5B_REQUIRES_ORDINARY_RLS_RELATIONS';
    END IF;
END;
$dependencies$;

-- Parent-first, once, retained to COMMIT. SHARE games stabilizes mapping's parent.
-- Mapping SHARE ROW EXCLUSIVE also satisfies ADD FK's referenced-table lock.
-- ACCESS EXCLUSIVE markers is needed for ADD UNIQUE; submissions for expand/FKs/
-- NOT NULL. Acquire final DDL modes now, avoiding later lock upgrades.
-- Side-effect SHARE locks stabilize exact snapshots against independent writers.
-- Reads pass except on DDL targets; 5s acquisition timeout aborts, never repairs.
LOCK TABLE public.games IN SHARE MODE;
LOCK TABLE private.game_legacy_identifiers IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.marcadores IN ACCESS EXCLUSIVE MODE;
LOCK TABLE public.marker_submissions IN ACCESS EXCLUSIVE MODE;
LOCK TABLE private.marker_editor_audit IN SHARE MODE;
LOCK TABLE public.marker_images IN SHARE MODE;
LOCK TABLE public.marker_sections IN SHARE MODE;
LOCK TABLE public.marker_section_rows IN SHARE MODE;
LOCK TABLE private.marker_submission_revisions IN SHARE MODE;
LOCK TABLE public.user_notifications IN SHARE MODE;

DO $bridge$
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
    v_oid oid;
    v_owner oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname=CURRENT_USER);
    v_service oid := pg_catalog.to_regrole('service_role');
    v_service_writer boolean := false;
    v_service_private_usage_added boolean := false;
    v_private_schema_before jsonb;
    v_private_schema_expected jsonb;
    v_private_acl_expected jsonb;
    v_private_acl_after jsonb;
    v_catalog_expected jsonb;
    v_rows bigint;
    v_affected bigint;
    v_before jsonb;
    v_after jsonb;
    v_data_before jsonb := '{}'::jsonb;
    v_data_after jsonb := '{}'::jsonb;
    v_data jsonb;
    v_relation text;
    v_name text;
    v_kind text;
    v_cols text[];
    v_target text;
    v_target_cols text[];
    v_delete text;
    v_schema text;
    v_table text;
    v_helper_before jsonb;
    v_resolver_before jsonb;
    v_relations regclass[] := ARRAY[
        'public.games'::pg_catalog.regclass,'private.game_legacy_identifiers'::pg_catalog.regclass,
        'public.marcadores'::pg_catalog.regclass,'public.marker_submissions'::pg_catalog.regclass,
        'private.marker_submission_revisions'::pg_catalog.regclass,'public.user_notifications'::pg_catalog.regclass,
        'private.marker_editor_audit'::pg_catalog.regclass,'public.marker_images'::pg_catalog.regclass,
        'public.marker_sections'::pg_catalog.regclass,'public.marker_section_rows'::pg_catalog.regclass];
    v_helper_body text := $expected_helper$
DECLARE
    v_game uuid;
BEGIN
    IF p_identifier IS NULL OR pg_catalog.btrim(p_identifier) = '' THEN
        RAISE EXCEPTION 'B5B_GAME_IDENTIFIER_REQUIRED';
    END IF;
    BEGIN
        SELECT i.game_id INTO STRICT v_game
        FROM private.game_legacy_identifiers AS i
        WHERE i.legacy_identifier = p_identifier;
    EXCEPTION
        WHEN no_data_found THEN RAISE EXCEPTION 'B5B_UNKNOWN_GAME_IDENTIFIER';
        WHEN too_many_rows THEN RAISE EXCEPTION 'B5B_AMBIGUOUS_GAME_IDENTIFIER';
    END;
    IF v_game IS NULL THEN RAISE EXCEPTION 'B5B_INVALID_GAME_MAPPING'; END IF;
    RETURN v_game;
END;
$expected_helper$;
    v_resolver_body text := $expected_resolver$
DECLARE
    v_game uuid;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.game_uuid IS NULL THEN
            IF (pg_catalog.to_jsonb(NEW) - 'game_uuid') IS DISTINCT FROM
               (pg_catalog.to_jsonb(OLD) - 'game_uuid') THEN
                RAISE EXCEPTION 'B5B_HYDRATION_MUST_PRESERVE_ALL_LEGACY_FIELDS';
            END IF;
            v_game := private.deepmap_game_uuid_from_legacy_identifier(OLD.game_id);
            IF NEW.game_uuid IS DISTINCT FROM v_game THEN
                RAISE EXCEPTION 'B5B_HYDRATION_REQUIRES_EXACT_GAME_UUID';
            END IF;
            RETURN NEW;
        END IF;
        IF NEW.game_id IS DISTINCT FROM OLD.game_id OR
           NEW.game_uuid IS DISTINCT FROM OLD.game_uuid THEN
            RAISE EXCEPTION 'B5B_SUBMISSION_GAME_IDENTITY_IS_IMMUTABLE';
        END IF;
    ELSIF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'B5B_UNSUPPORTED_SUBMISSION_TRIGGER_EVENT';
    END IF;
    v_game := private.deepmap_game_uuid_from_legacy_identifier(NEW.game_id);
    IF NEW.game_uuid IS NULL THEN
        NEW.game_uuid := v_game;
    ELSIF NEW.game_uuid IS DISTINCT FROM v_game THEN
        RAISE EXCEPTION 'B5B_SUBMISSION_GAME_MAPPING_MISMATCH';
    END IF;
    -- marker_id remains mutable. Declarative FKs enforce coherence without RLS reads.
    RETURN NEW;
END;
$expected_resolver$;
    v_marker_body text := $expected_marker$
    DECLARE
        v_game uuid;
        v_layer uuid;
        v_layer_game uuid;
        v_layer_changed boolean := false;
    BEGIN
        IF TG_OP='UPDATE' THEN
            IF OLD.game_uuid IS NULL AND OLD.layer_uuid IS NULL THEN
                IF (pg_catalog.to_jsonb(NEW)-ARRAY['game_uuid','layer_uuid']::text[])
                   IS DISTINCT FROM (pg_catalog.to_jsonb(OLD)-ARRAY['game_uuid','layer_uuid']::text[]) THEN
                    RAISE EXCEPTION 'B4B_HYDRATION_MUST_PRESERVE_LEGACY_FIELDS';
                END IF;
            ELSIF OLD.game_uuid IS NULL OR OLD.layer_uuid IS NULL THEN
                RAISE EXCEPTION 'B4B_PARTIAL_MARKER_IDENTITY';
            ELSE
                IF NEW.game_id IS DISTINCT FROM OLD.game_id OR NEW.game_uuid IS DISTINCT FROM OLD.game_uuid THEN
                    RAISE EXCEPTION 'B4B_MARKER_GAME_REASSIGNMENT_NOT_SUPPORTED';
                END IF;
                v_layer_changed := NEW.map_layer IS DISTINCT FROM OLD.map_layer;
                IF NOT v_layer_changed AND NEW.layer_uuid IS DISTINCT FROM OLD.layer_uuid THEN
                    RAISE EXCEPTION 'B4B_UUID_ONLY_LAYER_CHANGE_NOT_SUPPORTED';
                END IF;
            END IF;
        ELSIF TG_OP<>'INSERT' THEN
            RAISE EXCEPTION 'B4B_UNSUPPORTED_MARKER_TRIGGER_EVENT';
        END IF;
        BEGIN
            SELECT i.game_id INTO STRICT v_game FROM private.game_legacy_identifiers i
                WHERE i.legacy_identifier=NEW.game_id;
        EXCEPTION WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B4B_MARKER_MAPPING_NOT_EXACTLY_ONE_VISIBLE_ROW';
        END;
        BEGIN
            SELECT l.layer_uuid,l.game_uuid INTO STRICT v_layer,v_layer_game
                FROM public.map_layers l WHERE l.game_id=NEW.game_id AND l.id=NEW.map_layer;
        EXCEPTION WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B4B_MARKER_LAYER_NOT_EXACTLY_ONE_VISIBLE_ROW';
        END;
        IF v_layer IS NULL OR v_layer_game IS DISTINCT FROM v_game THEN
            RAISE EXCEPTION 'B4B_MARKER_LAYER_GAME_MAPPING_MISMATCH';
        END IF;
        IF NEW.game_uuid IS NULL THEN NEW.game_uuid := v_game;
        ELSIF NEW.game_uuid IS DISTINCT FROM v_game THEN
            RAISE EXCEPTION 'B4B_MARKER_LEGACY_GAME_UUID_MISMATCH';
        END IF;
        IF v_layer_changed THEN
            IF NEW.layer_uuid IS NOT NULL AND NEW.layer_uuid IS DISTINCT FROM OLD.layer_uuid
               AND NEW.layer_uuid IS DISTINCT FROM v_layer THEN
                RAISE EXCEPTION 'B4B_MARKER_EXPLICIT_NEW_LAYER_UUID_MISMATCH';
            END IF;
            NEW.layer_uuid := v_layer;
        ELSIF NEW.layer_uuid IS NULL THEN NEW.layer_uuid := v_layer;
        ELSIF NEW.layer_uuid IS DISTINCT FROM v_layer THEN
            RAISE EXCEPTION 'B4B_MARKER_LEGACY_LAYER_UUID_MISMATCH';
        END IF;
        RETURN NEW;
    END;
    $expected_marker$;
    v_snapshot_sql text := $snapshot$
        WITH relations AS (SELECT pg_catalog.unnest($1::pg_catalog.regclass[]) AS oid),
        additions AS (SELECT c.oid,c.conindid,c.contype FROM pg_catalog.pg_constraint c WHERE
            (c.conrelid='public.marcadores'::pg_catalog.regclass AND c.conname='marcadores_id_game_identity_unique') OR
            (c.conrelid='public.marker_submissions'::pg_catalog.regclass AND c.conname IN
                ('marker_submissions_legacy_game_uuid_fk','marker_submissions_marker_game_uuid_fk')))
        SELECT pg_catalog.jsonb_build_object(
            'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attrelid,a.attnum)
                FROM pg_catalog.pg_attribute a WHERE a.attrelid IN (SELECT oid FROM relations) AND a.attnum>0
                  AND NOT (a.attrelid='public.marker_submissions'::pg_catalog.regclass AND a.attname='game_uuid')),
            'defaults',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.adrelid,d.adnum)
                FROM pg_catalog.pg_attrdef d WHERE d.adrelid IN (SELECT oid FROM relations)),
            'constraints',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid)
                FROM pg_catalog.pg_constraint c WHERE c.conrelid IN (SELECT oid FROM relations)
                  AND c.oid NOT IN (SELECT oid FROM additions)
                  AND NOT (c.conrelid='public.marker_submissions'::pg_catalog.regclass AND c.contype='n'
                    AND c.conkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a
                        WHERE a.attrelid=c.conrelid AND a.attname='game_uuid' AND NOT a.attisdropped)]::smallint[])),
            'indexes',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.indexrelid)
                FROM pg_catalog.pg_index i WHERE i.indrelid IN (SELECT oid FROM relations)
                  AND i.indexrelid NOT IN (SELECT conindid FROM additions WHERE contype='u')),
            'triggers',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY t.oid)
                FROM pg_catalog.pg_trigger t WHERE t.tgrelid IN (SELECT oid FROM relations)
                  AND NOT (t.tgrelid='public.marker_submissions'::pg_catalog.regclass AND t.tgname='deepmap_marker_submissions_identity')
                  AND NOT (t.tgisinternal AND t.tgconstraint IN (SELECT oid FROM additions))),
            'policies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid)
                FROM pg_catalog.pg_policy p WHERE p.polrelid IN (SELECT oid FROM relations)),
            'security',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('oid',c.oid,'owner',c.relowner,
                'acl',c.relacl,'rls',c.relrowsecurity,'force',c.relforcerowsecurity) ORDER BY c.oid)
                FROM pg_catalog.pg_class c WHERE c.oid IN (SELECT oid FROM relations)),
            'namespaces',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(n) ORDER BY n.oid)
                FROM pg_catalog.pg_namespace n WHERE n.nspname IN ('public','private')),
            'functions',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid)
                FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
                WHERE n.nspname IN ('private','public') AND NOT (n.nspname='private' AND p.proname IN
                    ('deepmap_game_uuid_from_legacy_identifier','deepmap_resolve_submission_identity'))),
            'sequence_class',(SELECT pg_catalog.to_jsonb(c) FROM pg_catalog.pg_class c
                WHERE c.oid='public.marker_submissions_id_seq'::pg_catalog.regclass),
            'sequence_config',(SELECT pg_catalog.to_jsonb(s) FROM pg_catalog.pg_sequence s
                WHERE s.seqrelid='public.marker_submissions_id_seq'::pg_catalog.regclass),
            'sequence_dependencies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d)
                ORDER BY d.classid,d.objid,d.objsubid,d.refclassid,d.refobjid,d.refobjsubid,d.deptype)
                FROM pg_catalog.pg_depend d WHERE (d.classid='pg_catalog.pg_class'::pg_catalog.regclass
                    AND d.objid='public.marker_submissions_id_seq'::pg_catalog.regclass)
                  OR (d.refclassid='pg_catalog.pg_class'::pg_catalog.regclass
                    AND d.refobjid='public.marker_submissions_id_seq'::pg_catalog.regclass))
        )
$snapshot$;
BEGIN
    -- Exact B5a final body reconstructed from its legacy body and approved guard.
    v_expected := pg_catalog.replace(v_expected,'begin'||pg_catalog.chr(10),
        'begin'||pg_catalog.chr(10)||v_guard);
    IF v_owner IS NULL OR pg_catalog.to_regrole('authenticated') IS NULL
       OR pg_catalog.to_regrole('anon') IS NULL THEN RAISE EXCEPTION 'B5B_REQUIRED_ROLE_MISSING'; END IF;
    -- Creator is the actual helper owner, never an invented role. Untrusted roles
    -- cannot inherit it or CREATE/replace functions in private.
    IF v_owner IN (pg_catalog.to_regrole('anon'),pg_catalog.to_regrole('authenticated'),v_service)
       OR pg_catalog.pg_has_role('anon',v_owner,'MEMBER')
       OR pg_catalog.pg_has_role('authenticated',v_owner,'MEMBER')
       OR pg_catalog.has_schema_privilege('anon','private','CREATE')
       OR pg_catalog.has_schema_privilege('authenticated','private','CREATE')
       OR NOT pg_catalog.has_schema_privilege('private','CREATE') THEN
        RAISE EXCEPTION 'B5B_UNTRUSTED_HELPER_CREATOR_OR_PRIVATE_SCHEMA';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.oid=v_owner
        WHERE c.oid=ANY(v_relations) AND (NOT pg_catalog.has_table_privilege(c.oid,'SELECT')
            OR NOT pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
            OR NOT (r.rolsuper OR r.rolbypassrls OR (r.oid=c.relowner AND NOT c.relforcerowsecurity)))) THEN
        RAISE EXCEPTION 'B5B_FULL_MAINTENANCE_VISIBILITY_REQUIRED';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.oid=v_owner
        WHERE c.oid IN ('public.marcadores'::pg_catalog.regclass,'public.marker_submissions'::pg_catalog.regclass)
          AND NOT (r.rolsuper OR pg_catalog.pg_has_role(r.oid,c.relowner,'USAGE'))) THEN
        RAISE EXCEPTION 'B5B_EFFECTIVE_DDL_OWNERSHIP_REQUIRED';
    END IF;
    IF NOT pg_catalog.has_schema_privilege('authenticated','private','USAGE') THEN
        RAISE EXCEPTION 'B5B_AUTHENTICATED_PRIVATE_USAGE_REQUIRED';
    END IF;
    IF NOT pg_catalog.has_table_privilege('authenticated','private.game_legacy_identifiers','SELECT')
       OR (SELECT count(*) FROM pg_catalog.pg_policy WHERE polrelid='private.game_legacy_identifiers'::pg_catalog.regclass)<>2
       OR EXISTS (SELECT 1 FROM (VALUES
            ('game_legacy_identifiers_admin_read','r'),('game_legacy_identifiers_admin_insert','a')) e(name,command)
            WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p
                WHERE p.polrelid='private.game_legacy_identifiers'::pg_catalog.regclass AND p.polname=e.name
                  AND p.polcmd::text=e.command AND p.polpermissive
                  AND p.polroles=ARRAY[('authenticated'::pg_catalog.regrole)::oid]
                  AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(
                    CASE WHEN e.command='r' THEN p.polqual ELSE p.polwithcheck END,p.polrelid),'[[:space:]()]','','g') IN
                    ('SELECTpublic.get_deepmap_roleASget_deepmap_role=''admin''::text',
                     'SELECTget_deepmap_roleASget_deepmap_role=''admin''::text'))) THEN
        RAISE EXCEPTION 'B5B_MAPPING_ADMIN_ONLY_POLICY_CONTRACT_REQUIRED';
    END IF;
    -- Earlier bridges must be present, not inferred solely from the handoff.
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.map_layers','game_uuid','uuid'),('public.map_layers','layer_uuid','uuid'),
        ('public.map_layers','game_map_id','uuid'),('public.marker_category_groups','game_uuid','uuid'),
        ('public.marker_categories','game_uuid','uuid'),('public.map_labels','game_uuid','uuid'),
        ('public.map_labels','layer_uuid','uuid'),('private.game_legacy_identifiers','legacy_identifier','text'),
        ('private.game_legacy_identifiers','game_id','uuid'),('public.games','id','uuid')) e(rel,name,type_name)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
            WHERE a.attrelid=pg_catalog.to_regclass(e.rel) AND a.attname=e.name AND a.attnum>0
              AND NOT a.attisdropped AND a.attnotnull AND a.atttypid=pg_catalog.to_regtype(e.type_name)
              AND a.attidentity='' AND a.attgenerated=''))
       OR EXISTS (SELECT 1 FROM (VALUES
        ('public.map_layers','deepmap_map_layers_identity','private.deepmap_resolve_layer_identity()'),
        ('public.marker_category_groups','deepmap_category_groups_identity','private.deepmap_resolve_category_group_identity()'),
        ('public.marker_categories','deepmap_categories_identity','private.deepmap_resolve_category_identity()'),
        ('public.map_labels','deepmap_map_labels_identity','private.deepmap_resolve_map_label_identity()')) e(rel,name,signature)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
            WHERE t.tgrelid=pg_catalog.to_regclass(e.rel) AND t.tgname=e.name AND t.tgfoid=pg_catalog.to_regprocedure(e.signature)
              AND t.tgtype=23 AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgnargs=0
              AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL AND NOT p.prosecdef
              AND p.proconfig=ARRAY['search_path=""']::text[])) THEN
        RAISE EXCEPTION 'B5B_EARLIER_PHASE_BRIDGE_DEPENDENCY_MISSING';
    END IF;
    IF v_service IS NOT NULL THEN
        v_service_writer := pg_catalog.has_any_column_privilege(v_service,'public.marker_submissions','INSERT')
            OR pg_catalog.has_any_column_privilege(v_service,'public.marker_submissions','UPDATE');
        IF pg_catalog.has_schema_privilege(v_service,'private','CREATE') THEN
            RAISE EXCEPTION 'B5B_SERVICE_PRIVATE_CREATE_FORBIDDEN';
        END IF;
        IF v_service_writer AND NOT pg_catalog.has_schema_privilege(v_service,'private','USAGE')
           AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_namespace n
               JOIN pg_catalog.pg_roles r ON r.oid=v_owner WHERE n.nspname='private'
               AND (r.rolsuper OR pg_catalog.pg_has_role(r.oid,n.nspowner,'USAGE'))) THEN
            RAISE EXCEPTION 'B5B_SERVICE_PRIVATE_USAGE_GRANT_AUTHORITY_REQUIRED';
        END IF;
    END IF;
    -- Keep the precise legacy writable-column contract; a table-wide grant would
    -- silently confer write access to the new column and must abort before expand.
    IF pg_catalog.has_table_privilege('authenticated','public.marker_submissions','INSERT')
       OR pg_catalog.has_table_privilege('authenticated','public.marker_submissions','UPDATE')
       OR NOT pg_catalog.has_table_privilege('authenticated','public.marker_submissions','SELECT')
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
            WHERE a.attrelid='public.marker_submissions'::pg_catalog.regclass AND a.attnum>0 AND NOT a.attisdropped
              AND (pg_catalog.has_column_privilege('authenticated',a.attrelid,a.attnum,'INSERT')
                    IS DISTINCT FROM (a.attname=ANY(ARRAY['game_id','marker_id','submission_type','correction_kind','status','submitted_by','payload','note']))
                OR pg_catalog.has_column_privilege('authenticated',a.attrelid,a.attnum,'UPDATE')
                    IS DISTINCT FROM (a.attname=ANY(ARRAY['payload','note','correction_kind'])))) THEN
        RAISE EXCEPTION 'B5B_LEGACY_AUTHENTICATED_COLUMN_GRANT_DRIFT';
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
        RAISE EXCEPTION 'B5B_SUBMISSION_COLUMN_CONTRACT_DRIFT';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid='public.marker_submissions'::pg_catalog.regclass AND a.attnum>0 AND NOT a.attisdropped
          AND a.attname IN ('game_uuid','layer_uuid','category_uuid','group_uuid','game_map_id'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='private' AND p.proname='deepmap_resolve_submission_identity') THEN
        RAISE EXCEPTION 'B5B_PARTIAL_BRIDGE_OR_UNEXPECTED_UUID_STATE';
    END IF;
    IF EXISTS (SELECT 1 FROM (VALUES ('game_uuid'),('layer_uuid')) e(name)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
            WHERE a.attrelid=pg_catalog.to_regclass('public.marcadores') AND a.attname=e.name
              AND a.attnum>0 AND NOT a.attisdropped AND a.atttypid='uuid'::pg_catalog.regtype AND a.attnotnull))
       OR pg_catalog.to_regprocedure('private.deepmap_resolve_marker_identity()') IS NULL
       OR (SELECT count(*) FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass('public.marcadores')
            AND c.conname IN ('marcadores_legacy_game_uuid_fk','marcadores_legacy_uuid_layer_fk')
            AND c.contype='f' AND c.convalidated AND NOT c.condeferrable)<>2 THEN
        RAISE EXCEPTION 'B5B_B4B_DEPENDENCY_MISSING';
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
        RAISE EXCEPTION 'B5B_TOUCH_BODY_OR_ATTRIBUTES_DRIFT';
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
        RAISE EXCEPTION 'B5B_SUBMISSION_TRIGGER_CONTRACT_DRIFT';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgfoid=v_oid AND NOT tgisinternal)<>1
       OR EXISTS (SELECT 1 FROM (VALUES
           ('private.deepmap_replace_quick_marker_content(bigint,jsonb)'),
           ('public.review_marker_submission(bigint,text,text)'),
           ('public.review_marker_submission_v2(bigint,text,text,jsonb)')) e(signature)
           WHERE pg_catalog.to_regprocedure(e.signature) IS NULL) THEN
        RAISE EXCEPTION 'B5B_UNKNOWN_TOUCH_USAGE_OR_MISSING_REVIEW_CONTRACT';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_rewrite r
        WHERE r.ev_class='public.marker_submissions'::pg_catalog.regclass)
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_inherits i WHERE i.inhrelid='public.marker_submissions'::pg_catalog.regclass
            OR i.inhparent='public.marker_submissions'::pg_catalog.regclass) THEN
        RAISE EXCEPTION 'B5B_UNEXPECTED_RULE_OR_INHERITANCE';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname IN ('private','public') AND p.proname IN
            ('deepmap_game_uuid_from_legacy_identifier','deepmap_resolve_submission_identity'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE
            (conrelid='public.marcadores'::pg_catalog.regclass AND conname='marcadores_id_game_identity_unique') OR
            (conrelid='public.marker_submissions'::pg_catalog.regclass AND conname IN
                ('marker_submissions_legacy_game_uuid_fk','marker_submissions_marker_game_uuid_fk')))
       OR pg_catalog.to_regclass('public.marcadores_id_game_identity_unique') IS NOT NULL THEN
        RAISE EXCEPTION 'B5B_PARTIAL_STATE_REQUIRES_HUMAN_REVIEW';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid IN
        ('private.marker_submission_revisions'::pg_catalog.regclass,'public.user_notifications'::pg_catalog.regclass)
        AND a.attnum>0 AND NOT a.attisdropped AND a.attname IN
            ('game_uuid','layer_uuid','category_uuid','group_uuid','game_map_id')) THEN
        RAISE EXCEPTION 'B5B_UNEXPECTED_RELATED_UUID_SCOPE';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_marker_identity()')
          AND p.pronargs=0 AND p.prorettype='trigger'::pg_catalog.regtype AND NOT p.prosecdef
          AND l.lanname='plpgsql' AND p.proconfig=ARRAY['search_path=""']::text[]
          AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=
              pg_catalog.replace(v_marker_body,pg_catalog.chr(13),''))
       OR (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='private' AND p.proname='deepmap_resolve_marker_identity')<>1
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.marcadores'::pg_catalog.regclass
            AND t.tgname='deepmap_marcadores_identity' AND t.tgfoid=pg_catalog.to_regprocedure('private.deepmap_resolve_marker_identity()')
            AND t.tgtype=23 AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgnargs=0
            AND t.tgqual IS NULL AND t.tgattr=''::pg_catalog.int2vector)
       OR EXISTS (SELECT 1 FROM (VALUES ('id','bigint'),('game_id','text'),('game_uuid','uuid')) e(name,type_name)
            WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
                WHERE a.attrelid='public.marcadores'::pg_catalog.regclass AND a.attname=e.name
                  AND a.attnum>0 AND NOT a.attisdropped AND a.attnotnull AND a.atttypid=pg_catalog.to_regtype(e.type_name))) THEN
        RAISE EXCEPTION 'B5B_B4B_MARKER_IDENTITY_CONTRACT_DRIFT';
    END IF;
    -- B4a audit plus legacy side-effect/review body digests detect baseline drift;
    -- full pg_proc equality below
    -- additionally proves no legacy body/owner/ACL/attribute changed in migration.
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.cancel_marker_submission(bigint)','32db8c8d8de026e6ef2220c752544a06'),
        ('private.deepmap_stamp_marker_audit()','233b6905e98f7b74ca01068488bb57c0'),
        ('private.deepmap_capture_submission_revision()','d3ff5f69ceb1cd15cf09cf72b26f55ce'),
        ('private.deepmap_autoapprove_moderator_submission()','9c7c5a38258ea603f205fcddb5b48861'),
        ('private.deepmap_notify_admin_submission_received()','c0ec4567cd4efa473e393a5e1e3f6016'),
        ('private.deepmap_notify_submission_review()','a423d83f1c880b7fcb81217d99e8c96d'),
        ('private.deepmap_materialize_submission_content()','09fdd39ed4b0565d21b1f51e6494c4eb'),
        ('private.deepmap_replace_quick_marker_content(bigint,jsonb)','74c611df1824cd9e78d76b98ca6f9920'),
        ('public.review_marker_submission(bigint,text,text)','c2d611f6339f023f3c2b43891f56af29'),
        ('public.review_marker_submission_v2(bigint,text,text,jsonb)','10327cfdf171ec2e3ba17380a909d644')
    ) e(signature,body_digest) WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid=pg_catalog.to_regprocedure(e.signature) AND p.prosecdef
          AND p.proconfig=ARRAY['search_path=""']::text[]
          AND pg_catalog.md5(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),''))=e.body_digest)) THEN
        RAISE EXCEPTION 'B5B_LEGACY_SIDE_EFFECT_OR_REVIEW_BODY_DRIFT';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid IN (
        pg_catalog.to_regprocedure('public.review_marker_submission(bigint,text,text)'),
        pg_catalog.to_regprocedure('public.review_marker_submission_v2(bigint,text,text,jsonb)'),
        pg_catalog.to_regprocedure('private.deepmap_autoapprove_moderator_submission()'),
        pg_catalog.to_regprocedure('public.cancel_marker_submission(bigint)'))
        AND (NOT pg_catalog.has_schema_privilege(p.proowner,'private','USAGE') OR NOT (
            pg_catalog.pg_has_role(p.proowner,v_owner,'USAGE')
            OR pg_catalog.pg_has_role(p.proowner,'authenticated','USAGE')
            OR (v_service_writer AND pg_catalog.pg_has_role(p.proowner,v_service,'USAGE'))))) THEN
        RAISE EXCEPTION 'B5B_EXISTING_DEFINER_WRITER_OWNER_CANNOT_CALL_LOOKUP';
    END IF;
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.cancel_marker_submission(bigint)'),('public.get_marker_submissions(text,text)'),
        ('public.get_my_marker_submissions_page(text,integer,integer)'),
        ('public.get_marker_submissions_page(text,text,integer,integer)')) e(signature)
        WHERE pg_catalog.to_regprocedure(e.signature) IS NULL) THEN
        RAISE EXCEPTION 'B5B_LEGACY_RPC_DEPENDENCY_MISSING';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_constraint WHERE conrelid='public.marker_submissions'::pg_catalog.regclass
        AND contype='c')<>4 OR EXISTS (SELECT 1 FROM (VALUES
        ('marker_submissions_submission_type_check', $check$submission_type=ANYARRAY['create'::text,'correction'::text]$check$),
        ('marker_submissions_correction_kind_check', $check$correction_kindISNULLORcorrection_kind=ANYARRAY['text'::text,'location'::text,'image'::text,'other'::text]$check$),
        ('marker_submissions_status_check', $check$status=ANYARRAY['pending'::text,'approved'::text,'rejected'::text,'cancelled'::text]$check$),
        ('marker_submissions_target_required', $check$submission_type<>'correction'::textORmarker_idISNOTNULL$check$)
    ) e(name,expr) WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.marker_submissions'::pg_catalog.regclass AND c.conname=e.name AND c.contype='c'
          AND c.convalidated AND NOT c.condeferrable
          AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(c.conbin,c.conrelid),'[[:space:]()]','','g')=e.expr))
       OR (SELECT count(*) FROM pg_catalog.pg_constraint WHERE conrelid='public.marker_submissions'::pg_catalog.regclass
            AND contype='f')<>1 THEN
        RAISE EXCEPTION 'B5B_LEGACY_CHECK_OR_FK_CONTRACT_DRIFT';
    END IF;
    -- Validated immediate real keys with complete, non-partial backing indexes.
    FOR v_relation,v_name,v_kind,v_cols IN SELECT * FROM (VALUES
        ('public.games','games_pkey','p',ARRAY['id']::text[]),
        ('public.marker_submissions','marker_submissions_pkey','p',ARRAY['id']::text[]),
        ('public.marcadores','marcadores_pkey','p',ARRAY['id']::text[]),
        ('private.game_legacy_identifiers','game_legacy_identifiers_identifier_unique','u',ARRAY['legacy_identifier']::text[]),
        ('private.game_legacy_identifiers','game_legacy_identifiers_identifier_game_unique','u',ARRAY['legacy_identifier','game_id']::text[])
    ) e(rel,name,kind,cols) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
            WHERE c.conrelid=pg_catalog.to_regclass(v_relation) AND c.conname=v_name AND c.contype::text=v_kind
              AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
              AND i.indisunique AND i.indimmediate AND i.indisvalid AND i.indisready AND i.indislive
              AND i.indpred IS NULL AND i.indexprs IS NULL
              AND i.indnkeyatts=pg_catalog.cardinality(v_cols) AND i.indnatts=i.indnkeyatts
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos)
                  JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=v_cols) THEN
            RAISE EXCEPTION 'B5B_REQUIRED_KEY_DRIFT: %.%',v_relation,v_name;
        END IF;
    END LOOP;
    FOR v_relation,v_name,v_cols,v_target,v_target_cols,v_delete IN SELECT * FROM (VALUES
        ('public.marker_submissions','marker_submissions_marker_id_fkey',ARRAY['marker_id']::text[],
            'public.marcadores',ARRAY['id']::text[],'c'),
        ('private.game_legacy_identifiers','game_legacy_identifiers_game_id_fkey',ARRAY['game_id']::text[],
            'public.games',ARRAY['id']::text[],'r'),
        ('public.marcadores','marcadores_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
            'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[],'r'),
        ('public.marcadores','marcadores_legacy_uuid_layer_fk',ARRAY['game_id','map_layer','game_uuid','layer_uuid']::text[],
            'public.map_layers',ARRAY['game_id','id','game_uuid','layer_uuid']::text[],'r'),
        ('public.map_layers','map_layers_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
            'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[],'r'),
        ('public.map_layers','map_layers_game_map_game_fk',ARRAY['game_map_id','game_uuid']::text[],
            'public.game_maps',ARRAY['id','game_id']::text[],'r'),
        ('public.game_maps','game_maps_game_id_fkey',ARRAY['game_id']::text[],
            'public.games',ARRAY['id']::text[],'r'),
        ('public.marker_category_groups','marker_category_groups_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
            'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[],'r'),
        ('public.marker_categories','marker_categories_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
            'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[],'r'),
        ('public.map_labels','map_labels_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
            'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[],'r'),
        ('public.map_labels','map_labels_legacy_uuid_layer_fk',ARRAY['game_id','map_layer','game_uuid','layer_uuid']::text[],
            'public.map_layers',ARRAY['game_id','id','game_uuid','layer_uuid']::text[],'r')
    ) e(rel,name,cols,target,target_cols,del) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            WHERE c.conrelid=pg_catalog.to_regclass(v_relation) AND c.conname=v_name AND c.contype='f'
              AND c.confrelid=pg_catalog.to_regclass(v_target) AND c.convalidated
              AND NOT c.condeferrable AND NOT c.condeferred AND c.confmatchtype='s'
              AND c.confupdtype='a' AND c.confdeltype::text=v_delete
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos)
                  JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=v_cols
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num,pos)
                  JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)=v_target_cols) THEN
            RAISE EXCEPTION 'B5B_REQUIRED_FK_DRIFT: %.%',v_relation,v_name;
        END IF;
    END LOOP;
    -- Five legacy indexes, including the usable marker_id-prefix partial index.
    IF (SELECT count(*) FROM pg_catalog.pg_index WHERE indrelid='public.marker_submissions'::pg_catalog.regclass)<>5
       OR EXISTS (SELECT 1 FROM (VALUES
        ('marker_submissions_pkey',true,ARRAY['id']::text[],NULL::text),
        ('marker_submissions_game_status_idx',false,ARRAY['game_id','status','created_at']::text[],NULL),
        ('marker_submissions_user_status_idx',false,ARRAY['submitted_by','status','created_at']::text[],NULL),
        ('marker_submissions_marker_idx',false,ARRAY['marker_id','created_at']::text[],'marker_idISNOTNULL'),
        ('marker_submissions_one_pending_correction_per_marker_idx',true,ARRAY['game_id','marker_id','submitted_by']::text[],
            $predicate$status='pending'::textANDsubmission_type='correction'::textANDmarker_idISNOTNULL$predicate$)
    ) e(name,is_unique,cols,predicate) WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index i
        JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid
        WHERE i.indrelid='public.marker_submissions'::pg_catalog.regclass AND c.relname=e.name
          AND i.indisunique=e.is_unique AND i.indisvalid AND i.indisready AND i.indislive
          AND i.indexprs IS NULL AND i.indnkeyatts=pg_catalog.cardinality(e.cols) AND i.indnatts=i.indnkeyatts
          AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(i.indkey::smallint[]) WITH ORDINALITY k(num,pos)
              JOIN pg_catalog.pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.num ORDER BY k.pos)=e.cols
          AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(i.indpred,i.indrelid),'[[:space:]()]','','g')
              IS NOT DISTINCT FROM e.predicate)) THEN RAISE EXCEPTION 'B5B_LEGACY_INDEX_DRIFT'; END IF;
    IF v_service IS NULL OR pg_catalog.to_regclass(pg_catalog.pg_get_serial_sequence('public.marker_submissions','id'))
        IS DISTINCT FROM pg_catalog.to_regclass('public.marker_submissions_id_seq')
       OR pg_catalog.has_sequence_privilege('anon','public.marker_submissions_id_seq','USAGE')
       OR pg_catalog.has_sequence_privilege('anon','public.marker_submissions_id_seq','SELECT')
       OR pg_catalog.has_sequence_privilege('anon','public.marker_submissions_id_seq','UPDATE')
       OR NOT pg_catalog.has_sequence_privilege('authenticated','public.marker_submissions_id_seq','USAGE')
       OR NOT pg_catalog.has_sequence_privilege('authenticated','public.marker_submissions_id_seq','SELECT')
       OR pg_catalog.has_sequence_privilege('authenticated','public.marker_submissions_id_seq','UPDATE')
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c CROSS JOIN LATERAL pg_catalog.aclexplode(
            COALESCE(c.relacl,pg_catalog.acldefault('s',c.relowner))) a
            WHERE c.oid='public.marker_submissions_id_seq'::pg_catalog.regclass AND a.grantee=0) THEN
        RAISE EXCEPTION 'B5B_SEQUENCE_HARDENING_REQUIRED';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_depend d WHERE d.classid='pg_catalog.pg_class'::pg_catalog.regclass
        AND d.objid='public.marker_submissions_id_seq'::pg_catalog.regclass AND d.deptype='i')<>1
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_depend d
        WHERE d.classid='pg_catalog.pg_class'::pg_catalog.regclass AND d.objid='public.marker_submissions_id_seq'::pg_catalog.regclass
          AND d.objsubid=0 AND d.refclassid='pg_catalog.pg_class'::pg_catalog.regclass
          AND d.refobjid='public.marker_submissions'::pg_catalog.regclass
          AND d.refobjsubid=(SELECT attnum FROM pg_catalog.pg_attribute
            WHERE attrelid='public.marker_submissions'::pg_catalog.regclass AND attname='id' AND NOT attisdropped)
          AND d.deptype='i') THEN RAISE EXCEPTION 'B5B_SEQUENCE_IDENTITY_DEPENDENCY_DRIFT'; END IF;
    -- Full-maintenance data validation, before hydration or any new constraint.
    IF EXISTS (SELECT 1 FROM public.marker_submissions s
        WHERE (SELECT count(*) FROM private.game_legacy_identifiers i WHERE i.legacy_identifier=s.game_id)<>1
          OR (SELECT count(*) FROM private.game_legacy_identifiers i JOIN public.games g ON g.id=i.game_id
              WHERE i.legacy_identifier=s.game_id)<>1
          OR (s.marker_id IS NOT NULL AND (SELECT count(*) FROM public.marcadores m
              JOIN private.game_legacy_identifiers i ON i.legacy_identifier=s.game_id
              WHERE m.id=s.marker_id AND m.game_id=s.game_id AND m.game_uuid=i.game_id)<>1))
       OR EXISTS (SELECT 1 FROM public.marcadores GROUP BY id,game_id,game_uuid HAVING count(*)>1) THEN
        RAISE EXCEPTION 'B5B_EXISTING_MAPPING_OR_MARKER_INCONSISTENCY';
    END IF;
    SELECT count(*) INTO v_rows FROM public.marker_submissions;
    EXECUTE v_snapshot_sql INTO v_before USING v_relations;
    -- Fixed qualified allow-list, never user input. JSONB arrays preserve duplicates
    -- and compare complete row multisets; no permanent snapshot objects created.
    FOREACH v_relation IN ARRAY ARRAY['public.games','private.game_legacy_identifiers','public.marcadores',
        'public.marker_submissions','private.marker_submission_revisions','public.user_notifications',
        'private.marker_editor_audit','public.marker_images','public.marker_sections','public.marker_section_rows'] LOOP
        v_schema := pg_catalog.split_part(v_relation,'.',1);
        v_table := pg_catalog.split_part(v_relation,'.',2);
        EXECUTE pg_catalog.format('SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY pg_catalog.to_jsonb(t)),''[]''::jsonb) FROM %I.%I t',v_schema,v_table)
            INTO v_data;
        v_data_before := v_data_before || pg_catalog.jsonb_build_object(v_relation,v_data);
    END LOOP;

    -- First persistent mutations: every baseline/data/authorization check passed.
    v_catalog_expected := v_before;
    IF v_service_writer AND NOT pg_catalog.has_schema_privilege(v_service,'private','USAGE') THEN
        SELECT pg_catalog.to_jsonb(n) INTO STRICT v_private_schema_before
            FROM pg_catalog.pg_namespace n WHERE n.nspname='private';
        IF v_private_schema_before IS DISTINCT FROM (SELECT n
            FROM pg_catalog.jsonb_array_elements(v_before->'namespaces') n WHERE n->>'nspname'='private') THEN
            RAISE EXCEPTION 'B5B_PRIVATE_SCHEMA_CHANGED_SINCE_SNAPSHOT';
        END IF;
        -- Preserve every ACL record, including its grantor and grant option. The
        -- sole addition must be owner-granted, non-grantable service_role USAGE.
        SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)
            ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable)
            INTO v_private_acl_expected FROM (
                SELECT x.* FROM pg_catalog.pg_namespace n
                CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(n.nspacl,pg_catalog.acldefault('n',n.nspowner))) x
                WHERE n.nspname='private'
                UNION ALL SELECT n.nspowner,v_service,'USAGE'::text,false
                    FROM pg_catalog.pg_namespace n WHERE n.nspname='private'
            ) a;
        GRANT USAGE ON SCHEMA private TO service_role;
        v_service_private_usage_added := true;
        SELECT pg_catalog.to_jsonb(n) INTO STRICT v_private_schema_expected
            FROM pg_catalog.pg_namespace n WHERE n.nspname='private';
        SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)
            ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable)
            INTO v_private_acl_after FROM pg_catalog.pg_namespace n
            CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(n.nspacl,pg_catalog.acldefault('n',n.nspowner))) a
            WHERE n.nspname='private';
        IF (v_private_schema_expected-'nspacl') IS DISTINCT FROM (v_private_schema_before-'nspacl')
           OR v_private_acl_after IS DISTINCT FROM v_private_acl_expected THEN
            RAISE EXCEPTION 'B5B_PRIVATE_SCHEMA_UNAPPROVED_DELTA';
        END IF;
        -- Rebase only the independently verified private namespace ACL delta.
        -- All namespace properties and all other namespaces remain snapshotted.
        SELECT pg_catalog.jsonb_set(v_before,ARRAY['namespaces'],
            pg_catalog.jsonb_agg(CASE WHEN n->>'nspname'='private'
                THEN v_private_schema_expected ELSE n END ORDER BY (n->>'oid')::oid))
            INTO v_catalog_expected FROM pg_catalog.jsonb_array_elements(v_before->'namespaces') n;
    END IF;
    IF v_service_writer AND NOT pg_catalog.has_schema_privilege(v_service,'private','USAGE') THEN
        RAISE EXCEPTION 'B5B_SERVICE_WRITER_PRIVATE_USAGE_REQUIRED';
    END IF;
    ALTER TABLE public.marcadores ADD CONSTRAINT marcadores_id_game_identity_unique
        UNIQUE (id,game_id,game_uuid) NOT DEFERRABLE;
    ALTER TABLE public.marker_submissions ADD COLUMN game_uuid uuid;
    -- Fixed CREATE statements and exact constant bodies. Neither created function
    -- contains dynamic SQL. CURRENT_USER remains owner; no ALTER OWNER.
    EXECUTE pg_catalog.format('CREATE FUNCTION private.deepmap_game_uuid_from_legacy_identifier(p_identifier text)
        RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = %L AS %L','',v_helper_body);
    REVOKE ALL ON FUNCTION private.deepmap_game_uuid_from_legacy_identifier(text) FROM PUBLIC,anon,authenticated;
    IF v_service IS NOT NULL THEN
        REVOKE ALL ON FUNCTION private.deepmap_game_uuid_from_legacy_identifier(text) FROM service_role;
    END IF;
    GRANT EXECUTE ON FUNCTION private.deepmap_game_uuid_from_legacy_identifier(text) TO authenticated;
    IF v_service_writer THEN
        GRANT EXECUTE ON FUNCTION private.deepmap_game_uuid_from_legacy_identifier(text) TO service_role;
    END IF;
    EXECUTE pg_catalog.format('CREATE FUNCTION private.deepmap_resolve_submission_identity()
        RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = %L AS %L','',v_resolver_body);
    -- Caller needs EXECUTE on nested helper, not direct EXECUTE on trigger function.
    REVOKE ALL ON FUNCTION private.deepmap_resolve_submission_identity() FROM PUBLIC,anon,authenticated;
    IF v_service IS NOT NULL THEN REVOKE ALL ON FUNCTION private.deepmap_resolve_submission_identity() FROM service_role; END IF;
    CREATE TRIGGER deepmap_marker_submissions_identity
        BEFORE INSERT OR UPDATE ON public.marker_submissions
        FOR EACH ROW EXECUTE FUNCTION private.deepmap_resolve_submission_identity();
    SELECT pg_catalog.to_jsonb(p) INTO STRICT v_helper_before FROM pg_catalog.pg_proc p
        WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_game_uuid_from_legacy_identifier(text)');
    SELECT pg_catalog.to_jsonb(p) INTO STRICT v_resolver_before FROM pg_catalog.pg_proc p
        WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_submission_identity()');

    -- Only game_uuid in SET: no legacy AFTER UPDATE OF event is selected.
    UPDATE public.marker_submissions s
        SET game_uuid=private.deepmap_game_uuid_from_legacy_identifier(s.game_id)
        WHERE s.game_uuid IS NULL;
    GET DIAGNOSTICS v_affected=ROW_COUNT;
    IF v_affected<>v_rows THEN RAISE EXCEPTION 'B5B_BACKFILL_COUNT_MISMATCH'; END IF;
    ALTER TABLE public.marker_submissions
        ADD CONSTRAINT marker_submissions_legacy_game_uuid_fk FOREIGN KEY (game_id,game_uuid)
            REFERENCES private.game_legacy_identifiers(legacy_identifier,game_id)
            MATCH SIMPLE ON UPDATE NO ACTION ON DELETE RESTRICT NOT DEFERRABLE,
        ADD CONSTRAINT marker_submissions_marker_game_uuid_fk FOREIGN KEY (marker_id,game_id,game_uuid)
            REFERENCES public.marcadores(id,game_id,game_uuid)
            MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;
    ALTER TABLE public.marker_submissions ALTER COLUMN game_uuid SET NOT NULL;

    FOREACH v_relation IN ARRAY ARRAY['public.games','private.game_legacy_identifiers','public.marcadores',
        'public.marker_submissions','private.marker_submission_revisions','public.user_notifications',
        'private.marker_editor_audit','public.marker_images','public.marker_sections','public.marker_section_rows'] LOOP
        v_schema := pg_catalog.split_part(v_relation,'.',1);
        v_table := pg_catalog.split_part(v_relation,'.',2);
        IF v_relation='public.marker_submissions' THEN
            SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(s)-'game_uuid'
                ORDER BY pg_catalog.to_jsonb(s)-'game_uuid'),'[]'::jsonb) INTO v_data FROM public.marker_submissions s;
        ELSE
            EXECUTE pg_catalog.format('SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY pg_catalog.to_jsonb(t)),''[]''::jsonb) FROM %I.%I t',v_schema,v_table)
                INTO v_data;
        END IF;
        v_data_after := v_data_after || pg_catalog.jsonb_build_object(v_relation,v_data);
    END LOOP;
    IF v_data_after IS DISTINCT FROM v_data_before THEN
        RAISE EXCEPTION 'B5B_LEGACY_OR_RELATED_ROWS_CHANGED';
    END IF;
    EXECUTE v_snapshot_sql INTO v_after USING v_relations;
    IF v_after IS DISTINCT FROM v_catalog_expected THEN
        RAISE EXCEPTION 'B5B_LEGACY_CATALOG_SECURITY_FUNCTION_OR_SEQUENCE_CHANGED';
    END IF;
    IF pg_catalog.has_schema_privilege('anon','private','CREATE')
       OR pg_catalog.has_schema_privilege('authenticated','private','CREATE')
       OR (v_service IS NOT NULL AND pg_catalog.has_schema_privilege(v_service,'private','CREATE'))
       OR (v_service_writer AND NOT pg_catalog.has_schema_privilege(v_service,'private','USAGE'))
       OR (v_service_private_usage_added AND NOT v_service_writer) THEN
        RAISE EXCEPTION 'B5B_PRIVATE_SCHEMA_FINAL_PRIVILEGE_MISMATCH';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_attribute WHERE attrelid='public.marker_submissions'::pg_catalog.regclass
        AND attnum>0 AND NOT attisdropped)<>15
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid='public.marker_submissions'::pg_catalog.regclass
            AND attname='game_uuid' AND atttypid='uuid'::pg_catalog.regtype AND attnotnull AND NOT atthasdef
            AND attidentity='' AND attgenerated='' AND NOT attisdropped)
       OR pg_catalog.has_column_privilege('authenticated','public.marker_submissions','game_uuid','INSERT')
       OR pg_catalog.has_column_privilege('authenticated','public.marker_submissions','game_uuid','UPDATE')
       OR (SELECT count(*) FROM public.marker_submissions)<>v_rows
       OR EXISTS (SELECT 1 FROM public.marker_submissions s WHERE s.game_uuid IS NULL
            OR (SELECT count(*) FROM private.game_legacy_identifiers i JOIN public.games g ON g.id=i.game_id
                WHERE i.legacy_identifier=s.game_id AND i.game_id=s.game_uuid)<>1
            OR (s.marker_id IS NOT NULL AND (SELECT count(*) FROM public.marcadores m
                WHERE m.id=s.marker_id AND m.game_id=s.game_id AND m.game_uuid=s.game_uuid)<>1)) THEN
        RAISE EXCEPTION 'B5B_FINAL_COLUMNS_GRANTS_OR_DATA_INVALID';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_constraint WHERE conrelid='public.marker_submissions'::pg_catalog.regclass
        AND contype='f')<>3 THEN RAISE EXCEPTION 'B5B_FINAL_FK_COUNT_INVALID'; END IF;
    FOR v_name,v_cols,v_target,v_target_cols,v_delete IN SELECT * FROM (VALUES
        ('marker_submissions_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
            'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[],'r'),
        ('marker_submissions_marker_game_uuid_fk',ARRAY['marker_id','game_id','game_uuid']::text[],
            'public.marcadores',ARRAY['id','game_id','game_uuid']::text[],'c')
    ) e(name,cols,target,target_cols,del) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            WHERE c.conrelid='public.marker_submissions'::pg_catalog.regclass AND c.conname=v_name AND c.contype='f'
              AND c.confrelid=pg_catalog.to_regclass(v_target) AND c.convalidated
              AND NOT c.condeferrable AND NOT c.condeferred AND c.confmatchtype='s'
              AND c.confupdtype='a' AND c.confdeltype::text=v_delete
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos)
                  JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=v_cols
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num,pos)
                  JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)=v_target_cols) THEN
            RAISE EXCEPTION 'B5B_FINAL_FK_INVALID: %',v_name;
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
        WHERE c.conrelid='public.marcadores'::pg_catalog.regclass AND c.conname='marcadores_id_game_identity_unique'
          AND c.contype='u' AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
          AND i.indisunique AND i.indimmediate AND i.indisvalid AND i.indisready AND i.indislive
          AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnkeyatts=3 AND i.indnatts=3
          AND i.indrelid=c.conrelid
          AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos)
              JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=ARRAY['id','game_id','game_uuid']::text[]
          AND ARRAY(SELECT k.num FROM pg_catalog.unnest(i.indkey::smallint[]) WITH ORDINALITY k(num,pos) ORDER BY k.pos)=c.conkey) THEN
        RAISE EXCEPTION 'B5B_FINAL_MARKER_SUPPORT_KEY_INVALID';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgrelid='public.marker_submissions'::pg_catalog.regclass
        AND NOT tgisinternal)<>8 OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid='public.marker_submissions'::pg_catalog.regclass AND t.tgname='deepmap_marker_submissions_identity'
          AND t.tgfoid=pg_catalog.to_regprocedure('private.deepmap_resolve_submission_identity()') AND t.tgtype=23
          AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgnargs=0 AND t.tgqual IS NULL AND t.tgattr=''::pg_catalog.int2vector)
       OR (SELECT pg_catalog.array_agg(t.tgname::text ORDER BY t.tgname COLLATE "C") FROM pg_catalog.pg_trigger t
            WHERE t.tgrelid='public.marker_submissions'::pg_catalog.regclass AND NOT t.tgisinternal
              AND (t.tgtype & 2)=2 AND (t.tgtype & 16)=16)
          IS DISTINCT FROM ARRAY['deepmap_marker_submissions_identity','deepmap_marker_submissions_touch_updated_at']::text[] THEN
        RAISE EXCEPTION 'B5B_FINAL_TRIGGER_COUNT_OR_ORDER_INVALID';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_game_uuid_from_legacy_identifier(text)')
          AND p.pronargs=1 AND p.proargtypes='25'::pg_catalog.oidvector AND p.prorettype='uuid'::pg_catalog.regtype
          AND p.pronargdefaults=0 AND p.provariadic=0 AND p.proargmodes IS NULL
          AND p.proargnames=ARRAY['p_identifier']::text[]
          AND p.prokind='f' AND NOT p.proretset AND p.prosecdef AND p.provolatile='s' AND l.lanname='plpgsql'
          AND p.proowner=v_owner AND p.proconfig=ARRAY['search_path=""']::text[]
          AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u'
          AND p.prosrc=v_helper_body AND pg_catalog.to_jsonb(p)=v_helper_before)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_submission_identity()')
          AND p.pronargs=0 AND p.prorettype='trigger'::pg_catalog.regtype AND p.prokind='f' AND NOT p.proretset
          AND p.pronargdefaults=0 AND p.provariadic=0 AND p.proargmodes IS NULL
          AND NOT p.prosecdef AND p.provolatile='v' AND l.lanname='plpgsql' AND p.proowner=v_owner
          AND p.proconfig=ARRAY['search_path=""']::text[] AND p.prosrc=v_resolver_body
          AND pg_catalog.to_jsonb(p)=v_resolver_before)
       OR (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname IN ('public','private') AND p.proname IN
                ('deepmap_game_uuid_from_legacy_identifier','deepmap_resolve_submission_identity'))<>2 THEN
        RAISE EXCEPTION 'B5B_FINAL_FUNCTION_BODY_ATTRIBUTES_OWNER_OR_OVERLOAD_INVALID';
    END IF;
    IF pg_catalog.has_function_privilege('anon','private.deepmap_game_uuid_from_legacy_identifier(text)','EXECUTE')
       OR NOT pg_catalog.has_function_privilege('authenticated','private.deepmap_game_uuid_from_legacy_identifier(text)','EXECUTE')
       OR (v_service_writer AND NOT pg_catalog.has_function_privilege(v_service,
            'private.deepmap_game_uuid_from_legacy_identifier(text)','EXECUTE'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(
            COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
            WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_game_uuid_from_legacy_identifier(text)')
              AND ((a.grantee NOT IN (v_owner,pg_catalog.to_regrole('authenticated'))
                AND NOT (v_service_writer AND a.grantee=v_service)) OR a.privilege_type<>'EXECUTE'
                OR (a.grantee<>v_owner AND a.is_grantable)))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(
            COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
            WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_submission_identity()') AND a.grantee<>v_owner) THEN
        RAISE EXCEPTION 'B5B_FINAL_HELPER_OR_RESOLVER_ACL_INVALID';
    END IF;
    IF pg_catalog.has_sequence_privilege('anon','public.marker_submissions_id_seq','USAGE')
       OR pg_catalog.has_sequence_privilege('anon','public.marker_submissions_id_seq','SELECT')
       OR pg_catalog.has_sequence_privilege('anon','public.marker_submissions_id_seq','UPDATE')
       OR NOT pg_catalog.has_sequence_privilege('authenticated','public.marker_submissions_id_seq','USAGE')
       OR NOT pg_catalog.has_sequence_privilege('authenticated','public.marker_submissions_id_seq','SELECT')
       OR pg_catalog.has_sequence_privilege('authenticated','public.marker_submissions_id_seq','UPDATE') THEN
        RAISE EXCEPTION 'B5B_FINAL_SEQUENCE_EFFECTIVE_ACL_DRIFT';
    END IF;
    -- Sequence class/config/owner/ACL/dependencies are in exact catalog equality.
    -- No nextval/setval/last_value read, sequence DDL or identity INSERT occurs.
END;
$bridge$;
COMMIT;
