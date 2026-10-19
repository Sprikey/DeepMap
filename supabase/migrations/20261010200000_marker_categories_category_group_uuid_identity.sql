-- DeepMap B6b: permanent category identity and nullable group UUID bridge.
-- Manual review/application only. Legacy consumers and FKs remain active.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = pg_catalog;
DO $dependencies$
BEGIN
    IF EXISTS (SELECT 1 FROM (VALUES ('public.games'),('private.game_legacy_identifiers'),
        ('public.marker_category_groups'),('public.marker_categories'),('public.marcadores')) e(name)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass(e.name)
            AND c.relkind='r' AND c.relrowsecurity)) THEN RAISE EXCEPTION 'B6B_ORDINARY_RLS_TABLES_REQUIRED'; END IF;
END;
$dependencies$;
-- Parent-first. Stabilize data context; referenced groups require this mode
-- for ADD FK anyway. Categories final DDL mode avoids subsequent upgrades.
-- No markers/submissions locks: their rows are neither read for snapshots nor written.
LOCK TABLE public.games IN SHARE MODE;
LOCK TABLE private.game_legacy_identifiers IN SHARE MODE;
LOCK TABLE public.marker_category_groups IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.marker_categories IN ACCESS EXCLUSIVE MODE;
DO $bridge$
DECLARE
    v_old_body text := pg_catalog.replace($b2b_body$
DECLARE
    v_game_uuid uuid;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.game_uuid IS NULL THEN
            -- Only technical hydration, before the later touch trigger.
            -- Final NOT NULL prevents this old-row state after COMMIT.
            IF (pg_catalog.to_jsonb(NEW) - 'game_uuid')
               IS DISTINCT FROM (pg_catalog.to_jsonb(OLD) - 'game_uuid') THEN
                RAISE EXCEPTION 'B2B_HYDRATION_MUST_PRESERVE_LEGACY_FIELDS';
            END IF;
        ELSIF NEW.game_id IS DISTINCT FROM OLD.game_id
           OR NEW.game_uuid IS DISTINCT FROM OLD.game_uuid THEN
            RAISE EXCEPTION 'B2B_CATEGORY_GAME_IDENTITY_IS_IMMUTABLE';
        END IF;
    ELSIF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'B2B_UNSUPPORTED_CATEGORY_TRIGGER_EVENT';
    END IF;

    BEGIN
        SELECT i.game_id INTO STRICT v_game_uuid
        FROM private.game_legacy_identifiers AS i
        WHERE i.legacy_identifier = NEW.game_id;
    EXCEPTION
        WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B2B_CATEGORY_MAPPING_NOT_EXACTLY_ONE_VISIBLE_ROW';
    END;

    IF NEW.game_uuid IS NULL THEN
        NEW.game_uuid := v_game_uuid;
    ELSIF NEW.game_uuid IS DISTINCT FROM v_game_uuid THEN
        RAISE EXCEPTION 'B2B_CATEGORY_LEGACY_GAME_UUID_MISMATCH';
    END IF;
    RETURN NEW;
END;
$b2b_body$,pg_catalog.chr(13),'');
    v_new_body text := pg_catalog.replace($b6b_body$
DECLARE
    v_game_uuid uuid;
    v_group_uuid uuid;
    v_group_game_uuid uuid;
    v_group_changed boolean := false;
    v_hydrating boolean := false;
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.category_uuid := pg_catalog.gen_random_uuid();
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.category_uuid IS NULL OR NEW.category_uuid IS NULL
           OR NEW.category_uuid IS DISTINCT FROM OLD.category_uuid THEN
            RAISE EXCEPTION 'B6B_CATEGORY_UUID_IS_IMMUTABLE';
        END IF;
        v_group_changed := NEW.group_id IS DISTINCT FROM OLD.group_id;
        -- Technical transition exists only before the validated pair CHECK.
        v_hydrating := OLD.group_id IS NOT NULL AND OLD.group_uuid IS NULL;
        IF v_hydrating THEN
            IF (pg_catalog.to_jsonb(NEW)-'group_uuid') IS DISTINCT FROM
               (pg_catalog.to_jsonb(OLD)-'group_uuid') THEN
                RAISE EXCEPTION 'B6B_GROUP_HYDRATION_MUST_PRESERVE_OTHER_FIELDS';
            END IF;
        ELSIF NOT v_group_changed AND NEW.group_uuid IS DISTINCT FROM OLD.group_uuid THEN
            RAISE EXCEPTION 'B6B_UUID_ONLY_GROUP_CHANGE_NOT_SUPPORTED';
        END IF;
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF OLD.game_uuid IS NULL THEN
            -- Only technical hydration, before the later touch trigger.
            -- Final NOT NULL prevents this old-row state after COMMIT.
            IF (pg_catalog.to_jsonb(NEW) - 'game_uuid')
               IS DISTINCT FROM (pg_catalog.to_jsonb(OLD) - 'game_uuid') THEN
                RAISE EXCEPTION 'B2B_HYDRATION_MUST_PRESERVE_LEGACY_FIELDS';
            END IF;
        ELSIF NEW.game_id IS DISTINCT FROM OLD.game_id
           OR NEW.game_uuid IS DISTINCT FROM OLD.game_uuid THEN
            RAISE EXCEPTION 'B2B_CATEGORY_GAME_IDENTITY_IS_IMMUTABLE';
        END IF;
    ELSIF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'B2B_UNSUPPORTED_CATEGORY_TRIGGER_EVENT';
    END IF;

    BEGIN
        SELECT i.game_id INTO STRICT v_game_uuid
        FROM private.game_legacy_identifiers AS i
        WHERE i.legacy_identifier = NEW.game_id;
    EXCEPTION
        WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B2B_CATEGORY_MAPPING_NOT_EXACTLY_ONE_VISIBLE_ROW';
    END;

    IF NEW.game_uuid IS NULL THEN
        NEW.game_uuid := v_game_uuid;
    ELSIF NEW.game_uuid IS DISTINCT FROM v_game_uuid THEN
        RAISE EXCEPTION 'B2B_CATEGORY_LEGACY_GAME_UUID_MISMATCH';
    END IF;
    IF NEW.group_id IS NULL THEN
        NEW.group_uuid := NULL;
    ELSE
        BEGIN
            SELECT g.group_uuid,g.game_uuid INTO STRICT v_group_uuid,v_group_game_uuid
            FROM public.marker_category_groups AS g
            WHERE g.game_id=NEW.game_id AND g.id=NEW.group_id;
        EXCEPTION WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B6B_GROUP_NOT_EXACTLY_ONE_VISIBLE_ROW';
        END;
        IF v_group_uuid IS NULL OR v_group_game_uuid IS DISTINCT FROM v_game_uuid THEN
            RAISE EXCEPTION 'B6B_GROUP_GAME_CONTEXT_MISMATCH';
        END IF;
        IF TG_OP = 'UPDATE' THEN
            IF v_hydrating THEN
                IF NEW.group_uuid IS DISTINCT FROM v_group_uuid THEN
                    RAISE EXCEPTION 'B6B_GROUP_HYDRATION_REQUIRES_EXACT_UUID';
                END IF;
            ELSIF v_group_changed THEN
                IF NEW.group_uuid IS NOT NULL AND NEW.group_uuid IS DISTINCT FROM OLD.group_uuid
                   AND NEW.group_uuid IS DISTINCT FROM v_group_uuid THEN
                    RAISE EXCEPTION 'B6B_EXPLICIT_NEW_GROUP_UUID_MISMATCH';
                END IF;
            ELSIF NEW.group_uuid IS DISTINCT FROM v_group_uuid THEN
                RAISE EXCEPTION 'B6B_EXISTING_GROUP_UUID_MISMATCH';
            END IF;
        END IF;
        NEW.group_uuid := v_group_uuid;
    END IF;
    RETURN NEW;
END;
$b6b_body$,pg_catalog.chr(13),'');
    v_group_body text := pg_catalog.replace($b6a_body$
DECLARE
    v_game_uuid uuid;
BEGIN
    -- Table-wide legacy INSERT grants must not let callers choose entity identity.
    -- Default fills rewritten old rows; the INSERT trigger owns new-row identity.
    IF TG_OP = 'INSERT' THEN
        NEW.group_uuid := pg_catalog.gen_random_uuid();
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.group_uuid IS NULL OR NEW.group_uuid IS NULL
           OR NEW.group_uuid IS DISTINCT FROM OLD.group_uuid THEN
            RAISE EXCEPTION 'B6A_GROUP_UUID_IS_IMMUTABLE';
        END IF;
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF OLD.game_uuid IS NULL THEN
            -- Only technical hydration, before the later touch trigger.
            -- Final NOT NULL prevents this old-row state after COMMIT.
            IF (pg_catalog.to_jsonb(NEW) - 'game_uuid')
               IS DISTINCT FROM (pg_catalog.to_jsonb(OLD) - 'game_uuid') THEN
                RAISE EXCEPTION 'B2A_HYDRATION_MUST_PRESERVE_LEGACY_FIELDS';
            END IF;
        ELSIF NEW.game_id IS DISTINCT FROM OLD.game_id
           OR NEW.game_uuid IS DISTINCT FROM OLD.game_uuid THEN
            RAISE EXCEPTION 'B2A_GROUP_GAME_IDENTITY_IS_IMMUTABLE';
        END IF;
    ELSIF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'B2A_UNSUPPORTED_GROUP_TRIGGER_EVENT';
    END IF;

    BEGIN
        SELECT i.game_id INTO STRICT v_game_uuid
        FROM private.game_legacy_identifiers AS i
        WHERE i.legacy_identifier = NEW.game_id;
    EXCEPTION
        WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B2A_GROUP_MAPPING_NOT_EXACTLY_ONE_VISIBLE_ROW';
    END;

    IF NEW.game_uuid IS NULL THEN
        NEW.game_uuid := v_game_uuid;
    ELSIF NEW.game_uuid IS DISTINCT FROM v_game_uuid THEN
        RAISE EXCEPTION 'B2A_GROUP_LEGACY_GAME_UUID_MISMATCH';
    END IF;
    RETURN NEW;
END;
$b6a_body$,pg_catalog.chr(13),'');
    v_touch_body text := pg_catalog.replace($touch_body$
begin
    new.updated_at := now();
    return new;
end;
$touch_body$,pg_catalog.chr(13),'');
    v_fn oid := pg_catalog.to_regprocedure('private.deepmap_resolve_category_identity()');
    v_service oid := pg_catalog.to_regrole('service_role');
    v_service_writer boolean := false;
    v_service_select_needed boolean := false;
    v_service_mapping_select_added boolean := false;
    v_mapping_acl_expected jsonb;
    v_mapping_acl_after jsonb;
    v_catalog_expected jsonb;
    v_fn_before jsonb;
    v_before jsonb;
    v_after jsonb;
    v_data_before jsonb;
    v_data_after jsonb;
    v_category_uuids jsonb;
    v_rows bigint;
    v_grouped bigint;
    v_affected bigint;
    v_catalog text := $catalog$
        WITH rels AS (SELECT pg_catalog.to_regclass(e.name) AS oid FROM (VALUES
            ('public.games'),('private.game_legacy_identifiers'),('public.marker_category_groups'),('public.marker_categories')) e(name)),
        added AS (SELECT c.oid,c.conindid,c.contype FROM pg_catalog.pg_constraint c
            WHERE c.conrelid='public.marker_categories'::pg_catalog.regclass
              AND c.conname IN ('marker_categories_category_uuid_unique','marker_categories_legacy_uuid_identity_unique','marker_categories_group_uuid_pair_check','marker_categories_legacy_uuid_group_fk'))
        SELECT pg_catalog.jsonb_build_object(
            'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attrelid,a.attnum)
                FROM pg_catalog.pg_attribute a WHERE a.attrelid IN (SELECT oid FROM rels) AND a.attnum>0
                AND NOT (a.attrelid='public.marker_categories'::pg_catalog.regclass AND a.attname IN ('category_uuid','group_uuid'))),
            'defaults',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.adrelid,d.adnum)
                FROM pg_catalog.pg_attrdef d JOIN pg_catalog.pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
                WHERE d.adrelid IN (SELECT oid FROM rels)
                AND NOT (a.attrelid='public.marker_categories'::pg_catalog.regclass AND a.attname IN ('category_uuid','group_uuid'))),
            'constraints',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid)
                FROM pg_catalog.pg_constraint c WHERE (c.conrelid IN (SELECT oid FROM rels) OR c.confrelid IN (SELECT oid FROM rels))
                AND c.oid NOT IN (SELECT oid FROM added)
                AND NOT (c.conrelid='public.marker_categories'::pg_catalog.regclass AND c.contype='n'
                  AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=c.conrelid AND attname='category_uuid')]::smallint[])),
            'indexes',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.indexrelid)
                FROM pg_catalog.pg_index i WHERE i.indrelid IN (SELECT oid FROM rels) AND i.indexrelid NOT IN (SELECT conindid FROM added WHERE contype='u')),
            'index_objects',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('oid',c.oid,'name',c.relname,
                'namespace',c.relnamespace,'owner',c.relowner,'acl',c.relacl,'am',c.relam,'options',c.reloptions,
                'definition',pg_catalog.pg_get_indexdef(c.oid)) ORDER BY c.oid)
                FROM pg_catalog.pg_class c JOIN pg_catalog.pg_index i ON i.indexrelid=c.oid
                WHERE i.indrelid IN (SELECT oid FROM rels) AND i.indexrelid NOT IN (SELECT conindid FROM added WHERE contype='u')),
            'security',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('oid',c.oid,'name',c.relname,'namespace',c.relnamespace,
                'owner',c.relowner,'acl',c.relacl,'kind',c.relkind,'persistence',c.relpersistence,'rls',c.relrowsecurity,
                'force',c.relforcerowsecurity,'options',c.reloptions,'replica_identity',c.relreplident) ORDER BY c.oid)
                FROM pg_catalog.pg_class c WHERE c.oid IN (SELECT oid FROM rels)),
            'policies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid) FROM pg_catalog.pg_policy p WHERE p.polrelid IN (SELECT oid FROM rels)),
            'triggers',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY t.oid) FROM pg_catalog.pg_trigger t WHERE t.tgrelid IN (SELECT oid FROM rels) AND NOT (t.tgisinternal AND t.tgconstraint IN (SELECT oid FROM added))),
            'rules',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) ORDER BY r.oid) FROM pg_catalog.pg_rewrite r WHERE r.ev_class IN (SELECT oid FROM rels)),
            'namespaces',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(n) ORDER BY n.oid) FROM pg_catalog.pg_namespace n WHERE n.nspname IN ('public','private')),
            'functions',(SELECT pg_catalog.jsonb_agg(CASE WHEN p.oid=$1 THEN pg_catalog.to_jsonb(p)-'prosrc' ELSE pg_catalog.to_jsonb(p) END ORDER BY p.oid)
                FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private')))
$catalog$;
    v_relation text;
    v_schema text;
    v_table text;
    v_data jsonb;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
        WHERE c.oid IN ('public.games'::pg_catalog.regclass,'private.game_legacy_identifiers'::pg_catalog.regclass,
            'public.marker_category_groups'::pg_catalog.regclass,'public.marker_categories'::pg_catalog.regclass)
        AND (NOT pg_catalog.has_table_privilege(c.oid,'SELECT') OR NOT pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
            OR NOT (r.rolsuper OR r.rolbypassrls OR (r.oid=c.relowner AND NOT c.relforcerowsecurity)))) THEN
        RAISE EXCEPTION 'B6B_FULL_MAINTENANCE_VISIBILITY_REQUIRED';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r JOIN pg_catalog.pg_class c ON c.oid='public.marker_categories'::pg_catalog.regclass
        JOIN pg_catalog.pg_proc p ON p.oid=v_fn WHERE r.rolname=CURRENT_USER
        AND (r.rolsuper OR pg_catalog.pg_has_role(r.oid,c.relowner,'USAGE'))
        AND (r.rolsuper OR pg_catalog.pg_has_role(r.oid,p.proowner,'USAGE'))) THEN RAISE EXCEPTION 'B6B_DDL_OWNERSHIP_REQUIRED'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pg_catalog.gen_random_uuid()')
        AND p.pronargs=0 AND p.prorettype='uuid'::pg_catalog.regtype AND p.provolatile='v' AND NOT p.prosecdef AND NOT p.proretset
        AND pg_catalog.has_function_privilege(p.oid,'EXECUTE')) THEN RAISE EXCEPTION 'B6B_CORE_UUID_GENERATOR_REQUIRED'; END IF;
    IF EXISTS (WITH expected(name,type_name,nn,def) AS (VALUES
        ('game_id','text',true,NULL::text),('id','text',true,NULL),('group_id','text',false,NULL),
        ('name_en','text',true,NULL),('name_pt','text',true,NULL),('icon_source','text',true,'''none''::text'),
        ('icon_ref','text',false,NULL),('color','text',true,'''#777777''::text'),('marker_width','integer',false,NULL),
        ('marker_height','integer',false,NULL),('symbol_size','integer',false,NULL),('sort_order','integer',true,'0'),
        ('is_active','boolean',true,'true'),('created_at','timestamptz',true,'now()'),('updated_at','timestamptz',true,'now()'),('game_uuid','uuid',true,NULL)),
        actual AS (SELECT a.*,pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS def FROM pg_catalog.pg_attribute a
            LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
            WHERE a.attrelid='public.marker_categories'::pg_catalog.regclass AND a.attnum>0 AND NOT a.attisdropped)
        SELECT 1 FROM expected e FULL JOIN actual a ON a.attname=e.name WHERE e.name IS NULL OR a.attname IS NULL
        OR a.atttypid<>pg_catalog.to_regtype(e.type_name) OR a.attnotnull IS DISTINCT FROM e.nn OR a.def IS DISTINCT FROM e.def
        OR a.attidentity<>'' OR a.attgenerated<>'') THEN RAISE EXCEPTION 'B6B_CATEGORY_COLUMNS_DRIFT_OR_PARTIAL_STATE'; END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conrelid='public.marker_categories'::pg_catalog.regclass
        AND (contype IN ('u','x') OR conname IN ('marker_categories_category_uuid_unique','marker_categories_legacy_uuid_identity_unique',
            'marker_categories_group_uuid_pair_check','marker_categories_legacy_uuid_group_fk')))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_class WHERE relnamespace='public'::pg_catalog.regnamespace
        AND relname IN ('marker_categories_category_uuid_unique','marker_categories_legacy_uuid_identity_unique'))
       OR (SELECT count(*) FROM pg_catalog.pg_index WHERE indrelid='public.marker_categories'::pg_catalog.regclass)<>1
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_rewrite WHERE ev_class='public.marker_categories'::pg_catalog.regclass)
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_inherits WHERE inhrelid='public.marker_categories'::pg_catalog.regclass
            OR inhparent='public.marker_categories'::pg_catalog.regclass) THEN RAISE EXCEPTION 'B6B_PARTIAL_OR_UNEXPECTED_CATEGORY_OBJECTS'; END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_constraint WHERE conrelid='public.marker_categories'::pg_catalog.regclass AND contype='c')<>7
       OR EXISTS (SELECT 1 FROM (VALUES
        ('marker_categories_id_format',$expr$(id ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'::text)$expr$),
        ('marker_categories_icon_source_check',$expr$(icon_source = ANY (ARRAY['none'::text, 'static'::text, 'r2'::text, 'external'::text]))$expr$),
        ('marker_categories_color_check',$expr$(color ~ '^#[0-9A-Fa-f]{6}$'::text)$expr$),
        ('marker_categories_marker_width_check',$expr$((marker_width IS NULL) OR (marker_width > 0))$expr$),
        ('marker_categories_marker_height_check',$expr$((marker_height IS NULL) OR (marker_height > 0))$expr$),
        ('marker_categories_symbol_size_check',$expr$((symbol_size IS NULL) OR (symbol_size > 0))$expr$),
        ('marker_categories_icon_ref_required',$expr$((icon_source = 'none'::text) OR (NULLIF(btrim(icon_ref), ''::text) IS NOT NULL))$expr$)) e(name,expression)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.marker_categories'::pg_catalog.regclass
        AND c.conname=e.name AND c.contype='c' AND c.convalidated
        AND pg_catalog.pg_get_expr(c.conbin,c.conrelid)=e.expression)) THEN RAISE EXCEPTION 'B6B_LEGACY_CHECK_DRIFT'; END IF;
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.marker_categories','marker_categories_pkey',ARRAY['game_id','id']::text[],'p'),
        ('public.marker_category_groups','marker_category_groups_pkey',ARRAY['game_id','id'],'p'),
        ('public.marker_category_groups','marker_category_groups_group_uuid_unique',ARRAY['group_uuid'],'u'),
        ('public.marker_category_groups','marker_category_groups_legacy_uuid_identity_unique',ARRAY['game_id','id','game_uuid','group_uuid'],'u')) e(rel,name,cols,kind)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
        JOIN pg_catalog.pg_class x ON x.oid=i.indexrelid JOIN pg_catalog.pg_am am ON am.oid=x.relam
        WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND c.conname=e.name AND c.contype::text=e.kind
        AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred AND i.indisunique AND i.indimmediate
        AND i.indisvalid AND i.indisready AND i.indislive AND am.amname='btree' AND i.indpred IS NULL AND i.indexprs IS NULL
        AND i.indnatts=i.indnkeyatts AND i.indnkeyatts=pg_catalog.cardinality(e.cols)
        AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(n,pos)
            JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.n ORDER BY k.pos)=e.cols)) THEN RAISE EXCEPTION 'B6B_LEGACY_PK_OR_B6A_SUPPORT_KEY_DRIFT'; END IF;
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.marker_categories','marker_categories_group_fk','public.marker_category_groups',ARRAY['game_id','group_id']::text[],ARRAY['game_id','id']::text[],'c','n'),
        ('public.marker_categories','marker_categories_legacy_game_uuid_fk','private.game_legacy_identifiers',ARRAY['game_id','game_uuid'],ARRAY['legacy_identifier','game_id'],'a','r'),
        ('public.marker_category_groups','marker_category_groups_legacy_game_uuid_fk','private.game_legacy_identifiers',ARRAY['game_id','game_uuid'],ARRAY['legacy_identifier','game_id'],'a','r'),
        ('private.game_legacy_identifiers','game_legacy_identifiers_game_id_fkey','public.games',ARRAY['game_id'],ARRAY['id'],'a','r'),
        ('public.marcadores','marcadores_category_fk','public.marker_categories',ARRAY['game_id','category_id'],ARRAY['game_id','id'],'c','a')) e(rel,name,parent,cols,pcols,upd,del)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND c.conname=e.name
        AND c.contype='f' AND c.confrelid=pg_catalog.to_regclass(e.parent) AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
        AND c.confmatchtype='s' AND c.confupdtype::text=e.upd AND c.confdeltype::text=e.del
        AND pg_catalog.to_jsonb(c)->>'confdelsetcols' IS NULL
        AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(n,pos)
            JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.n ORDER BY k.pos)=e.cols
        AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(n,pos)
            JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.n ORDER BY k.pos)=e.pcols)) THEN RAISE EXCEPTION 'B6B_LEGACY_FK_DRIFT'; END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_constraint WHERE conrelid='public.marker_categories'::pg_catalog.regclass AND contype IN ('p','f','c','u','x'))<>10
       OR (SELECT count(*) FROM pg_catalog.pg_constraint WHERE confrelid='public.marker_categories'::pg_catalog.regclass AND contype='f')<>1 THEN
        RAISE EXCEPTION 'B6B_UNEXPECTED_CATEGORY_CONSTRAINT_OR_INCOMING_FK'; END IF;
    IF EXISTS (SELECT 1 FROM (VALUES ('game_uuid',NULL::text),('group_uuid','gen_random_uuid()')) e(name,def)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
        WHERE a.attrelid='public.marker_category_groups'::pg_catalog.regclass AND a.attname=e.name AND a.attnotnull AND a.atttypid='uuid'::pg_catalog.regtype
        AND NOT a.attisdropped AND a.attidentity='' AND a.attgenerated='' AND pg_catalog.pg_get_expr(d.adbin,d.adrelid) IS NOT DISTINCT FROM e.def)) THEN
        RAISE EXCEPTION 'B6B_B6A_GROUP_COLUMN_DRIFT'; END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_attribute WHERE attrelid='public.marker_category_groups'::pg_catalog.regclass
        AND attnum>0 AND NOT attisdropped)<>10
       OR (SELECT count(*) FROM pg_catalog.pg_index WHERE indrelid='public.marker_category_groups'::pg_catalog.regclass)<>3
       OR (SELECT count(*) FROM pg_catalog.pg_constraint WHERE conrelid='public.marker_category_groups'::pg_catalog.regclass
            AND contype IN ('p','u','c','f','x'))<>5
       OR EXISTS (SELECT 1 FROM (VALUES ('game_id','text',NULL::text),('id','text',NULL),('name_en','text',NULL),('name_pt','text',NULL),
            ('sort_order','integer','0'),('is_active','boolean','true'),('created_at','timestamptz','now()'),('updated_at','timestamptz','now()')) e(name,type_name,def)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
        WHERE a.attrelid='public.marker_category_groups'::pg_catalog.regclass AND a.attname=e.name AND a.attnotnull
        AND a.atttypid=pg_catalog.to_regtype(e.type_name) AND NOT a.attisdropped AND a.attidentity='' AND a.attgenerated=''
        AND pg_catalog.pg_get_expr(d.adbin,d.adrelid) IS NOT DISTINCT FROM e.def))
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.marker_category_groups'::pg_catalog.regclass
        AND c.conname='marker_category_groups_id_format' AND c.contype='c' AND c.convalidated
        AND pg_catalog.pg_get_expr(c.conbin,c.conrelid)='(id ~ ''^[a-z0-9]+(?:[_-][a-z0-9]+)*$''::text)') THEN
        RAISE EXCEPTION 'B6B_B6A_GROUP_BASELINE_DRIFT'; END IF;
    SELECT pg_catalog.to_jsonb(p) INTO STRICT v_fn_before FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=v_fn AND p.pronargs=0 AND p.prorettype='trigger'::pg_catalog.regtype AND l.lanname='plpgsql'
        AND NOT p.prosecdef AND p.proconfig=ARRAY['search_path=""']::text[] AND p.provolatile='v' AND p.proparallel='u'
        AND NOT p.proisstrict AND NOT p.proleakproof AND NOT p.proretset AND p.procost=100
        AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=v_old_body;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_category_group_identity()')
        AND NOT p.prosecdef AND p.proconfig=ARRAY['search_path=""']::text[] AND p.pronargs=0 AND p.prorettype='trigger'::pg_catalog.regtype
        AND l.lanname='plpgsql' AND p.provolatile='v' AND p.proparallel='u' AND NOT p.proisstrict
        AND NOT p.proleakproof AND NOT p.proretset AND p.procost=100
        AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=v_group_body)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
        AND NOT p.prosecdef AND p.prorettype='trigger'::pg_catalog.regtype AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=v_touch_body)
       OR EXISTS (SELECT 1 FROM (VALUES ('deepmap_resolve_category_identity'),('deepmap_resolve_category_group_identity')) e(name)
        WHERE (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='private'::pg_catalog.regnamespace AND proname=e.name)<>1) THEN
        RAISE EXCEPTION 'B6B_RESOLVER_OR_TOUCH_BASELINE_DRIFT'; END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
        WHERE p.oid IN (v_fn,pg_catalog.to_regprocedure('private.deepmap_resolve_category_group_identity()'))
        AND (a.grantee<>p.proowner OR a.privilege_type<>'EXECUTE')) THEN
        RAISE EXCEPTION 'B6B_RESOLVER_OWNER_ONLY_ACL_REQUIRED'; END IF;
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.marker_categories','deepmap_categories_identity',23,'private.deepmap_resolve_category_identity()'),
        ('public.marker_categories','deepmap_marker_categories_touch_updated_at',19,'private.deepmap_touch_updated_at()'),
        ('public.marker_category_groups','deepmap_category_groups_identity',23,'private.deepmap_resolve_category_group_identity()'),
        ('public.marker_category_groups','deepmap_category_groups_touch_updated_at',19,'private.deepmap_touch_updated_at()')) e(rel,name,kind,signature)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid=pg_catalog.to_regclass(e.rel) AND t.tgname=e.name
        AND t.tgtype=e.kind AND t.tgfoid=pg_catalog.to_regprocedure(e.signature) AND NOT t.tgisinternal AND t.tgenabled='O'
        AND t.tgnargs=0 AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL))
       OR EXISTS (SELECT 1 FROM (VALUES ('public.marker_categories'),('public.marker_category_groups')) e(rel)
        WHERE (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass(e.rel) AND NOT tgisinternal)<>2) THEN
        RAISE EXCEPTION 'B6B_UNEXPECTED_EDITORIAL_TRIGGER_OR_TRIGGER_DRIFT'; END IF;
    -- Identical Admin predicates on categories and groups prove authenticated
    -- writers can read inactive groups too. All other effective writer roles
    -- must have full group visibility, or inherit this authenticated contract.
    IF EXISTS (SELECT 1 FROM (VALUES ('public.marker_categories','marker_categories'),('public.marker_category_groups','marker_category_groups')) e(rel,prefix)
        WHERE (SELECT count(*) FROM pg_catalog.pg_policy WHERE polrelid=pg_catalog.to_regclass(e.rel))<>2
        OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid=pg_catalog.to_regclass(e.rel) AND p.polname=e.prefix||'_public_read'
            AND p.polcmd='r' AND p.polpermissive AND p.polwithcheck IS NULL AND pg_catalog.pg_get_expr(p.polqual,p.polrelid)='(is_active = true)'
            AND ARRAY(SELECT r.rolname::text FROM pg_catalog.unnest(p.polroles) x(oid) JOIN pg_catalog.pg_roles r ON r.oid=x.oid ORDER BY r.rolname COLLATE "C")=ARRAY['anon','authenticated']::text[])
        OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid=pg_catalog.to_regclass(e.rel) AND p.polname=e.prefix||'_admin_all'
            AND p.polcmd='*' AND p.polpermissive AND p.polroles=ARRAY['authenticated'::pg_catalog.regrole::oid]
            AND pg_catalog.pg_get_expr(p.polqual,p.polrelid)='private.is_deepmap_admin()'
            AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)='private.is_deepmap_admin()')) THEN RAISE EXCEPTION 'B6B_ADMIN_POLICY_CONTRACT_DRIFT'; END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles r CROSS JOIN pg_catalog.pg_class g WHERE g.oid='public.marker_category_groups'::pg_catalog.regclass
        -- Built-in capability roles are not application callers; any actual
        -- role inheriting them remains included and must satisfy visibility.
        AND r.rolname !~ '^pg_'
        AND (pg_catalog.has_any_column_privilege(r.oid,'public.marker_categories','INSERT') OR pg_catalog.has_any_column_privilege(r.oid,'public.marker_categories','UPDATE'))
        AND (NOT pg_catalog.has_table_privilege(r.oid,g.oid,'SELECT') OR NOT pg_catalog.has_schema_privilege(r.oid,g.relnamespace,'USAGE')
        OR NOT pg_catalog.has_schema_privilege(r.oid,'private','USAGE') OR NOT pg_catalog.has_schema_privilege(r.oid,'pg_catalog','USAGE')
        OR NOT pg_catalog.has_function_privilege(r.oid,'pg_catalog.gen_random_uuid()','EXECUTE')
        OR NOT (r.rolsuper OR r.rolbypassrls OR (r.oid=g.relowner AND NOT g.relforcerowsecurity)
            OR pg_catalog.pg_has_role(r.oid,'authenticated','USAGE')))) THEN RAISE EXCEPTION 'B6B_INVOKER_WRITER_GROUP_VISIBILITY_REQUIRED'; END IF;
    IF EXISTS (SELECT 1 FROM (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE')) e(privilege)
        WHERE NOT pg_catalog.has_table_privilege('authenticated','public.marker_categories',e.privilege))
       OR NOT pg_catalog.has_table_privilege('anon','public.marker_categories','SELECT') THEN RAISE EXCEPTION 'B6B_LEGACY_GRANTS_REQUIRED'; END IF;
    IF NOT pg_catalog.has_table_privilege('authenticated','private.game_legacy_identifiers','SELECT')
       OR NOT pg_catalog.has_function_privilege('authenticated','private.is_deepmap_admin()','EXECUTE')
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='private.game_legacy_identifiers'::pg_catalog.regclass
        AND p.polname='game_legacy_identifiers_admin_read' AND p.polcmd='r' AND p.polpermissive
        AND p.polroles=ARRAY['authenticated'::pg_catalog.regrole::oid]
        AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'[[:space:]()]','','g') IN
            ('SELECTpublic.get_deepmap_roleASget_deepmap_role=''admin''::text',
             'SELECTget_deepmap_roleASget_deepmap_role=''admin''::text')) THEN
        RAISE EXCEPTION 'B6B_B2B_INVOKER_MAPPING_ACCESS_DRIFT'; END IF;
    -- Preserve B2b's fail-closed protection: restrictive SELECT/ALL policies
    -- could invalidate the authenticated Admin lookup contract below.
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_policy p
        WHERE p.polrelid='private.game_legacy_identifiers'::pg_catalog.regclass
        AND NOT p.polpermissive AND p.polcmd IN ('r','*')) THEN
        RAISE EXCEPTION 'B6B_RESTRICTIVE_MAPPING_READ_POLICY_UNSUPPORTED';
    END IF;
    -- Plan the single approved ACL repair; every other requirement is fatal.
    IF v_service IS NOT NULL THEN
        v_service_writer := pg_catalog.has_any_column_privilege(v_service,'public.marker_categories','INSERT')
            OR pg_catalog.has_any_column_privilege(v_service,'public.marker_categories','UPDATE');
        v_service_select_needed := v_service_writer
            AND NOT pg_catalog.has_table_privilege(v_service,'private.game_legacy_identifiers','SELECT');
    END IF;
    IF v_service_select_needed AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class m
        JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
        WHERE m.oid='private.game_legacy_identifiers'::pg_catalog.regclass
        AND (r.rolsuper OR pg_catalog.pg_has_role(r.oid,m.relowner,'USAGE'))) THEN
        RAISE EXCEPTION 'B6B_SERVICE_MAPPING_SELECT_GRANT_AUTHORITY_REQUIRED';
    END IF;
    -- Same effective application-writer population as the group sweep. BOTH
    -- contexts must be readable under the actual INVOKER, including service_role.
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles r CROSS JOIN pg_catalog.pg_class m
        WHERE m.oid='private.game_legacy_identifiers'::pg_catalog.regclass
        AND r.rolname !~ '^pg_'
        AND (pg_catalog.has_any_column_privilege(r.oid,'public.marker_categories','INSERT')
            OR pg_catalog.has_any_column_privilege(r.oid,'public.marker_categories','UPDATE'))
        AND (NOT pg_catalog.has_schema_privilege(r.oid,m.relnamespace,'USAGE')
            OR (NOT pg_catalog.has_table_privilege(r.oid,m.oid,'SELECT')
                AND NOT (r.oid IS NOT DISTINCT FROM v_service AND v_service_select_needed))
            OR NOT (r.rolsuper OR r.rolbypassrls OR (r.oid=m.relowner AND NOT m.relforcerowsecurity)
                OR (pg_catalog.pg_has_role(r.oid,'authenticated','USAGE')
                    AND pg_catalog.has_function_privilege(r.oid,'public.get_deepmap_role()','EXECUTE'))))) THEN
        RAISE EXCEPTION 'B6B_INVOKER_WRITER_MAPPING_VISIBILITY_REQUIRED';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid IN ('public.marcadores'::pg_catalog.regclass,
        'public.marker_submissions'::pg_catalog.regclass,'private.marker_submission_revisions'::pg_catalog.regclass,'public.user_notifications'::pg_catalog.regclass)
        AND attnum>0 AND NOT attisdropped AND attname IN ('category_uuid','group_uuid')) THEN RAISE EXCEPTION 'B6B_REQUIRES_PRE_B6C_SCOPE'; END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname IN ('public','private') AND p.proname ~ '^deepmap_resolve_(marker|submission|notification|revision)_(category|group)_identity$') THEN
        RAISE EXCEPTION 'B6B_LATER_RESOLVER_ALREADY_PRESENT'; END IF;
    IF EXISTS (SELECT 1 FROM public.marker_categories c WHERE
        (SELECT count(*) FROM private.game_legacy_identifiers i JOIN public.games p ON p.id=i.game_id WHERE i.legacy_identifier=c.game_id AND i.game_id=c.game_uuid)<>1
        OR (c.group_id IS NOT NULL AND (SELECT count(*) FROM public.marker_category_groups g
            WHERE g.game_id=c.game_id AND g.id=c.group_id AND g.game_uuid=c.game_uuid AND g.group_uuid IS NOT NULL)<>1)) THEN
        RAISE EXCEPTION 'B6B_EXISTING_GAME_OR_GROUP_CONTEXT_INVALID'; END IF;
    -- now() is the BEGIN timestamp, not the lock-acquisition time. A writer
    -- committed while we waited for the locks may have a newer updated_at.
    -- Abort instead of letting the technical touch move its timestamp backwards.
    IF EXISTS (SELECT 1 FROM public.marker_categories
        WHERE group_id IS NOT NULL AND updated_at>pg_catalog.now()) THEN
        RAISE EXCEPTION 'B6B_GROUPED_UPDATED_AT_AFTER_TRANSACTION_TIMESTAMP';
    END IF;
    SELECT count(*),count(*) FILTER(WHERE group_id IS NOT NULL) INTO v_rows,v_grouped FROM public.marker_categories;
    v_data_before := '{}'::jsonb;
    FOREACH v_relation IN ARRAY ARRAY['public.games','private.game_legacy_identifiers','public.marker_category_groups','public.marker_categories'] LOOP
        v_schema:=pg_catalog.split_part(v_relation,'.',1); v_table:=pg_catalog.split_part(v_relation,'.',2);
        EXECUTE pg_catalog.format('SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY pg_catalog.to_jsonb(t)),''[]''::jsonb) FROM %I.%I t',v_schema,v_table) INTO v_data;
        v_data_before:=v_data_before||pg_catalog.jsonb_build_object(v_relation,v_data);
    END LOOP;
    EXECUTE v_catalog INTO v_before USING v_fn;
    v_catalog_expected := v_before;
    IF v_service_select_needed THEN
        -- First persistent mutation when needed: approved non-grantable SELECT.
        -- Every non-fixable baseline/data/writer check has already passed.
        IF NOT v_service_writer OR pg_catalog.has_table_privilege(v_service,'private.game_legacy_identifiers','SELECT') THEN
            RAISE EXCEPTION 'B6B_SERVICE_MAPPING_GRANT_PREREQUISITES_CHANGED';
        END IF;
        IF (SELECT COALESCE(pg_catalog.to_jsonb(c.relacl),'null'::jsonb)
            FROM pg_catalog.pg_class c WHERE c.oid='private.game_legacy_identifiers'::pg_catalog.regclass)
           IS DISTINCT FROM (SELECT n->'acl' FROM pg_catalog.jsonb_array_elements(v_before->'security') n
            WHERE (n->>'oid')::oid='private.game_legacy_identifiers'::pg_catalog.regclass) THEN
            RAISE EXCEPTION 'B6B_MAPPING_ACL_CHANGED_SINCE_SNAPSHOT';
        END IF;
        SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable)
            INTO v_mapping_acl_expected FROM (
                SELECT x.* FROM pg_catalog.pg_class c CROSS JOIN LATERAL
                    pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) x
                    WHERE c.oid='private.game_legacy_identifiers'::pg_catalog.regclass
                UNION ALL SELECT c.relowner,v_service,'SELECT'::text,false FROM pg_catalog.pg_class c
                    WHERE c.oid='private.game_legacy_identifiers'::pg_catalog.regclass
            ) a;
        GRANT SELECT ON TABLE private.game_legacy_identifiers TO service_role;
        v_service_mapping_select_added := true;
        SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable)
            INTO v_mapping_acl_after FROM pg_catalog.pg_class c CROSS JOIN LATERAL
                pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
                WHERE c.oid='private.game_legacy_identifiers'::pg_catalog.regclass;
        IF v_mapping_acl_after IS DISTINCT FROM v_mapping_acl_expected THEN
            RAISE EXCEPTION 'B6B_UNAPPROVED_MAPPING_ACL_DELTA';
        END IF;
        -- Rebase only the independently validated ACL of this one relation.
        -- Other mapping properties, schema ACLs and all other ACLs stay exact.
        SELECT pg_catalog.jsonb_set(v_before,ARRAY['security'],pg_catalog.jsonb_agg(
            CASE WHEN (n->>'oid')::oid=c.oid THEN pg_catalog.jsonb_set(n,ARRAY['acl'],
                COALESCE(pg_catalog.to_jsonb(c.relacl),'null'::jsonb)) ELSE n END ORDER BY (n->>'oid')::oid))
            INTO v_catalog_expected FROM pg_catalog.jsonb_array_elements(v_before->'security') n
            CROSS JOIN pg_catalog.pg_class c WHERE c.oid='private.game_legacy_identifiers'::pg_catalog.regclass;
    END IF;
    -- Same effective application-writer population as the group sweep. BOTH
    -- contexts must be readable under the actual INVOKER, including service_role.
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles r CROSS JOIN pg_catalog.pg_class m
        WHERE m.oid='private.game_legacy_identifiers'::pg_catalog.regclass
        AND r.rolname !~ '^pg_'
        AND (pg_catalog.has_any_column_privilege(r.oid,'public.marker_categories','INSERT')
            OR pg_catalog.has_any_column_privilege(r.oid,'public.marker_categories','UPDATE'))
        AND (NOT pg_catalog.has_schema_privilege(r.oid,m.relnamespace,'USAGE')
            OR NOT pg_catalog.has_table_privilege(r.oid,m.oid,'SELECT')
            OR NOT (r.rolsuper OR r.rolbypassrls OR (r.oid=m.relowner AND NOT m.relforcerowsecurity)
                OR (pg_catalog.pg_has_role(r.oid,'authenticated','USAGE')
                    AND pg_catalog.has_function_privilege(r.oid,'public.get_deepmap_role()','EXECUTE'))))) THEN
        RAISE EXCEPTION 'B6B_INVOKER_WRITER_MAPPING_VISIBILITY_REQUIRED';
    END IF;
    -- First persistent mutation if no grant was needed; otherwise first DDL.
    -- Volatile default rewrites rows, not row events.
    ALTER TABLE public.marker_categories ADD COLUMN category_uuid uuid NOT NULL DEFAULT pg_catalog.gen_random_uuid(), ADD COLUMN group_uuid uuid;
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('game_id',game_id,'id',id,'category_uuid',category_uuid)
        ORDER BY game_id,id),'[]'::jsonb) INTO v_category_uuids FROM public.marker_categories;
    EXECUTE pg_catalog.format('CREATE OR REPLACE FUNCTION private.deepmap_resolve_category_identity()
        RETURNS trigger LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE CALLED ON NULL INPUT SECURITY INVOKER COST 100 SET search_path = %L AS %L','',v_new_body);
    UPDATE public.marker_categories c SET group_uuid=g.group_uuid FROM public.marker_category_groups g
        WHERE c.group_id IS NOT NULL AND c.group_uuid IS NULL AND g.game_id=c.game_id AND g.id=c.group_id AND g.game_uuid=c.game_uuid;
    GET DIAGNOSTICS v_affected=ROW_COUNT;
    IF v_affected<>v_grouped THEN RAISE EXCEPTION 'B6B_GROUP_FILL_COUNT_MISMATCH'; END IF;
    ALTER TABLE public.marker_categories
        ADD CONSTRAINT marker_categories_category_uuid_unique UNIQUE(category_uuid) NOT DEFERRABLE,
        ADD CONSTRAINT marker_categories_legacy_uuid_identity_unique UNIQUE(game_id,id,game_uuid,category_uuid) NOT DEFERRABLE,
        ADD CONSTRAINT marker_categories_group_uuid_pair_check CHECK ((group_id IS NULL AND group_uuid IS NULL) OR (group_id IS NOT NULL AND group_uuid IS NOT NULL)),
        ADD CONSTRAINT marker_categories_legacy_uuid_group_fk FOREIGN KEY(game_id,group_id,game_uuid,group_uuid)
            REFERENCES public.marker_category_groups(game_id,id,game_uuid,group_uuid)
            MATCH SIMPLE ON UPDATE CASCADE ON DELETE RESTRICT NOT DEFERRABLE;
    EXECUTE v_catalog INTO v_after USING v_fn;
    IF v_after IS DISTINCT FROM v_catalog_expected THEN RAISE EXCEPTION 'B6B_UNAPPROVED_CATALOG_CHANGE'; END IF;
    IF v_service_writer AND (NOT pg_catalog.has_schema_privilege(v_service,'private','USAGE')
        OR NOT pg_catalog.has_table_privilege(v_service,'private.game_legacy_identifiers','SELECT')) THEN
        RAISE EXCEPTION 'B6B_SERVICE_WRITER_FINAL_MAPPING_ACCESS_REQUIRED';
    END IF;
    IF v_service_mapping_select_added AND NOT v_service_writer THEN
        RAISE EXCEPTION 'B6B_UNAUTHORIZED_SERVICE_MAPPING_SELECT';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_fn AND pg_catalog.to_jsonb(p)-'prosrc'=v_fn_before-'prosrc'
        AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=v_new_body) THEN RAISE EXCEPTION 'B6B_RESOLVER_REPLACEMENT_DRIFT'; END IF;
    v_data_after := '{}'::jsonb;
    FOREACH v_relation IN ARRAY ARRAY['public.games','private.game_legacy_identifiers','public.marker_category_groups','public.marker_categories'] LOOP
        IF v_relation='public.marker_categories' THEN
            -- Keep the original timestamp in the comparison only for filled rows;
            -- it is separately required to equal this transaction's touch value.
            SELECT COALESCE(pg_catalog.jsonb_agg((pg_catalog.to_jsonb(c)-ARRAY['category_uuid','group_uuid']::text[]) ||
                CASE WHEN c.group_id IS NOT NULL THEN pg_catalog.jsonb_build_object('updated_at',b->'updated_at') ELSE '{}'::jsonb END
                ORDER BY (pg_catalog.to_jsonb(c)-ARRAY['category_uuid','group_uuid']::text[]) ||
                CASE WHEN c.group_id IS NOT NULL THEN pg_catalog.jsonb_build_object('updated_at',b->'updated_at') ELSE '{}'::jsonb END),'[]'::jsonb)
                INTO v_data FROM public.marker_categories c JOIN pg_catalog.jsonb_array_elements(v_data_before->v_relation) b
                ON b->>'game_id'=c.game_id AND b->>'id'=c.id;
            IF EXISTS (SELECT 1 FROM public.marker_categories WHERE group_id IS NOT NULL AND updated_at IS DISTINCT FROM pg_catalog.now()) THEN
                RAISE EXCEPTION 'B6B_GROUPED_TIMESTAMP_NOT_TECHNICAL_TOUCH'; END IF;
        ELSE
            v_schema:=pg_catalog.split_part(v_relation,'.',1); v_table:=pg_catalog.split_part(v_relation,'.',2);
            EXECUTE pg_catalog.format('SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY pg_catalog.to_jsonb(t)),''[]''::jsonb) FROM %I.%I t',v_schema,v_table) INTO v_data;
        END IF;
        v_data_after:=v_data_after||pg_catalog.jsonb_build_object(v_relation,v_data);
    END LOOP;
    IF v_data_after IS DISTINCT FROM v_data_before OR (SELECT count(*) FROM public.marker_categories)<>v_rows
       OR (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('game_id',game_id,'id',id,'category_uuid',category_uuid)
           ORDER BY game_id,id),'[]'::jsonb) FROM public.marker_categories) IS DISTINCT FROM v_category_uuids THEN RAISE EXCEPTION 'B6B_UNAPPROVED_ROW_OR_CATEGORY_UUID_CHANGE'; END IF;
    IF (SELECT count(DISTINCT category_uuid) FROM public.marker_categories)<>v_rows
       OR EXISTS (SELECT 1 FROM public.marker_categories c WHERE c.category_uuid IS NULL
        OR (c.group_id IS NULL) IS DISTINCT FROM (c.group_uuid IS NULL)
        OR (SELECT count(*) FROM private.game_legacy_identifiers i JOIN public.games p ON p.id=i.game_id WHERE i.legacy_identifier=c.game_id AND i.game_id=c.game_uuid)<>1
        OR (c.group_id IS NOT NULL AND (SELECT count(*) FROM public.marker_category_groups g WHERE g.game_id=c.game_id AND g.id=c.group_id
            AND g.game_uuid=c.game_uuid AND g.group_uuid=c.group_uuid)<>1)) THEN RAISE EXCEPTION 'B6B_FINAL_GAME_CATEGORY_GROUP_IDENTITY_INVALID'; END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_attribute WHERE attrelid='public.marker_categories'::pg_catalog.regclass AND attnum>0 AND NOT attisdropped)<>18
       OR EXISTS (SELECT 1 FROM (VALUES ('category_uuid',true,'gen_random_uuid()'::text),('group_uuid',false,NULL::text)) e(name,nn,def)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
        WHERE a.attrelid='public.marker_categories'::pg_catalog.regclass AND a.attname=e.name AND a.atttypid='uuid'::pg_catalog.regtype
        AND a.attnotnull=e.nn AND a.attidentity='' AND a.attgenerated='' AND a.attacl IS NULL AND NOT a.attisdropped
        AND pg_catalog.pg_get_expr(d.adbin,d.adrelid) IS NOT DISTINCT FROM e.def)) THEN RAISE EXCEPTION 'B6B_FINAL_COLUMNS_INVALID'; END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_index WHERE indrelid='public.marker_categories'::pg_catalog.regclass)<>3
       OR EXISTS (SELECT 1 FROM (VALUES ('marker_categories_category_uuid_unique',ARRAY['category_uuid']::text[]),
        ('marker_categories_legacy_uuid_identity_unique',ARRAY['game_id','id','game_uuid','category_uuid'])) e(name,cols)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
        JOIN pg_catalog.pg_class x ON x.oid=i.indexrelid JOIN pg_catalog.pg_am am ON am.oid=x.relam
        WHERE c.conrelid='public.marker_categories'::pg_catalog.regclass AND c.conname=e.name AND c.contype='u' AND c.convalidated
        AND NOT c.condeferrable AND NOT c.condeferred AND i.indisunique AND i.indimmediate AND i.indisvalid AND i.indisready AND i.indislive
        AND am.amname='btree' AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnatts=i.indnkeyatts AND i.indnkeyatts=pg_catalog.cardinality(e.cols)
        AND ARRAY(SELECT k FROM pg_catalog.unnest(i.indkey) k)=c.conkey
        AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(n,pos)
            JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.n ORDER BY k.pos)=e.cols)) THEN RAISE EXCEPTION 'B6B_FINAL_UNIQUE_INDEX_INVALID'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conrelid='public.marker_categories'::pg_catalog.regclass
        AND conname='marker_categories_group_uuid_pair_check' AND contype='c' AND convalidated
        AND pg_catalog.pg_get_expr(conbin,conrelid)=
            '(((group_id IS NULL) AND (group_uuid IS NULL)) OR ((group_id IS NOT NULL) AND (group_uuid IS NOT NULL)))')
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.marker_categories'::pg_catalog.regclass
        AND c.conname='marker_categories_legacy_uuid_group_fk' AND c.contype='f' AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
        AND c.confrelid='public.marker_category_groups'::pg_catalog.regclass AND c.confmatchtype='s' AND c.confupdtype='c' AND c.confdeltype='r'
        AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(n,pos)
            JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.n ORDER BY k.pos)=ARRAY['game_id','group_id','game_uuid','group_uuid']::text[]
        AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(n,pos)
            JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.n ORDER BY k.pos)=ARRAY['game_id','id','game_uuid','group_uuid']::text[]) THEN RAISE EXCEPTION 'B6B_FINAL_PAIR_OR_GROUP_FK_INVALID'; END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid IN ('public.marcadores'::pg_catalog.regclass,
        'public.marker_submissions'::pg_catalog.regclass,'private.marker_submission_revisions'::pg_catalog.regclass,'public.user_notifications'::pg_catalog.regclass)
        AND attnum>0 AND NOT attisdropped AND attname IN ('category_uuid','group_uuid'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname IN ('public','private') AND p.proname ~ '^deepmap_resolve_(marker|submission|notification|revision)_(category|group)_identity$') THEN
        RAISE EXCEPTION 'B6B_FINAL_SCOPE_EXCEEDS_PRE_B6C'; END IF;
END;
$bridge$;
COMMIT;
