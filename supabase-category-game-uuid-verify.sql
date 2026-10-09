-- DeepMap post-B2b verifier. Execute MANUALLY after B2b, with maintenance
-- SELECT privileges and full RLS visibility. One SELECT, one statement snapshot.
-- No RPC or trigger function is invoked. FAIL visibility invalidates data PASSes.
-- Missing required tables/SELECT permission abort the statement; do not interpret
-- an execution error as success. JSONB reads permit reporting missing UUID columns.
-- No historical baseline: current invariants cannot prove unchanged OIDs/data/ACLs.
WITH
attrs AS (
    SELECT a.*, n.nspname, c.relname,
           n.nspname || '.' || c.relname AS relation_name
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE a.attnum > 0 AND NOT a.attisdropped
),
constraints AS (
    SELECT c.*,
        ARRAY(SELECT a.attname::text
              FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos)
              JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num
              ORDER BY k.pos) AS source_columns,
        ARRAY(SELECT a.attname::text
              FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num,pos)
              JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num
              ORDER BY k.pos) AS target_columns
    FROM pg_catalog.pg_constraint c
),
categories AS (SELECT pg_catalog.to_jsonb(c) AS row_data FROM public.marker_categories c),
groups AS (SELECT pg_catalog.to_jsonb(g) AS row_data FROM public.marker_category_groups g),
mapping AS (
    SELECT i.legacy_identifier, i.game_id, g.id AS parent_id
    FROM private.game_legacy_identifiers i LEFT JOIN public.games g ON g.id=i.game_id
),
mapping_counts AS (
    SELECT legacy_identifier, count(*) AS rows, count(DISTINCT game_id) AS targets,
           count(parent_id) AS parents
    FROM mapping GROUP BY legacy_identifier
),
fn AS (
    SELECT p.* FROM pg_catalog.pg_proc p
    WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_category_identity()')
),
expected_columns(relation_name,column_name,type_oid,not_null,no_default) AS (
    VALUES
    ('public.marker_categories','game_uuid','uuid'::pg_catalog.regtype,true,true),
    ('public.marker_categories','game_id','text'::pg_catalog.regtype,true,false),
    ('public.marker_categories','id','text'::pg_catalog.regtype,true,false),
    ('public.marker_categories','group_id','text'::pg_catalog.regtype,false,false),
    ('public.marker_category_groups','game_uuid','uuid'::pg_catalog.regtype,true,true)
),
expected_fks(relation_name,name,target,source_columns,target_columns,update_action,delete_action) AS (
    VALUES
    ('public.marker_categories','marker_categories_legacy_game_uuid_fk',
     'private.game_legacy_identifiers',ARRAY['game_id','game_uuid'],ARRAY['legacy_identifier','game_id'],'a','r'),
    ('public.marker_categories','marker_categories_group_fk',
     'public.marker_category_groups',ARRAY['game_id','group_id'],ARRAY['game_id','id'],'c','n'),
    ('public.marker_category_groups','marker_category_groups_legacy_game_uuid_fk',
     'private.game_legacy_identifiers',ARRAY['game_id','game_uuid'],ARRAY['legacy_identifier','game_id'],'a','r')
),
expected_triggers(name,function_name,type_bits) AS (
    VALUES ('deepmap_categories_identity','private.deepmap_resolve_category_identity()',23),
           ('deepmap_marker_categories_touch_updated_at','private.deepmap_touch_updated_at()',19)
),
checks AS (
    SELECT 'column.'||e.relation_name||'.'||e.column_name AS check_name,
        EXISTS (SELECT 1 FROM attrs a WHERE a.relation_name=e.relation_name
            AND a.attname=e.column_name AND a.atttypid=e.type_oid
            AND a.attnotnull=e.not_null AND a.attidentity='' AND a.attgenerated=''
            AND (NOT e.no_default OR (NOT a.atthasdef AND NOT EXISTS (
                SELECT 1 FROM pg_catalog.pg_attrdef d WHERE d.adrelid=a.attrelid AND d.adnum=a.attnum)))) AS ok,
        pg_catalog.format('Expected %s, NOT NULL=%s, no default required=%s',e.type_oid,e.not_null,e.no_default) AS details
    FROM expected_columns e
    UNION ALL
    SELECT 'fk.'||e.name, EXISTS (
        SELECT 1 FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass(e.relation_name)
        AND c.conname=e.name AND c.contype='f' AND c.convalidated
        AND NOT c.condeferrable AND NOT c.condeferred AND c.confmatchtype='s'
        AND c.confrelid=pg_catalog.to_regclass(e.target)
        AND c.source_columns=e.source_columns AND c.target_columns=e.target_columns
        AND c.confupdtype::text=e.update_action AND c.confdeltype::text=e.delete_action
        -- NULL means SET NULL applies to the whole composite key (legacy).
        AND pg_catalog.to_jsonb(c)->>'confdelsetcols' IS NULL),
        pg_catalog.format('%s %s -> %s %s; validated, immediate; update=%s delete=%s (a=NO ACTION,r=RESTRICT,c=CASCADE,n=SET NULL)',
            e.relation_name,e.source_columns,e.target,e.target_columns,e.update_action,e.delete_action)
    FROM expected_fks e
    UNION ALL
    SELECT 'pk.marker_categories',
        (SELECT count(*) FROM constraints WHERE conrelid=pg_catalog.to_regclass('public.marker_categories') AND contype='p')=1
        AND EXISTS (SELECT 1 FROM constraints c JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
            WHERE c.conrelid=pg_catalog.to_regclass('public.marker_categories') AND c.contype='p'
            AND c.source_columns=ARRAY['game_id','id'] AND c.convalidated AND NOT c.condeferrable
            AND i.indisvalid AND i.indisready), 'Exactly one valid PK (game_id,id), in that order'
    UNION ALL
    SELECT 'data.categories.null_uuid', count(*)=0, 'NULL/missing game_uuid rows='||count(*)
    FROM categories WHERE row_data->>'game_uuid' IS NULL
    UNION ALL
    SELECT 'data.mapping.invalid_or_ambiguous', count(*)=0, 'Invalid/ambiguous aliases='||count(*)
    FROM mapping_counts WHERE legacy_identifier IS NULL OR rows<>1 OR targets<>1 OR parents<>1
    UNION ALL
    SELECT 'data.categories.unmapped_game_id', count(*)=0, 'Categories without mapping='||count(*)
    FROM categories c WHERE NOT EXISTS (SELECT 1 FROM mapping m WHERE m.legacy_identifier=c.row_data->>'game_id')
    UNION ALL
    SELECT 'data.categories.mapping_mismatch', count(*)=0, 'Categories without exactly one matching valid mapping='||count(*)
    FROM categories c WHERE (SELECT count(*) FROM mapping m
        WHERE m.legacy_identifier=c.row_data->>'game_id' AND m.game_id::text=c.row_data->>'game_uuid'
        AND m.parent_id IS NOT NULL)<>1
    UNION ALL
    SELECT 'data.groups.mapping_integrity', count(*)=0, 'Groups without exactly one matching valid mapping='||count(*)
    FROM groups g WHERE (SELECT count(*) FROM mapping m
        WHERE m.legacy_identifier=g.row_data->>'game_id' AND m.game_id::text=g.row_data->>'game_uuid'
        AND m.parent_id IS NOT NULL)<>1
    UNION ALL
    SELECT 'data.categories.group_context', count(*)=0, 'Grouped categories without exactly one consistent legacy group/mapping='||count(*)
    FROM categories c WHERE c.row_data->>'group_id' IS NOT NULL AND (
        SELECT count(*) FROM groups g JOIN mapping m ON m.legacy_identifier=g.row_data->>'game_id'
        AND m.game_id::text=g.row_data->>'game_uuid' AND m.parent_id IS NOT NULL
        WHERE g.row_data->>'id'=c.row_data->>'group_id'
        AND g.row_data->>'game_id'=c.row_data->>'game_id'
        AND g.row_data->>'game_uuid'=c.row_data->>'game_uuid')<>1
    UNION ALL
    SELECT 'trigger.'||e.name, EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid=pg_catalog.to_regclass('public.marker_categories') AND t.tgname=e.name
        AND t.tgfoid=pg_catalog.to_regprocedure(e.function_name) AND t.tgtype=e.type_bits
        AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgnargs=0
        AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL), 'Expected enabled origin trigger, exact events/function, no WHEN/column filter/arguments'
    FROM expected_triggers e
    UNION ALL
    SELECT 'function.identity.invoker_search_path', EXISTS (SELECT 1 FROM fn
        WHERE NOT prosecdef AND prorettype='trigger'::pg_catalog.regtype AND pronargs=0
        AND prokind='f' AND proconfig=ARRAY['search_path=""']::text[]),
        'SECURITY INVOKER, trigger(), exact approved empty search_path'
    UNION ALL
    SELECT 'function.identity.direct_acl', EXISTS (SELECT 1 FROM fn) AND NOT EXISTS (
        SELECT 1 FROM fn p CROSS JOIN LATERAL pg_catalog.aclexplode(
            COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
        WHERE a.grantee<>p.proowner), 'Only owner direct ACL permitted; no PUBLIC/anon/authenticated/service_role grants'
    UNION ALL
    SELECT 'function.touch.body', EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
        AND NOT p.prosecdef AND p.prorettype='trigger'::pg_catalog.regtype
        AND pg_catalog.lower(pg_catalog.regexp_replace(p.prosrc,'[[:space:]]','','g'))='beginnew.updated_at:=now();returnnew;end;'),
        'Approved invoker body: NEW.updated_at := now(); RETURN NEW'
    UNION ALL
    SELECT 'visibility.full.'||v.name, EXISTS (
        SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
        WHERE c.oid=pg_catalog.to_regclass(v.name) AND pg_catalog.has_table_privilege(c.oid,'SELECT')
        AND pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
        AND (NOT c.relrowsecurity OR r.rolsuper OR r.rolbypassrls OR (c.relowner=r.oid AND NOT c.relforcerowsecurity))),
        'Requires full maintenance visibility; FAIL invalidates all data checks'
    FROM (VALUES ('public.marker_categories'),('public.marker_category_groups'),
        ('private.game_legacy_identifiers'),('public.games')) v(name)
    UNION ALL
    SELECT 'rls.enabled.'||v.name, EXISTS (SELECT 1 FROM pg_catalog.pg_class c
        WHERE c.oid=pg_catalog.to_regclass(v.name) AND c.relkind='r' AND c.relrowsecurity),
        'RLS must remain enabled; policy history needs external baseline'
    FROM (VALUES ('public.marker_categories'),('public.marker_category_groups'),
        ('private.game_legacy_identifiers'),('public.games')) v(name)
    UNION ALL
    SELECT 'scope.no_premature_game_uuid.'||v.name,
        pg_catalog.to_regclass(v.name) IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM attrs WHERE relation_name=v.name AND attname='game_uuid'), 'Table exists and has no game_uuid column'
    FROM (VALUES ('public.marcadores'),('public.map_labels'),('public.marker_submissions'),('public.user_notifications')) v(name)
    UNION ALL
    SELECT 'scope.no_category_uuid_or_group_uuid', count(*)=0,
        'Unexpected public/private columns='||COALESCE(string_agg(relation_name||'.'||attname,', '),'none')
    FROM attrs WHERE nspname IN ('public','private') AND attname IN ('category_uuid','group_uuid')
    UNION ALL
    SELECT 'scope.category_columns', count(*)=0, 'Unexpected category columns='||COALESCE(string_agg(attname,', '),'none')
    FROM attrs WHERE relation_name='public.marker_categories' AND attname<>ALL(ARRAY[
        'game_id','id','group_id','name_en','name_pt','icon_source','icon_ref','color',
        'marker_width','marker_height','symbol_size','sort_order','is_active','created_at','updated_at','game_uuid'])
    UNION ALL
    SELECT 'scope.category_user_triggers', count(*)=2 AND bool_and(tgname IN (
        'deepmap_categories_identity','deepmap_marker_categories_touch_updated_at')), 'Expected exactly two user triggers; actual='||count(*)
    FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass('public.marker_categories') AND NOT tgisinternal
    UNION ALL
    SELECT 'acl.authenticated.mapping_access', EXISTS (
        SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname='authenticated'
        AND pg_catalog.has_schema_privilege(r.oid,pg_catalog.to_regnamespace('private'),'USAGE')
        AND pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('private.game_legacy_identifiers'),'SELECT')
        AND pg_catalog.has_function_privilege(r.oid,pg_catalog.to_regprocedure('public.get_deepmap_role()'),'EXECUTE')),
        'Approved invoker access: private USAGE, mapping SELECT, role helper EXECUTE'
    UNION ALL
    SELECT 'rls.mapping.admin_read', EXISTS (
        SELECT 1 FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_roles r ON r.rolname='authenticated'
        WHERE p.polrelid=pg_catalog.to_regclass('private.game_legacy_identifiers')
        AND p.polname='game_legacy_identifiers_admin_read' AND p.polcmd='r' AND p.polpermissive
        AND r.oid=ANY(p.polroles)
        AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'[[:space:]()]','','g')
            IN ('SELECTpublic.get_deepmap_roleASget_deepmap_role=''admin''::text',
                'SELECTget_deepmap_roleASget_deepmap_role=''admin''::text'))
        AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p
            WHERE p.polrelid=pg_catalog.to_regclass('private.game_legacy_identifiers')
            AND NOT p.polpermissive AND p.polcmd IN ('r','*')),
        'Exact approved admin-read policy; no restrictive SELECT/ALL policy'
    UNION ALL
    SELECT 'scope.no_uuid_named_objects', count(*)=0,
        'Unexpected public/private UUID-named objects='||COALESCE(string_agg(object_name,', '),'none')
    FROM (
        SELECT n.nspname||'.'||c.relname AS object_name FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('public','private') AND c.relname ~ '(category_uuid|group_uuid)'
        UNION ALL
        SELECT n.nspname||'.'||p.proname FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname IN ('public','private') AND p.proname ~ '(category_uuid|group_uuid)'
        UNION ALL
        SELECT n.nspname||'.'||c.conname FROM pg_catalog.pg_constraint c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.connamespace
        WHERE n.nspname IN ('public','private') AND c.conname ~ '(category_uuid|group_uuid)'
    ) unexpected
    UNION ALL
    SELECT 'scope.identity_overloads', count(*)=1, 'Expected exactly one private category resolver; actual='||count(*)
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='private' AND p.proname='deepmap_resolve_category_identity'
)
SELECT check_name, CASE WHEN ok IS TRUE THEN 'PASS' ELSE 'FAIL' END AS status, details
FROM checks ORDER BY check_name;
