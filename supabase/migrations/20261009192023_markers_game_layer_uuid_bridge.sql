-- DeepMap B4b: parallel marker game/layer UUID bridge, legacy TEXT authority.
-- Manual review/execution only. No consumer/RPC/editor/publication changes.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = pg_catalog;

DO $dependencies$
BEGIN
    IF EXISTS (SELECT 1 FROM (VALUES ('private.game_legacy_identifiers'),('public.map_layers'),
        ('public.marcadores'),('private.marker_editor_audit'),('public.games'),('public.game_maps')) e(name)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
            WHERE c.oid=pg_catalog.to_regclass(e.name) AND c.relkind='r' AND c.relrowsecurity)) THEN
        RAISE EXCEPTION 'B4B_REQUIRES_ORDINARY_RLS_TABLES';
    END IF;
    IF pg_catalog.to_regprocedure('private.deepmap_stamp_marker_audit()') IS NULL
       OR pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()') IS NULL THEN
        RAISE EXCEPTION 'B4B_AUDIT_OR_TOUCH_MISSING';
    END IF;
END;
$dependencies$;

-- Parent-first. Parent mode stabilizes DML and is needed by ADD FK; reads pass.
-- Markers need ACCESS EXCLUSIVE for columns/NOT NULL. SHARE audit stabilizes
-- direct RPC writes for its exact snapshot. No other explicit table locks.
LOCK TABLE private.game_legacy_identifiers IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.map_layers IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.marcadores IN ACCESS EXCLUSIVE MODE;
LOCK TABLE private.marker_editor_audit IN SHARE MODE;

DO $bridge$
DECLARE
    v_markers oid := 'public.marcadores'::pg_catalog.regclass;
    v_rows bigint;
    v_affected bigint;
    v_before jsonb;
    v_after jsonb;
    v_identity_function jsonb;
    v_relation text;
    v_name text;
    v_kind text;
    v_cols text[];
    v_target text;
    v_target_cols text[];
    v_up text;
    v_del text;
    v_expected_audit text := pg_catalog.replace($audit_b4a$
declare
    v_user_id uuid := (select auth.uid());
    v_content_changed boolean := false;
begin
    if tg_op = 'INSERT' then
        insert into private.marker_editor_audit as audit (
            marker_id,
            created_by,
            created_at,
            updated_by,
            updated_at,
            published_by,
            published_at,
            approved_by,
            approved_at
        ) values (
            new.id,
            v_user_id,
            now(),
            v_user_id,
            now(),
            case when new.is_published then v_user_id else null end,
            case when new.is_published then now() else null end,
            null,
            null
        )
        on conflict (marker_id) do update
        set
            updated_by = excluded.updated_by,
            updated_at = excluded.updated_at,
            published_by = case
                when new.is_published then coalesce(audit.published_by, excluded.published_by)
                else audit.published_by
            end,
            published_at = case
                when new.is_published then coalesce(audit.published_at, excluded.published_at)
                else audit.published_at
            end,
            approved_by = null,
            approved_at = null;

        return new;
    end if;

    -- B4a: only a genuine UUID-shadow-only UPDATE bypasses the audit UPSERT.
    -- is_published stays in both projections; missing JSONB keys are safe.
    if tg_op = 'UPDATE'
       and (pg_catalog.to_jsonb(new) - 'updated_at')
           is distinct from (pg_catalog.to_jsonb(old) - 'updated_at')
       and (pg_catalog.to_jsonb(new) - ARRAY['updated_at','game_uuid','layer_uuid']::text[])
           is not distinct from
           (pg_catalog.to_jsonb(old) - ARRAY['updated_at','game_uuid','layer_uuid']::text[]) then
        return new;
    end if;

    -- Publication toggles alone do not count as a content modification.
    v_content_changed :=
        (to_jsonb(new) - ARRAY['updated_at','is_published','game_uuid','layer_uuid']::text[])
        is distinct from
        (to_jsonb(old) - ARRAY['updated_at','is_published','game_uuid','layer_uuid']::text[]);

    insert into private.marker_editor_audit as audit (
        marker_id,
        created_by,
        created_at,
        updated_by,
        updated_at,
        published_by,
        published_at,
        approved_by,
        approved_at
    ) values (
        new.id,
        null,
        null,
        case when v_content_changed then v_user_id else null end,
        case when v_content_changed then now() else null end,
        case when new.is_published then v_user_id else null end,
        case when new.is_published then now() else null end,
        null,
        null
    )
    on conflict (marker_id) do update
    set
        updated_by = case
            when v_content_changed then v_user_id
            else audit.updated_by
        end,
        updated_at = case
            when v_content_changed then now()
            else audit.updated_at
        end,
        published_by = case
            when new.is_published
                 and (
                     old.is_published = false
                     or old.is_published is null
                     or audit.published_by is null
                 )
                then v_user_id
            else audit.published_by
        end,
        published_at = case
            when new.is_published
                 and (
                     old.is_published = false
                     or old.is_published is null
                     or audit.published_at is null
                 )
                then now()
            else audit.published_at
        end,
        -- Any direct content edit creates a new version that has not passed moderation.
        approved_by = case
            when v_content_changed then null
            else audit.approved_by
        end,
        approved_at = case
            when v_content_changed then null
            else audit.approved_at
        end;

    return new;
end;
$audit_b4a$,pg_catalog.chr(13),'');
    -- Same read-only snapshot before/after. Exclude only approved additions and
    -- technical marker updated_at; all audit values/timestamps stay included.
    v_snapshot_sql text := $snapshot$
        WITH relations AS (
            SELECT oid FROM pg_catalog.pg_class WHERE oid IN (
                'public.marcadores'::pg_catalog.regclass,'private.marker_editor_audit'::pg_catalog.regclass,
                'private.game_legacy_identifiers'::pg_catalog.regclass,'public.map_layers'::pg_catalog.regclass,
                'public.games'::pg_catalog.regclass,'public.game_maps'::pg_catalog.regclass)
        ), additions AS (
            SELECT oid FROM pg_catalog.pg_constraint WHERE conrelid='public.marcadores'::pg_catalog.regclass
              AND conname IN ('marcadores_legacy_game_uuid_fk','marcadores_legacy_uuid_layer_fk')
        )
        SELECT jsonb_build_object(
            'marker_count',(SELECT count(*) FROM public.marcadores),
            'marker_legacy',(SELECT COALESCE(jsonb_agg(to_jsonb(m)-ARRAY['game_uuid','layer_uuid','updated_at']::text[]
                ORDER BY m.id),'[]'::jsonb) FROM public.marcadores m),
            'audit',(SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.marker_id),'[]'::jsonb)
                FROM private.marker_editor_audit a),
            'mapping',(SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.legacy_identifier),'[]'::jsonb)
                FROM private.game_legacy_identifiers i),
            'layers',(SELECT COALESCE(jsonb_agg(to_jsonb(l) ORDER BY l.game_id,l.id),'[]'::jsonb)
                FROM public.map_layers l),
            'columns',(SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.attrelid,a.attnum),'[]'::jsonb)
                FROM pg_catalog.pg_attribute a WHERE a.attrelid IN (SELECT oid FROM relations) AND a.attnum>0
                  AND NOT (a.attrelid='public.marcadores'::pg_catalog.regclass AND a.attname IN ('game_uuid','layer_uuid'))),
            'defaults',(SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.adrelid,d.adnum),'[]'::jsonb)
                FROM pg_catalog.pg_attrdef d WHERE d.adrelid IN (SELECT oid FROM relations)),
            'constraints',(SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.oid),'[]'::jsonb)
                FROM pg_catalog.pg_constraint c WHERE c.conrelid IN (SELECT oid FROM relations)
                  AND c.oid NOT IN (SELECT oid FROM additions)
                  AND NOT (c.conrelid='public.marcadores'::pg_catalog.regclass AND c.contype='n'
                    AND c.conkey <@ ARRAY(SELECT a.attnum FROM pg_catalog.pg_attribute a
                        WHERE a.attrelid=c.conrelid AND a.attname IN ('game_uuid','layer_uuid') AND NOT a.attisdropped))),
            'indexes',(SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.indexrelid),'[]'::jsonb)
                FROM pg_catalog.pg_index i WHERE i.indrelid IN (SELECT oid FROM relations)),
            'triggers',(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.oid),'[]'::jsonb)
                FROM pg_catalog.pg_trigger t WHERE t.tgrelid IN (SELECT oid FROM relations)
                  AND NOT (t.tgrelid='public.marcadores'::pg_catalog.regclass AND t.tgname='deepmap_marcadores_identity')
                  AND NOT (t.tgisinternal AND t.tgconstraint IN (SELECT oid FROM additions))),
            'policies',(SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.oid),'[]'::jsonb)
                FROM pg_catalog.pg_policy p WHERE p.polrelid IN (SELECT oid FROM relations)),
            'security',(SELECT jsonb_agg(jsonb_build_object('oid',c.oid,'owner',c.relowner,
                'acl',c.relacl,'rls',c.relrowsecurity,'force',c.relforcerowsecurity) ORDER BY c.oid)
                FROM pg_catalog.pg_class c WHERE c.oid IN (SELECT oid FROM relations)),
            'functions',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.oid) FROM pg_catalog.pg_proc p
                WHERE p.oid IN (pg_catalog.to_regprocedure('private.deepmap_stamp_marker_audit()'),
                    pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()'),
                    pg_catalog.to_regprocedure('public.get_deepmap_role()'),
                    pg_catalog.to_regprocedure('private.is_deepmap_admin()'),
                    pg_catalog.to_regprocedure('public.review_marker_submission(bigint,text,text)'),
                    pg_catalog.to_regprocedure('public.review_marker_submission_v2(bigint,text,text,jsonb)')))
        )
    $snapshot$;
BEGIN
    -- Complete final marker shape, including the later optional Portuguese title.
    -- Legacy game/layer defaults are inspected, never used by the resolver.
    IF EXISTS (
        WITH expected(name,type_oid,nn,identity_kind,default_expr) AS (VALUES
            ('id','bigint'::pg_catalog.regtype,true,'d',NULL::text),
            ('game_id','text'::pg_catalog.regtype,true,'','''elden-ring''::text'),
            ('map_layer','text'::pg_catalog.regtype,true,'','''surface''::text'),
            ('slug','text'::pg_catalog.regtype,true,'',NULL::text),
            ('category_id','text'::pg_catalog.regtype,true,'',NULL::text),
            ('region_id','text'::pg_catalog.regtype,false,'',NULL::text),
            ('title_en','text'::pg_catalog.regtype,true,'',NULL::text),
            ('title_pt','text'::pg_catalog.regtype,false,'',NULL::text),
            ('coordinate_x','double precision'::pg_catalog.regtype,true,'',NULL::text),
            ('coordinate_y','double precision'::pg_catalog.regtype,true,'',NULL::text),
            ('description_en','text'::pg_catalog.regtype,false,'',NULL::text),
            ('description_pt','text'::pg_catalog.regtype,false,'',NULL::text),
            ('video_url','text'::pg_catalog.regtype,false,'',NULL::text),
            ('color_override','text'::pg_catalog.regtype,false,'',NULL::text),
            ('icon_source_override','text'::pg_catalog.regtype,false,'',NULL::text),
            ('icon_ref_override','text'::pg_catalog.regtype,false,'',NULL::text),
            ('marker_width_override','integer'::pg_catalog.regtype,false,'',NULL::text),
            ('marker_height_override','integer'::pg_catalog.regtype,false,'',NULL::text),
            ('symbol_size_override','integer'::pg_catalog.regtype,false,'',NULL::text),
            ('is_published','boolean'::pg_catalog.regtype,true,'','false'),
            ('created_at','timestamptz'::pg_catalog.regtype,true,'','now()'),
            ('updated_at','timestamptz'::pg_catalog.regtype,true,'','now()')
        ), actual AS (
            SELECT a.attname::text AS name,a.atttypid,a.attnotnull,a.attidentity::text,a.attgenerated,
                pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS default_expr
            FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d
              ON d.adrelid=a.attrelid AND d.adnum=a.attnum
            WHERE a.attrelid=v_markers AND a.attnum>0 AND NOT a.attisdropped
        ) SELECT 1 FROM expected e FULL JOIN actual a USING(name)
        WHERE e.name IS NULL OR a.name IS NULL OR a.atttypid<>e.type_oid OR a.attnotnull IS DISTINCT FROM e.nn
          OR a.attidentity<>e.identity_kind OR a.attgenerated<>'' OR a.default_expr IS DISTINCT FROM e.default_expr
    ) THEN RAISE EXCEPTION 'B4B_UNEXPECTED_MARKER_SCHEMA_OR_PARTIAL_BRIDGE'; END IF;
    IF EXISTS (SELECT 1 FROM (VALUES
        ('private.game_legacy_identifiers','legacy_identifier','text'::pg_catalog.regtype),
        ('private.game_legacy_identifiers','game_id','uuid'::pg_catalog.regtype),
        ('public.map_layers','game_id','text'::pg_catalog.regtype),
        ('public.map_layers','id','text'::pg_catalog.regtype),
        ('public.map_layers','game_uuid','uuid'::pg_catalog.regtype),
        ('public.map_layers','layer_uuid','uuid'::pg_catalog.regtype),
        ('public.map_layers','game_map_id','uuid'::pg_catalog.regtype),
        ('public.games','id','uuid'::pg_catalog.regtype),
        ('public.game_maps','id','uuid'::pg_catalog.regtype),
        ('public.game_maps','game_id','uuid'::pg_catalog.regtype)
    ) e(rel,name,type_oid) LEFT JOIN pg_catalog.pg_attribute a
        ON a.attrelid=pg_catalog.to_regclass(e.rel) AND a.attname=e.name AND a.attnum>0 AND NOT a.attisdropped
        WHERE a.attname IS NULL OR a.atttypid<>e.type_oid OR NOT a.attnotnull
          OR a.attidentity<>'' OR a.attgenerated<>'') THEN
        RAISE EXCEPTION 'B4B_UNEXPECTED_PARENT_COLUMNS';
    END IF;
    IF EXISTS (
        WITH expected(name,type_oid,nn) AS (VALUES
            ('marker_id','bigint'::pg_catalog.regtype,true),
            ('created_by','uuid'::pg_catalog.regtype,false),
            ('created_at','timestamptz'::pg_catalog.regtype,false),
            ('updated_by','uuid'::pg_catalog.regtype,false),
            ('updated_at','timestamptz'::pg_catalog.regtype,false),
            ('published_by','uuid'::pg_catalog.regtype,false),
            ('published_at','timestamptz'::pg_catalog.regtype,false),
            ('approved_by','uuid'::pg_catalog.regtype,false),
            ('approved_at','timestamptz'::pg_catalog.regtype,false)
        ), actual AS (SELECT attname::text AS name,atttypid,attnotnull,atthasdef,attidentity,attgenerated
            FROM pg_catalog.pg_attribute WHERE attrelid='private.marker_editor_audit'::pg_catalog.regclass
              AND attnum>0 AND NOT attisdropped)
        SELECT 1 FROM expected e FULL JOIN actual a USING(name)
        WHERE e.name IS NULL OR a.name IS NULL OR a.atttypid<>e.type_oid OR a.attnotnull IS DISTINCT FROM e.nn
          OR a.atthasdef OR a.attidentity<>'' OR a.attgenerated<>''
    ) THEN RAISE EXCEPTION 'B4B_UNEXPECTED_AUDIT_SCHEMA'; END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='private' AND p.proname ~ '^deepmap_resolve_marker.*identity$')
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conrelid=v_markers
           AND conname IN ('marcadores_legacy_game_uuid_fk','marcadores_legacy_uuid_layer_fk'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_inherits
           WHERE inhrelid IN (v_markers,'private.marker_editor_audit'::pg_catalog.regclass)
              OR inhparent IN (v_markers,'private.marker_editor_audit'::pg_catalog.regclass))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_rewrite
           WHERE ev_class IN (v_markers,'private.marker_editor_audit'::pg_catalog.regclass)) THEN
        RAISE EXCEPTION 'B4B_EXISTING_RESOLVER_FK_OR_UNKNOWN_RULES';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_constraint WHERE conrelid=v_markers AND contype='c')<>7
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conrelid=v_markers AND contype='c'
           AND (NOT convalidated OR conname<>ALL(ARRAY['marcadores_slug_format','marcadores_color_override_format',
               'marcadores_icon_source_override_valid','marcadores_icon_override_ref_required',
               'marcadores_marker_width_override_valid','marcadores_marker_height_override_valid',
               'marcadores_symbol_size_override_valid']))) THEN
        RAISE EXCEPTION 'B4B_UNEXPECTED_LEGACY_CHECKS';
    END IF;
    FOR v_relation,v_name,v_kind,v_cols IN SELECT * FROM (VALUES
        ('public.marcadores',NULL::text,'p',ARRAY['id']::text[]),
        ('private.marker_editor_audit',NULL::text,'p',ARRAY['marker_id']::text[]),
        ('public.map_layers',NULL::text,'p',ARRAY['game_id','id']::text[]),
        ('public.map_layers','map_layers_layer_uuid_unique','u',ARRAY['layer_uuid']::text[]),
        ('public.map_layers','map_layers_legacy_uuid_identity_unique','u',ARRAY['game_id','id','game_uuid','layer_uuid']::text[]),
        ('private.game_legacy_identifiers','game_legacy_identifiers_identifier_game_unique','u',ARRAY['legacy_identifier','game_id']::text[]),
        ('public.game_maps','game_maps_id_game_unique','u',ARRAY['id','game_id']::text[])
    ) e(rel,name,kind,cols)
    LOOP
        IF (SELECT count(*) FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass(v_relation)
            AND c.contype::text=v_kind AND (v_name IS NULL OR c.conname=v_name))<>1
           OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
            WHERE c.conrelid=pg_catalog.to_regclass(v_relation) AND c.contype::text=v_kind
              AND (v_name IS NULL OR c.conname=v_name) AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
              AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
              AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnkeyatts=cardinality(v_cols) AND i.indnatts=i.indnkeyatts
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey)
                  WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                  ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=v_cols) THEN
            RAISE EXCEPTION 'B4B_INVALID_REQUIRED_KEY: %.%',v_relation,COALESCE(v_name,'PK');
        END IF;
    END LOOP;
    FOR v_relation,v_name,v_cols,v_target,v_target_cols,v_up,v_del IN SELECT * FROM (VALUES
        ('public.marcadores','marcadores_layer_fk',ARRAY['game_id','map_layer']::text[],
            'public.map_layers',ARRAY['game_id','id']::text[],'c','a'),
        ('public.marcadores','marcadores_category_fk',ARRAY['game_id','category_id']::text[],
            'public.marker_categories',ARRAY['game_id','id']::text[],'c','a'),
        ('private.marker_editor_audit','marker_editor_audit_marker_id_fkey',ARRAY['marker_id']::text[],
            'public.marcadores',ARRAY['id']::text[],'a','c'),
        ('public.map_layers','map_layers_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
            'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[],'a','r'),
        ('public.map_layers','map_layers_game_map_game_fk',ARRAY['game_map_id','game_uuid']::text[],
            'public.game_maps',ARRAY['id','game_id']::text[],'a','r')
    ) e(rel,name,cols,target,target_cols,up,del)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            WHERE c.conrelid=pg_catalog.to_regclass(v_relation) AND c.conname=v_name AND c.contype='f'
              AND c.confrelid=pg_catalog.to_regclass(v_target) AND c.convalidated
              AND NOT c.condeferrable AND NOT c.condeferred AND c.confmatchtype='s'
              AND c.confupdtype::text=v_up AND c.confdeltype::text=v_del
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey)
                  WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                  ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=v_cols
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey)
                  WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                  ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)=v_target_cols) THEN
            RAISE EXCEPTION 'B4B_INVALID_REQUIRED_FK: %',v_name;
        END IF;
    END LOOP;
    -- Parents must retain validated game references; no extra game/map locks.
    IF EXISTS (SELECT 1 FROM (VALUES ('private.game_legacy_identifiers'),('public.game_maps')) e(rel)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass(e.rel)
          AND c.contype='f' AND c.confrelid='public.games'::pg_catalog.regclass AND c.convalidated
          AND NOT c.condeferrable AND c.confupdtype='a' AND c.confdeltype='r'
          AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute
              WHERE attrelid=c.conrelid AND attname='game_id' AND NOT attisdropped)]::smallint[]
          AND c.confkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute
              WHERE attrelid=c.confrelid AND attname='id' AND NOT attisdropped)]::smallint[])) THEN
        RAISE EXCEPTION 'B4B_INVALID_GAME_PARENT_FOREIGN_KEYS';
    END IF;
    FOR v_name,v_kind,v_cols IN SELECT * FROM (VALUES
        ('marcadores_game_slug_unique','unique',ARRAY['game_id','slug']::text[]),
        ('marcadores_map_lookup_idx','lookup',ARRAY['game_id','map_layer','is_published','category_id']::text[])
    ) e(name,kind,cols)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid
            WHERE i.indrelid=v_markers AND c.relname=v_name AND i.indisunique=(v_kind='unique')
              AND i.indisvalid AND i.indisready AND i.indislive AND i.indpred IS NULL AND i.indexprs IS NULL
              AND i.indnkeyatts=cardinality(v_cols) AND i.indnatts=i.indnkeyatts
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(i.indkey::smallint[])
                  WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                  ON a.attrelid=i.indrelid AND a.attnum=k.num ORDER BY k.pos)=v_cols) THEN
            RAISE EXCEPTION 'B4B_INVALID_LEGACY_INDEX: %',v_name;
        END IF;
    END LOOP;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_stamp_marker_audit()')
          AND p.pronargs=0 AND p.prorettype='trigger'::pg_catalog.regtype AND p.prokind='f' AND NOT p.proretset
          AND l.lanname='plpgsql' AND p.prosecdef AND p.proconfig=ARRAY['search_path=""']::text[]
          AND p.provolatile='v' AND p.proparallel='u' AND NOT p.proleakproof AND NOT p.proisstrict
          AND p.procost=100 AND p.prorows=0 AND replace(p.prosrc,chr(13),'')=v_expected_audit)
       OR (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='private' AND p.proname='deepmap_stamp_marker_audit')<>1
       OR (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgrelid=v_markers AND NOT tgisinternal)<>2
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgrelid='private.marker_editor_audit'::pg_catalog.regclass AND NOT tgisinternal)
       OR EXISTS (SELECT 1 FROM (VALUES
            ('deepmap_marker_editor_audit','private.deepmap_stamp_marker_audit()',21),
            ('deepmap_marcadores_touch_updated_at','private.deepmap_touch_updated_at()',19)
        ) e(name,fn,bits) WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
            WHERE t.tgrelid=v_markers AND t.tgname=e.name AND t.tgfoid=pg_catalog.to_regprocedure(e.fn)
              AND t.tgtype=e.bits AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgnargs=0
              AND t.tgqual IS NULL AND t.tgattr=''::pg_catalog.int2vector))
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
           AND NOT p.prosecdef AND p.prorettype='trigger'::pg_catalog.regtype
           AND lower(regexp_replace(p.prosrc,'[[:space:]]','','g'))='beginnew.updated_at:=now();returnnew;end;') THEN
        RAISE EXCEPTION 'B4B_REQUIRES_EXACT_B4A_AUDIT_AND_LEGACY_TRIGGERS';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c CROSS JOIN pg_catalog.pg_roles r
        WHERE c.oid IN (v_markers,'private.marker_editor_audit'::pg_catalog.regclass,
            'private.game_legacy_identifiers'::pg_catalog.regclass,'public.map_layers'::pg_catalog.regclass,
            'public.games'::pg_catalog.regclass,'public.game_maps'::pg_catalog.regclass) AND r.rolname=CURRENT_USER
          AND (NOT pg_catalog.has_table_privilege(c.oid,'SELECT') OR NOT pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
            OR NOT (r.rolsuper OR r.rolbypassrls OR (c.relowner=r.oid AND NOT c.relforcerowsecurity)))) THEN
        RAISE EXCEPTION 'B4B_REQUIRES_FULL_MAINTENANCE_VISIBILITY';
    END IF;
    -- Direct Admin writer dependencies; no grant/policy changes.
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid=pg_catalog.to_regprocedure('public.get_deepmap_role()')
          AND lower(regexp_replace(p.prosrc,'[[:space:]]','','g'))=
            'selectcasewhenprivate.is_deepmap_banned()then''banned''whenprivate.is_deepmap_admin()then''admin''whenprivate.is_deepmap_moderator()then''moderator''else''user''end;') THEN
        RAISE EXCEPTION 'B4B_UNKNOWN_ADMIN_ROLE_HELPER_CONTRACT';
    END IF;
    IF NOT pg_catalog.has_schema_privilege('authenticated','private','USAGE')
       OR NOT pg_catalog.has_table_privilege('authenticated','private.game_legacy_identifiers','SELECT')
       OR NOT pg_catalog.has_table_privilege('authenticated','public.map_layers','SELECT')
       OR NOT pg_catalog.has_function_privilege('authenticated','public.get_deepmap_role()','EXECUTE')
       OR NOT pg_catalog.has_function_privilege('authenticated','private.is_deepmap_admin()','EXECUTE')
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='private.game_legacy_identifiers'::pg_catalog.regclass
           AND p.polname='game_legacy_identifiers_admin_read' AND p.polcmd='r' AND p.polpermissive
           AND ('authenticated'::pg_catalog.regrole)::oid=ANY(p.polroles)
           AND regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'[[:space:]()]','','g') IN (
               'SELECTpublic.get_deepmap_roleASget_deepmap_role=''admin''::text',
               'SELECTget_deepmap_roleASget_deepmap_role=''admin''::text'))
       OR EXISTS (SELECT 1 FROM (VALUES ('public.map_layers','map_layers_admin_all'),('public.marcadores','marcadores_admin_all')) e(rel,name)
           WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid=pg_catalog.to_regclass(e.rel)
               AND p.polname=e.name AND p.polcmd='*' AND p.polpermissive
               AND ('authenticated'::pg_catalog.regrole)::oid=ANY(p.polroles)
               AND regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'[[:space:]()]','','g')='private.is_deepmap_admin'
               AND regexp_replace(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),'[[:space:]()]','','g')='private.is_deepmap_admin'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid IN (
           'private.game_legacy_identifiers'::pg_catalog.regclass,'public.map_layers'::pg_catalog.regclass)
           AND NOT p.polpermissive AND p.polcmd IN ('r','*')) THEN
        RAISE EXCEPTION 'B4B_ADMIN_INVOKER_AUTHORIZATION_REQUIRES_REVIEW';
    END IF;
    -- INVOKER trigger runs as the effective owner inside DEFINER moderation RPCs.
    -- Require full parent visibility for those owners; never widen grants/RLS.
    IF EXISTS (SELECT 1 FROM (VALUES ('public.review_marker_submission(bigint,text,text)'),
        ('public.review_marker_submission_v2(bigint,text,text,jsonb)')) e(signature)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
            WHERE p.oid=pg_catalog.to_regprocedure(e.signature) AND p.prosecdef
              AND p.proconfig=ARRAY['search_path=""']::text[]
              AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c WHERE c.oid IN (
                  'private.game_legacy_identifiers'::pg_catalog.regclass,'public.map_layers'::pg_catalog.regclass)
                AND (NOT pg_catalog.has_table_privilege(r.oid,c.oid,'SELECT')
                  OR NOT pg_catalog.has_schema_privilege(r.oid,c.relnamespace,'USAGE')
                  OR NOT (r.rolsuper OR r.rolbypassrls OR (r.oid=c.relowner AND NOT c.relforcerowsecurity)))))) THEN
        RAISE EXCEPTION 'B4B_MODERATION_RPC_OWNER_CANNOT_RESOLVE_IDENTITY';
    END IF;
    IF EXISTS (SELECT 1 FROM public.marcadores c
        WHERE (SELECT count(*) FROM private.game_legacy_identifiers i WHERE i.legacy_identifier=c.game_id)<>1
          OR (SELECT count(*) FROM public.map_layers l WHERE l.game_id=c.game_id AND l.id=c.map_layer)<>1
          OR (SELECT count(*) FROM private.game_legacy_identifiers i JOIN public.games g ON g.id=i.game_id
              JOIN public.map_layers l ON l.game_id=i.legacy_identifier AND l.game_uuid=i.game_id
              JOIN public.game_maps m ON m.id=l.game_map_id AND m.game_id=l.game_uuid
              WHERE i.legacy_identifier=c.game_id AND l.id=c.map_layer AND l.layer_uuid IS NOT NULL)<>1) THEN
        RAISE EXCEPTION 'B4B_MARKER_MAPPING_LAYER_OR_PARENTS_INVALID';
    END IF;

    SELECT count(*) INTO v_rows FROM public.marcadores;
    EXECUTE v_snapshot_sql INTO v_before;
    ALTER TABLE public.marcadores ADD COLUMN game_uuid uuid, ADD COLUMN layer_uuid uuid;
    EXECUTE $ddl$
    CREATE FUNCTION private.deepmap_resolve_marker_identity()
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
    $function$;
    $ddl$;
    -- Alphabetical BEFORE order: identity, then touch; audit is AFTER.
    CREATE TRIGGER deepmap_marcadores_identity BEFORE INSERT OR UPDATE ON public.marcadores
        FOR EACH ROW EXECUTE FUNCTION private.deepmap_resolve_marker_identity();
    REVOKE ALL ON FUNCTION private.deepmap_resolve_marker_identity() FROM PUBLIC,anon,authenticated;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='service_role') THEN
        REVOKE ALL ON FUNCTION private.deepmap_resolve_marker_identity() FROM service_role;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
        WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_marker_identity()') AND a.grantee<>p.proowner) THEN
        RAISE EXCEPTION 'B4B_UNEXPECTED_DIRECT_IDENTITY_FUNCTION_GRANTS';
    END IF;
    SELECT to_jsonb(p) INTO STRICT v_identity_function FROM pg_catalog.pg_proc p
        WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_marker_identity()');
    IF EXISTS (SELECT 1 FROM public.marcadores WHERE game_uuid IS NOT NULL OR layer_uuid IS NOT NULL) THEN
        RAISE EXCEPTION 'B4B_UNEXPECTED_PARTIAL_HYDRATION_BEFORE_FILL';
    END IF;
    UPDATE public.marcadores c SET game_uuid=i.game_id,layer_uuid=l.layer_uuid
        FROM private.game_legacy_identifiers i JOIN public.map_layers l
          ON l.game_id=i.legacy_identifier AND l.game_uuid=i.game_id
        WHERE c.game_id=i.legacy_identifier AND c.map_layer=l.id
          AND c.game_uuid IS NULL AND c.layer_uuid IS NULL;
    GET DIAGNOSTICS v_affected=ROW_COUNT;
    IF v_affected<>v_rows THEN RAISE EXCEPTION 'B4B_FILL_COUNT_MISMATCH'; END IF;

    ALTER TABLE public.marcadores
        ADD CONSTRAINT marcadores_legacy_game_uuid_fk FOREIGN KEY (game_id,game_uuid)
            REFERENCES private.game_legacy_identifiers(legacy_identifier,game_id)
            MATCH SIMPLE ON UPDATE NO ACTION ON DELETE RESTRICT NOT DEFERRABLE,
        ADD CONSTRAINT marcadores_legacy_uuid_layer_fk FOREIGN KEY (game_id,map_layer,game_uuid,layer_uuid)
            REFERENCES public.map_layers(game_id,id,game_uuid,layer_uuid)
            MATCH SIMPLE ON UPDATE NO ACTION ON DELETE RESTRICT NOT DEFERRABLE;
    ALTER TABLE public.marcadores ALTER COLUMN game_uuid SET NOT NULL, ALTER COLUMN layer_uuid SET NOT NULL;

    EXECUTE v_snapshot_sql INTO v_after;
    IF v_before IS DISTINCT FROM v_after THEN
        RAISE EXCEPTION 'B4B_LEGACY_AUDIT_PARENT_DATA_OR_OBJECTS_CHANGED';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_attribute WHERE attrelid=v_markers AND attname IN ('game_uuid','layer_uuid')
        AND atttypid='uuid'::pg_catalog.regtype AND attnotnull AND NOT atthasdef AND NOT attisdropped
        AND attidentity='' AND attgenerated='')<>2
       OR (SELECT to_jsonb(p) FROM pg_catalog.pg_proc p
           WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_marker_identity()')) IS DISTINCT FROM v_identity_function
       OR (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='private' AND p.proname='deepmap_resolve_marker_identity')<>1
       OR EXISTS (SELECT 1 FROM public.marcadores WHERE updated_at IS DISTINCT FROM pg_catalog.now())
       OR EXISTS (SELECT 1 FROM public.marcadores c WHERE c.game_uuid IS NULL OR c.layer_uuid IS NULL
           OR (SELECT count(*) FROM private.game_legacy_identifiers i JOIN public.map_layers l
               ON l.game_id=i.legacy_identifier AND l.game_uuid=i.game_id
               JOIN public.games g ON g.id=i.game_id
               JOIN public.game_maps m ON m.id=l.game_map_id AND m.game_id=l.game_uuid
               WHERE i.legacy_identifier=c.game_id AND i.game_id=c.game_uuid AND l.id=c.map_layer AND l.layer_uuid=c.layer_uuid)<>1)
       OR (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgrelid=v_markers AND NOT tgisinternal)<>3
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
           WHERE t.tgrelid=v_markers AND t.tgname='deepmap_marcadores_identity' AND t.tgtype=23 AND t.tgenabled='O'
             AND NOT t.tgisinternal AND t.tgnargs=0 AND t.tgqual IS NULL AND t.tgattr=''::pg_catalog.int2vector
             AND t.tgfoid=pg_catalog.to_regprocedure('private.deepmap_resolve_marker_identity()')
             AND NOT p.prosecdef AND p.prorettype='trigger'::pg_catalog.regtype AND p.proconfig=ARRAY['search_path=""']::text[]) THEN
        RAISE EXCEPTION 'B4B_FINAL_DATA_COLUMNS_OR_IDENTITY_TRIGGER_INVALID';
    END IF;
    FOR v_name,v_cols,v_target,v_target_cols IN SELECT * FROM (VALUES
        ('marcadores_legacy_game_uuid_fk',ARRAY['game_id','game_uuid']::text[],
            'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id']::text[]),
        ('marcadores_legacy_uuid_layer_fk',ARRAY['game_id','map_layer','game_uuid','layer_uuid']::text[],
            'public.map_layers',ARRAY['game_id','id','game_uuid','layer_uuid']::text[])
    ) e(name,cols,target,target_cols)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid=v_markers AND c.conname=v_name
            AND c.contype='f' AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
            AND c.confrelid=pg_catalog.to_regclass(v_target) AND c.confmatchtype='s' AND c.confupdtype='a' AND c.confdeltype='r'
            AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey)
                WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=v_cols
            AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey)
                WITH ORDINALITY k(num,pos) JOIN pg_catalog.pg_attribute a
                ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)=v_target_cols) THEN
            RAISE EXCEPTION 'B4B_INVALID_FINAL_FK: %',v_name;
        END IF;
    END LOOP;
END;
$bridge$;
COMMIT;
