-- DeepMap B6a: permanent group identity; legacy consumers remain unchanged.
-- Manual review/application only. No UPDATE fill, no category UUID bridge.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = pg_catalog;
DO $dependencies$
BEGIN
    IF EXISTS (SELECT 1 FROM (VALUES ('public.games'),('private.game_legacy_identifiers'),
        ('public.marker_category_groups'),('public.marker_categories')) e(name)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
            WHERE c.oid=pg_catalog.to_regclass(e.name) AND c.relkind='r' AND c.relrowsecurity)) THEN
        RAISE EXCEPTION 'B6A_REQUIRES_ORDINARY_RLS_TABLES';
    END IF;
END;
$dependencies$;
-- Parent-first: stabilize game context, then DDL target, then legacy child.
-- SHARE parents/child blocks writers for exact row snapshots, permits readers.
-- Groups ACCESS EXCLUSIVE is required by volatile ADD COLUMN/default rewrite
-- and UNIQUE creation. No locks on unrelated content/submissions tables.
LOCK TABLE public.games IN SHARE MODE;
LOCK TABLE private.game_legacy_identifiers IN SHARE MODE;
LOCK TABLE public.marker_category_groups IN ACCESS EXCLUSIVE MODE;
LOCK TABLE public.marker_categories IN SHARE MODE;
DO $identity$
DECLARE
    v_old_body text := pg_catalog.replace($b2a_body$
DECLARE
    v_game_uuid uuid;
BEGIN
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
$b2a_body$,pg_catalog.chr(13),'');
    v_new_body text := pg_catalog.replace($b6a_body$
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
    v_function oid := pg_catalog.to_regprocedure('private.deepmap_resolve_category_group_identity()');
    v_function_before jsonb;
    v_before jsonb;
    v_after jsonb;
    v_groups_before jsonb;
    v_categories_before jsonb;
    v_games_before jsonb;
    v_mapping_before jsonb;
    v_rows bigint;
    v_catalog text := $catalog$
        WITH rels AS (SELECT pg_catalog.to_regclass(e.name) AS oid FROM (VALUES
            ('public.games'),('private.game_legacy_identifiers'),('public.marker_category_groups'),('public.marker_categories')) e(name)),
        added AS (SELECT c.oid,c.conindid FROM pg_catalog.pg_constraint c
            WHERE c.conrelid='public.marker_category_groups'::pg_catalog.regclass
              AND c.conname IN ('marker_category_groups_group_uuid_unique','marker_category_groups_legacy_uuid_identity_unique'))
        SELECT pg_catalog.jsonb_build_object(
            'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attrelid,a.attnum)
                FROM pg_catalog.pg_attribute a WHERE a.attrelid IN (SELECT oid FROM rels) AND a.attnum>0
                AND NOT (a.attrelid='public.marker_category_groups'::pg_catalog.regclass AND a.attname='group_uuid')),
            'defaults',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.adrelid,d.adnum)
                FROM pg_catalog.pg_attrdef d JOIN pg_catalog.pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
                WHERE d.adrelid IN (SELECT oid FROM rels)
                AND NOT (a.attrelid='public.marker_category_groups'::pg_catalog.regclass AND a.attname='group_uuid')),
            'constraints',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid)
                FROM pg_catalog.pg_constraint c WHERE (c.conrelid IN (SELECT oid FROM rels) OR c.confrelid IN (SELECT oid FROM rels))
                AND c.oid NOT IN (SELECT oid FROM added)
                AND NOT (c.conrelid='public.marker_category_groups'::pg_catalog.regclass AND c.contype='n'
                  AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=c.conrelid AND attname='group_uuid')]::smallint[])),
            'indexes',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.indexrelid)
                FROM pg_catalog.pg_index i WHERE i.indrelid IN (SELECT oid FROM rels) AND i.indexrelid NOT IN (SELECT conindid FROM added)),
            'index_objects',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('oid',c.oid,'name',c.relname,
                'namespace',c.relnamespace,'owner',c.relowner,'acl',c.relacl,'am',c.relam,'options',c.reloptions,
                'definition',pg_catalog.pg_get_indexdef(c.oid)) ORDER BY c.oid)
                FROM pg_catalog.pg_class c JOIN pg_catalog.pg_index i ON i.indexrelid=c.oid
                WHERE i.indrelid IN (SELECT oid FROM rels) AND i.indexrelid NOT IN (SELECT conindid FROM added)),
            'security',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('oid',c.oid,'name',c.relname,'namespace',c.relnamespace,
                'owner',c.relowner,'acl',c.relacl,'kind',c.relkind,'persistence',c.relpersistence,'rls',c.relrowsecurity,
                'force',c.relforcerowsecurity,'options',c.reloptions,'replica_identity',c.relreplident) ORDER BY c.oid)
                FROM pg_catalog.pg_class c WHERE c.oid IN (SELECT oid FROM rels)),
            'policies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid) FROM pg_catalog.pg_policy p WHERE p.polrelid IN (SELECT oid FROM rels)),
            'triggers',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY t.oid) FROM pg_catalog.pg_trigger t WHERE t.tgrelid IN (SELECT oid FROM rels)),
            'rules',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) ORDER BY r.oid) FROM pg_catalog.pg_rewrite r WHERE r.ev_class IN (SELECT oid FROM rels)),
            'namespaces',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(n) ORDER BY n.oid) FROM pg_catalog.pg_namespace n WHERE n.nspname IN ('public','private')),
            'functions',(SELECT pg_catalog.jsonb_agg(CASE WHEN p.oid=$1 THEN pg_catalog.to_jsonb(p)-'prosrc' ELSE pg_catalog.to_jsonb(p) END ORDER BY p.oid)
                FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private')))
$catalog$;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
        WHERE c.oid IN ('public.games'::pg_catalog.regclass,'private.game_legacy_identifiers'::pg_catalog.regclass,
            'public.marker_category_groups'::pg_catalog.regclass,'public.marker_categories'::pg_catalog.regclass)
        AND (NOT pg_catalog.has_table_privilege(c.oid,'SELECT') OR NOT pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
             OR NOT (r.rolsuper OR r.rolbypassrls OR (r.oid=c.relowner AND NOT c.relforcerowsecurity)))) THEN
        RAISE EXCEPTION 'B6A_FULL_MAINTENANCE_VISIBILITY_REQUIRED';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
        WHERE c.oid='public.marker_category_groups'::pg_catalog.regclass AND (r.rolsuper OR pg_catalog.pg_has_role(r.oid,c.relowner,'USAGE')))
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
        WHERE p.oid=v_function AND (r.rolsuper OR pg_catalog.pg_has_role(r.oid,p.proowner,'USAGE'))) THEN
        RAISE EXCEPTION 'B6A_DDL_OWNERSHIP_REQUIRED';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pg_catalog.gen_random_uuid()')
        AND p.prorettype='uuid'::pg_catalog.regtype AND p.pronargs=0 AND p.provolatile='v'
        AND NOT p.prosecdef AND NOT p.proretset AND pg_catalog.has_function_privilege(p.oid,'EXECUTE')) THEN
        RAISE EXCEPTION 'B6A_CORE_UUID_GENERATOR_REQUIRED';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname IN ('authenticated','service_role')
        AND (pg_catalog.has_any_column_privilege(r.oid,'public.marker_category_groups','INSERT')
            OR pg_catalog.has_any_column_privilege(r.oid,'public.marker_category_groups','UPDATE'))
        AND (NOT pg_catalog.has_schema_privilege(r.oid,'pg_catalog','USAGE')
            OR NOT pg_catalog.has_function_privilege(r.oid,'pg_catalog.gen_random_uuid()','EXECUTE'))) THEN
        RAISE EXCEPTION 'B6A_LEGACY_WRITER_UUID_GENERATOR_ACCESS_REQUIRED';
    END IF;
    IF EXISTS (WITH expected(name,type_name,default_expr) AS (VALUES
        ('game_id','text',NULL::text),('id','text',NULL),('name_en','text',NULL),('name_pt','text',NULL),
        ('sort_order','integer','0'),('is_active','boolean','true'),('created_at','timestamptz','now()'),
        ('updated_at','timestamptz','now()'),('game_uuid','uuid',NULL)),
        actual AS (SELECT a.*,pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS default_expr FROM pg_catalog.pg_attribute a
            LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
            WHERE a.attrelid='public.marker_category_groups'::pg_catalog.regclass AND a.attnum>0 AND NOT a.attisdropped)
        SELECT 1 FROM expected e FULL JOIN actual a ON a.attname=e.name WHERE e.name IS NULL OR a.attname IS NULL
        OR a.atttypid<>pg_catalog.to_regtype(e.type_name) OR NOT a.attnotnull OR a.attidentity<>'' OR a.attgenerated<>''
        OR a.default_expr IS DISTINCT FROM e.default_expr) THEN
        RAISE EXCEPTION 'B6A_GROUP_BASELINE_COLUMNS_DRIFT_OR_PARTIAL_STATE';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conrelid='public.marker_category_groups'::pg_catalog.regclass
        AND (conname IN ('marker_category_groups_group_uuid_unique','marker_category_groups_legacy_uuid_identity_unique') OR contype='u'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_class WHERE relnamespace='public'::pg_catalog.regnamespace
        AND relname IN ('marker_category_groups_group_uuid_unique','marker_category_groups_legacy_uuid_identity_unique'))
       OR (SELECT count(*) FROM pg_catalog.pg_index WHERE indrelid='public.marker_category_groups'::pg_catalog.regclass)<>1
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_inherits WHERE inhrelid='public.marker_category_groups'::pg_catalog.regclass
           OR inhparent='public.marker_category_groups'::pg_catalog.regclass)
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_rewrite WHERE ev_class='public.marker_category_groups'::pg_catalog.regclass) THEN
        RAISE EXCEPTION 'B6A_UNEXPECTED_GROUP_KEYS_INDEXES_RULES_OR_PARTIAL_STATE';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_constraint WHERE conrelid='public.marker_category_groups'::pg_catalog.regclass AND contype IN ('p','c','f','u','x'))<>3
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
        JOIN pg_catalog.pg_class x ON x.oid=i.indexrelid JOIN pg_catalog.pg_am am ON am.oid=x.relam
        WHERE c.conrelid='public.marker_category_groups'::pg_catalog.regclass AND c.conname='marker_category_groups_pkey'
        AND c.contype='p' AND c.conkey=ARRAY[1,2]::smallint[] AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
        AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive AND i.indimmediate AND am.amname='btree'
        AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnkeyatts=2 AND i.indnatts=2)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.marker_category_groups'::pg_catalog.regclass
        AND c.conname='marker_category_groups_id_format' AND c.contype='c' AND c.convalidated
        AND pg_catalog.pg_get_expr(c.conbin,c.conrelid)='(id ~ ''^[a-z0-9]+(?:[_-][a-z0-9]+)*$''::text)') THEN
        RAISE EXCEPTION 'B6A_LEGACY_GROUP_PK_OR_CHECK_DRIFT';
    END IF;
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.marker_category_groups','marker_category_groups_legacy_game_uuid_fk','private.game_legacy_identifiers',ARRAY['game_id','game_uuid']::text[],ARRAY['legacy_identifier','game_id']::text[],'a','r'),
        ('public.marker_categories','marker_categories_group_fk','public.marker_category_groups',ARRAY['game_id','group_id'],ARRAY['game_id','id'],'c','n'),
        ('private.game_legacy_identifiers','game_legacy_identifiers_game_id_fkey','public.games',ARRAY['game_id'],ARRAY['id'],'a','r')) e(rel,name,parent,cols,parent_cols,upd,del)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass(e.rel)
        AND c.conname=e.name AND c.contype='f' AND c.confrelid=pg_catalog.to_regclass(e.parent)
        AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred AND c.confmatchtype='s'
        AND c.confupdtype::text=e.upd AND c.confdeltype::text=e.del
        AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(n,pos)
            JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.n ORDER BY k.pos)=e.cols
        AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(n,pos)
            JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.n ORDER BY k.pos)=e.parent_cols)) THEN
        RAISE EXCEPTION 'B6A_GAME_OR_CATEGORY_GROUP_FK_DRIFT';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_constraint WHERE confrelid='public.marker_category_groups'::pg_catalog.regclass
        AND contype='f')<>1 THEN RAISE EXCEPTION 'B6A_UNEXPECTED_GROUP_INCOMING_FK'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid='public.marker_categories'::pg_catalog.regclass
        AND attname='game_uuid' AND atttypid='uuid'::pg_catalog.regtype AND attnotnull AND NOT attisdropped)
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid IN ('public.marker_categories'::pg_catalog.regclass,
            'public.marcadores'::pg_catalog.regclass,'public.marker_submissions'::pg_catalog.regclass,
            'private.marker_submission_revisions'::pg_catalog.regclass,'public.user_notifications'::pg_catalog.regclass)
        AND attnum>0 AND NOT attisdropped AND attname IN ('category_uuid','group_uuid')) THEN
        RAISE EXCEPTION 'B6A_REQUIRES_PRE_B6B_SCOPE';
    END IF;
    SELECT pg_catalog.to_jsonb(p) INTO STRICT v_function_before FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=v_function AND p.pronargs=0 AND p.prorettype='trigger'::pg_catalog.regtype AND l.lanname='plpgsql'
        AND NOT p.prosecdef AND p.proconfig=ARRAY['search_path=""']::text[] AND p.provolatile='v' AND p.proparallel='u'
        AND NOT p.proretset AND NOT p.proisstrict AND NOT p.proleakproof AND p.procost=100
        AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=v_old_body;
    IF (SELECT count(*) FROM pg_catalog.pg_proc WHERE pronamespace='private'::pg_catalog.regnamespace
        AND proname='deepmap_resolve_category_group_identity')<>1
       OR (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgrelid='public.marker_category_groups'::pg_catalog.regclass AND NOT tgisinternal)<>2
       OR EXISTS (SELECT 1 FROM (VALUES ('deepmap_category_groups_identity',23,'private.deepmap_resolve_category_group_identity()'),
            ('deepmap_category_groups_touch_updated_at',19,'private.deepmap_touch_updated_at()')) e(name,kind,signature)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.marker_category_groups'::pg_catalog.regclass
        AND t.tgname=e.name AND t.tgtype=e.kind AND t.tgfoid=pg_catalog.to_regprocedure(e.signature)
        AND NOT t.tgisinternal AND t.tgenabled='O' AND t.tgnargs=0 AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL))
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
        AND NOT p.prosecdef AND p.prorettype='trigger'::pg_catalog.regtype
        AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=pg_catalog.replace($touch$
begin
    new.updated_at := now();
    return new;
end;
$touch$,pg_catalog.chr(13),'')) THEN RAISE EXCEPTION 'B6A_GROUP_TRIGGER_OR_TOUCH_DRIFT'; END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_policy WHERE polrelid='public.marker_category_groups'::pg_catalog.regclass)<>2
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.marker_category_groups'::pg_catalog.regclass
        AND polname='marker_category_groups_public_read' AND polcmd='r' AND polpermissive
        AND ARRAY(SELECT r.rolname::text FROM pg_catalog.unnest(polroles) x(oid)
            JOIN pg_catalog.pg_roles r ON r.oid=x.oid ORDER BY r.rolname COLLATE "C")=ARRAY['anon','authenticated']::text[]
        AND pg_catalog.pg_get_expr(polqual,polrelid)='(is_active = true)' AND polwithcheck IS NULL)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.marker_category_groups'::pg_catalog.regclass
        AND polname='marker_category_groups_admin_all' AND polcmd='*' AND polpermissive
        AND polroles=ARRAY['authenticated'::pg_catalog.regrole::oid]
        AND pg_catalog.pg_get_expr(polqual,polrelid)='private.is_deepmap_admin()'
        AND pg_catalog.pg_get_expr(polwithcheck,polrelid)='private.is_deepmap_admin()') THEN
        RAISE EXCEPTION 'B6A_GROUP_POLICY_DRIFT';
    END IF;
    IF NOT pg_catalog.has_table_privilege('anon','public.marker_category_groups','SELECT')
       OR EXISTS (SELECT 1 FROM (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE')) e(privilege)
            WHERE NOT pg_catalog.has_table_privilege('authenticated','public.marker_category_groups',e.privilege)) THEN
        RAISE EXCEPTION 'B6A_LEGACY_GROUP_GRANTS_REQUIRED';
    END IF;
    IF EXISTS (SELECT 1 FROM public.marker_category_groups g WHERE
        (SELECT count(*) FROM private.game_legacy_identifiers i JOIN public.games p ON p.id=i.game_id
            WHERE i.legacy_identifier=g.game_id AND i.game_id=g.game_uuid)<>1) THEN
        RAISE EXCEPTION 'B6A_GROUP_GAME_CONTEXT_INVALID';
    END IF;
    SELECT count(*),COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(g) ORDER BY g.game_id,g.id),'[]'::jsonb)
        INTO v_rows,v_groups_before FROM public.marker_category_groups g;
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.game_id,c.id),'[]'::jsonb) INTO v_categories_before FROM public.marker_categories c;
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(g) ORDER BY g.id),'[]'::jsonb) INTO v_games_before FROM public.games g;
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.legacy_identifier),'[]'::jsonb) INTO v_mapping_before FROM private.game_legacy_identifiers i;
    EXECUTE v_catalog INTO v_before USING v_function;
    -- First persistent mutation. VOLATILE default evaluates per existing row;
    -- PostgreSQL rewrites storage without row INSERT/UPDATE trigger events.
    ALTER TABLE public.marker_category_groups ADD COLUMN group_uuid uuid NOT NULL DEFAULT pg_catalog.gen_random_uuid();
    ALTER TABLE public.marker_category_groups
        ADD CONSTRAINT marker_category_groups_group_uuid_unique UNIQUE (group_uuid) NOT DEFERRABLE,
        ADD CONSTRAINT marker_category_groups_legacy_uuid_identity_unique UNIQUE (game_id,id,game_uuid,group_uuid) NOT DEFERRABLE;
    -- CREATE OR REPLACE keeps function OID/owner/ACL and existing trigger target.
    EXECUTE pg_catalog.format('CREATE OR REPLACE FUNCTION private.deepmap_resolve_category_group_identity()
        RETURNS trigger LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE CALLED ON NULL INPUT SECURITY INVOKER
        COST 100 SET search_path = %L AS %L','',v_new_body);
    EXECUTE v_catalog INTO v_after USING v_function;
    IF v_after IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'B6A_UNAPPROVED_CATALOG_CHANGE'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_function
        AND pg_catalog.to_jsonb(p)-'prosrc'=v_function_before-'prosrc'
        AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=v_new_body) THEN
        RAISE EXCEPTION 'B6A_RESOLVER_REPLACEMENT_DRIFT';
    END IF;
    IF (SELECT count(*) FROM public.marker_category_groups)<>v_rows
       OR (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(g)-'group_uuid' ORDER BY g.game_id,g.id),'[]'::jsonb)
           FROM public.marker_category_groups g) IS DISTINCT FROM v_groups_before
       OR (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.game_id,c.id),'[]'::jsonb)
           FROM public.marker_categories c) IS DISTINCT FROM v_categories_before
       OR (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(g) ORDER BY g.id),'[]'::jsonb)
           FROM public.games g) IS DISTINCT FROM v_games_before
       OR (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.legacy_identifier),'[]'::jsonb)
           FROM private.game_legacy_identifiers i) IS DISTINCT FROM v_mapping_before THEN
        RAISE EXCEPTION 'B6A_LEGACY_ROWS_OR_TIMESTAMPS_CHANGED';
    END IF;
    IF (SELECT count(DISTINCT group_uuid) FROM public.marker_category_groups)<>v_rows
       OR EXISTS (SELECT 1 FROM public.marker_category_groups g WHERE g.group_uuid IS NULL OR
        (SELECT count(*) FROM private.game_legacy_identifiers i JOIN public.games p ON p.id=i.game_id
            WHERE i.legacy_identifier=g.game_id AND i.game_id=g.game_uuid)<>1)
       OR (SELECT count(*) FROM pg_catalog.pg_attribute WHERE attrelid='public.marker_category_groups'::pg_catalog.regclass AND attnum>0 AND NOT attisdropped)<>10
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
        WHERE a.attrelid='public.marker_category_groups'::pg_catalog.regclass AND a.attname='group_uuid'
        AND a.atttypid='uuid'::pg_catalog.regtype AND a.attnotnull AND a.attidentity='' AND a.attgenerated=''
        AND pg_catalog.pg_get_expr(d.adbin,d.adrelid)='gen_random_uuid()') THEN
        RAISE EXCEPTION 'B6A_FINAL_GROUP_UUID_OR_GAME_CONTEXT_INVALID';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_index WHERE indrelid='public.marker_category_groups'::pg_catalog.regclass)<>3
       OR EXISTS (SELECT 1 FROM (VALUES ('marker_category_groups_group_uuid_unique',ARRAY['group_uuid']::text[]),
            ('marker_category_groups_legacy_uuid_identity_unique',ARRAY['game_id','id','game_uuid','group_uuid'])) e(name,cols)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
        JOIN pg_catalog.pg_class x ON x.oid=i.indexrelid JOIN pg_catalog.pg_am am ON am.oid=x.relam
        WHERE c.conrelid='public.marker_category_groups'::pg_catalog.regclass AND c.conname=e.name AND c.contype='u'
        AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred AND i.indisunique AND i.indisvalid
        AND i.indisready AND i.indislive AND i.indimmediate AND am.amname='btree'
        AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnatts=i.indnkeyatts AND i.indnkeyatts=pg_catalog.cardinality(e.cols)
        AND ARRAY(SELECT k FROM pg_catalog.unnest(i.indkey) k)=c.conkey
        AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(n,pos)
            JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.n ORDER BY k.pos)=e.cols)) THEN
        RAISE EXCEPTION 'B6A_FINAL_UNIQUE_SUPPORT_INDEX_INVALID';
    END IF;
END;
$identity$;
COMMIT;
