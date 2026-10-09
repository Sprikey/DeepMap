-- DeepMap B3: parallel game/layer UUID references for legacy map labels.
-- Manual review/execution only. Current clients keep using TEXT identifiers.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = pg_catalog;

DO $dependencies$
BEGIN
    IF EXISTS (SELECT 1 FROM (VALUES
        ('private.game_legacy_identifiers'),('public.map_layers'),('public.map_labels'),
        ('public.games'),('public.game_maps')) e(name)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
            WHERE c.oid=pg_catalog.to_regclass(e.name) AND c.relkind='r' AND c.relrowsecurity)) THEN
        RAISE EXCEPTION 'B3_REQUIRES_ORDINARY_RLS_TABLES';
    END IF;
    IF pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()') IS NULL
       OR pg_catalog.to_regprocedure('private.is_deepmap_admin()') IS NULL
       OR pg_catalog.to_regprocedure('public.get_deepmap_role()') IS NULL THEN
        RAISE EXCEPTION 'B3_REQUIRED_FUNCTION_MISSING';
    END IF;
END;
$dependencies$;

-- Parent-first, as in B1/B2. SHARE ROW EXCLUSIVE stabilizes aliases/layers
-- against DML and conflicting DDL while permitting ordinary SELECTs. These
-- parents also need this mode for ADD FOREIGN KEY. Labels need ACCESS EXCLUSIVE
-- for columns/NOT NULL; acquire once before snapshots to serialize writers.
LOCK TABLE private.game_legacy_identifiers IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.map_layers IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.map_labels IN ACCESS EXCLUSIVE MODE;

DO $bridge$
DECLARE
    v_labels oid := 'public.map_labels'::pg_catalog.regclass;
    v_rows bigint;
    v_affected bigint;
    v_legacy_data jsonb;
    v_columns jsonb;
    v_defaults jsonb;
    v_constraints jsonb;
    v_indexes jsonb;
    v_triggers jsonb;
    v_touch_function jsonb;
    v_policies jsonb;
    v_security jsonb;
    v_adjacent_columns jsonb;
    v_layer_data jsonb;
    v_layer_constraints jsonb;
    v_relation text;
    v_name text;
    v_kind text;
    v_columns_expected text[];
    v_target text;
    v_target_columns text[];
    v_update text;
    v_delete text;
BEGIN
    IF EXISTS (
        WITH expected(name,type_oid,identity_kind,default_expr) AS (VALUES
            ('id','bigint'::pg_catalog.regtype,'d',NULL::text),
            ('game_id','text'::pg_catalog.regtype,'',NULL::text),
            ('map_layer','text'::pg_catalog.regtype,'','''surface''::text'),
            ('slug','text'::pg_catalog.regtype,'',NULL::text),
            ('text_en','text'::pg_catalog.regtype,'',NULL::text),
            ('text_pt','text'::pg_catalog.regtype,'',NULL::text),
            ('coordinate_x','double precision'::pg_catalog.regtype,'',NULL::text),
            ('coordinate_y','double precision'::pg_catalog.regtype,'',NULL::text),
            ('font_size','integer'::pg_catalog.regtype,'','34'),
            ('font_weight','integer'::pg_catalog.regtype,'','700'),
            ('color','text'::pg_catalog.regtype,'','''#E8D7A4''::text'),
            ('opacity','double precision'::pg_catalog.regtype,'','0.82'),
            ('uppercase','boolean'::pg_catalog.regtype,'','true'),
            ('is_published','boolean'::pg_catalog.regtype,'','false'),
            ('created_at','timestamptz'::pg_catalog.regtype,'','now()'),
            ('updated_at','timestamptz'::pg_catalog.regtype,'','now()')
        ), actual AS (
            SELECT a.attname::text AS name,a.atttypid,a.attnotnull,a.attidentity::text,
                a.attgenerated,pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS default_expr
            FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d
              ON d.adrelid=a.attrelid AND d.adnum=a.attnum
            WHERE a.attrelid=v_labels AND a.attnum>0 AND NOT a.attisdropped
        ) SELECT 1 FROM expected e FULL JOIN actual a USING(name)
        WHERE e.name IS NULL OR a.name IS NULL OR a.atttypid<>e.type_oid OR NOT a.attnotnull
           OR a.attidentity<>e.identity_kind OR a.attgenerated<>''
           OR (CASE WHEN e.name='opacity' THEN replace(replace(
               regexp_replace(a.default_expr,'[[:space:]()]','','g'),'::doubleprecision',''),'''','')
               ELSE a.default_expr END) IS DISTINCT FROM e.default_expr
    ) THEN
        RAISE EXCEPTION 'B3_UNEXPECTED_LABEL_COLUMNS_DEFAULTS_OR_PARTIAL_STATE';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_catalog.pg_inherits WHERE inhrelid=v_labels OR inhparent=v_labels)
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_rewrite WHERE ev_class=v_labels)
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='private' AND p.proname='deepmap_resolve_map_label_identity')
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conrelid=v_labels
           AND conname IN ('map_labels_legacy_game_uuid_fk','map_labels_legacy_uuid_layer_fk')) THEN
        RAISE EXCEPTION 'B3_UNEXPECTED_RULE_INHERITANCE_OR_EXISTING_BRIDGE';
    END IF;

    -- Verify exact keys and support indexes, never recreate parent keys.
    FOR v_relation,v_name,v_kind,v_columns_expected IN SELECT * FROM (VALUES
        ('public.map_labels',NULL::text,'p',ARRAY['id']::text[]),
        ('public.map_labels','map_labels_game_slug_unique','u',ARRAY['game_id','slug']::text[]),
        ('public.map_layers',NULL::text,'p',ARRAY['game_id','id']::text[]),
        ('public.map_layers','map_layers_layer_uuid_unique','u',ARRAY['layer_uuid']::text[]),
        ('public.map_layers','map_layers_legacy_uuid_identity_unique','u',ARRAY['game_id','id','game_uuid','layer_uuid']::text[]),
        ('private.game_legacy_identifiers','game_legacy_identifiers_identifier_game_unique','u',ARRAY['legacy_identifier','game_id']::text[]),
        ('public.game_maps','game_maps_id_game_unique','u',ARRAY['id','game_id']::text[])
    ) e(relation_name,name,kind,cols)
    LOOP
        IF (SELECT count(*) FROM pg_catalog.pg_constraint c
            WHERE c.conrelid=pg_catalog.to_regclass(v_relation) AND c.contype::text=v_kind
              AND (v_name IS NULL OR c.conname=v_name))<>1
           OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
            WHERE c.conrelid=pg_catalog.to_regclass(v_relation) AND c.contype::text=v_kind
              AND (v_name IS NULL OR c.conname=v_name)
              AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
              AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
              AND i.indpred IS NULL AND i.indexprs IS NULL
              AND i.indnkeyatts=cardinality(v_columns_expected) AND i.indnatts=i.indnkeyatts
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey)
                  WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                  ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=v_columns_expected) THEN
            RAISE EXCEPTION 'B3_INVALID_REQUIRED_KEY: %.%',v_relation,COALESCE(v_name,'PK');
        END IF;
    END LOOP;

    IF EXISTS (SELECT 1 FROM (VALUES ('private.game_legacy_identifiers'),('public.game_maps')) e(rel)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND c.contype='f'
              AND c.confrelid='public.games'::pg_catalog.regclass
              AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
              AND c.confupdtype='a' AND c.confdeltype='r'
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey)
                  WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                  ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=ARRAY['game_id']::text[]
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey)
                  WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                  ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)=ARRAY['id']::text[])) THEN
        RAISE EXCEPTION 'B3_INVALID_GAME_PARENT_FOREIGN_KEYS';
    END IF;

    FOR v_relation,v_name,v_columns_expected,v_target,v_target_columns,v_update,v_delete
        IN SELECT * FROM (VALUES
        ('public.map_labels','map_labels_layer_fk',ARRAY['game_id','map_layer']::text[],
            'public.map_layers',ARRAY['game_id','id']::text[],'c','a'),
        ('public.map_layers','map_layers_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
            'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[],'a','r'),
        ('public.map_layers','map_layers_game_map_game_fk',ARRAY['game_map_id','game_uuid']::text[],
            'public.game_maps',ARRAY['id','game_id']::text[],'a','r')
    ) e(relation_name,name,cols,target,target_cols,up,del)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            WHERE c.conrelid=pg_catalog.to_regclass(v_relation) AND c.conname=v_name AND c.contype='f'
              AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred AND c.confmatchtype='s'
              AND c.confrelid=pg_catalog.to_regclass(v_target)
              AND c.confupdtype::text=v_update AND c.confdeltype::text=v_delete
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey)
                  WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                  ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=v_columns_expected
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey)
                  WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                  ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)=v_target_columns) THEN
            RAISE EXCEPTION 'B3_INVALID_REQUIRED_FK: %',v_name;
        END IF;
    END LOOP;

    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.map_layers','game_id','text'::pg_catalog.regtype),
        ('public.map_layers','id','text'::pg_catalog.regtype),
        ('public.map_layers','game_uuid','uuid'::pg_catalog.regtype),
        ('public.map_layers','layer_uuid','uuid'::pg_catalog.regtype),
        ('public.map_layers','game_map_id','uuid'::pg_catalog.regtype),
        ('private.game_legacy_identifiers','legacy_identifier','text'::pg_catalog.regtype),
        ('private.game_legacy_identifiers','game_id','uuid'::pg_catalog.regtype),
        ('public.games','id','uuid'::pg_catalog.regtype),
        ('public.game_maps','id','uuid'::pg_catalog.regtype),
        ('public.game_maps','game_id','uuid'::pg_catalog.regtype)
    ) e(rel,name,type_oid) LEFT JOIN pg_catalog.pg_attribute a
        ON a.attrelid=pg_catalog.to_regclass(e.rel) AND a.attname=e.name AND a.attnum>0 AND NOT a.attisdropped
        WHERE a.attname IS NULL OR a.atttypid<>e.type_oid OR NOT a.attnotnull) THEN
        RAISE EXCEPTION 'B3_INVALID_PARENT_COLUMNS';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index i
        JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid
        WHERE i.indrelid=v_labels AND c.relname='map_labels_map_lookup_idx'
          AND i.indisvalid AND i.indisready AND i.indislive AND NOT i.indisunique
          AND i.indnkeyatts=4 AND i.indnatts=4 AND i.indpred IS NULL AND i.indexprs IS NULL
          AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(i.indkey::smallint[])
              WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
              ON a.attrelid=i.indrelid AND a.attnum=k.num ORDER BY k.pos)
              =ARRAY['game_id','map_layer','is_published','id']::text[]) THEN
        RAISE EXCEPTION 'B3_INVALID_LEGACY_LOOKUP_INDEX';
    END IF;
    -- Existing CHECKs are preserved verbatim below; require all five known checks.
    IF (SELECT count(*) FROM pg_catalog.pg_constraint WHERE conrelid=v_labels AND contype='c')<>5
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conrelid=v_labels AND contype='c'
           AND (NOT convalidated OR conname<>ALL(ARRAY['map_labels_slug_format',
               'map_labels_font_size_check','map_labels_font_weight_check','map_labels_color_check',
               'map_labels_opacity_check']))) THEN
        RAISE EXCEPTION 'B3_UNEXPECTED_LEGACY_CHECKS';
    END IF;
    IF EXISTS (SELECT 1 FROM (VALUES
        ('map_labels_font_size_check','font_size>=10andfont_size<=160'),
        ('map_labels_font_weight_check','font_weight>=100andfont_weight<=900'),
        ('map_labels_color_check','color~''^#[0-9a-fa-f]{6}$''::text'),
        ('map_labels_opacity_check','opacity>=0andopacity<=1'),
        ('map_labels_slug_format','slug~''^[a-z0-9]+?:-[a-z0-9]+*$''::text')
    ) e(name,expr) WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid=v_labels AND c.conname=e.name AND c.contype='c'
          AND (CASE WHEN e.name='map_labels_opacity_check' THEN replace(replace(
              lower(regexp_replace(pg_catalog.pg_get_expr(c.conbin,c.conrelid),'[[:space:]()]','','g')),
              '::doubleprecision',''),'''','') ELSE lower(regexp_replace(
              pg_catalog.pg_get_expr(c.conbin,c.conrelid),'[[:space:]()]','','g')) END)=e.expr)) THEN
        RAISE EXCEPTION 'B3_UNEXPECTED_LEGACY_CHECK_EXPRESSIONS';
    END IF;

    IF (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgrelid=v_labels AND NOT tgisinternal)<>1
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
           WHERE t.tgrelid=v_labels AND t.tgname='deepmap_map_labels_touch_updated_at'
             AND t.tgtype=19 AND t.tgenabled='O' AND NOT t.tgisinternal
             AND t.tgfoid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
             AND t.tgnargs=0 AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
           WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
             AND NOT p.prosecdef AND p.prorettype='trigger'::pg_catalog.regtype
             AND lower(regexp_replace(p.prosrc,'[[:space:]]','','g'))='beginnew.updated_at:=now();returnnew;end;') THEN
        RAISE EXCEPTION 'B3_UNEXPECTED_AUDIT_OR_TOUCH_TRIGGER';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c CROSS JOIN pg_catalog.pg_roles r
        WHERE r.rolname=CURRENT_USER AND c.oid IN (v_labels,
            'public.map_layers'::pg_catalog.regclass,'private.game_legacy_identifiers'::pg_catalog.regclass,
            'public.game_maps'::pg_catalog.regclass,'public.games'::pg_catalog.regclass)
        AND NOT (r.rolsuper OR r.rolbypassrls OR (c.relowner=r.oid AND NOT c.relforcerowsecurity))) THEN
        RAISE EXCEPTION 'B3_REQUIRES_FULL_MAINTENANCE_VISIBILITY';
    END IF;
    IF NOT pg_catalog.has_schema_privilege('authenticated','private','USAGE')
       OR NOT pg_catalog.has_table_privilege('authenticated','private.game_legacy_identifiers','SELECT')
       OR NOT pg_catalog.has_table_privilege('authenticated','public.map_layers','SELECT')
       OR NOT pg_catalog.has_function_privilege('authenticated','public.get_deepmap_role()','EXECUTE')
       OR NOT pg_catalog.has_function_privilege('authenticated','private.is_deepmap_admin()','EXECUTE') THEN
        RAISE EXCEPTION 'B3_INVOKER_PRIVILEGES_REQUIRE_REVIEW';
    END IF;
    -- Approved role helper uses the same admin predicate as legacy policies.
    -- The newer helper additionally denies banned accounts, as in B1/B2.
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid=pg_catalog.to_regprocedure('public.get_deepmap_role()')
          AND lower(regexp_replace(p.prosrc,'[[:space:]]','','g')) IN (
            'selectcasewhenprivate.is_deepmap_admin()then''admin''whenprivate.is_deepmap_moderator()then''moderator''else''user''end;',
            'selectcasewhenprivate.is_deepmap_banned()then''banned''whenprivate.is_deepmap_admin()then''admin''whenprivate.is_deepmap_moderator()then''moderator''else''user''end;')) THEN
        RAISE EXCEPTION 'B3_UNKNOWN_ADMIN_ROLE_HELPER_CONTRACT';
    END IF;
    -- Exact permissive admin policy predicates; unknown restrictive reads
    -- could hide mapping/layers from otherwise authorized Admin writers.
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p
        WHERE p.polrelid='private.game_legacy_identifiers'::pg_catalog.regclass
          AND p.polname='game_legacy_identifiers_admin_read' AND p.polcmd='r' AND p.polpermissive
          AND ('authenticated'::pg_catalog.regrole)::oid=ANY(p.polroles)
          AND regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'[[:space:]()]','','g') IN (
              'SELECTpublic.get_deepmap_roleASget_deepmap_role=''admin''::text',
              'SELECTget_deepmap_roleASget_deepmap_role=''admin''::text'))
       OR EXISTS (SELECT 1 FROM (VALUES ('public.map_layers','map_layers_admin_all'),
            ('public.map_labels','map_labels_admin_all')) e(rel,name)
            WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p
                WHERE p.polrelid=pg_catalog.to_regclass(e.rel) AND p.polname=e.name
                  AND p.polcmd='*' AND p.polpermissive
                  AND ('authenticated'::pg_catalog.regrole)::oid=ANY(p.polroles)
                  AND regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'[[:space:]()]','','g')='private.is_deepmap_admin'
                  AND regexp_replace(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),'[[:space:]()]','','g')='private.is_deepmap_admin'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_policy p
            WHERE p.polrelid IN ('private.game_legacy_identifiers'::pg_catalog.regclass,
                'public.map_layers'::pg_catalog.regclass) AND NOT p.polpermissive AND p.polcmd IN ('r','*')) THEN
        RAISE EXCEPTION 'B3_INVOKER_RLS_REQUIRES_REVIEW';
    END IF;

    IF EXISTS (SELECT 1 FROM public.map_labels c WHERE (
        SELECT count(*) FROM private.game_legacy_identifiers i
        JOIN public.games g ON g.id=i.game_id
        JOIN public.map_layers l ON l.game_id=i.legacy_identifier AND l.game_uuid=i.game_id
        JOIN public.game_maps m ON m.id=l.game_map_id AND m.game_id=l.game_uuid
        WHERE i.legacy_identifier=c.game_id AND l.id=c.map_layer AND l.layer_uuid IS NOT NULL)<>1
        OR (SELECT count(*) FROM private.game_legacy_identifiers i WHERE i.legacy_identifier=c.game_id)<>1) THEN
        RAISE EXCEPTION 'B3_LABEL_MAPPING_LAYER_OR_PARENT_INVALID';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attnum>0 AND NOT a.attisdropped AND (
            (a.attrelid IN ('public.marcadores'::pg_catalog.regclass,
                'public.marker_submissions'::pg_catalog.regclass,'public.user_notifications'::pg_catalog.regclass)
                AND a.attname IN ('game_uuid','layer_uuid'))
            OR (a.attrelid IN (v_labels,'public.map_layers'::pg_catalog.regclass,
                'public.marker_categories'::pg_catalog.regclass,'public.marker_category_groups'::pg_catalog.regclass,
                'public.marcadores'::pg_catalog.regclass,'public.marker_submissions'::pg_catalog.regclass,
                'public.user_notifications'::pg_catalog.regclass) AND a.attname IN ('category_uuid','group_uuid')))) THEN
        RAISE EXCEPTION 'B3_UNEXPECTED_PREMATURE_ADJACENT_UUID_COLUMNS';
    END IF;

    SELECT count(*),COALESCE(jsonb_agg(to_jsonb(c)-'updated_at' ORDER BY c.id),'[]'::jsonb)
        INTO v_rows,v_legacy_data FROM public.map_labels c;
    SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.attnum),'[]'::jsonb) INTO v_columns
        FROM pg_catalog.pg_attribute a WHERE a.attrelid=v_labels AND a.attnum>0;
    SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.adnum),'[]'::jsonb) INTO v_defaults
        FROM pg_catalog.pg_attrdef d WHERE d.adrelid=v_labels;
    SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.oid),'[]'::jsonb) INTO v_constraints
        FROM pg_catalog.pg_constraint c WHERE c.conrelid=v_labels;
    SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.indexrelid),'[]'::jsonb) INTO v_indexes
        FROM pg_catalog.pg_index i WHERE i.indrelid=v_labels;
    SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.oid),'[]'::jsonb) INTO v_triggers
        FROM pg_catalog.pg_trigger t WHERE t.tgrelid=v_labels;
    SELECT to_jsonb(p) INTO v_touch_function FROM pg_catalog.pg_proc p
        WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()');
    SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.oid),'[]'::jsonb) INTO v_policies
        FROM pg_catalog.pg_policy p WHERE p.polrelid=v_labels;
    SELECT jsonb_build_object('acl',c.relacl,'owner',c.relowner,'rls',c.relrowsecurity,'force',c.relforcerowsecurity)
        INTO v_security FROM pg_catalog.pg_class c WHERE c.oid=v_labels;
    SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.attrelid,a.attnum),'[]'::jsonb) INTO v_adjacent_columns
        FROM pg_catalog.pg_attribute a WHERE a.attnum>0 AND a.attrelid IN (
            'public.map_layers'::pg_catalog.regclass,'public.marker_categories'::pg_catalog.regclass,
            'public.marker_category_groups'::pg_catalog.regclass,'public.marcadores'::pg_catalog.regclass,
            'public.marker_submissions'::pg_catalog.regclass,'public.user_notifications'::pg_catalog.regclass);
    SELECT COALESCE(jsonb_agg(to_jsonb(l) ORDER BY l.game_id,l.id),'[]'::jsonb) INTO v_layer_data FROM public.map_layers l;
    SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.oid),'[]'::jsonb) INTO v_layer_constraints
        FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.map_layers'::pg_catalog.regclass;

    ALTER TABLE public.map_labels ADD COLUMN game_uuid uuid, ADD COLUMN layer_uuid uuid;

    EXECUTE $ddl$
    CREATE FUNCTION private.deepmap_resolve_map_label_identity()
    RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
    AS $function$
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
                    RAISE EXCEPTION 'B3_HYDRATION_MUST_PRESERVE_LEGACY_FIELDS';
                END IF;
            ELSIF OLD.game_uuid IS NULL OR OLD.layer_uuid IS NULL THEN
                RAISE EXCEPTION 'B3_PARTIAL_LABEL_IDENTITY';
            ELSE
                IF NEW.game_id IS DISTINCT FROM OLD.game_id
                   OR NEW.game_uuid IS DISTINCT FROM OLD.game_uuid THEN
                    RAISE EXCEPTION 'B3_LABEL_GAME_REASSIGNMENT_NOT_SUPPORTED';
                END IF;
                v_layer_changed := NEW.map_layer IS DISTINCT FROM OLD.map_layer;
                IF NOT v_layer_changed AND NEW.layer_uuid IS DISTINCT FROM OLD.layer_uuid THEN
                    RAISE EXCEPTION 'B3_LABEL_LAYER_UUID_CHANGE_REQUIRES_LEGACY_LAYER_CHANGE';
                END IF;
            END IF;
        ELSIF TG_OP<>'INSERT' THEN
            RAISE EXCEPTION 'B3_UNSUPPORTED_LABEL_TRIGGER_EVENT';
        END IF;
        BEGIN
            SELECT i.game_id INTO STRICT v_game FROM private.game_legacy_identifiers i
                WHERE i.legacy_identifier=NEW.game_id;
        EXCEPTION WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B3_LABEL_MAPPING_NOT_EXACTLY_ONE_VISIBLE_ROW';
        END;
        BEGIN
            SELECT l.layer_uuid,l.game_uuid INTO STRICT v_layer,v_layer_game
                FROM public.map_layers l WHERE l.game_id=NEW.game_id AND l.id=NEW.map_layer;
        EXCEPTION WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B3_LABEL_LAYER_NOT_EXACTLY_ONE_VISIBLE_ROW';
        END;
        IF v_layer IS NULL OR v_layer_game IS DISTINCT FROM v_game THEN
            RAISE EXCEPTION 'B3_LABEL_LAYER_GAME_MAPPING_MISMATCH';
        END IF;
        IF NEW.game_uuid IS NULL THEN NEW.game_uuid := v_game;
        ELSIF NEW.game_uuid IS DISTINCT FROM v_game THEN
            RAISE EXCEPTION 'B3_LABEL_LEGACY_GAME_UUID_MISMATCH';
        END IF;
        IF v_layer_changed THEN
            -- Legacy UPDATE carries OLD.layer_uuid without mentioning it.
            -- Accept that inherited value, NULL, or the correct supplied NEW
            -- identity; reject any other explicitly changed UUID.
            IF NEW.layer_uuid IS NOT NULL AND NEW.layer_uuid IS DISTINCT FROM OLD.layer_uuid
               AND NEW.layer_uuid IS DISTINCT FROM v_layer THEN
                RAISE EXCEPTION 'B3_LABEL_EXPLICIT_NEW_LAYER_UUID_MISMATCH';
            END IF;
            NEW.layer_uuid := v_layer;
        ELSIF NEW.layer_uuid IS NULL THEN NEW.layer_uuid := v_layer;
        ELSIF NEW.layer_uuid IS DISTINCT FROM v_layer THEN
            RAISE EXCEPTION 'B3_LABEL_LEGACY_LAYER_UUID_MISMATCH';
        END IF;
        RETURN NEW;
    END;
    $function$;
    $ddl$;

    CREATE TRIGGER deepmap_map_labels_identity BEFORE INSERT OR UPDATE ON public.map_labels
        FOR EACH ROW EXECUTE FUNCTION private.deepmap_resolve_map_label_identity();
    REVOKE ALL ON FUNCTION private.deepmap_resolve_map_label_identity() FROM PUBLIC,anon,authenticated;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='service_role') THEN
        REVOKE ALL ON FUNCTION private.deepmap_resolve_map_label_identity() FROM service_role;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
        WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_map_label_identity()')
          AND a.grantee<>p.proowner) THEN
        RAISE EXCEPTION 'B3_UNEXPECTED_DIRECT_FUNCTION_GRANTS';
    END IF;
    IF EXISTS (SELECT 1 FROM public.map_labels WHERE game_uuid IS NOT NULL OR layer_uuid IS NOT NULL) THEN
        RAISE EXCEPTION 'B3_UNEXPECTED_PARTIAL_HYDRATION_BEFORE_FILL';
    END IF;
    UPDATE public.map_labels c SET game_uuid=i.game_id,layer_uuid=l.layer_uuid
        FROM private.game_legacy_identifiers i JOIN public.map_layers l
          ON l.game_id=i.legacy_identifier AND l.game_uuid=i.game_id
        WHERE c.game_id=i.legacy_identifier AND c.map_layer=l.id
          AND c.game_uuid IS NULL AND c.layer_uuid IS NULL;
    GET DIAGNOSTICS v_affected=ROW_COUNT;
    IF v_affected<>v_rows THEN RAISE EXCEPTION 'B3_FILL_COUNT_MISMATCH'; END IF;

    ALTER TABLE public.map_labels
        ADD CONSTRAINT map_labels_legacy_game_uuid_fk FOREIGN KEY (game_id,game_uuid)
            REFERENCES private.game_legacy_identifiers(legacy_identifier,game_id)
            ON UPDATE NO ACTION ON DELETE RESTRICT NOT DEFERRABLE,
        ADD CONSTRAINT map_labels_legacy_uuid_layer_fk FOREIGN KEY (game_id,map_layer,game_uuid,layer_uuid)
            REFERENCES public.map_layers(game_id,id,game_uuid,layer_uuid)
            ON UPDATE NO ACTION ON DELETE RESTRICT NOT DEFERRABLE;
    ALTER TABLE public.map_labels ALTER COLUMN game_uuid SET NOT NULL, ALTER COLUMN layer_uuid SET NOT NULL;

    IF (SELECT count(*) FROM public.map_labels)<>v_rows
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(c)-ARRAY['game_uuid','layer_uuid','updated_at']::text[] ORDER BY c.id),'[]'::jsonb)
           FROM public.map_labels c) IS DISTINCT FROM v_legacy_data
       OR EXISTS (SELECT 1 FROM public.map_labels WHERE updated_at IS DISTINCT FROM pg_catalog.now())
       OR EXISTS (SELECT 1 FROM public.map_labels c WHERE c.game_uuid IS NULL OR c.layer_uuid IS NULL
           OR (SELECT count(*) FROM private.game_legacy_identifiers i JOIN public.map_layers l
               ON l.game_id=i.legacy_identifier AND l.game_uuid=i.game_id
               JOIN public.games g ON g.id=i.game_id
               JOIN public.game_maps m ON m.id=l.game_map_id AND m.game_id=l.game_uuid
               WHERE i.legacy_identifier=c.game_id AND i.game_id=c.game_uuid
                 AND l.id=c.map_layer AND l.layer_uuid=c.layer_uuid)<>1) THEN
        RAISE EXCEPTION 'B3_FINAL_LABEL_DATA_INVARIANTS_FAILED';
    END IF;
    IF (SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.attnum),'[]'::jsonb)
        FROM pg_catalog.pg_attribute a WHERE a.attrelid=v_labels AND a.attnum>0
        AND a.attname NOT IN ('game_uuid','layer_uuid')) IS DISTINCT FROM v_columns
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.adnum),'[]'::jsonb)
           FROM pg_catalog.pg_attrdef d WHERE d.adrelid=v_labels) IS DISTINCT FROM v_defaults
       OR (SELECT count(*) FROM pg_catalog.pg_attribute WHERE attrelid=v_labels
           AND attname IN ('game_uuid','layer_uuid') AND atttypid='uuid'::pg_catalog.regtype
           AND attnotnull AND NOT atthasdef AND NOT attisdropped AND attidentity='' AND attgenerated='')<>2
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.oid),'[]'::jsonb)
           FROM pg_catalog.pg_constraint c WHERE c.conrelid=v_labels
           AND c.conname NOT IN ('map_labels_legacy_game_uuid_fk','map_labels_legacy_uuid_layer_fk')
           -- PostgreSQL versions with catalogued NOT NULL constraints may add
           -- these implicitly for the two new columns; legacy ones stay checked.
           AND NOT (c.contype='n' AND c.conkey <@ ARRAY(SELECT a.attnum
               FROM pg_catalog.pg_attribute a WHERE a.attrelid=v_labels
               AND a.attname IN ('game_uuid','layer_uuid') AND NOT a.attisdropped))) IS DISTINCT FROM v_constraints
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.indexrelid),'[]'::jsonb)
           FROM pg_catalog.pg_index i WHERE i.indrelid=v_labels) IS DISTINCT FROM v_indexes
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.oid),'[]'::jsonb)
           FROM pg_catalog.pg_trigger t WHERE t.tgrelid=v_labels
           AND t.tgname<>'deepmap_map_labels_identity'
           AND NOT (t.tgisinternal AND t.tgconstraint IN (SELECT oid FROM pg_catalog.pg_constraint
               WHERE conrelid=v_labels AND conname IN ('map_labels_legacy_game_uuid_fk','map_labels_legacy_uuid_layer_fk')))) IS DISTINCT FROM v_triggers
       OR (SELECT to_jsonb(p) FROM pg_catalog.pg_proc p
           WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')) IS DISTINCT FROM v_touch_function
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.oid),'[]'::jsonb)
           FROM pg_catalog.pg_policy p WHERE p.polrelid=v_labels) IS DISTINCT FROM v_policies
       OR (SELECT jsonb_build_object('acl',c.relacl,'owner',c.relowner,'rls',c.relrowsecurity,'force',c.relforcerowsecurity)
           FROM pg_catalog.pg_class c WHERE c.oid=v_labels) IS DISTINCT FROM v_security
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.attrelid,a.attnum),'[]'::jsonb)
           FROM pg_catalog.pg_attribute a WHERE a.attnum>0 AND a.attrelid IN (
               'public.map_layers'::pg_catalog.regclass,'public.marker_categories'::pg_catalog.regclass,
               'public.marker_category_groups'::pg_catalog.regclass,'public.marcadores'::pg_catalog.regclass,
               'public.marker_submissions'::pg_catalog.regclass,'public.user_notifications'::pg_catalog.regclass)) IS DISTINCT FROM v_adjacent_columns
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(l) ORDER BY l.game_id,l.id),'[]'::jsonb) FROM public.map_layers l) IS DISTINCT FROM v_layer_data
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.oid),'[]'::jsonb)
           FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.map_layers'::pg_catalog.regclass) IS DISTINCT FROM v_layer_constraints THEN
        RAISE EXCEPTION 'B3_LEGACY_OR_ADJACENT_OBJECTS_CHANGED';
    END IF;

    FOR v_name,v_columns_expected,v_target,v_target_columns IN SELECT * FROM (VALUES
        ('map_labels_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
            'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[]),
        ('map_labels_legacy_uuid_layer_fk',ARRAY['game_id','map_layer','game_uuid','layer_uuid']::text[],
            'public.map_layers',ARRAY['game_id','id','game_uuid','layer_uuid']::text[])
    ) e(name,cols,target,target_cols)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            WHERE c.conrelid=v_labels AND c.conname=v_name AND c.contype='f'
              AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
              AND c.confupdtype='a' AND c.confdeltype='r' AND c.confmatchtype='s'
              AND c.confrelid=pg_catalog.to_regclass(v_target)
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey)
                  WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                  ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=v_columns_expected
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey)
                  WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                  ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)=v_target_columns) THEN
            RAISE EXCEPTION 'B3_INVALID_FINAL_FK: %',v_name;
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
        WHERE t.tgrelid=v_labels AND t.tgname='deepmap_map_labels_identity' AND t.tgtype=23
          AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgnargs=0 AND t.tgqual IS NULL
          AND t.tgattr=''::pg_catalog.int2vector
          AND t.tgfoid=pg_catalog.to_regprocedure('private.deepmap_resolve_map_label_identity()')
          AND NOT p.prosecdef AND p.prorettype='trigger'::pg_catalog.regtype AND p.proconfig=ARRAY['search_path=""']::text[]) THEN
        RAISE EXCEPTION 'B3_INVALID_FINAL_IDENTITY_TRIGGER';
    END IF;
END;
$bridge$;
COMMIT;
