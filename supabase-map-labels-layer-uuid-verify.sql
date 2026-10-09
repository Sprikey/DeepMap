-- DeepMap post-B3 / pre-B4. Execute MANUALLY after applying B3.
-- One read-only SELECT; no application, RPC or trigger function is called.
-- Requires maintenance SELECT/USAGE and full RLS visibility on all data tables.
-- Failed visibility forces data checks to FAIL. Missing tables/SELECT permission
-- can abort the statement: an execution error never means successful validation.
-- No pre-migration snapshot: current invariants do not prove historical equality
-- of row counts, timestamps, all ACLs/policies or every object outside this scope.
WITH
attributes AS (
    SELECT a.*,n.nspname,c.relname,n.nspname||'.'||c.relname AS relation_name,
        pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS default_expr
    FROM pg_catalog.pg_attribute a JOIN pg_catalog.pg_class c ON c.oid=a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
    WHERE a.attnum>0 AND NOT a.attisdropped AND n.nspname IN ('public','private')
),
constraints AS (
    SELECT c.*,
        ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey)
            WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
            ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos) AS source_columns,
        ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey)
            WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
            ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos) AS target_columns
    FROM pg_catalog.pg_constraint c
),
expected_columns(name,type_oid,identity_kind,default_expr) AS (VALUES
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
    ('updated_at','timestamptz'::pg_catalog.regtype,'','now()'),
    ('game_uuid','uuid'::pg_catalog.regtype,'',NULL::text),
    ('layer_uuid','uuid'::pg_catalog.regtype,'',NULL::text)
),
expected_keys(relation_name,check_name,name,kind,columns) AS (VALUES
    ('public.map_labels','key.labels_pk',NULL::text,'p',ARRAY['id']::text[]),
    ('public.map_labels','key.labels_game_slug','map_labels_game_slug_unique','u',ARRAY['game_id','slug']::text[]),
    ('public.map_layers','key.b3a_support','map_layers_legacy_uuid_identity_unique','u',ARRAY['game_id','id','game_uuid','layer_uuid']::text[])
),
expected_fks(name,source_columns,target,target_columns,update_action,delete_action) AS (VALUES
    ('map_labels_layer_fk',ARRAY['game_id','map_layer']::text[],
        'public.map_layers',ARRAY['game_id','id']::text[],'c','a'),
    ('map_labels_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
        'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[],'a','r'),
    ('map_labels_legacy_uuid_layer_fk',ARRAY['game_id','map_layer','game_uuid','layer_uuid']::text[],
        'public.map_layers',ARRAY['game_id','id','game_uuid','layer_uuid']::text[],'a','r')
),
expected_checks(name,expression) AS (VALUES
    ('map_labels_font_size_check','font_size>=10andfont_size<=160'),
    ('map_labels_font_weight_check','font_weight>=100andfont_weight<=900'),
    ('map_labels_color_check','color~''^#[0-9A-Fa-f]{6}$''::text'),
    ('map_labels_opacity_check','opacity>=0andopacity<=1'),
    ('map_labels_slug_format','slug~''^[a-z0-9]+?:-[a-z0-9]+*$''::text')
),
expected_triggers(name,function_name,bits) AS (VALUES
    ('deepmap_map_labels_identity','private.deepmap_resolve_map_label_identity()',23),
    ('deepmap_map_labels_touch_updated_at','private.deepmap_touch_updated_at()',19)
),
labels AS (SELECT pg_catalog.to_jsonb(c) AS row_data FROM public.map_labels c),
layers AS (SELECT pg_catalog.to_jsonb(l) AS row_data FROM public.map_layers l),
mapping AS (SELECT legacy_identifier,game_id FROM private.game_legacy_identifiers),
identity_function AS (SELECT p.* FROM pg_catalog.pg_proc p
    WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_map_label_identity()')),
visibility AS (
    SELECT e.name,EXISTS (SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
        WHERE c.oid=pg_catalog.to_regclass(e.name) AND c.relkind='r'
          AND pg_catalog.has_table_privilege(c.oid,'SELECT')
          AND pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
          AND (NOT c.relrowsecurity OR r.rolsuper OR r.rolbypassrls
              OR (c.relowner=r.oid AND NOT c.relforcerowsecurity))) AS ok
    FROM (VALUES ('public.map_labels'),('public.map_layers'),('private.game_legacy_identifiers'),
        ('public.games'),('public.game_maps')) e(name)
),
checks AS (
    SELECT 'table.rls.'||v.name AS check_name,EXISTS (SELECT 1 FROM pg_catalog.pg_class c
        WHERE c.oid=pg_catalog.to_regclass(v.name) AND c.relkind='r' AND c.relrowsecurity) AS ok,
        'Expected ordinary table with RLS enabled' AS details FROM visibility v
    UNION ALL
    SELECT 'visibility.full.'||name,ok,'Full maintenance SELECT/USAGE and RLS visibility required' FROM visibility
    UNION ALL
    SELECT 'column.labels.'||e.name,EXISTS (SELECT 1 FROM attributes a
        WHERE a.relation_name='public.map_labels' AND a.attname=e.name AND a.atttypid=e.type_oid
          AND a.attnotnull AND a.attidentity::text=e.identity_kind AND a.attgenerated=''
          AND (CASE WHEN e.name='opacity' THEN pg_catalog.replace(pg_catalog.replace(
              pg_catalog.regexp_replace(a.default_expr,'[[:space:]()]','','g'),'::doubleprecision',''),'''','')
              ELSE pg_catalog.replace(a.default_expr,'pg_catalog.now()','now()') END) IS NOT DISTINCT FROM e.default_expr
          AND (e.default_expr IS NOT NULL OR (NOT a.atthasdef AND a.default_expr IS NULL))),
        pg_catalog.format('Expected %s NOT NULL; identity=%s; default=%s',e.type_oid,
            CASE WHEN e.identity_kind='d' THEN 'BY DEFAULT' ELSE 'none' END,COALESCE(e.default_expr,'none'))
    FROM expected_columns e
    UNION ALL
    SELECT 'schema.labels.no_extra_columns',count(*)=0,
        'Unexpected columns='||COALESCE(pg_catalog.string_agg(a.attname,', '),'none')
    FROM attributes a WHERE a.relation_name='public.map_labels'
      AND NOT EXISTS (SELECT 1 FROM expected_columns e WHERE e.name=a.attname)
    UNION ALL
    SELECT e.check_name,(SELECT count(*) FROM constraints c
        WHERE c.conrelid=pg_catalog.to_regclass(e.relation_name) AND c.contype::text=e.kind
          AND (e.name IS NULL OR c.conname=e.name))=1 AND EXISTS (
        SELECT 1 FROM constraints c JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
        WHERE c.conrelid=pg_catalog.to_regclass(e.relation_name) AND c.contype::text=e.kind
          AND (e.name IS NULL OR c.conname=e.name) AND c.source_columns=e.columns
          AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
          AND i.indrelid=c.conrelid AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
          AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnkeyatts=pg_catalog.cardinality(e.columns)
          AND i.indnatts=i.indnkeyatts AND ARRAY(SELECT a.attname::text
              FROM pg_catalog.unnest(i.indkey::smallint[]) WITH ORDINALITY k(num,pos)
              JOIN pg_catalog.pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.num ORDER BY k.pos)=e.columns),
        pg_catalog.format('%s %s; validated/non-deferrable; UNIQUE index valid/ready/live, no predicate/expression/INCLUDE',
            COALESCE(e.name,'legacy PK'),e.columns) FROM expected_keys e
    UNION ALL
    SELECT 'fk.'||e.name,EXISTS (SELECT 1 FROM constraints c
        WHERE c.conrelid=pg_catalog.to_regclass('public.map_labels') AND c.conname=e.name
          AND c.contype='f' AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
          AND c.confmatchtype='s' AND c.confrelid=pg_catalog.to_regclass(e.target)
          AND c.source_columns=e.source_columns AND c.target_columns=e.target_columns
          AND c.confupdtype::text=e.update_action AND c.confdeltype::text=e.delete_action),
        pg_catalog.format('%s -> %s %s; validated/non-deferrable MATCH SIMPLE; UPDATE %s / DELETE %s',
            e.source_columns,e.target,e.target_columns,
            CASE e.update_action WHEN 'c' THEN 'CASCADE' ELSE 'NO ACTION' END,
            CASE e.delete_action WHEN 'r' THEN 'RESTRICT' ELSE 'NO ACTION' END) FROM expected_fks e
    UNION ALL
    SELECT 'index.labels_legacy_lookup',EXISTS (SELECT 1 FROM pg_catalog.pg_index i
        JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid
        WHERE i.indrelid=pg_catalog.to_regclass('public.map_labels') AND c.relname='map_labels_map_lookup_idx'
          AND NOT i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
          AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnkeyatts=4 AND i.indnatts=4
          AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(i.indkey::smallint[])
              WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
              ON a.attrelid=i.indrelid AND a.attnum=k.num ORDER BY k.pos)
              =ARRAY['game_id','map_layer','is_published','id']::text[]),
        'Valid/ready/live lookup index (game_id,map_layer,is_published,id)'
    UNION ALL
    SELECT 'check.labels.'||e.name,EXISTS (SELECT 1 FROM constraints c
        WHERE c.conrelid=pg_catalog.to_regclass('public.map_labels') AND c.conname=e.name
          AND c.contype='c' AND c.convalidated AND NOT c.connoinherit
          AND (CASE WHEN e.name='map_labels_opacity_check' THEN pg_catalog.replace(pg_catalog.replace(
              pg_catalog.regexp_replace(pg_catalog.pg_get_expr(c.conbin,c.conrelid),'[[:space:]()]','','g'),
              '::doubleprecision',''),'''','') ELSE pg_catalog.regexp_replace(
              pg_catalog.pg_get_expr(c.conbin,c.conrelid),'[[:space:]()]','','g') END)
              =pg_catalog.replace(e.expression,'and','AND')),
        'Expected validated legacy expression: '||e.expression FROM expected_checks e
    UNION ALL
    SELECT 'check.labels.exact_count',count(*)=5,'Expected five legacy CHECKs; actual='||count(*)
    FROM constraints WHERE conrelid=pg_catalog.to_regclass('public.map_labels') AND contype='c'
    UNION ALL
    SELECT 'data.labels.null_game_uuid',count(*)=0,'NULL/missing game_uuid rows='||count(*)
    FROM labels WHERE row_data->>'game_uuid' IS NULL
    UNION ALL
    SELECT 'data.labels.null_layer_uuid',count(*)=0,'NULL/missing layer_uuid rows='||count(*)
    FROM labels WHERE row_data->>'layer_uuid' IS NULL
    UNION ALL
    SELECT 'data.labels.missing_mapping',count(*)=0,'Labels without mapping='||count(*) FROM labels c
    WHERE NOT EXISTS (SELECT 1 FROM mapping i WHERE i.legacy_identifier=c.row_data->>'game_id')
    UNION ALL
    SELECT 'data.labels.mapping_exact_match',count(*)=0,'Labels with ambiguous/mismatched mapping='||count(*) FROM labels c
    WHERE (SELECT count(*) FROM mapping i WHERE i.legacy_identifier=c.row_data->>'game_id')<>1
       OR (SELECT count(*) FROM mapping i WHERE i.legacy_identifier=c.row_data->>'game_id'
           AND i.game_id::text=c.row_data->>'game_uuid')<>1
    UNION ALL
    SELECT 'data.labels.missing_legacy_layer',count(*)=0,'Labels without legacy layer='||count(*) FROM labels c
    WHERE NOT EXISTS (SELECT 1 FROM layers l WHERE l.row_data->>'game_id'=c.row_data->>'game_id'
        AND l.row_data->>'id'=c.row_data->>'map_layer')
    UNION ALL
    SELECT 'data.labels.layer_exact_match',count(*)=0,'Labels without exactly one coherent TEXT/UUID layer='||count(*) FROM labels c
    WHERE (SELECT count(*) FROM layers l WHERE l.row_data->>'game_id'=c.row_data->>'game_id'
        AND l.row_data->>'id'=c.row_data->>'map_layer')<>1
       OR (SELECT count(*) FROM layers l WHERE l.row_data->>'game_id'=c.row_data->>'game_id'
        AND l.row_data->>'id'=c.row_data->>'map_layer' AND l.row_data->>'game_uuid'=c.row_data->>'game_uuid'
        AND l.row_data->>'layer_uuid'=c.row_data->>'layer_uuid')<>1
    UNION ALL
    SELECT 'data.labels.game_parent',count(*)=0,'Labels without exactly one existing game parent='||count(*) FROM labels c
    WHERE (SELECT count(*) FROM public.games g WHERE g.id::text=c.row_data->>'game_uuid')<>1
    UNION ALL
    SELECT 'data.labels.layer_map_game_parents',count(*)=0,'Labels without coherent layer/map/game parents='||count(*) FROM labels c
    WHERE (SELECT count(*) FROM layers l JOIN public.game_maps m ON m.id::text=l.row_data->>'game_map_id'
        AND m.game_id::text=l.row_data->>'game_uuid' JOIN public.games g ON g.id=m.game_id
        WHERE l.row_data->>'game_id'=c.row_data->>'game_id' AND l.row_data->>'id'=c.row_data->>'map_layer'
        AND l.row_data->>'layer_uuid'=c.row_data->>'layer_uuid' AND g.id::text=c.row_data->>'game_uuid')<>1
    UNION ALL
    SELECT 'trigger.'||e.name,EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid=pg_catalog.to_regclass('public.map_labels') AND t.tgname=e.name
          AND t.tgfoid=pg_catalog.to_regprocedure(e.function_name) AND t.tgtype=e.bits
          AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgnargs=0
          AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL),
        pg_catalog.format('%s: enabled origin BEFORE %s FOR EACH ROW; no WHEN/args/column filter',e.function_name,
            CASE WHEN e.bits=23 THEN 'INSERT OR UPDATE' ELSE 'UPDATE' END) FROM expected_triggers e
    UNION ALL
    SELECT 'trigger.labels.exact_user_triggers',count(*)=2 AND bool_and(tgname IN (
        'deepmap_map_labels_identity','deepmap_map_labels_touch_updated_at')),
        'Expected two user triggers; internal FK triggers excluded; actual='||count(*)
    FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass('public.map_labels') AND NOT tgisinternal
    UNION ALL
    SELECT 'function.identity.invoker_search_path',EXISTS (SELECT 1 FROM identity_function p
        JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE NOT p.prosecdef AND p.prorettype='trigger'::pg_catalog.regtype AND p.pronargs=0
          AND p.prokind='f' AND l.lanname='plpgsql' AND p.proconfig=ARRAY['search_path=""']::text[]),
        'Expected trigger() PL/pgSQL SECURITY INVOKER, exact empty search_path'
    UNION ALL
    SELECT 'function.identity.direct_acl',EXISTS (SELECT 1 FROM identity_function) AND NOT EXISTS (
        SELECT 1 FROM identity_function p CROSS JOIN LATERAL pg_catalog.aclexplode(
            COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a WHERE a.grantee<>p.proowner),
        'Only owner direct ACL; no PUBLIC/anon/authenticated/service_role or other non-owner grants'
    UNION ALL
    SELECT 'function.identity.no_overloads',count(*)=1,'Expected exactly one private identity resolver; actual='||count(*)
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='private' AND p.proname='deepmap_resolve_map_label_identity'
    UNION ALL
    SELECT 'function.touch.invoker_body',EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
          AND NOT p.prosecdef AND p.prorettype='trigger'::pg_catalog.regtype
          AND pg_catalog.lower(pg_catalog.regexp_replace(p.prosrc,'[[:space:]]','','g'))
              ='beginnew.updated_at:=now();returnnew;end;'),
        'Expected invoker touch function with legacy updated_at := now() body'
    UNION ALL
    SELECT 'scope.no_premature.'||e.relation_name||'.'||e.column_name,
        pg_catalog.to_regclass(e.relation_name) IS NOT NULL AND NOT EXISTS (SELECT 1 FROM attributes a
            WHERE a.relation_name=e.relation_name AND a.attname=e.column_name),
        'Table must exist with no '||e.column_name
    FROM (VALUES ('public.marcadores','game_uuid'),('public.marcadores','layer_uuid'),
        ('public.marker_submissions','game_uuid'),('public.user_notifications','game_uuid'),
        ('public.map_labels','game_map_id')) e(relation_name,column_name)
    UNION ALL
    SELECT 'scope.no_category_uuid_or_group_uuid',count(*)=0,
        'Unexpected public/private columns='||COALESCE(pg_catalog.string_agg(relation_name||'.'||attname,', '),'none')
    FROM attributes WHERE attname IN ('category_uuid','group_uuid')
    UNION ALL
    SELECT 'scope.no_category_uuid_or_group_uuid_named_objects',count(*)=0,
        'Unexpected public/private object names='||COALESCE(pg_catalog.string_agg(object_name,', '),'none')
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
)
SELECT check_name,
    CASE WHEN ok IS TRUE AND (check_name NOT LIKE 'data.%' OR (SELECT bool_and(ok) FROM visibility))
        THEN 'PASS' ELSE 'FAIL' END AS status,
    details || CASE WHEN check_name LIKE 'data.%' AND NOT (SELECT bool_and(ok) FROM visibility)
        THEN '; INVALID DATA RESULT: incomplete maintenance visibility' ELSE '' END AS details
FROM checks ORDER BY check_name;
