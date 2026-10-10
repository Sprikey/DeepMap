-- DeepMap B6b: execute manually AFTER application, with maintenance visibility.
-- One read-only statement. No application/trigger/generator calls.
-- Historical timestamps/data/OIDs/ACL equality belongs to migration snapshots.
WITH
sources(name,signature,body) AS (VALUES
 ('category','private.deepmap_resolve_category_identity()',pg_catalog.replace($category_body$
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
$category_body$,pg_catalog.chr(13),'')),
 ('group','private.deepmap_resolve_category_group_identity()',pg_catalog.replace($group_body$
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
$group_body$,pg_catalog.chr(13),'')),
 ('touch','private.deepmap_touch_updated_at()',pg_catalog.replace($touch_body$
begin
    new.updated_at := now();
    return new;
end;
$touch_body$,pg_catalog.chr(13),''))
),
relations AS (
 SELECT e.name,c.* FROM (VALUES ('public.games'),('private.game_legacy_identifiers'),('public.marker_category_groups'),('public.marker_categories')) e(name)
 LEFT JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass(e.name)
),
visibility AS (
 SELECT c.name,COALESCE(c.relkind='r' AND c.relrowsecurity AND pg_catalog.has_table_privilege(c.oid,'SELECT')
 AND pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
 AND (r.rolsuper OR r.rolbypassrls OR (r.oid=c.relowner AND NOT c.relforcerowsecurity)),false) AS ok
 FROM relations c JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
),
full_visibility AS (SELECT pg_catalog.count(*)=4 AND COALESCE(pg_catalog.bool_and(ok),false) AS ok FROM visibility),
attributes AS (
 SELECT a.*,pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS default_expr FROM pg_catalog.pg_attribute a
 LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attnum>0 AND NOT a.attisdropped
),
expected_columns(name,type_name,nn,def) AS (VALUES
        ('game_id','text',true,NULL::text),('id','text',true,NULL),('group_id','text',false,NULL),
        ('name_en','text',true,NULL),('name_pt','text',true,NULL),('icon_source','text',true,'''none''::text'),
        ('icon_ref','text',false,NULL),('color','text',true,'''#777777''::text'),('marker_width','integer',false,NULL),
        ('marker_height','integer',false,NULL),('symbol_size','integer',false,NULL),('sort_order','integer',true,'0'),
        ('is_active','boolean',true,'true'),('created_at','timestamptz',true,'now()'),('updated_at','timestamptz',true,'now()'),('game_uuid','uuid',true,NULL),
 ('category_uuid','uuid',true,'gen_random_uuid()'),('group_uuid','uuid',false,NULL)
),
constraints AS (
 SELECT c.*,ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(n,pos)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.n ORDER BY k.pos) AS columns,
 ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(n,pos)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.n ORDER BY k.pos) AS parent_columns FROM pg_catalog.pg_constraint c
),
indexes AS (
 SELECT i.*,c.relname,am.amname,ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(i.indkey) WITH ORDINALITY k(n,pos)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.n ORDER BY k.pos) AS columns
 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid JOIN pg_catalog.pg_am am ON am.oid=c.relam
),
expected_keys(rel,name,kind,columns) AS (VALUES
 ('public.marker_categories','marker_categories_pkey','p',ARRAY['game_id','id']::text[]),
 ('public.marker_categories','marker_categories_category_uuid_unique','u',ARRAY['category_uuid']),
 ('public.marker_categories','marker_categories_legacy_uuid_identity_unique','u',ARRAY['game_id','id','game_uuid','category_uuid']),
 ('public.marker_category_groups','marker_category_groups_pkey','p',ARRAY['game_id','id']),
 ('public.marker_category_groups','marker_category_groups_group_uuid_unique','u',ARRAY['group_uuid']),
 ('public.marker_category_groups','marker_category_groups_legacy_uuid_identity_unique','u',ARRAY['game_id','id','game_uuid','group_uuid'])
),
expected_checks(name,expression) AS (VALUES
 ('marker_categories_id_format',$expression$(id ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'::text)$expression$),
 ('marker_categories_icon_source_check',$expression$(icon_source = ANY (ARRAY['none'::text, 'static'::text, 'r2'::text, 'external'::text]))$expression$),
 ('marker_categories_color_check',$expression$(color ~ '^#[0-9A-Fa-f]{6}$'::text)$expression$),
 ('marker_categories_marker_width_check',$expression$((marker_width IS NULL) OR (marker_width > 0))$expression$),
 ('marker_categories_marker_height_check',$expression$((marker_height IS NULL) OR (marker_height > 0))$expression$),
 ('marker_categories_symbol_size_check',$expression$((symbol_size IS NULL) OR (symbol_size > 0))$expression$),
 ('marker_categories_icon_ref_required',$expression$((icon_source = 'none'::text) OR (NULLIF(btrim(icon_ref), ''::text) IS NOT NULL))$expression$),
 ('marker_categories_group_uuid_pair_check',$expression$(((group_id IS NULL) AND (group_uuid IS NULL)) OR ((group_id IS NOT NULL) AND (group_uuid IS NOT NULL)))$expression$)
),
expected_fks(rel,name,parent,columns,parent_columns,upd,del) AS (VALUES
 ('public.marker_categories','marker_categories_legacy_game_uuid_fk','private.game_legacy_identifiers',ARRAY['game_id','game_uuid']::text[],ARRAY['legacy_identifier','game_id']::text[],'a','r'),
 ('public.marker_categories','marker_categories_group_fk','public.marker_category_groups',ARRAY['game_id','group_id'],ARRAY['game_id','id'],'c','n'),
 ('public.marker_categories','marker_categories_legacy_uuid_group_fk','public.marker_category_groups',ARRAY['game_id','group_id','game_uuid','group_uuid'],ARRAY['game_id','id','game_uuid','group_uuid'],'c','r'),
 ('public.marcadores','marcadores_category_fk','public.marker_categories',ARRAY['game_id','category_id'],ARRAY['game_id','id'],'c','a'),
 ('public.marker_category_groups','marker_category_groups_legacy_game_uuid_fk','private.game_legacy_identifiers',ARRAY['game_id','game_uuid'],ARRAY['legacy_identifier','game_id'],'a','r'),
 ('private.game_legacy_identifiers','game_legacy_identifiers_game_id_fkey','public.games',ARRAY['game_id'],ARRAY['id'],'a','r')
),
functions AS (
 SELECT s.name AS contract,s.signature,s.body AS expected_body,p.*,l.lanname FROM sources s
 JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(s.signature) JOIN pg_catalog.pg_language l ON l.oid=p.prolang
),
body_matches AS (SELECT s.name,EXISTS(SELECT 1 FROM functions p WHERE p.contract=s.name
 AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=s.body) AS ok FROM sources s),
api_roles AS (SELECT * FROM pg_catalog.pg_roles WHERE rolname IN('anon','authenticated','service_role')),
resolver_acl AS (SELECT p.contract,p.proowner,a.* FROM functions p
 CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a WHERE p.contract IN('category','group')),
category_acl AS (SELECT c.relowner,a.* FROM pg_catalog.pg_class c
 CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
 WHERE c.oid=pg_catalog.to_regclass('public.marker_categories')),
mapping_acl AS (SELECT c.relowner,a.* FROM pg_catalog.pg_class c
 CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
 WHERE c.oid=pg_catalog.to_regclass('private.game_legacy_identifiers')),
triggers AS (SELECT * FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass('public.marker_categories') AND NOT tgisinternal),
policies AS (
 SELECT p.*,ARRAY(SELECT r.rolname::text FROM pg_catalog.unnest(p.polroles) x(oid)
 JOIN pg_catalog.pg_roles r ON r.oid=x.oid ORDER BY r.rolname COLLATE "C") AS roles,
 pg_catalog.pg_get_expr(p.polqual,p.polrelid) AS qual,pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) AS with_check FROM pg_catalog.pg_policy p
),
policy_contracts AS (
 SELECT e.rel,EXISTS(SELECT 1 FROM policies p WHERE p.polrelid=pg_catalog.to_regclass(e.rel) AND p.polname=e.prefix||'_public_read'
 AND p.polcmd='r' AND p.polpermissive AND p.roles=ARRAY['anon','authenticated']::text[] AND p.qual='(is_active = true)' AND p.with_check IS NULL) AS public_ok,
 EXISTS(SELECT 1 FROM policies p WHERE p.polrelid=pg_catalog.to_regclass(e.rel) AND p.polname=e.prefix||'_admin_all'
 AND p.polcmd='*' AND p.polpermissive AND p.roles=ARRAY['authenticated']::text[]
 AND p.qual='private.is_deepmap_admin()' AND p.with_check='private.is_deepmap_admin()') AS admin_ok,
 (SELECT pg_catalog.count(*) FROM policies p WHERE p.polrelid=pg_catalog.to_regclass(e.rel))=2 AS exact_set
 FROM (VALUES('public.marker_categories','marker_categories'),('public.marker_category_groups','marker_category_groups')) e(rel,prefix)
),
admin_contract AS (SELECT pg_catalog.count(*)=2 AND COALESCE(pg_catalog.bool_and(public_ok AND admin_ok AND exact_set),false) AS ok FROM policy_contracts),
mapping_contract AS (
 SELECT EXISTS(SELECT 1 FROM policies p WHERE p.polrelid=pg_catalog.to_regclass('private.game_legacy_identifiers')
 AND p.polname='game_legacy_identifiers_admin_read' AND p.polcmd='r' AND p.polpermissive AND p.roles=ARRAY['authenticated']::text[]
 AND pg_catalog.regexp_replace(p.qual,'[[:space:]()]','','g') IN
 ('SELECTpublic.get_deepmap_roleASget_deepmap_role=''admin''::text','SELECTget_deepmap_roleASget_deepmap_role=''admin''::text'))
 AND NOT EXISTS(SELECT 1 FROM policies p WHERE p.polrelid=pg_catalog.to_regclass('private.game_legacy_identifiers')
 AND NOT p.polpermissive AND p.polcmd IN('r','*')) AS ok
),
writers AS (
 SELECT r.* FROM pg_catalog.pg_roles r WHERE r.rolname !~ '^pg_'
 AND (pg_catalog.has_any_column_privilege(r.oid,pg_catalog.to_regclass('public.marker_categories'),'INSERT')
 OR pg_catalog.has_any_column_privilege(r.oid,pg_catalog.to_regclass('public.marker_categories'),'UPDATE'))
),
writer_access AS (
 SELECT r.rolname,
 COALESCE(pg_catalog.has_table_privilege(r.oid,g.oid,'SELECT') AND pg_catalog.has_schema_privilege(r.oid,g.relnamespace,'USAGE')
 AND pg_catalog.has_schema_privilege(r.oid,'private','USAGE') AND pg_catalog.has_schema_privilege(r.oid,'pg_catalog','USAGE')
 AND pg_catalog.has_function_privilege(r.oid,'pg_catalog.gen_random_uuid()','EXECUTE')
 AND (r.rolsuper OR r.rolbypassrls OR (r.oid=g.relowner AND NOT g.relforcerowsecurity)
 OR (pg_catalog.pg_has_role(r.oid,'authenticated','USAGE') AND (SELECT ok FROM admin_contract))),false) AS group_ok,
 COALESCE(pg_catalog.has_schema_privilege(r.oid,m.relnamespace,'USAGE') AND pg_catalog.has_table_privilege(r.oid,m.oid,'SELECT')
 AND (r.rolsuper OR r.rolbypassrls OR (r.oid=m.relowner AND NOT m.relforcerowsecurity)
 OR (pg_catalog.pg_has_role(r.oid,'authenticated','USAGE') AND (SELECT ok FROM mapping_contract)
 AND pg_catalog.has_function_privilege(r.oid,'public.get_deepmap_role()','EXECUTE'))),false) AS mapping_ok
 FROM writers r LEFT JOIN pg_catalog.pg_class g ON g.oid=pg_catalog.to_regclass('public.marker_category_groups')
 LEFT JOIN pg_catalog.pg_class m ON m.oid=pg_catalog.to_regclass('private.game_legacy_identifiers')
),
category_data AS MATERIALIZED (
 SELECT c.*,
 (SELECT pg_catalog.count(*) FROM private.game_legacy_identifiers i WHERE i.legacy_identifier=c.game_id) AS mapping_count,
 (SELECT pg_catalog.count(*) FROM private.game_legacy_identifiers i WHERE i.legacy_identifier=c.game_id AND i.game_id=c.game_uuid) AS exact_mapping_count,
 (SELECT pg_catalog.count(*) FROM public.games p WHERE p.id=c.game_uuid) AS parent_count,
 (SELECT pg_catalog.count(*) FROM public.marker_category_groups g WHERE g.game_id=c.game_id AND g.id=c.group_id
 AND g.game_uuid=c.game_uuid AND g.group_uuid=c.group_uuid) AS group_count FROM public.marker_categories c
),
data_stats AS (
 SELECT pg_catalog.count(*) AS total,pg_catalog.count(DISTINCT category_uuid) AS distinct_uuid,
 pg_catalog.count(*) FILTER(WHERE category_uuid IS NULL) AS null_uuid,
 pg_catalog.count(*) FILTER(WHERE mapping_count<>1 OR exact_mapping_count<>1) AS mapping_invalid,
 pg_catalog.count(*) FILTER(WHERE mapping_count=0) AS mapping_missing,
 pg_catalog.count(*) FILTER(WHERE mapping_count>1) AS mapping_ambiguous,
 pg_catalog.count(*) FILTER(WHERE exact_mapping_count<>1) AS mapping_mismatch,
 pg_catalog.count(*) FILTER(WHERE parent_count<>1) AS parent_invalid,
 pg_catalog.count(*) FILTER(WHERE (group_id IS NULL) IS DISTINCT FROM (group_uuid IS NULL)) AS pair_invalid,
 pg_catalog.count(*) FILTER(WHERE group_id IS NOT NULL AND group_count<>1) AS group_invalid,
 pg_catalog.count(*) FILTER(WHERE updated_at IS NULL OR created_at IS NULL) AS timestamp_null FROM category_data
),
checks AS (
 SELECT 'maintenance.visibility.'||name AS check_name,ok,'Full SELECT/schema USAGE/RLS maintenance visibility; all data checks depend on all four tables'::text AS details FROM visibility
 UNION ALL SELECT 'schema.object.'||name,oid IS NOT NULL AND relkind='r' AND relrowsecurity,'Existing ordinary table with RLS' FROM relations
 UNION ALL SELECT 'schema.category.column.'||e.name,EXISTS(SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass('public.marker_categories')
 AND a.attname=e.name AND a.atttypid=pg_catalog.to_regtype(e.type_name) AND a.attnotnull=e.nn
 AND a.default_expr IS NOT DISTINCT FROM e.def AND a.attidentity='' AND a.attgenerated=''),
 'Exact type/nullability/default/no identity/generated; default='||COALESCE(e.def,'none') FROM expected_columns e
 UNION ALL SELECT 'schema.category.exact_columns',pg_catalog.count(*)=18 AND COALESCE(pg_catalog.bool_and(attname IN(SELECT name FROM expected_columns)),false),
 'Exactly 18 current columns; actual='||pg_catalog.count(*) FROM attributes WHERE attrelid=pg_catalog.to_regclass('public.marker_categories')
 UNION ALL SELECT 'constraint.key.'||e.name,EXISTS(SELECT 1 FROM constraints c JOIN indexes i ON i.indexrelid=c.conindid
 WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND c.conname=e.name AND c.contype::text=e.kind AND c.columns=e.columns
 AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred AND i.indrelid=c.conrelid AND i.relname=e.name AND i.columns=e.columns
 AND i.indisunique AND i.indimmediate AND i.indisvalid AND i.indisready AND i.indislive AND i.amname='btree'
 AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnkeyatts=pg_catalog.cardinality(e.columns) AND i.indnatts=i.indnkeyatts
 AND ARRAY(SELECT k FROM pg_catalog.unnest(i.indkey) k)=c.conkey),
 'Real immediate validated constraint and exact UNIQUE B-tree backing index, without predicate/expression/INCLUDE' FROM expected_keys e
 UNION ALL SELECT 'constraint.check.'||e.name,EXISTS(SELECT 1 FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass('public.marker_categories')
 AND c.conname=e.name AND c.contype='c' AND c.convalidated AND pg_catalog.pg_get_expr(c.conbin,c.conrelid)=e.expression),
 'Exact approved catalog expression; full legacy/pair CHECK semantics' FROM expected_checks e
 UNION ALL SELECT 'constraint.fk.'||e.name,EXISTS(SELECT 1 FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass(e.rel)
 AND c.conname=e.name AND c.contype='f' AND c.confrelid=pg_catalog.to_regclass(e.parent) AND c.columns=e.columns AND c.parent_columns=e.parent_columns
 AND c.confmatchtype='s' AND c.confupdtype::text=e.upd AND c.confdeltype::text=e.del AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
 AND pg_catalog.to_jsonb(c)->>'confdelsetcols' IS NULL),
 'Exact source/target/SIMPLE/actions/validated/immediate; legacy group SET NULL remains unchanged' FROM expected_fks e
 UNION ALL SELECT 'constraint.category.exact_set',pg_catalog.count(*)=14 AND COALESCE(pg_catalog.bool_and(conname IN
 (SELECT name FROM expected_keys WHERE rel='public.marker_categories' UNION ALL SELECT name FROM expected_checks
 UNION ALL SELECT name FROM expected_fks WHERE rel='public.marker_categories')),false),
 'Exactly 1 PK, 8 CHECKs, 3 FKs, 2 UNIQUEs; NOT NULL catalog constraints excluded by version'
 FROM constraints WHERE conrelid=pg_catalog.to_regclass('public.marker_categories') AND contype IN('p','c','f','u','x')
 UNION ALL SELECT 'index.category.exact_set',pg_catalog.count(*)=3 AND COALESCE(pg_catalog.bool_and(relname IN
 (SELECT name FROM expected_keys WHERE rel='public.marker_categories')),false),'Exactly three approved backing indexes; actual='||pg_catalog.count(*)
 FROM indexes WHERE indrelid=pg_catalog.to_regclass('public.marker_categories')
 UNION ALL SELECT 'function.'||s.name||'.attributes',EXISTS(SELECT 1 FROM functions p WHERE p.contract=s.name
 AND p.pronamespace=pg_catalog.to_regnamespace('private') AND p.pronargs=0 AND p.proargtypes=''::pg_catalog.oidvector
 AND p.proargnames IS NULL AND p.proargmodes IS NULL AND p.proallargtypes IS NULL AND p.provariadic=0 AND p.pronargdefaults=0 AND p.proargdefaults IS NULL
 AND p.prorettype='trigger'::pg_catalog.regtype AND p.prokind='f' AND p.lanname='plpgsql' AND NOT p.prosecdef
 AND p.proconfig=ARRAY['search_path=""']::text[] AND p.provolatile='v' AND p.proparallel='u' AND NOT p.proisstrict
 AND NOT p.proleakproof AND NOT p.proretset AND p.procost=100 AND p.prorows=0),
 'Private zero-arg trigger plpgsql INVOKER, empty search_path, VOLATILE/UNSAFE/called on NULL/non-leakproof/COST100' FROM sources s
 UNION ALL SELECT 'function.'||name||'.exact_body',ok,'Complete approved literal equality, symmetric CR removal only; never invoked' FROM body_matches
 UNION ALL SELECT 'function.'||s.name||'.single_overload',(SELECT pg_catalog.count(*)=1 AND COALESCE(pg_catalog.bool_and(n.nspname='private'
 AND p.oid=pg_catalog.to_regprocedure(s.signature)),false) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN('public','private') AND p.proname=pg_catalog.split_part(pg_catalog.split_part(s.signature,'.',2),'(',1)),
 'Single private signature, no public/private overload' FROM sources s
 UNION ALL SELECT 'function.category.contract.'||e.name,b.ok,e.details FROM body_matches b CROSS JOIN (VALUES
 ('insert_category','Unconditional DB-owned category_uuid INSERT generation, overriding caller/default/NULL'),
 ('insert_game','B2b STRICT mapping lookup/fill/mismatch retained'),('insert_group','Derives group UUID from group_id, clears NULL group, ignores explicit INSERT UUID'),
 ('update_category','Rejects NULL or altered category UUID'),('update_game','B2b game identity immutable after hydration'),
 ('update_group','Rejects UUID-only change; supports group to NULL or destination, transported OLD UUID and correct destination UUID; rejects contradiction'),
 ('hydration','Only group_uuid may change in transitional hydration, exact resolved UUID required'),
 ('editorial_untouched','No id/editorial mutation, recursive DML, dynamic SQL or DEFINER')) e(name,details) WHERE b.name='category'
 UNION ALL SELECT 'acl.resolver.'||s.name||'.owner_only',EXISTS(SELECT 1 FROM functions WHERE contract=s.name)
 AND NOT EXISTS(SELECT 1 FROM resolver_acl WHERE contract=s.name AND (grantee<>proowner OR privilege_type<>'EXECUTE')),
 'Raw B2b/B6a owner-only EXECUTE, no PUBLIC/API/unexpected direct grants; historical ACL preservation requires snapshots'
 FROM sources s WHERE s.name IN('category','group')
 UNION ALL SELECT 'acl.resolver.'||s.name||'.trusted_owner',EXISTS(SELECT 1 FROM functions p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
 WHERE p.contract=s.name AND r.rolname NOT IN('anon','authenticated','service_role')
 AND EXISTS(SELECT 1 FROM api_roles WHERE rolname='anon') AND EXISTS(SELECT 1 FROM api_roles WHERE rolname='authenticated')
 AND NOT EXISTS(SELECT 1 FROM api_roles a WHERE a.rolname IN('anon','authenticated') AND pg_catalog.pg_has_role(a.oid,r.oid,'MEMBER'))),
 'Actual owner exists and is not an API role/inherited by untrusted callers; no fixed role/OID' FROM sources s WHERE s.name IN('category','group')
 UNION ALL SELECT 'acl.private.no_untrusted_create',EXISTS(SELECT 1 FROM api_roles WHERE rolname='anon')
 AND EXISTS(SELECT 1 FROM api_roles WHERE rolname='authenticated') AND NOT EXISTS(SELECT 1 FROM api_roles r
 WHERE r.rolname IN('anon','authenticated') AND pg_catalog.has_schema_privilege(r.oid,'private','CREATE')),
 'Untrusted callers cannot replace private resolvers'
 UNION ALL SELECT 'trigger.category.exact_set',pg_catalog.count(*)=2 AND COALESCE(pg_catalog.bool_and(tgname IN
 ('deepmap_categories_identity','deepmap_marker_categories_touch_updated_at')),false),'Exactly two user triggers, internal RI triggers excluded' FROM triggers
 UNION ALL SELECT 'trigger.category.'||e.name,EXISTS(SELECT 1 FROM triggers t WHERE t.tgname=e.name AND t.tgtype=e.kind
 AND t.tgfoid=pg_catalog.to_regprocedure(e.signature) AND t.tgenabled='O' AND t.tgnargs=0 AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL),
 'Exact BEFORE/events/ROW/target/origin/zero args/no UPDATE OF/no WHEN' FROM (VALUES
 ('deepmap_categories_identity',23,'private.deepmap_resolve_category_identity()'),
 ('deepmap_marker_categories_touch_updated_at',19,'private.deepmap_touch_updated_at()')) e(name,kind,signature)
 UNION ALL SELECT 'trigger.category.before_update_order',(SELECT pg_catalog.array_agg(tgname::text ORDER BY tgname COLLATE "C")
 FROM triggers WHERE (tgtype & 2)=2 AND (tgtype & 16)=16) IS NOT DISTINCT FROM
 ARRAY['deepmap_categories_identity','deepmap_marker_categories_touch_updated_at']::text[],
 'PostgreSQL name order identity then touch; no OID ordering'
 UNION ALL SELECT 'parent.group.column.'||e.name,EXISTS(SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass('public.marker_category_groups')
 AND a.attname=e.name AND a.atttypid='uuid'::pg_catalog.regtype AND a.attnotnull AND a.attidentity='' AND a.attgenerated=''
 AND a.default_expr IS NOT DISTINCT FROM e.def),'Required B6a parent UUID context/default' FROM (VALUES('game_uuid',NULL::text),('group_uuid','gen_random_uuid()')) e(name,def)
 UNION ALL SELECT 'parent.group.legacy_text_keys',pg_catalog.count(*)=2 AND COALESCE(pg_catalog.bool_and(atttypid='text'::pg_catalog.regtype AND attnotnull),false),
 'Legacy parent game_id/id remain TEXT NOT NULL' FROM attributes WHERE attrelid=pg_catalog.to_regclass('public.marker_category_groups') AND attname IN('game_id','id')
 UNION ALL SELECT 'parent.group.user_triggers',
 (SELECT pg_catalog.count(*) FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass('public.marker_category_groups') AND NOT tgisinternal)=2
 AND NOT EXISTS(SELECT 1 FROM (VALUES('deepmap_category_groups_identity',23,'private.deepmap_resolve_category_group_identity()'),
 ('deepmap_category_groups_touch_updated_at',19,'private.deepmap_touch_updated_at()')) e(name,kind,signature)
 WHERE NOT EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid=pg_catalog.to_regclass('public.marker_category_groups')
 AND NOT t.tgisinternal AND t.tgname=e.name AND t.tgtype=e.kind AND t.tgfoid=pg_catalog.to_regprocedure(e.signature)
 AND t.tgenabled='O' AND t.tgnargs=0 AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL)),
 'B6a parent retains the same two exact user triggers; new B6b internal RI triggers excluded'
 UNION ALL SELECT 'policy.'||rel||'.public_read',public_ok,'Exact permissive SELECT anon/authenticated USING is_active=true' FROM policy_contracts
 UNION ALL SELECT 'policy.'||rel||'.admin_all',admin_ok,'Exact permissive authenticated ALL Admin USING/WITH CHECK, including inactive groups' FROM policy_contracts
 UNION ALL SELECT 'policy.'||rel||'.exact_set',exact_set,'Exactly two legacy policies; no B6b additions' FROM policy_contracts
 UNION ALL SELECT 'mapping.policy.admin_read_contract',ok,'Exact authenticated Admin read policy and no restrictive SELECT/ALL' FROM mapping_contract
 UNION ALL SELECT 'mapping.policy.no_restrictive_reads',pg_catalog.to_regclass('private.game_legacy_identifiers') IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM policies WHERE polrelid=pg_catalog.to_regclass('private.game_legacy_identifiers') AND NOT polpermissive AND polcmd IN('r','*')),
 'B2b protection against restrictive mapping SELECT/ALL retained'
 UNION ALL SELECT 'mapping.acl.authenticated_lookup',EXISTS(SELECT 1 FROM api_roles r WHERE r.rolname='authenticated'
 AND pg_catalog.has_schema_privilege(r.oid,'private','USAGE')
 AND pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('private.game_legacy_identifiers'),'SELECT')
 AND pg_catalog.has_function_privilege(r.oid,'public.get_deepmap_role()','EXECUTE')),
 'Current authenticated private USAGE/mapping SELECT/role helper EXECUTE; role helper never invoked'
 UNION ALL SELECT 'writer.invoker.groups.'||rolname,group_ok,'Effective non-pg_* category writer requires group SELECT/schema/core generator access and full visibility or validated Admin contract' FROM writer_access
 UNION ALL SELECT 'writer.invoker.mapping.'||rolname,mapping_ok,'Effective non-pg_* category writer requires private USAGE/mapping SELECT/full visibility or validated authenticated Admin contract' FROM writer_access
 UNION ALL SELECT 'writer.invoker.all_groups',NOT EXISTS(SELECT 1 FROM writer_access WHERE NOT group_ok) AND (SELECT ok FROM admin_contract),
 'No effective application writer lacks group access; both legacy Admin policy contracts validated'
 UNION ALL SELECT 'writer.invoker.all_mapping',NOT EXISTS(SELECT 1 FROM writer_access WHERE NOT mapping_ok) AND (SELECT ok FROM mapping_contract),
 'No effective application writer lacks mapping access; no automatic service_role exemption'
 UNION ALL SELECT 'acl.mapping.service_writer_access',
 pg_catalog.to_regclass('private.game_legacy_identifiers') IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM writer_access WHERE rolname='service_role' AND (NOT mapping_ok OR NOT group_ok)),
 'If service_role is an effective category writer, private USAGE/mapping SELECT/valid RLS and group/generator access are all required; no artificial SELECT for non-writer'
 UNION ALL SELECT 'acl.mapping.no_unexpected_grants',
 pg_catalog.to_regclass('private.game_legacy_identifiers') IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM mapping_acl a WHERE a.grantee<>a.relowner
 AND NOT EXISTS(SELECT 1 FROM api_roles r WHERE r.oid=a.grantee AND NOT a.is_grantable
 AND ((r.rolname='authenticated' AND a.privilege_type IN('SELECT','INSERT'))
 OR (r.rolname='service_role' AND a.privilege_type='SELECT' AND a.grantor=a.relowner
 AND EXISTS(SELECT 1 FROM writers w WHERE w.oid=r.oid)))))
 AND NOT EXISTS(SELECT 1 FROM attributes a CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) x
 WHERE a.attrelid=pg_catalog.to_regclass('private.game_legacy_identifiers') AND x.grantee<>(
 SELECT c.relowner FROM pg_catalog.pg_class c WHERE c.oid=a.attrelid)),
 'Current mapping ACL: actual owner, legacy authenticated SELECT/INSERT, non-grantable service SELECT only for effective writer; no PUBLIC/anon/other grants or added column grants; historical delta belongs to migration snapshots'
 UNION ALL SELECT 'acl.category.anon_select',EXISTS(SELECT 1 FROM api_roles r WHERE r.rolname='anon'
 AND pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('public.marker_categories'),'SELECT')),'Legacy anon table SELECT'
 UNION ALL SELECT 'acl.category.authenticated.'||e.privilege,EXISTS(SELECT 1 FROM api_roles r WHERE r.rolname='authenticated'
 AND pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('public.marker_categories'),e.privilege)),
 'Legacy authenticated table-wide '||e.privilege FROM (VALUES('SELECT'),('INSERT'),('UPDATE'),('DELETE')) e(privilege)
 UNION ALL SELECT 'acl.category.no_unexpected_grants',pg_catalog.to_regclass('public.marker_categories') IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM category_acl a WHERE a.grantee<>a.relowner AND NOT EXISTS(SELECT 1 FROM api_roles r WHERE r.oid=a.grantee AND
 (r.rolname='service_role' OR (NOT a.is_grantable AND ((r.rolname='anon' AND a.privilege_type='SELECT')
 OR (r.rolname='authenticated' AND a.privilege_type IN('SELECT','INSERT','UPDATE','DELETE'))))))),
 'Current legacy owner/service ACL permitted; no PUBLIC/unexpected API/direct table escalation; no historical ACL claim'
 UNION ALL SELECT 'acl.category.uuid_columns_no_separate_acl',pg_catalog.count(*)=2 AND COALESCE(pg_catalog.bool_and(attacl IS NULL),false),
 'No separate grants on category_uuid/group_uuid; inherited table privileges remain' FROM attributes
 WHERE attrelid=pg_catalog.to_regclass('public.marker_categories') AND attname IN('category_uuid','group_uuid')
 UNION ALL SELECT 'acl.category.uuid_table_wide_defense',EXISTS(SELECT 1 FROM api_roles r WHERE r.rolname='authenticated'
 AND NOT EXISTS(SELECT 1 FROM (VALUES('category_uuid','INSERT'),('category_uuid','UPDATE'),('group_uuid','INSERT'),('group_uuid','UPDATE')) e(col,priv)
 WHERE NOT pg_catalog.has_column_privilege(r.oid,pg_catalog.to_regclass('public.marker_categories'),e.col,e.priv)))
 AND (SELECT ok FROM body_matches WHERE name='category'),
 'UUIDs technically writable via table ACL; exact resolver owns category identity and derives group relationship'
 UNION ALL SELECT 'function.uuid_generator.attributes',EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pg_catalog.gen_random_uuid()')
 AND p.pronargs=0 AND p.prorettype='uuid'::pg_catalog.regtype AND p.provolatile='v' AND NOT p.prosecdef AND NOT p.proretset),
 'Core UUID generator exists/zero args/UUID/VOLATILE/INVOKER/non-set-returning; never called'
 UNION ALL SELECT 'data.category_uuid.non_null',null_uuid=0,'NULL category UUID rows='||null_uuid FROM data_stats
 UNION ALL SELECT 'data.category_uuid.no_duplicates',NOT EXISTS(SELECT 1 FROM category_data GROUP BY category_uuid HAVING pg_catalog.count(*)>1),'No duplicate category UUIDs'
 UNION ALL SELECT 'data.category_uuid.distinct_count',distinct_uuid=total,'Distinct UUID='||distinct_uuid||'; rows='||total FROM data_stats
 UNION ALL SELECT 'data.game_context.mapping',mapping_invalid=0,'Categories without exactly one exact mapping='||mapping_invalid FROM data_stats
 UNION ALL SELECT 'data.game_context.mapping_missing',mapping_missing=0,'Unknown mappings='||mapping_missing FROM data_stats
 UNION ALL SELECT 'data.game_context.mapping_ambiguous',mapping_ambiguous=0,'Ambiguous mappings='||mapping_ambiguous FROM data_stats
 UNION ALL SELECT 'data.game_context.mapping_uuid',mapping_mismatch=0,'UUID mapping mismatches='||mapping_mismatch FROM data_stats
 UNION ALL SELECT 'data.game_context.parent',parent_invalid=0,'Rows without exactly one game parent='||parent_invalid FROM data_stats
 UNION ALL SELECT 'data.group_pair',pair_invalid=0,'Partial group_id/group_uuid pairs='||pair_invalid FROM data_stats
 UNION ALL SELECT 'data.group_context.exact',group_invalid=0,'Grouped categories without exactly one full identity parent='||group_invalid FROM data_stats
 UNION ALL SELECT 'data.legacy_identity_unique',NOT EXISTS(SELECT 1 FROM category_data GROUP BY game_id,id HAVING pg_catalog.count(*)>1),'No duplicate legacy game_id/id'
 UNION ALL SELECT 'data.timestamps.non_null',timestamp_null=0,'Current NULL timestamps='||timestamp_null||'; no historical monotonicity claim' FROM data_stats
 UNION ALL SELECT 'scope.pre_b6c.columns.'||e.rel,pg_catalog.to_regclass(e.rel) IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass(e.rel) AND a.attname IN('category_uuid','group_uuid')),
 'No category/group entity UUID bridge in this table yet' FROM (VALUES('public.marcadores'),('public.marker_submissions'),('private.marker_submission_revisions'),('public.user_notifications')) e(rel)
 UNION ALL SELECT 'scope.pre_b6c.no_identifiable_resolvers',NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN('public','private') AND p.proname ~ '^deepmap_resolve_(marker|submission|notification|revision)_(category|group)_identity$'),
 'No identifiable later marker/submission/notification/revision category/group resolvers'
 UNION ALL SELECT 'scope.pre_b6c.no_uuid_constraints',NOT EXISTS(SELECT 1 FROM constraints c
 WHERE c.conrelid IN(pg_catalog.to_regclass('public.marcadores'),pg_catalog.to_regclass('public.marker_submissions'),
 pg_catalog.to_regclass('private.marker_submission_revisions'),pg_catalog.to_regclass('public.user_notifications'))
 AND (c.columns && ARRAY['category_uuid','group_uuid']::text[] OR c.parent_columns && ARRAY['category_uuid','group_uuid']::text[]
 OR c.conname ~* '(category_uuid|group_uuid|b6c)')),
 'No identifiable B6c UUID constraints; category support key belongs to B6b only'
)
SELECT check_name,CASE WHEN ok IS TRUE AND (check_name NOT LIKE 'data.%' OR (SELECT ok FROM full_visibility))
 THEN 'PASS' ELSE 'FAIL' END AS status,
 details||CASE WHEN check_name LIKE 'data.%' AND NOT(SELECT ok FROM full_visibility)
 THEN '; INVALID DATA RESULT: incomplete maintenance visibility' ELSE '' END AS details
FROM checks ORDER BY check_name;
