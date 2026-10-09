-- DeepMap post-B3a, pre-B3. Execute MANUALLY after applying B3a.
-- One read-only SELECT; no application/trigger function is called.
-- Run with maintenance SELECT/USAGE privileges and full RLS visibility.
-- A FAIL visibility check invalidates data PASSes. Missing required tables or
-- insufficient SELECT privilege abort execution: an error is never success.
-- Without a pre-B3a baseline, this verifies current invariants, not historical
-- equality of all data, ACLs, policies, objects or row counts.
WITH
attributes AS (
    SELECT a.* FROM pg_catalog.pg_attribute a
    WHERE a.attrelid=pg_catalog.to_regclass('public.map_layers')
      AND a.attnum>0 AND NOT a.attisdropped
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
    WHERE c.conrelid=pg_catalog.to_regclass('public.map_layers')
),
layers AS (SELECT pg_catalog.to_jsonb(l) AS row_data FROM public.map_layers l),
mapping AS (SELECT legacy_identifier,game_id FROM private.game_legacy_identifiers),
expected_columns(name,type_oid) AS (VALUES
    ('game_id','text'::pg_catalog.regtype), ('id','text'::pg_catalog.regtype),
    ('game_uuid','uuid'::pg_catalog.regtype), ('layer_uuid','uuid'::pg_catalog.regtype),
    ('game_map_id','uuid'::pg_catalog.regtype)
),
expected_keys(check_name,constraint_name,kind,columns) AS (VALUES
    ('key.legacy_pk',NULL::text,'p',ARRAY['game_id','id']::text[]),
    ('key.layer_uuid','map_layers_layer_uuid_unique','u',ARRAY['layer_uuid']::text[]),
    ('key.label_fk_support','map_layers_legacy_uuid_identity_unique','u',
        ARRAY['game_id','id','game_uuid','layer_uuid']::text[])
),
expected_fks(name,source_columns,target,target_columns) AS (VALUES
    ('map_layers_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
        'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[]),
    ('map_layers_game_map_game_fk',ARRAY['game_map_id','game_uuid']::text[],
        'public.game_maps',ARRAY['id','game_id']::text[])
),
expected_triggers(name,function_name,type_bits) AS (VALUES
    ('deepmap_map_layers_identity','private.deepmap_resolve_layer_identity()',23),
    ('deepmap_map_layers_touch_updated_at','private.deepmap_touch_updated_at()',19)
),
checks AS (
    SELECT 'table.map_layers.rls' AS check_name, EXISTS (
        SELECT 1 FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass('public.map_layers')
        AND c.relkind='r' AND c.relrowsecurity) AS ok,
        'Expected existing ordinary table with RLS enabled' AS details
    UNION ALL
    SELECT 'column.'||e.name, EXISTS (SELECT 1 FROM attributes a
        WHERE a.attname=e.name AND a.atttypid=e.type_oid AND a.attnotnull
        AND a.attidentity='' AND a.attgenerated=''),
        pg_catalog.format('Expected %s NOT NULL, not generated/identity',e.type_oid)
    FROM expected_columns e
    UNION ALL
    SELECT e.check_name, (SELECT count(*) FROM constraints c
        WHERE c.contype::text=e.kind AND (e.constraint_name IS NULL OR c.conname=e.constraint_name))=1
        AND EXISTS (SELECT 1 FROM constraints c JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
            WHERE c.contype::text=e.kind AND (e.constraint_name IS NULL OR c.conname=e.constraint_name)
            AND c.source_columns=e.columns AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
            AND i.indrelid=c.conrelid AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
            AND i.indpred IS NULL AND i.indexprs IS NULL
            AND i.indnkeyatts=pg_catalog.cardinality(e.columns) AND i.indnatts=i.indnkeyatts
            AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(i.indkey::smallint[])
                WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                ON a.attrelid=i.indrelid AND a.attnum=k.num ORDER BY k.pos)=e.columns),
        pg_catalog.format('Expected %s %s; validated/immediate; UNIQUE index valid/ready/live; no predicate/expression/INCLUDE',
            COALESCE(e.constraint_name,'legacy PK'),e.columns)
    FROM expected_keys e
    UNION ALL
    SELECT 'fk.'||e.name, EXISTS (SELECT 1 FROM constraints c
        WHERE c.conname=e.name AND c.contype='f' AND c.convalidated
        AND NOT c.condeferrable AND NOT c.condeferred AND c.confmatchtype='s'
        AND c.source_columns=e.source_columns AND c.target_columns=e.target_columns
        AND c.confrelid=pg_catalog.to_regclass(e.target)
        AND c.confupdtype='a' AND c.confdeltype='r'),
        pg_catalog.format('%s -> %s %s; validated, non-deferrable; UPDATE NO ACTION / DELETE RESTRICT',
            e.source_columns,e.target,e.target_columns)
    FROM expected_fks e
    UNION ALL
    SELECT 'data.null_identity', count(*)=0, 'Rows with NULL/missing identity component='||count(*)
    FROM layers WHERE row_data->>'game_id' IS NULL OR row_data->>'id' IS NULL
        OR row_data->>'game_uuid' IS NULL OR row_data->>'layer_uuid' IS NULL
        OR row_data->>'game_map_id' IS NULL
    UNION ALL
    SELECT 'data.duplicate_layer_uuid', count(*)=0, 'Duplicate UUID groups='||count(*)
    FROM (SELECT row_data->>'layer_uuid' FROM layers GROUP BY row_data->>'layer_uuid' HAVING count(*)>1) d
    UNION ALL
    SELECT 'data.duplicate_legacy_pk', count(*)=0, 'Duplicate legacy PK groups='||count(*)
    FROM (SELECT row_data->>'game_id',row_data->>'id' FROM layers
        GROUP BY row_data->>'game_id',row_data->>'id' HAVING count(*)>1) d
    UNION ALL
    SELECT 'data.duplicate_support_key', count(*)=0, 'Duplicate four-column groups='||count(*)
    FROM (SELECT row_data->>'game_id',row_data->>'id',row_data->>'game_uuid',row_data->>'layer_uuid'
        FROM layers GROUP BY row_data->>'game_id',row_data->>'id',row_data->>'game_uuid',row_data->>'layer_uuid'
        HAVING count(*)>1) d
    UNION ALL
    SELECT 'data.mapping_exact_identity', count(*)=0, 'Layers with absent/ambiguous/mismatched mapping='||count(*)
    FROM layers l WHERE (SELECT count(*) FROM mapping m WHERE m.legacy_identifier=l.row_data->>'game_id')<>1
        OR (SELECT count(*) FROM mapping m WHERE m.legacy_identifier=l.row_data->>'game_id'
            AND m.game_id::text=l.row_data->>'game_uuid')<>1
    UNION ALL
    SELECT 'data.game_parent', count(*)=0, 'Layers without exactly one existing game parent='||count(*)
    FROM layers l WHERE (SELECT count(*) FROM public.games g WHERE g.id::text=l.row_data->>'game_uuid')<>1
    UNION ALL
    SELECT 'data.map_exact_identity', count(*)=0, 'Layers without exactly one matching map/game pair='||count(*)
    FROM layers l WHERE (SELECT count(*) FROM public.game_maps m
        WHERE m.id::text=l.row_data->>'game_map_id' AND m.game_id::text=l.row_data->>'game_uuid')<>1
    UNION ALL
    SELECT 'data.map_game_parent', count(*)=0, 'Layers without exactly one map with matching existing game parent='||count(*)
    FROM layers l WHERE (SELECT count(*) FROM public.game_maps m JOIN public.games g ON g.id=m.game_id
        WHERE m.id::text=l.row_data->>'game_map_id' AND m.game_id::text=l.row_data->>'game_uuid')<>1
    UNION ALL
    SELECT 'trigger.'||e.name, EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
        JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
        WHERE t.tgrelid=pg_catalog.to_regclass('public.map_layers') AND t.tgname=e.name
        AND NOT t.tgisinternal AND t.tgenabled='O' AND t.tgtype=e.type_bits
        AND t.tgfoid=pg_catalog.to_regprocedure(e.function_name) AND t.tgnargs=0
        AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL
        AND NOT p.prosecdef AND p.prorettype='trigger'::pg_catalog.regtype),
        pg_catalog.format('%s; enabled origin, BEFORE %s FOR EACH ROW; no WHEN/args/column filter; invoker trigger function',
            e.function_name,CASE WHEN e.type_bits=23 THEN 'INSERT OR UPDATE' ELSE 'UPDATE' END)
    FROM expected_triggers e
    UNION ALL
    SELECT 'scope.layer_user_triggers', count(*)=2 AND bool_and(tgname IN (
        'deepmap_map_layers_identity','deepmap_map_layers_touch_updated_at')),
        'Expected exactly two known user triggers; actual='||count(*)
    FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass('public.map_layers') AND NOT tgisinternal
    UNION ALL
    SELECT 'visibility.full.'||e.name, EXISTS (SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
        WHERE c.oid=pg_catalog.to_regclass(e.name)
        AND pg_catalog.has_table_privilege(c.oid,'SELECT') AND pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
        AND (NOT c.relrowsecurity OR r.rolsuper OR r.rolbypassrls OR (c.relowner=r.oid AND NOT c.relforcerowsecurity))),
        'Full maintenance visibility required; FAIL invalidates all data checks'
    FROM (VALUES ('public.map_layers'),('private.game_legacy_identifiers'),('public.games'),('public.game_maps')) e(name)
    UNION ALL
    SELECT 'scope.pre_b3.map_labels_no_'||e.name,
        pg_catalog.to_regclass('public.map_labels') IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid=pg_catalog.to_regclass('public.map_labels')
            AND a.attname=e.name AND a.attnum>0 AND NOT a.attisdropped),
        'map_labels must exist and have no '||e.name||'; no label bridge is validated'
    FROM (VALUES ('game_uuid'),('layer_uuid')) e(name)
)
SELECT check_name, CASE WHEN ok IS TRUE THEN 'PASS' ELSE 'FAIL' END AS status, details
FROM checks ORDER BY check_name;
