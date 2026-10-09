-- DeepMap post-B4b / pre-B5. Run manually in a maintenance session.
-- One read-only statement. Embedded function bodies are inert comparison literals.
-- Missing relations/permissions may abort explicitly; such errors invalidate verification.
-- No historical baseline: transactional preservation is proved by the migration, not this query.
WITH
source AS (
 SELECT pg_catalog.replace($resolver_body$
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
    $resolver_body$,pg_catalog.chr(13),'') AS resolver_body,
 pg_catalog.replace($audit_body$
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
$audit_body$,pg_catalog.chr(13),'') AS audit_body
),
relations(name) AS (VALUES ('public.marcadores'),('private.marker_editor_audit'),
 ('private.game_legacy_identifiers'),('public.map_layers'),('public.games'),('public.game_maps')),
visibility AS (
 SELECT e.name,EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
 WHERE c.oid=pg_catalog.to_regclass(e.name) AND c.relkind='r'
 AND pg_catalog.has_table_privilege(c.oid,'SELECT') AND pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
 AND (r.rolsuper OR r.rolbypassrls OR (c.relowner=r.oid AND NOT c.relforcerowsecurity))) AS ok FROM relations e
),
attributes AS (
 SELECT a.*,pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS default_expr
 FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
 WHERE a.attnum>0 AND NOT a.attisdropped
),
constraints AS (
 SELECT c.*,
 ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,ord)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.ord) AS source_columns,
 ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num,ord)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.ord) AS target_columns
 FROM pg_catalog.pg_constraint c
),
indexes AS (
 SELECT i.*,c.relname,
 ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(i.indkey::smallint[]) WITH ORDINALITY k(num,ord)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.num ORDER BY k.ord) AS columns
 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid
),
expected_columns(name,type_name,nn,identity_kind,default_expr) AS (VALUES
 ('id','bigint',true,'d',NULL),('game_id','text',true,'','''elden-ring''::text'),
 ('map_layer','text',true,'','''surface''::text'),('slug','text',true,'',NULL),
 ('category_id','text',true,'',NULL),('region_id','text',false,'',NULL),
 ('title_en','text',true,'',NULL),('title_pt','text',false,'',NULL),
 ('coordinate_x','double precision',true,'',NULL),('coordinate_y','double precision',true,'',NULL),
 ('description_en','text',false,'',NULL),('description_pt','text',false,'',NULL),
 ('video_url','text',false,'',NULL),('color_override','text',false,'',NULL),
 ('icon_source_override','text',false,'',NULL),('icon_ref_override','text',false,'',NULL),
 ('marker_width_override','integer',false,'',NULL),('marker_height_override','integer',false,'',NULL),
 ('symbol_size_override','integer',false,'',NULL),('is_published','boolean',true,'','false'),
 ('created_at','timestamp with time zone',true,'','now()'),('updated_at','timestamp with time zone',true,'','now()'),
 ('game_uuid','uuid',true,'',NULL),('layer_uuid','uuid',true,'',NULL)
),
expected_checks(name,expression) AS (VALUES
 ('marcadores_slug_format','slug ~ ''^[a-z0-9]+(?:-[a-z0-9]+)*$''::text'),
 ('marcadores_color_override_format','color_override IS NULL OR color_override ~ ''^#[0-9A-Fa-f]{6}$''::text'),
 ('marcadores_icon_source_override_valid','icon_source_override IS NULL OR icon_source_override = ANY (ARRAY[''none''::text, ''static''::text, ''r2''::text, ''external''::text])'),
 ('marcadores_icon_override_ref_required','icon_source_override IS NULL OR icon_source_override = ''none''::text OR NULLIF(btrim(icon_ref_override), ''''::text) IS NOT NULL'),
 ('marcadores_marker_width_override_valid','marker_width_override IS NULL OR marker_width_override > 0'),
 ('marcadores_marker_height_override_valid','marker_height_override IS NULL OR marker_height_override > 0'),
 ('marcadores_symbol_size_override_valid','symbol_size_override IS NULL OR symbol_size_override > 0')
),
expected_keys(rel,name,kind,columns) AS (VALUES
 ('public.marcadores',NULL,'p',ARRAY['id']),
 ('private.marker_editor_audit',NULL,'p',ARRAY['marker_id']),
 ('private.game_legacy_identifiers','game_legacy_identifiers_identifier_game_unique','u',ARRAY['legacy_identifier','game_id']),
 ('public.map_layers',NULL,'p',ARRAY['game_id','id']),
 ('public.map_layers','map_layers_layer_uuid_unique','u',ARRAY['layer_uuid']),
 ('public.map_layers','map_layers_legacy_uuid_identity_unique','u',ARRAY['game_id','id','game_uuid','layer_uuid']),
 ('public.game_maps','game_maps_id_game_unique','u',ARRAY['id','game_id'])
),
expected_fks(name,rel,columns,parent,target,up,del) AS (VALUES
 ('marcadores_layer_fk','public.marcadores',ARRAY['game_id','map_layer'],'public.map_layers',ARRAY['game_id','id'],'c','a'),
 ('marcadores_category_fk','public.marcadores',ARRAY['game_id','category_id'],'public.marker_categories',ARRAY['game_id','id'],'c','a'),
 ('marcadores_legacy_game_uuid_fk','public.marcadores',ARRAY['game_id','game_uuid'],'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id'],'a','r'),
 ('marcadores_legacy_uuid_layer_fk','public.marcadores',ARRAY['game_id','map_layer','game_uuid','layer_uuid'],'public.map_layers',ARRAY['game_id','id','game_uuid','layer_uuid'],'a','r'),
 ('audit_marker','private.marker_editor_audit',ARRAY['marker_id'],'public.marcadores',ARRAY['id'],'a','c')
),
expected_triggers(name,signature,bits) AS (VALUES
 ('deepmap_marcadores_identity','private.deepmap_resolve_marker_identity()',23),
 ('deepmap_marcadores_touch_updated_at','private.deepmap_touch_updated_at()',19),
 ('deepmap_marker_editor_audit','private.deepmap_stamp_marker_audit()',21)
),
functions AS (
 SELECT p.*,n.nspname,l.lanname,pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'') AS body
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 JOIN pg_catalog.pg_language l ON l.oid=p.prolang
 WHERE n.nspname='private' AND p.proname IN ('deepmap_resolve_marker_identity','deepmap_stamp_marker_audit','deepmap_touch_updated_at')
),
body_matches AS (
 SELECT EXISTS (SELECT 1 FROM functions p CROSS JOIN source s WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_marker_identity()') AND p.body=s.resolver_body) AS resolver_ok,
 EXISTS (SELECT 1 FROM functions p CROSS JOIN source s WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_stamp_marker_audit()') AND p.body=s.audit_body) AS audit_ok
),
markers AS (SELECT pg_catalog.to_jsonb(m) AS row FROM public.marcadores m),
marker_resolution AS (
 SELECT m.row,
 (SELECT count(*) FROM private.game_legacy_identifiers x WHERE x.legacy_identifier=m.row->>'game_id') AS mapping_count,
 (SELECT count(*) FROM private.game_legacy_identifiers x JOIN public.games g ON g.id=x.game_id
 WHERE x.legacy_identifier=m.row->>'game_id' AND x.game_id::text=m.row->>'game_uuid') AS valid_game_count,
 (SELECT count(*) FROM public.map_layers l WHERE l.game_id=m.row->>'game_id' AND l.id=m.row->>'map_layer') AS layer_count,
 (SELECT count(*) FROM public.map_layers l JOIN public.game_maps gm ON gm.id=l.game_map_id AND gm.game_id=l.game_uuid
 JOIN public.games g ON g.id=gm.game_id
 WHERE l.game_id=m.row->>'game_id' AND l.id=m.row->>'map_layer'
 AND l.game_uuid::text=m.row->>'game_uuid' AND l.layer_uuid::text=m.row->>'layer_uuid') AS valid_layer_count
 FROM markers m
),
checks AS (
 SELECT 'table.rls.'||e.name AS check_name,EXISTS (SELECT 1 FROM pg_catalog.pg_class c
 WHERE c.oid=pg_catalog.to_regclass(e.name) AND c.relkind='r' AND c.relrowsecurity) AS ok,
 'Ordinary table exists with RLS enabled' AS details FROM relations e
 UNION ALL SELECT 'visibility.full.'||name,ok,'SELECT/schema USAGE and maintenance RLS bypass/owner visibility required' FROM visibility
 UNION ALL SELECT 'schema.marker.column.'||e.name,EXISTS (SELECT 1 FROM attributes a
 WHERE a.attrelid=pg_catalog.to_regclass('public.marcadores') AND a.attname=e.name
 AND a.atttypid=pg_catalog.to_regtype(e.type_name) AND a.attnotnull=e.nn
 AND a.attidentity::text=e.identity_kind AND a.attgenerated=''
 AND a.default_expr IS NOT DISTINCT FROM e.default_expr AND a.atthasdef=(e.default_expr IS NOT NULL)),
 pg_catalog.format('%s; NOT NULL=%s; identity=%s; default=%s; no generated expression',e.type_name,e.nn,e.identity_kind,COALESCE(e.default_expr,'none')) FROM expected_columns e
 UNION ALL SELECT 'schema.audit.marker_id_not_null',EXISTS (SELECT 1 FROM attributes
 WHERE attrelid=pg_catalog.to_regclass('private.marker_editor_audit') AND attname='marker_id'
 AND atttypid='bigint'::pg_catalog.regtype AND attnotnull AND NOT atthasdef AND attidentity='' AND attgenerated=''),
 'Audit marker_id BIGINT NOT NULL, no default/identity/generated; PK checked separately'
 UNION ALL SELECT 'schema.marker.exact_columns',(SELECT count(*) FROM attributes WHERE attrelid=pg_catalog.to_regclass('public.marcadores'))=24
 AND NOT EXISTS (SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass('public.marcadores') AND NOT EXISTS (SELECT 1 FROM expected_columns e WHERE e.name=a.attname)),
 'Exactly 22 legacy columns plus game_uuid/layer_uuid'
 UNION ALL SELECT 'check.legacy.'||e.name,EXISTS (SELECT 1 FROM constraints c
 WHERE c.conrelid=pg_catalog.to_regclass('public.marcadores') AND c.conname=e.name AND c.contype='c' AND c.convalidated
 AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(c.conbin,c.conrelid),'[[:space:]()]','','g')
 =pg_catalog.regexp_replace(e.expression,'[[:space:]()]','','g')),
 'Validated legacy expression: '||e.expression FROM expected_checks e
 UNION ALL SELECT 'check.legacy.exact_set',count(*)=7 AND bool_and(conname IN (SELECT name FROM expected_checks)),
 'Exactly seven legacy CHECKs; actual='||count(*) FROM constraints WHERE conrelid=pg_catalog.to_regclass('public.marcadores') AND contype='c'
 UNION ALL SELECT 'key.'||e.rel||'.'||COALESCE(e.name,'primary_key'),
 EXISTS (SELECT 1 FROM constraints c JOIN indexes i ON i.indexrelid=c.conindid
 WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND (e.name IS NULL OR c.conname=e.name) AND c.contype::text=e.kind
 AND c.source_columns=e.columns AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
 AND i.indrelid=c.conrelid AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
 AND i.indpred IS NULL AND i.indexprs IS NULL AND i.columns=e.columns AND i.indnatts=i.indnkeyatts
 AND (e.kind<>'p' OR (SELECT count(*) FROM constraints p WHERE p.conrelid=c.conrelid AND p.contype='p')=1)),
 'Validated immediate key '||e.kind||' ('||array_to_string(e.columns,',')||'); UNIQUE valid/ready/live index, no predicate/expression/INCLUDE' FROM expected_keys e
 UNION ALL SELECT 'fk.'||e.name,EXISTS (SELECT 1 FROM constraints c
 WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND (e.name='audit_marker' OR c.conname=e.name) AND c.contype='f'
 AND c.confrelid=pg_catalog.to_regclass(e.parent) AND c.source_columns=e.columns AND c.target_columns=e.target
 AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred AND c.confmatchtype='s'
 AND c.confupdtype::text=e.up AND c.confdeltype::text=e.del),
 pg_catalog.format('(%s) -> %s(%s), MATCH SIMPLE, validated/immediate; update=%s delete=%s',array_to_string(e.columns,','),e.parent,array_to_string(e.target,','),e.up,e.del) FROM expected_fks e
 UNION ALL SELECT 'fk.marker.exact_set',count(*)=4 AND bool_and(conname IN (SELECT name FROM expected_fks WHERE rel='public.marcadores')),
 'Exactly two legacy and two bridge FKs; actual='||count(*) FROM constraints WHERE conrelid=pg_catalog.to_regclass('public.marcadores') AND contype='f'
 UNION ALL SELECT 'index.legacy.'||e.name,EXISTS (SELECT 1 FROM indexes i WHERE i.indrelid=pg_catalog.to_regclass('public.marcadores')
 AND i.relname=e.name AND i.columns=e.columns AND i.indisunique=e.is_unique AND i.indisvalid AND i.indisready AND i.indislive
 AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnatts=i.indnkeyatts),
 'Exact legacy columns/order; unique='||e.is_unique||'; valid/ready/live; no predicate/expression/INCLUDE'
 FROM (VALUES ('marcadores_game_slug_unique',ARRAY['game_id','slug'],true),('marcadores_map_lookup_idx',ARRAY['game_id','map_layer','is_published','category_id'],false)) e(name,columns,is_unique)
 UNION ALL SELECT 'index.marker.no_uuid_indexes',count(*)=0,'UUID indexes='||count(*) FROM indexes
 WHERE indrelid=pg_catalog.to_regclass('public.marcadores') AND (relname ~* 'uuid'
 OR columns && ARRAY['game_uuid','layer_uuid','game_map_id','category_uuid','group_uuid']
 OR COALESCE(pg_catalog.pg_get_expr(indexprs,indrelid),'') ~ '(game_uuid|layer_uuid)'
 OR COALESCE(pg_catalog.pg_get_expr(indpred,indrelid),'') ~ '(game_uuid|layer_uuid)')
 UNION ALL SELECT 'data.marker.uuid_nulls',count(*)=0,'Markers with NULL UUID shadows='||count(*) FROM marker_resolution WHERE row->>'game_uuid' IS NULL OR row->>'layer_uuid' IS NULL
 UNION ALL SELECT 'data.marker.game_mapping',count(*)=0,'Missing/ambiguous legacy mapping or UUID mismatch/missing game='||count(*) FROM marker_resolution WHERE mapping_count<>1 OR valid_game_count<>1
 UNION ALL SELECT 'data.marker.layer_context',count(*)=0,'Missing/ambiguous layer or UUID/game/map parent mismatch='||count(*) FROM marker_resolution WHERE layer_count<>1 OR valid_layer_count<>1
 UNION ALL SELECT 'data.audit.orphans',count(*)=0,'Audit orphans='||count(*) FROM private.marker_editor_audit a WHERE NOT EXISTS (SELECT 1 FROM public.marcadores m WHERE m.id=a.marker_id)
 UNION ALL SELECT 'data.audit.duplicate_ids',count(*)=0,'Duplicate marker_id groups='||count(*) FROM (SELECT marker_id FROM private.marker_editor_audit GROUP BY marker_id HAVING count(*)>1) d
 UNION ALL SELECT 'data.audit.null_ids',count(*)=0,'NULL marker_id='||count(*) FROM private.marker_editor_audit WHERE marker_id IS NULL
 UNION ALL SELECT 'function.'||e.name||'.attributes',EXISTS (SELECT 1 FROM functions p WHERE p.proname=e.name
 AND p.pronargs=0 AND p.prorettype='trigger'::pg_catalog.regtype AND p.prokind='f' AND NOT p.proretset
 AND p.lanname='plpgsql' AND p.prosecdef=e.definer AND p.proconfig=ARRAY['search_path=""']::text[]
 AND p.provolatile='v' AND p.proparallel='u' AND NOT p.proleakproof AND NOT p.proisstrict AND p.procost=100 AND p.prorows=0),
 'trigger(), PL/pgSQL, empty search_path, expected security, VOLATILE/UNSAFE, non-leakproof/non-strict, COST 100'
 FROM (VALUES ('deepmap_resolve_marker_identity',false),('deepmap_stamp_marker_audit',true)) e(name,definer)
 UNION ALL SELECT 'function.'||e.name||'.no_overloads',(SELECT count(*) FROM functions p WHERE p.proname=e.name)=1,
 'Exactly one private function with this name' FROM (VALUES ('deepmap_resolve_marker_identity'),('deepmap_stamp_marker_audit')) e(name)
 UNION ALL SELECT 'function.resolver.exact_body',resolver_ok,'Complete approved B4b prosrc; only CRLF/LF normalization' FROM body_matches
 UNION ALL SELECT 'function.resolver.contract.'||e.name,resolver_ok,e.details FROM body_matches CROSS JOIN (VALUES
 ('insert','Exact body proves strict mapping/layer resolution, NULL fill and explicit mismatch rejection'),
 ('hydration','Exact body proves both OLD UUIDs NULL, legacy unchanged, partial identity rejected'),
 ('update','Exact body rejects game reassignment/UUID mutation; layer change accepts inherited OLD/NULL/correct new UUID and rejects mismatch')) e(name,details)
 UNION ALL SELECT 'function.resolver.owner_only_execute',EXISTS (SELECT 1 FROM functions WHERE proname='deepmap_resolve_marker_identity')
 AND NOT EXISTS (SELECT 1 FROM functions p CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
 WHERE p.proname='deepmap_resolve_marker_identity' AND a.privilege_type='EXECUTE' AND a.grantee<>p.proowner),
 'No non-owner direct EXECUTE, including PUBLIC/anon/authenticated/service_role'
 UNION ALL SELECT 'function.audit.exact_body',audit_ok,'Complete approved B4a prosrc copied from B4b dependency snapshot; only CRLF/LF normalization' FROM body_matches
 UNION ALL SELECT 'function.audit.contract.'||e.name,audit_ok,e.details FROM body_matches CROSS JOIN (VALUES
 ('uuid_guard','Exact body proves real difference excluding updated_at, equality excluding updated_at/game_uuid/layer_uuid, RETURN before UPDATE UPSERT'),
 ('semantic_projection','Exact body excludes updated_at/is_published/game_uuid/layer_uuid only; game_id/map_layer/category_id remain semantic; publication remains in UUID guard'),
 ('insert_publication_approval','Exact full body preserves legacy INSERT and UPDATE attribution/publication/approval CASEs')) e(name,details)
 UNION ALL SELECT 'function.audit.no_public_client_execute',EXISTS (SELECT 1 FROM functions WHERE proname='deepmap_stamp_marker_audit')
 AND NOT EXISTS (SELECT 1 FROM functions p CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
 LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE p.proname='deepmap_stamp_marker_audit' AND a.privilege_type='EXECUTE'
 AND (a.grantee=0 OR r.rolname IN ('anon','authenticated'))),'No direct PUBLIC/anon/authenticated EXECUTE; historical service_role ACL permitted'
 UNION ALL SELECT 'function.touch.legacy_body',EXISTS (SELECT 1 FROM functions p WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
 AND p.prorettype='trigger'::pg_catalog.regtype AND NOT p.prosecdef AND p.lanname='plpgsql'
 AND pg_catalog.lower(pg_catalog.regexp_replace(p.body,'[[:space:]]','','g'))='beginnew.updated_at:=now();returnnew;end;'),
 'Legacy INVOKER touch: NEW.updated_at := now(); RETURN NEW'
 UNION ALL SELECT 'trigger.'||e.name,EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid=pg_catalog.to_regclass('public.marcadores')
 AND t.tgname=e.name AND t.tgfoid=pg_catalog.to_regprocedure(e.signature) AND t.tgtype=e.bits AND t.tgenabled='O'
 AND NOT t.tgisinternal AND t.tgnargs=0 AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL),
 e.signature||'; expected timing/events, row-level, origin enabled, no args/WHEN/column filter' FROM expected_triggers e
 UNION ALL SELECT 'trigger.marker.exact_set',count(*)=3 AND bool_and(tgname IN (SELECT name FROM expected_triggers)),
 'Exactly three user triggers; internal FK triggers ignored; actual='||count(*) FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass('public.marcadores') AND NOT tgisinternal
 UNION ALL SELECT 'trigger.audit.no_user_triggers',count(*)=0,'Audit user triggers='||count(*) FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass('private.marker_editor_audit') AND NOT tgisinternal
 UNION ALL SELECT 'trigger.before.order', 'deepmap_marcadores_identity' COLLATE "C" < 'deepmap_marcadores_touch_updated_at' COLLATE "C"
 AND (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass('public.marcadores') AND NOT tgisinternal AND tgtype=23 AND tgname='deepmap_marcadores_identity')=1
 AND (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass('public.marcadores') AND NOT tgisinternal AND tgtype=19 AND tgname='deepmap_marcadores_touch_updated_at')=1,
 'PostgreSQL alphabetical order for same timing/event: identity before touch on UPDATE'
 UNION ALL SELECT 'security.role_helper.legacy_contract',EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
 WHERE p.oid=pg_catalog.to_regprocedure('public.get_deepmap_role()')
 AND pg_catalog.lower(pg_catalog.regexp_replace(p.prosrc,'[[:space:]]','','g'))=
 'selectcasewhenprivate.is_deepmap_banned()then''banned''whenprivate.is_deepmap_admin()then''admin''whenprivate.is_deepmap_moderator()then''moderator''else''user''end;'),
 'Exact role-helper contract required by approved B4b preflight'
 UNION ALL SELECT 'security.authenticated.invoker_dependencies',EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname='authenticated'
 AND pg_catalog.has_schema_privilege(r.oid,pg_catalog.to_regnamespace('private'),'USAGE')
 AND pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('private.game_legacy_identifiers'),'SELECT')
 AND pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('public.map_layers'),'SELECT')
 AND pg_catalog.has_function_privilege(r.oid,pg_catalog.to_regprocedure('public.get_deepmap_role()'),'EXECUTE')
 AND pg_catalog.has_function_privilege(r.oid,pg_catalog.to_regprocedure('private.is_deepmap_admin()'),'EXECUTE')),
 'Authenticated USAGE private, SELECT mapping/layers, EXECUTE role/admin helpers'
 UNION ALL SELECT 'security.policy.'||e.name,EXISTS (SELECT 1 FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_roles r ON r.rolname='authenticated'
 WHERE p.polrelid=pg_catalog.to_regclass(e.rel) AND p.polname=e.name AND p.polcmd='*' AND p.polpermissive AND r.oid=ANY(p.polroles)
 AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'[[:space:]()]','','g')='private.is_deepmap_admin'
 AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),'[[:space:]()]','','g')='private.is_deepmap_admin'),
 'Legacy permissive authenticated Admin ALL policy with matching USING/WITH CHECK' FROM (VALUES ('public.marcadores','marcadores_admin_all'),('public.map_layers','map_layers_admin_all')) e(rel,name)
 UNION ALL SELECT 'security.policy.mapping_admin_read',EXISTS (SELECT 1 FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_roles r ON r.rolname='authenticated'
 WHERE p.polrelid=pg_catalog.to_regclass('private.game_legacy_identifiers') AND p.polname='game_legacy_identifiers_admin_read' AND p.polcmd='r' AND p.polpermissive AND r.oid=ANY(p.polroles)
 AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'[[:space:]()]','','g') IN
 ('SELECTpublic.get_deepmap_roleASget_deepmap_role=''admin''::text','SELECTget_deepmap_roleASget_deepmap_role=''admin''::text')),
 'Existing mapping Admin read policy'
 UNION ALL SELECT 'security.parents.no_restrictive_read_policies',count(*)=0,'Unexpected restrictive parent SELECT/ALL policies='||count(*) FROM pg_catalog.pg_policy
 WHERE polrelid IN (pg_catalog.to_regclass('private.game_legacy_identifiers'),pg_catalog.to_regclass('public.map_layers')) AND NOT polpermissive AND polcmd IN ('r','*')
 UNION ALL SELECT 'security.policy.markers_public_read',EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid=pg_catalog.to_regclass('public.marcadores')
 AND p.polname='marcadores_public_read' AND p.polcmd='r' AND p.polpermissive
 AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'[[:space:]()]','','g')='is_published=true'
 AND (SELECT count(*) FROM pg_catalog.unnest(p.polroles) x(role_oid) JOIN pg_catalog.pg_roles r ON r.oid=x.role_oid WHERE r.rolname IN ('anon','authenticated'))=2 AND cardinality(p.polroles)=2),
 'Legacy public read limited to published markers, anon/authenticated'
 UNION ALL SELECT 'security.policy.markers_exact_set',count(*)=2 AND bool_and(polname IN ('marcadores_public_read','marcadores_admin_all')),
 'Exactly the two legacy marker policies; no additional policy opening' FROM pg_catalog.pg_policy WHERE polrelid=pg_catalog.to_regclass('public.marcadores')
 UNION ALL SELECT 'security.markers.no_public_write_acl',NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
 CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
 LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE c.oid=pg_catalog.to_regclass('public.marcadores')
 AND (a.grantee=0 OR r.rolname='anon') AND a.privilege_type<>'SELECT'),
 'No direct PUBLIC/anon table privileges beyond SELECT'
 UNION ALL SELECT 'security.markers.no_public_column_write_acl',NOT EXISTS (SELECT 1 FROM attributes a
 CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) x LEFT JOIN pg_catalog.pg_roles r ON r.oid=x.grantee
 WHERE a.attrelid=pg_catalog.to_regclass('public.marcadores') AND (x.grantee=0 OR r.rolname='anon') AND x.privilege_type<>'SELECT'),
 'No direct PUBLIC/anon column privileges beyond SELECT'
 UNION ALL SELECT 'security.rpc.'||e.signature,EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
 WHERE p.oid=pg_catalog.to_regprocedure(e.signature) AND p.prosecdef AND p.proconfig=ARRAY['search_path=""']::text[]
 AND (SELECT count(*) FROM pg_catalog.pg_class c WHERE c.oid IN (pg_catalog.to_regclass('private.game_legacy_identifiers'),pg_catalog.to_regclass('public.map_layers'))
 AND pg_catalog.has_table_privilege(r.oid,c.oid,'SELECT') AND pg_catalog.has_schema_privilege(r.oid,c.relnamespace,'USAGE')
 AND (r.rolsuper OR r.rolbypassrls OR (r.oid=c.relowner AND NOT c.relforcerowsecurity)))=2),
 'Existing DEFINER RPC, empty search_path, owner full mapping/layer visibility; never invoked'
 FROM (VALUES ('public.review_marker_submission(bigint,text,text)'),('public.review_marker_submission_v2(bigint,text,text,jsonb)')) e(signature)
 UNION ALL SELECT 'scope.pre_b5.marker_no_extra_uuid_columns',NOT EXISTS (SELECT 1 FROM attributes WHERE attrelid=pg_catalog.to_regclass('public.marcadores') AND attname IN ('game_map_id','category_uuid','group_uuid')),
 'No game_map_id/category_uuid/group_uuid on markers'
 UNION ALL SELECT 'scope.pre_b5.submissions_no_game_uuid',pg_catalog.to_regclass('public.marker_submissions') IS NOT NULL
 AND NOT EXISTS (SELECT 1 FROM attributes WHERE attrelid=pg_catalog.to_regclass('public.marker_submissions') AND attname='game_uuid'),
 'marker_submissions.game_uuid must remain absent'
 UNION ALL SELECT 'scope.pre_b5_b6.no_premature_resolvers',count(*)=0,'Premature submission/notification identity resolvers='||count(*)
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('private','public') AND p.proname ~ '^deepmap_resolve_.*(submission|notification).*identity$'
 UNION ALL SELECT 'scope.pre_b5_b6.no_premature_uuid_objects',NOT EXISTS (SELECT 1 FROM attributes a JOIN pg_catalog.pg_class c ON c.oid=a.attrelid
 JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname IN ('marker_submissions','user_notifications')
 AND a.attname IN ('game_uuid','layer_uuid','category_uuid','group_uuid'))
 AND NOT EXISTS (SELECT 1 FROM constraints WHERE conrelid IN (pg_catalog.to_regclass('public.marker_submissions'),pg_catalog.to_regclass('public.user_notifications')) AND conname ~* 'uuid')
 AND NOT EXISTS (SELECT 1 FROM indexes WHERE indrelid IN (pg_catalog.to_regclass('public.marker_submissions'),pg_catalog.to_regclass('public.user_notifications'))
 AND (relname ~* 'uuid' OR columns && ARRAY['game_uuid','layer_uuid','category_uuid','group_uuid']
 OR COALESCE(pg_catalog.pg_get_expr(indexprs,indrelid),'') ~ '(game_uuid|layer_uuid|category_uuid|group_uuid)'
 OR COALESCE(pg_catalog.pg_get_expr(indpred,indrelid),'') ~ '(game_uuid|layer_uuid|category_uuid|group_uuid)')),
 'Known later-phase UUID columns/constraints absent; no claim that B5/B6 are complete'
)
SELECT check_name,
 CASE WHEN ok IS TRUE AND (check_name NOT LIKE 'data.%' OR (SELECT bool_and(ok) FROM visibility)) THEN 'PASS' ELSE 'FAIL' END AS status,
 details || CASE WHEN check_name LIKE 'data.%' AND NOT (SELECT bool_and(ok) FROM visibility)
 THEN '; INVALID DATA RESULT: incomplete maintenance visibility' ELSE '' END AS details
FROM checks ORDER BY check_name;
