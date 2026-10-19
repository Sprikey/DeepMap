-- DeepMap B3a: exact legacy/UUID support key for the future map_labels FK.
-- Manual execution only after review. No row writes, B3 bridge or API changes.
-- The legacy PK proves logical uniqueness, but the future four-column FK
-- requires a matching referencable UNIQUE key. Its extra index is deliberate.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = pg_catalog;

DO $dependencies$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class
        WHERE oid=pg_catalog.to_regclass('public.map_layers')
          AND relkind='r' AND relrowsecurity) THEN
        RAISE EXCEPTION 'B3A_REQUIRES_ORDINARY_RLS_MAP_LAYERS';
    END IF;
    IF pg_catalog.to_regclass('private.game_legacy_identifiers') IS NULL
       OR pg_catalog.to_regclass('public.game_maps') IS NULL
       OR pg_catalog.to_regclass('public.games') IS NULL THEN
        RAISE EXCEPTION 'B3A_MISSING_B1_PARENTS';
    END IF;
END;
$dependencies$;

-- ADD UNIQUE needs this lock anyway. Acquire once before preflight/snapshots.
-- No explicit parent/adjacent locks. Reads and writes of layers wait until
-- COMMIT; 5s bounds acquisition waits, not total index construction time.
LOCK TABLE public.map_layers IN ACCESS EXCLUSIVE MODE;

DO $support_key$
DECLARE
    v_relation oid := 'public.map_layers'::pg_catalog.regclass;
    v_key smallint[];
    v_rows bigint;
    v_data jsonb;
    v_columns jsonb;
    v_constraints jsonb;
    v_indexes jsonb;
    v_triggers jsonb;
    v_functions jsonb;
    v_policies jsonb;
    v_acl jsonb;
    v_new_constraint oid;
    v_new_index oid;
    v_name text;
    v_expected text[];
    v_target text;
    v_target_columns text[];
BEGIN
    -- Exact post-B1 shape. Unknown extensions/partial states require review.
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_inherits
        WHERE inhrelid=v_relation OR inhparent=v_relation)
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_rewrite WHERE ev_class=v_relation) THEN
        RAISE EXCEPTION 'B3A_UNEXPECTED_LAYER_INHERITANCE_OR_RULES';
    END IF;
    IF EXISTS (
        WITH expected(name,type_oid,not_null) AS (VALUES
            ('game_id','text'::pg_catalog.regtype,true),
            ('id','text'::pg_catalog.regtype,true),
            ('name_en','text'::pg_catalog.regtype,true),
            ('name_pt','text'::pg_catalog.regtype,true),
            ('image_source','text'::pg_catalog.regtype,true),
            ('image_ref','text'::pg_catalog.regtype,false),
            ('width','integer'::pg_catalog.regtype,true),
            ('height','integer'::pg_catalog.regtype,true),
            ('sort_order','integer'::pg_catalog.regtype,true),
            ('is_active','boolean'::pg_catalog.regtype,true),
            ('created_at','timestamptz'::pg_catalog.regtype,true),
            ('updated_at','timestamptz'::pg_catalog.regtype,true),
            ('layer_uuid','uuid'::pg_catalog.regtype,true),
            ('game_uuid','uuid'::pg_catalog.regtype,true),
            ('game_map_id','uuid'::pg_catalog.regtype,true)
        ), actual AS (
            SELECT attname::text AS name,atttypid,attnotnull,attidentity,attgenerated
            FROM pg_catalog.pg_attribute WHERE attrelid=v_relation
              AND attnum>0 AND NOT attisdropped
        )
        SELECT 1 FROM expected e FULL JOIN actual a USING(name)
        WHERE e.name IS NULL OR a.name IS NULL OR a.atttypid<>e.type_oid
           OR a.attnotnull IS DISTINCT FROM e.not_null
           OR a.attidentity<>'' OR a.attgenerated<>''
    ) THEN
        RAISE EXCEPTION 'B3A_UNEXPECTED_POST_B1_COLUMNS';
    END IF;

    SELECT ARRAY(SELECT a.attnum FROM pg_catalog.unnest(
        ARRAY['game_id','id','game_uuid','layer_uuid']::text[])
        WITH ORDINALITY k(name,pos)
        JOIN pg_catalog.pg_attribute a ON a.attrelid=v_relation AND a.attname=k.name
        AND a.attnum>0 AND NOT a.attisdropped ORDER BY k.pos) INTO v_key;

    IF pg_catalog.to_regclass('public.map_layers_legacy_uuid_identity_unique') IS NOT NULL
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
           WHERE c.conrelid=v_relation AND (
               c.conname='map_layers_legacy_uuid_identity_unique'
               OR (c.contype IN ('p','u') AND cardinality(c.conkey)=4
                   AND c.conkey @> v_key AND c.conkey <@ v_key)))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_index i
           WHERE i.indrelid=v_relation AND i.indisunique AND i.indnkeyatts=4
             AND ARRAY(SELECT k.num FROM pg_catalog.unnest(i.indkey::smallint[])
                 WITH ORDINALITY k(num,pos) WHERE k.pos<=i.indnkeyatts ORDER BY k.num)
                 = ARRAY(SELECT k.num FROM pg_catalog.unnest(v_key) k(num) ORDER BY k.num)) THEN
        RAISE EXCEPTION 'B3A_SUPPORT_KEY_OR_EQUIVALENT_INDEX_ALREADY_EXISTS';
    END IF;

    IF (SELECT count(*) FROM pg_catalog.pg_constraint
        WHERE conrelid=v_relation AND contype='p')<>1 THEN
        RAISE EXCEPTION 'B3A_UNEXPECTED_PRIMARY_KEY_COUNT';
    END IF;
    FOR v_name,v_expected IN
        SELECT * FROM (VALUES
            (NULL::text,ARRAY['game_id','id']::text[]),
            ('map_layers_layer_uuid_unique',ARRAY['layer_uuid']::text[])) e(name,cols)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
            WHERE c.conrelid=v_relation
              AND ((v_name IS NULL AND c.contype='p') OR (c.conname=v_name AND c.contype='u'))
              AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
              AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey)
                  WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                  ON a.attrelid=v_relation AND a.attnum=k.num ORDER BY k.pos)=v_expected) THEN
            RAISE EXCEPTION 'B3A_INVALID_B1_KEY: %',COALESCE(v_name,'legacy PK');
        END IF;
    END LOOP;

    FOR v_name,v_expected,v_target,v_target_columns IN
        SELECT * FROM (VALUES
            ('map_layers_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
                'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[]),
            ('map_layers_game_map_game_fk',ARRAY['game_map_id','game_uuid']::text[],
                'public.game_maps',ARRAY['id','game_id']::text[])) e(name,cols,target,target_cols)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            WHERE c.conrelid=v_relation AND c.conname=v_name AND c.contype='f'
              AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
              AND c.confrelid=pg_catalog.to_regclass(v_target)
              AND c.confupdtype='a' AND c.confdeltype='r' AND c.confmatchtype='s'
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey)
                  WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                  ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=v_expected
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey)
                  WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                  ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)=v_target_columns) THEN
            RAISE EXCEPTION 'B3A_INVALID_B1_FOREIGN_KEY: %',v_name;
        END IF;
    END LOOP;

    -- Reject hidden RLS subsets rather than validating only visible layers.
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c
        CROSS JOIN pg_catalog.pg_roles r
        WHERE r.rolname=CURRENT_USER AND c.oid IN (v_relation,
            'private.game_legacy_identifiers'::pg_catalog.regclass,
            'public.game_maps'::pg_catalog.regclass,'public.games'::pg_catalog.regclass)
        AND (NOT pg_catalog.has_table_privilege(c.oid,'SELECT')
            OR NOT pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
            OR (c.relrowsecurity AND NOT (r.rolsuper OR r.rolbypassrls
                OR (c.relowner=r.oid AND NOT c.relforcerowsecurity))))) THEN
        RAISE EXCEPTION 'B3A_REQUIRES_FULL_MAINTENANCE_VISIBILITY';
    END IF;

    IF EXISTS (SELECT 1 FROM public.map_layers l
        WHERE l.game_id IS NULL OR l.id IS NULL OR l.game_uuid IS NULL OR l.layer_uuid IS NULL
          OR l.game_map_id IS NULL
          OR (SELECT count(*) FROM private.game_legacy_identifiers m
              JOIN public.games g ON g.id=m.game_id
              WHERE m.legacy_identifier=l.game_id AND m.game_id=l.game_uuid)<>1
          OR (SELECT count(*) FROM private.game_legacy_identifiers m
              WHERE m.legacy_identifier=l.game_id)<>1
          OR (SELECT count(*) FROM public.game_maps m JOIN public.games g ON g.id=m.game_id
              WHERE m.id=l.game_map_id AND m.game_id=l.game_uuid)<>1)
       OR EXISTS (SELECT 1 FROM public.map_layers GROUP BY layer_uuid HAVING count(*)<>1)
       OR EXISTS (SELECT 1 FROM public.map_layers GROUP BY game_id,id HAVING count(*)<>1) THEN
        RAISE EXCEPTION 'B3A_INCONSISTENT_B1_LAYER_DATA';
    END IF;

    -- Known triggers only; this DDL never fires row triggers.
    IF (SELECT count(*) FROM pg_catalog.pg_trigger
        WHERE tgrelid=v_relation AND NOT tgisinternal)<>2
       OR EXISTS (SELECT 1 FROM (VALUES
            ('deepmap_map_layers_identity','private.deepmap_resolve_layer_identity()',23),
            ('deepmap_map_layers_touch_updated_at','private.deepmap_touch_updated_at()',19)
        ) e(name,fn,bits) WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
            JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
            WHERE t.tgrelid=v_relation AND t.tgname=e.name AND NOT t.tgisinternal
              AND t.tgfoid=pg_catalog.to_regprocedure(e.fn) AND t.tgtype=e.bits
              AND t.tgenabled='O' AND t.tgnargs=0 AND t.tgqual IS NULL
              AND t.tgattr=''::pg_catalog.int2vector AND NOT p.prosecdef
              AND p.prorettype='trigger'::pg_catalog.regtype)) THEN
        RAISE EXCEPTION 'B3A_UNEXPECTED_B1_TRIGGERS';
    END IF;

    SELECT count(*),COALESCE(jsonb_agg(to_jsonb(l) ORDER BY l.game_id,l.id),'[]'::jsonb)
        INTO v_rows,v_data FROM public.map_layers l;
    SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.attnum),'[]'::jsonb) INTO v_columns
        FROM pg_catalog.pg_attribute a WHERE a.attrelid=v_relation AND a.attnum>0;
    -- Include default expressions, not just atthasdef, in the column snapshot.
    v_columns := jsonb_build_object('attributes',v_columns,'defaults',
        (SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.adnum),'[]'::jsonb)
         FROM pg_catalog.pg_attrdef d WHERE d.adrelid=v_relation));
    SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.oid),'[]'::jsonb) INTO v_constraints
        FROM pg_catalog.pg_constraint c WHERE c.conrelid=v_relation;
    SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.indexrelid),'[]'::jsonb) INTO v_indexes
        FROM pg_catalog.pg_index i WHERE i.indrelid=v_relation;
    SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.oid),'[]'::jsonb) INTO v_triggers
        FROM pg_catalog.pg_trigger t WHERE t.tgrelid=v_relation;
    SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.oid),'[]'::jsonb) INTO v_functions
        FROM pg_catalog.pg_proc p WHERE p.oid IN (
            pg_catalog.to_regprocedure('private.deepmap_resolve_layer_identity()'),
            pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()'));
    SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.oid),'[]'::jsonb) INTO v_policies
        FROM pg_catalog.pg_policy p WHERE p.polrelid=v_relation;
    SELECT jsonb_build_object('acl',c.relacl,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,
        'owner',c.relowner) INTO v_acl FROM pg_catalog.pg_class c WHERE c.oid=v_relation;

    -- The only schema mutation in B3a; creates its one implicit UNIQUE index.
    ALTER TABLE public.map_layers
        ADD CONSTRAINT map_layers_legacy_uuid_identity_unique
        UNIQUE (game_id,id,game_uuid,layer_uuid) NOT DEFERRABLE;

    SELECT c.oid,c.conindid INTO STRICT v_new_constraint,v_new_index
        FROM pg_catalog.pg_constraint c WHERE c.conrelid=v_relation
          AND c.conname='map_layers_legacy_uuid_identity_unique';
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
        JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
        WHERE c.oid=v_new_constraint AND c.contype='u' AND c.conkey=v_key
          AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
          AND i.indrelid=v_relation AND i.indisunique AND i.indisvalid AND i.indisready
          AND i.indislive AND i.indnkeyatts=4 AND i.indnatts=4
          AND i.indpred IS NULL AND i.indexprs IS NULL) THEN
        RAISE EXCEPTION 'B3A_INVALID_NEW_SUPPORT_KEY';
    END IF;

    IF (SELECT count(*) FROM public.map_layers)<>v_rows
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(l) ORDER BY l.game_id,l.id),'[]'::jsonb)
           FROM public.map_layers l) IS DISTINCT FROM v_data
       OR jsonb_build_object('attributes',
            (SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.attnum),'[]'::jsonb)
             FROM pg_catalog.pg_attribute a WHERE a.attrelid=v_relation AND a.attnum>0),
            'defaults',(SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.adnum),'[]'::jsonb)
             FROM pg_catalog.pg_attrdef d WHERE d.adrelid=v_relation)) IS DISTINCT FROM v_columns
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.oid),'[]'::jsonb)
           FROM pg_catalog.pg_constraint c WHERE c.conrelid=v_relation AND c.oid<>v_new_constraint)
           IS DISTINCT FROM v_constraints
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.indexrelid),'[]'::jsonb)
           FROM pg_catalog.pg_index i WHERE i.indrelid=v_relation AND i.indexrelid<>v_new_index)
           IS DISTINCT FROM v_indexes
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.oid),'[]'::jsonb)
           FROM pg_catalog.pg_trigger t WHERE t.tgrelid=v_relation) IS DISTINCT FROM v_triggers
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.oid),'[]'::jsonb)
           FROM pg_catalog.pg_proc p WHERE p.oid IN (
               pg_catalog.to_regprocedure('private.deepmap_resolve_layer_identity()'),
               pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')))
           IS DISTINCT FROM v_functions
       OR (SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.oid),'[]'::jsonb)
           FROM pg_catalog.pg_policy p WHERE p.polrelid=v_relation) IS DISTINCT FROM v_policies
       OR (SELECT jsonb_build_object('acl',c.relacl,'rls',c.relrowsecurity,
            'force',c.relforcerowsecurity,'owner',c.relowner) FROM pg_catalog.pg_class c
            WHERE c.oid=v_relation) IS DISTINCT FROM v_acl THEN
        RAISE EXCEPTION 'B3A_EXISTING_LAYER_DATA_OR_OBJECTS_CHANGED';
    END IF;
    -- Parent and adjacent tables are only read or untouched by this script.
    -- No global snapshots/locks: concurrent unrelated edits are not B3a changes.
END;
$support_key$;

COMMIT;
