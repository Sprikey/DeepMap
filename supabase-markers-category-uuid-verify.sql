-- DeepMap B6c post-application verifier. One read-only WITH ... SELECT.
-- Source: approved 20261011120000_markers_category_uuid_bridge.sql.
-- Function bodies are inert literals, never invoked. CR removal is symmetric.
-- No historical row/OID/ACL/audit/timestamp preservation claims: the migration
-- proves those with transactional snapshots/locks and timestamp guards.
-- Missing tables/SELECT privileges may raise SQL errors; errors invalidate the
-- verification and never mean PASS. Partial RLS visibility invalidates data.*.
WITH
sources(name,signature,definer,body) AS (VALUES
 ('marker','private.deepmap_resolve_marker_identity()',false,$marker_b6c$
    DECLARE
        v_game uuid;
        v_layer uuid;
        v_layer_game uuid;
        v_layer_changed boolean := false;
        v_category_uuid uuid;
        v_category_game_uuid uuid;
        v_category_changed boolean := false;
        v_category_hydrating boolean := false;
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
        IF TG_OP='UPDATE' THEN
            v_category_changed := NEW.category_id IS DISTINCT FROM OLD.category_id;
            v_category_hydrating := OLD.category_uuid IS NULL;
            IF v_category_hydrating THEN
                -- Identity BEFORE touch: every other key, even updated_at,
                -- must still be exactly OLD. NOT NULL ends this transition.
                IF (pg_catalog.to_jsonb(NEW)-'category_uuid') IS DISTINCT FROM
                   (pg_catalog.to_jsonb(OLD)-'category_uuid') THEN
                    RAISE EXCEPTION 'B6C_CATEGORY_HYDRATION_MUST_PRESERVE_OTHER_FIELDS';
                END IF;
            ELSIF NOT v_category_changed AND NEW.category_uuid IS DISTINCT FROM OLD.category_uuid THEN
                RAISE EXCEPTION 'B6C_UUID_ONLY_CATEGORY_CHANGE_NOT_SUPPORTED';
            END IF;
        END IF;
        BEGIN
            SELECT c.category_uuid,c.game_uuid INTO STRICT v_category_uuid,v_category_game_uuid
                FROM public.marker_categories c WHERE c.game_id=NEW.game_id AND c.id=NEW.category_id;
        EXCEPTION WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B6C_CATEGORY_NOT_EXACTLY_ONE_VISIBLE_ROW';
        END;
        IF v_category_uuid IS NULL OR v_category_game_uuid IS DISTINCT FROM NEW.game_uuid THEN
            RAISE EXCEPTION 'B6C_CATEGORY_GAME_CONTEXT_MISMATCH';
        END IF;
        IF TG_OP='UPDATE' THEN
            IF v_category_hydrating THEN
                IF NEW.category_uuid IS DISTINCT FROM v_category_uuid THEN
                    RAISE EXCEPTION 'B6C_CATEGORY_HYDRATION_REQUIRES_EXACT_UUID';
                END IF;
            ELSIF v_category_changed THEN
                -- Legacy callers transport OLD or NULL; correctly supplied
                -- destination UUID is also safe. Reject every other UUID.
                IF NEW.category_uuid IS NOT NULL AND NEW.category_uuid IS DISTINCT FROM OLD.category_uuid
                   AND NEW.category_uuid IS DISTINCT FROM v_category_uuid THEN
                    RAISE EXCEPTION 'B6C_EXPLICIT_NEW_CATEGORY_UUID_MISMATCH';
                END IF;
            ELSIF NEW.category_uuid IS DISTINCT FROM v_category_uuid THEN
                RAISE EXCEPTION 'B6C_EXISTING_CATEGORY_UUID_MISMATCH';
            END IF;
        END IF;
        -- INSERT callers never own category identity; always derive it.
        NEW.category_uuid := v_category_uuid;
        RETURN NEW;
    END;
    $marker_b6c$),
 ('audit','private.deepmap_stamp_marker_audit()',true,$audit_b6c$
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
       and (pg_catalog.to_jsonb(new) - ARRAY['updated_at','game_uuid','layer_uuid','category_uuid']::text[])
           is not distinct from
           (pg_catalog.to_jsonb(old) - ARRAY['updated_at','game_uuid','layer_uuid','category_uuid']::text[]) then
        return new;
    end if;

    -- Publication toggles alone do not count as a content modification.
    v_content_changed :=
        (to_jsonb(new) - ARRAY['updated_at','is_published','game_uuid','layer_uuid','category_uuid']::text[])
        is distinct from
        (to_jsonb(old) - ARRAY['updated_at','is_published','game_uuid','layer_uuid','category_uuid']::text[]);

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
$audit_b6c$),
 ('category','private.deepmap_resolve_category_identity()',false,$category_b6b$
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
$category_b6b$),
 ('group','private.deepmap_resolve_category_group_identity()',false,$group_b6a$
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
$group_b6a$),
 ('touch','private.deepmap_touch_updated_at()',false,$touch_body$
begin
    new.updated_at := now();
    return new;
end;
$touch_body$)
),
relations AS (
 SELECT e.name,c.* FROM (VALUES
 ('public.games'),('public.game_maps'),('private.game_legacy_identifiers'),('public.map_layers'),
 ('public.marker_categories'),('public.marker_category_groups'),('public.marcadores'),('private.marker_editor_audit'),
 ('public.marker_submissions'),('private.marker_submission_revisions'),('public.user_notifications'),
 ('public.marker_images'),('public.marker_sections'),('public.marker_section_rows')) e(name)
 LEFT JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass(e.name)
),
api_roles AS (SELECT * FROM pg_catalog.pg_roles WHERE rolname IN ('anon','authenticated','service_role')),
visibility AS (
 SELECT c.name,COALESCE(c.oid IS NOT NULL AND c.relkind='r' AND c.relrowsecurity
 AND pg_catalog.has_table_privilege(c.oid,'SELECT') AND pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
 AND (r.rolsuper OR r.rolbypassrls OR (r.oid=c.relowner AND NOT c.relforcerowsecurity)),false) AS ok
 FROM relations c LEFT JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
 WHERE c.name IN ('public.games','public.game_maps','private.game_legacy_identifiers','public.map_layers',
 'public.marker_categories','public.marker_category_groups','public.marcadores','private.marker_editor_audit')
),
full_visibility AS (SELECT pg_catalog.count(*)=8 AND COALESCE(pg_catalog.bool_and(ok),false) AS ok FROM visibility),
attributes AS (
 SELECT a.*,pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS default_expr FROM pg_catalog.pg_attribute a
 LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attnum>0 AND NOT a.attisdropped
),
expected_marker_columns(name,type_name,nn,identity_kind,default_expr) AS (VALUES
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
        ('game_uuid','uuid',true,'',NULL),('layer_uuid','uuid',true,'',NULL),
 ('category_uuid','uuid',true,'',NULL)
),
expected_category_columns(name,type_name,nn,default_expr) AS (VALUES
 ('game_id','text',true,NULL::text),('id','text',true,NULL),('group_id','text',false,NULL),
        ('name_en','text',true,NULL),('name_pt','text',true,NULL),('icon_source','text',true,'''none''::text'),
        ('icon_ref','text',false,NULL),('color','text',true,'''#777777''::text'),('marker_width','integer',false,NULL),
        ('marker_height','integer',false,NULL),('symbol_size','integer',false,NULL),('sort_order','integer',true,'0'),
        ('is_active','boolean',true,'true'),('created_at','timestamptz',true,'now()'),('updated_at','timestamptz',true,'now()'),('game_uuid','uuid',true,NULL),
        ('category_uuid','uuid',true,'gen_random_uuid()'),('group_uuid','uuid',false,NULL)
),
expected_audit_columns(name,type_name,nn) AS (VALUES
 ('marker_id','bigint',true),('created_by','uuid',false),('created_at','timestamptz',false),
        ('updated_by','uuid',false),('updated_at','timestamptz',false),('published_by','uuid',false),
        ('published_at','timestamptz',false),('approved_by','uuid',false),('approved_at','timestamptz',false)
),
expected_columns AS (
 SELECT 'public.marcadores'::text AS rel,e.* FROM expected_marker_columns e
 UNION ALL SELECT 'public.marker_categories',e.name,e.type_name,e.nn,'',e.default_expr FROM expected_category_columns e
 UNION ALL SELECT 'private.marker_editor_audit',e.name,e.type_name,e.nn,'',NULL FROM expected_audit_columns e
),
constraints AS (
 SELECT c.*,ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos) AS columns,
 ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num,pos)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos) AS parent_columns
 FROM pg_catalog.pg_constraint c
),
indexes AS (
 SELECT i.*,c.relname,am.amname,ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(i.indkey) WITH ORDINALITY k(num,pos)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.num ORDER BY k.pos) AS columns
 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid JOIN pg_catalog.pg_am am ON am.oid=c.relam
),
expected_keys(rel,name,kind,columns) AS (VALUES
 ('public.marcadores','marcadores_pkey','p',ARRAY['id']::text[]),
        ('public.marcadores','marcadores_id_game_identity_unique','u',ARRAY['id','game_id','game_uuid']),
        ('private.marker_editor_audit','marker_editor_audit_pkey','p',ARRAY['marker_id']),
        ('public.marker_categories','marker_categories_pkey','p',ARRAY['game_id','id']),
        ('public.marker_categories','marker_categories_category_uuid_unique','u',ARRAY['category_uuid']),
        ('public.marker_categories','marker_categories_legacy_uuid_identity_unique','u',ARRAY['game_id','id','game_uuid','category_uuid']),
        ('public.map_layers','map_layers_legacy_uuid_identity_unique','u',ARRAY['game_id','id','game_uuid','layer_uuid']),
        ('private.game_legacy_identifiers','game_legacy_identifiers_identifier_game_unique','u',ARRAY['legacy_identifier','game_id'])
),
expected_marker_checks(name,expression) AS (VALUES
 ('marcadores_slug_format','slug ~ ''^[a-z0-9]+(?:-[a-z0-9]+)*$''::text'),
        ('marcadores_color_override_format','color_override IS NULL OR color_override ~ ''^#[0-9A-Fa-f]{6}$''::text'),
        ('marcadores_icon_source_override_valid','icon_source_override IS NULL OR icon_source_override = ANY (ARRAY[''none''::text, ''static''::text, ''r2''::text, ''external''::text])'),
        ('marcadores_icon_override_ref_required','icon_source_override IS NULL OR icon_source_override = ''none''::text OR NULLIF(btrim(icon_ref_override), ''''::text) IS NOT NULL'),
        ('marcadores_marker_width_override_valid','marker_width_override IS NULL OR marker_width_override > 0'),
        ('marcadores_marker_height_override_valid','marker_height_override IS NULL OR marker_height_override > 0'),
        ('marcadores_symbol_size_override_valid','symbol_size_override IS NULL OR symbol_size_override > 0')
),
expected_category_checks(name,expression) AS (VALUES
 ('marker_categories_id_format',$expr$(id ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'::text)$expr$),
        ('marker_categories_icon_source_check',$expr$(icon_source = ANY (ARRAY['none'::text, 'static'::text, 'r2'::text, 'external'::text]))$expr$),
        ('marker_categories_color_check',$expr$(color ~ '^#[0-9A-Fa-f]{6}$'::text)$expr$),
        ('marker_categories_marker_width_check',$expr$((marker_width IS NULL) OR (marker_width > 0))$expr$),
        ('marker_categories_marker_height_check',$expr$((marker_height IS NULL) OR (marker_height > 0))$expr$),
        ('marker_categories_symbol_size_check',$expr$((symbol_size IS NULL) OR (symbol_size > 0))$expr$),
        ('marker_categories_icon_ref_required',$expr$((icon_source = 'none'::text) OR (NULLIF(btrim(icon_ref), ''::text) IS NOT NULL))$expr$),
        ('marker_categories_group_uuid_pair_check',$expr$(((group_id IS NULL) AND (group_uuid IS NULL)) OR ((group_id IS NOT NULL) AND (group_uuid IS NOT NULL)))$expr$)
),
expected_checks AS (
 SELECT 'public.marcadores'::text AS rel,e.* FROM expected_marker_checks e
 UNION ALL SELECT 'public.marker_categories',e.* FROM expected_category_checks e
),
expected_fks(rel,name,parent,columns,parent_columns,upd,del) AS (VALUES
 ('public.marcadores','marcadores_category_fk','public.marker_categories',ARRAY['game_id','category_id']::text[],ARRAY['game_id','id']::text[],'c','a'),
        ('public.marcadores','marcadores_layer_fk','public.map_layers',ARRAY['game_id','map_layer'],ARRAY['game_id','id'],'c','a'),
        ('public.marcadores','marcadores_legacy_game_uuid_fk','private.game_legacy_identifiers',ARRAY['game_id','game_uuid'],ARRAY['legacy_identifier','game_id'],'a','r'),
        ('public.marcadores','marcadores_legacy_uuid_layer_fk','public.map_layers',ARRAY['game_id','map_layer','game_uuid','layer_uuid'],ARRAY['game_id','id','game_uuid','layer_uuid'],'a','r'),
        ('private.marker_editor_audit','marker_editor_audit_marker_id_fkey','public.marcadores',ARRAY['marker_id'],ARRAY['id'],'a','c'),
        ('public.marker_submissions','marker_submissions_marker_game_uuid_fk','public.marcadores',ARRAY['marker_id','game_id','game_uuid'],ARRAY['id','game_id','game_uuid'],'a','c'),
        ('private.game_legacy_identifiers','game_legacy_identifiers_game_id_fkey','public.games',ARRAY['game_id'],ARRAY['id'],'a','r'),
        ('public.marker_categories','marker_categories_legacy_game_uuid_fk','private.game_legacy_identifiers',ARRAY['game_id','game_uuid'],ARRAY['legacy_identifier','game_id'],'a','r'),
        ('public.marker_categories','marker_categories_group_fk','public.marker_category_groups',ARRAY['game_id','group_id'],ARRAY['game_id','id'],'c','n'),
        ('public.marker_categories','marker_categories_legacy_uuid_group_fk','public.marker_category_groups',ARRAY['game_id','group_id','game_uuid','group_uuid'],ARRAY['game_id','id','game_uuid','group_uuid'],'c','r'),
 ('public.marcadores','marcadores_legacy_uuid_category_fk','public.marker_categories',
 ARRAY['game_id','category_id','game_uuid','category_uuid']::text[],ARRAY['game_id','id','game_uuid','category_uuid']::text[],'c','a')
),
expected_marker_indexes(name,uq,columns) AS (VALUES
 ('marcadores_pkey',true,ARRAY['id']::text[]),
 ('marcadores_game_slug_unique',true,ARRAY['game_id','slug']),
 ('marcadores_map_lookup_idx',false,ARRAY['game_id','map_layer','is_published','category_id']),
 ('marcadores_id_game_identity_unique',true,ARRAY['id','game_id','game_uuid'])
),
expected_indexes AS (
 SELECT 'public.marcadores'::text AS rel,e.* FROM expected_marker_indexes e
 UNION ALL SELECT rel,name,true,columns FROM expected_keys WHERE rel='public.marker_categories'
),
expected_logical_constraints AS (
 SELECT rel,name,kind AS kind FROM expected_keys WHERE rel IN ('public.marcadores','public.marker_categories','private.marker_editor_audit')
 UNION ALL SELECT rel,name,'c' FROM expected_checks
 UNION ALL SELECT rel,name,'f' FROM expected_fks WHERE rel IN ('public.marcadores','public.marker_categories','private.marker_editor_audit')
),
functions AS (
 SELECT s.name AS contract,p.*,l.lanname FROM sources s
 JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(s.signature)
 JOIN pg_catalog.pg_language l ON l.oid=p.prolang
),
body_matches AS (
 SELECT s.name,EXISTS(SELECT 1 FROM functions p WHERE p.contract=s.name
 AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=pg_catalog.replace(s.body,pg_catalog.chr(13),'')) AS ok FROM sources s
),
function_acl AS (
 SELECT p.contract,p.proowner,a.* FROM functions p
 CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
),
trusted_function_owners AS (
 SELECT s.name,EXISTS(SELECT 1 FROM functions p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
 WHERE p.contract=s.name AND r.rolname NOT IN ('anon','authenticated','service_role')
 AND (SELECT pg_catalog.count(*) FROM api_roles WHERE rolname IN ('anon','authenticated'))=2
 AND NOT EXISTS(SELECT 1 FROM api_roles a WHERE a.rolname IN ('anon','authenticated')
 AND pg_catalog.pg_has_role(a.oid,r.oid,'MEMBER'))) AS ok FROM sources s
),
triggers AS (SELECT * FROM pg_catalog.pg_trigger WHERE NOT tgisinternal),
policies AS (
 SELECT p.*,ARRAY(SELECT r.rolname::text FROM pg_catalog.unnest(p.polroles) x(oid)
 JOIN pg_catalog.pg_roles r ON r.oid=x.oid ORDER BY r.rolname COLLATE "C") AS roles,
 pg_catalog.pg_get_expr(p.polqual,p.polrelid) AS qual,pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) AS with_check
 FROM pg_catalog.pg_policy p
),
policy_contracts AS (
 SELECT e.rel,EXISTS(SELECT 1 FROM policies p WHERE p.polrelid=pg_catalog.to_regclass(e.rel)
 AND p.polname=e.prefix||'_public_read' AND p.polcmd='r' AND p.polpermissive
 AND p.roles=ARRAY['anon','authenticated']::text[] AND p.qual='('||e.flag||' = true)' AND p.with_check IS NULL) AS public_ok,
 EXISTS(SELECT 1 FROM policies p WHERE p.polrelid=pg_catalog.to_regclass(e.rel) AND p.polname=e.prefix||'_admin_all'
 AND p.polcmd='*' AND p.polpermissive AND p.roles=ARRAY['authenticated']::text[]
 AND p.qual='private.is_deepmap_admin()' AND p.with_check='private.is_deepmap_admin()') AS admin_ok,
 (SELECT pg_catalog.count(*) FROM policies p WHERE p.polrelid=pg_catalog.to_regclass(e.rel))=2 AS exact_set
 FROM (VALUES ('public.marcadores','marcadores','is_published'),('public.marker_categories','marker_categories','is_active'),
 ('public.map_layers','map_layers','is_active')) e(rel,prefix,flag)
),
role_helper_contract AS (
 -- Final helper source is an inert literal; no whitespace/body normalization.
 SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
 WHERE p.oid=pg_catalog.to_regprocedure('public.get_deepmap_role()') AND p.pronargs=0 AND p.prorettype='text'::pg_catalog.regtype
 AND l.lanname='sql' AND p.prosecdef AND p.provolatile='s' AND p.proconfig=ARRAY['search_path=""']::text[]
 AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=pg_catalog.replace($role_helper$
    select case
        when private.is_deepmap_banned() then 'banned'
        when private.is_deepmap_admin() then 'admin'
        when private.is_deepmap_moderator() then 'moderator'
        else 'user'
    end;
$role_helper$,pg_catalog.chr(13),'')) AS ok
),
mapping_contract AS (
 SELECT EXISTS(SELECT 1 FROM policies p WHERE p.polrelid=pg_catalog.to_regclass('private.game_legacy_identifiers')
 AND p.polname='game_legacy_identifiers_admin_read' AND p.polcmd='r' AND p.polpermissive AND p.roles=ARRAY['authenticated']::text[]
 AND pg_catalog.regexp_replace(p.qual,'[[:space:]()]','','g') IN
 ('SELECTpublic.get_deepmap_roleASget_deepmap_role=''admin''::text','SELECTget_deepmap_roleASget_deepmap_role=''admin''::text'))
 AND NOT EXISTS(SELECT 1 FROM policies p WHERE p.polrelid=pg_catalog.to_regclass('private.game_legacy_identifiers')
 AND NOT p.polpermissive AND p.polcmd IN ('r','*')) AS ok
),
admin_contract AS (
 SELECT (SELECT pg_catalog.count(*)=3 AND COALESCE(pg_catalog.bool_and(public_ok AND admin_ok AND exact_set),false) FROM policy_contracts)
 AND (SELECT ok FROM mapping_contract) AND (SELECT ok FROM role_helper_contract)
 AND (SELECT pg_catalog.count(*)=4 AND COALESCE(pg_catalog.bool_and(relrowsecurity),false) FROM relations
 WHERE name IN ('public.marcadores','public.marker_categories','public.map_layers','private.game_legacy_identifiers')) AS ok
),
expected_side_bodies(signature,digest) AS (VALUES
 ('public.cancel_marker_submission(bigint)','32db8c8d8de026e6ef2220c752544a06'),
        ('private.deepmap_capture_submission_revision()','d3ff5f69ceb1cd15cf09cf72b26f55ce'),
        ('private.deepmap_autoapprove_moderator_submission()','9c7c5a38258ea603f205fcddb5b48861'),
        ('private.deepmap_notify_admin_submission_received()','c0ec4567cd4efa473e393a5e1e3f6016'),
        ('private.deepmap_notify_submission_review()','a423d83f1c880b7fcb81217d99e8c96d'),
        ('private.deepmap_materialize_submission_content()','09fdd39ed4b0565d21b1f51e6494c4eb'),
        ('private.deepmap_replace_quick_marker_content(bigint,jsonb)','74c611df1824cd9e78d76b98ca6f9920'),
        ('public.review_marker_submission(bigint,text,text)','c2d611f6339f023f3c2b43891f56af29'),
        ('public.review_marker_submission_v2(bigint,text,text,jsonb)','10327cfdf171ec2e3ba17380a909d644')
),
rpc_owners AS (
 SELECT e.signature,p.oid,p.proowner,p.prosecdef,p.proconfig,r.rolname
 FROM (VALUES ('public.review_marker_submission(bigint,text,text)'),
 ('public.review_marker_submission_v2(bigint,text,text,jsonb)')) e(signature)
 LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature)
 LEFT JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
),
writers AS (
 SELECT r.*,EXISTS(SELECT 1 FROM rpc_owners p WHERE p.proowner=r.oid) AS rpc_owner
 FROM pg_catalog.pg_roles r WHERE r.rolname !~ '^pg_'
 AND (pg_catalog.has_any_column_privilege(r.oid,pg_catalog.to_regclass('public.marcadores'),'INSERT')
 OR pg_catalog.has_any_column_privilege(r.oid,pg_catalog.to_regclass('public.marcadores'),'UPDATE')
 OR r.oid IN (SELECT proowner FROM rpc_owners WHERE proowner IS NOT NULL))
),
writer_access AS (
 SELECT r.oid,r.rolname,r.rpc_owner,c.name AS parent,
 COALESCE(c.oid IS NOT NULL AND pg_catalog.has_schema_privilege(r.oid,c.relnamespace,'USAGE'),false) AS usage_ok,
 COALESCE(c.oid IS NOT NULL AND pg_catalog.has_table_privilege(r.oid,c.oid,'SELECT'),false) AS select_ok,
 COALESCE(c.oid IS NOT NULL AND (r.rolsuper OR r.rolbypassrls OR (r.oid=c.relowner AND NOT c.relforcerowsecurity)
 OR (NOT r.rpc_owner AND pg_catalog.pg_has_role(r.oid,'authenticated','USAGE') AND (SELECT ok FROM admin_contract)
 AND pg_catalog.has_function_privilege(r.oid,pg_catalog.to_regprocedure('private.is_deepmap_admin()'),'EXECUTE')
 AND pg_catalog.has_function_privilege(r.oid,pg_catalog.to_regprocedure('public.get_deepmap_role()'),'EXECUTE'))),false) AS rls_ok
 FROM writers r CROSS JOIN relations c WHERE c.name IN
 ('private.game_legacy_identifiers','public.map_layers','public.marker_categories')
),
mapping_acl AS (
 SELECT c.relowner,a.* FROM relations c CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
 WHERE c.name='private.game_legacy_identifiers' AND c.oid IS NOT NULL
),
marker_data AS MATERIALIZED (
 SELECT m.id,m.game_id,m.map_layer,m.category_id,m.game_uuid,m.layer_uuid,m.created_at,m.updated_at,
 pg_catalog.to_jsonb(m)->>'category_uuid' AS category_uuid,
 (SELECT pg_catalog.count(*) FROM public.marker_categories c WHERE c.game_id=m.game_id AND c.id=m.category_id) AS legacy_category_count,
 (SELECT pg_catalog.count(*) FROM public.marker_categories c WHERE c.game_id=m.game_id AND c.id=m.category_id
 AND c.game_uuid=m.game_uuid AND c.category_uuid::text=(pg_catalog.to_jsonb(m)->>'category_uuid')) AS category_count,
 (SELECT pg_catalog.count(*) FROM private.game_legacy_identifiers i WHERE i.legacy_identifier=m.game_id) AS mapping_count,
 (SELECT pg_catalog.count(*) FROM private.game_legacy_identifiers i JOIN public.games g ON g.id=i.game_id
 WHERE i.legacy_identifier=m.game_id AND i.game_id=m.game_uuid) AS game_count,
 (SELECT pg_catalog.count(*) FROM public.map_layers l WHERE l.game_id=m.game_id AND l.id=m.map_layer) AS legacy_layer_count,
 (SELECT pg_catalog.count(*) FROM public.map_layers l JOIN public.game_maps gm ON gm.id=l.game_map_id AND gm.game_id=l.game_uuid
 JOIN public.games g ON g.id=gm.game_id WHERE l.game_id=m.game_id AND l.id=m.map_layer
 AND l.game_uuid=m.game_uuid AND l.layer_uuid=m.layer_uuid) AS layer_count
 FROM public.marcadores m
),
data_stats AS (
 SELECT pg_catalog.count(*) AS total,pg_catalog.count(*) FILTER (WHERE category_uuid IS NULL) AS null_category,
 pg_catalog.count(*) FILTER (WHERE category_count<>1) AS category_invalid,
 pg_catalog.count(*) FILTER (WHERE game_uuid IS NULL OR mapping_count<>1 OR game_count<>1) AS game_invalid,
 pg_catalog.count(*) FILTER (WHERE layer_uuid IS NULL OR legacy_layer_count<>1 OR layer_count<>1) AS layer_invalid,
 pg_catalog.count(*) FILTER (WHERE created_at IS NULL OR updated_at IS NULL) AS timestamp_null,
 pg_catalog.count(*) FILTER (WHERE id IS NULL OR game_id IS NULL OR category_id IS NULL OR map_layer IS NULL) AS legacy_null,
 pg_catalog.count(*) FILTER (WHERE legacy_category_count<>1) AS legacy_category_invalid,
 pg_catalog.count(*) FILTER (WHERE legacy_layer_count<>1) AS legacy_layer_invalid FROM marker_data
),
checks AS (
 SELECT 'maintenance.visibility.'||name AS check_name,ok,'Full SELECT/schema USAGE plus superuser/BYPASSRLS/owner without FORCE RLS'::text AS details FROM visibility
 UNION ALL SELECT 'maintenance.visibility.all_data',ok,'All eight data relations visible without partial RLS' FROM full_visibility
 UNION ALL SELECT 'schema.object.'||name,oid IS NOT NULL AND relkind='r' AND relrowsecurity,'Ordinary table with RLS enabled' FROM relations
 UNION ALL SELECT 'schema.column.'||e.rel||'.'||e.name,EXISTS(SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass(e.rel)
 AND a.attname=e.name AND a.atttypid=pg_catalog.to_regtype(e.type_name) AND a.attnotnull=e.nn AND a.attidentity::text=e.identity_kind
 AND a.attgenerated='' AND a.default_expr IS NOT DISTINCT FROM e.default_expr AND a.atthasdef=(e.default_expr IS NOT NULL)),
 'Exact type/NOT NULL/default/identity; no generated expression; default='||COALESCE(e.default_expr,'none') FROM expected_columns e
 UNION ALL SELECT 'schema.exact_columns.'||e.rel,(SELECT pg_catalog.count(*) FROM attributes WHERE attrelid=pg_catalog.to_regclass(e.rel))=e.total
 AND NOT EXISTS(SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass(e.rel) AND a.attname NOT IN
 (SELECT name FROM expected_columns WHERE rel=e.rel)), 'Exactly '||e.total||' approved columns' FROM
 (VALUES ('public.marcadores',25),('public.marker_categories',18),('private.marker_editor_audit',9)) e(rel,total)
 UNION ALL SELECT 'schema.marker.no_group_uuid',pg_catalog.to_regclass('public.marcadores') IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM attributes WHERE attrelid=pg_catalog.to_regclass('public.marcadores') AND attname='group_uuid'),
 'Only category_uuid is added in B6c'
 UNION ALL SELECT 'constraint.key.'||e.name,EXISTS(SELECT 1 FROM constraints c JOIN indexes i ON i.indexrelid=c.conindid
 WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND c.conname=e.name AND c.contype::text=e.kind AND c.columns=e.columns
 AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred AND i.indrelid=c.conrelid AND i.relname=e.name AND i.columns=e.columns
 AND i.indisunique AND i.indisprimary=(e.kind='p') AND i.indimmediate AND i.indisvalid AND i.indisready AND i.indislive AND i.amname='btree'
 AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnatts=i.indnkeyatts AND i.indnkeyatts=pg_catalog.cardinality(e.columns)
 AND ARRAY(SELECT k FROM pg_catalog.unnest(i.indkey) k)=c.conkey),
 'Validated immediate key/backing unique B-tree valid/ready/live, no predicate/expression/INCLUDE' FROM expected_keys e
 UNION ALL SELECT 'constraint.check.'||e.name,EXISTS(SELECT 1 FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass(e.rel)
 AND c.conname=e.name AND c.contype='c' AND c.convalidated AND CASE WHEN e.rel='public.marcadores'
 THEN pg_catalog.regexp_replace(pg_catalog.pg_get_expr(c.conbin,c.conrelid),'[[:space:]()]','','g')=
 pg_catalog.regexp_replace(e.expression,'[[:space:]()]','','g') ELSE pg_catalog.pg_get_expr(c.conbin,c.conrelid)=e.expression END),
 'Approved validated CHECK expression: '||e.expression FROM expected_checks e
 UNION ALL SELECT 'constraint.fk.'||e.name,EXISTS(SELECT 1 FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass(e.rel)
 AND c.conname=e.name AND c.contype='f' AND c.confrelid=pg_catalog.to_regclass(e.parent) AND c.columns=e.columns AND c.parent_columns=e.parent_columns
 AND c.confmatchtype='s' AND c.confupdtype::text=e.upd AND c.confdeltype::text=e.del AND c.convalidated
 AND NOT c.condeferrable AND NOT c.condeferred AND pg_catalog.to_jsonb(c)->>'confdelsetcols' IS NULL),
 'Exact source/target/SIMPLE/actions/validated/immediate; UPDATE='||e.upd||'; DELETE='||e.del FROM expected_fks e
 UNION ALL SELECT 'constraint.logical_exact_set.'||e.rel,(SELECT pg_catalog.count(*) FROM constraints
 WHERE conrelid=pg_catalog.to_regclass(e.rel) AND contype IN ('p','c','f','u','x'))=e.total
 AND NOT EXISTS(SELECT 1 FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND c.contype IN ('p','c','f','u','x')
 AND NOT EXISTS(SELECT 1 FROM expected_logical_constraints x WHERE x.rel=e.rel AND x.name=c.conname AND x.kind=c.contype::text)),
 'Exact logical p/c/f/u/x set; total='||e.total||'; version-specific NOT NULL constraints separate' FROM
 (VALUES ('public.marcadores',14),('public.marker_categories',14),('private.marker_editor_audit',2)) e(rel,total)
 UNION ALL SELECT 'constraint.not_null_catalog.'||e.rel,pg_catalog.to_regclass(e.rel) IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND c.contype='n'
 AND (NOT c.convalidated OR NOT EXISTS(SELECT 1 FROM expected_columns x WHERE x.rel=e.rel AND x.nn AND c.columns=ARRAY[x.name]::text[]))),
 'If catalog represents NOT NULL, every entry matches an approved NOT NULL column; attnotnull remains authoritative'
 FROM (VALUES ('public.marcadores'),('public.marker_categories'),('private.marker_editor_audit')) e(rel)
 UNION ALL SELECT 'constraint.marker.no_standalone_category_uuid_fk',pg_catalog.to_regclass('public.marcadores') IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM constraints WHERE conrelid=pg_catalog.to_regclass('public.marcadores') AND contype='f'
 AND columns=ARRAY['category_uuid']::text[]),'The full composite category FK is the only category UUID relation'
 UNION ALL SELECT 'index.'||e.name,EXISTS(SELECT 1 FROM indexes i WHERE i.indrelid=pg_catalog.to_regclass(e.rel)
 AND i.relname=e.name AND i.columns=e.columns AND i.indisunique=e.uq AND i.indimmediate AND i.indisvalid AND i.indisready AND i.indislive
 AND i.amname='btree' AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnatts=i.indnkeyatts AND i.indnkeyatts=pg_catalog.cardinality(e.columns)),
 'Exact approved index keys/uniqueness, B-tree valid/ready/live/immediate; no predicate/expression/INCLUDE' FROM expected_indexes e
 UNION ALL SELECT 'index.exact_set.'||e.rel,(SELECT pg_catalog.count(*) FROM indexes WHERE indrelid=pg_catalog.to_regclass(e.rel))=e.total
 AND NOT EXISTS(SELECT 1 FROM indexes i WHERE i.indrelid=pg_catalog.to_regclass(e.rel) AND i.relname NOT IN
 (SELECT name FROM expected_indexes WHERE rel=e.rel)), 'Exactly '||e.total||' indexes; no new marker category UUID index' FROM
 (VALUES ('public.marcadores',4),('public.marker_categories',3)) e(rel,total)
 UNION ALL SELECT 'function.'||s.name||'.attributes',EXISTS(SELECT 1 FROM functions p WHERE p.contract=s.name
 AND p.pronamespace=pg_catalog.to_regnamespace('private') AND p.pronargs=0 AND p.proargtypes=''::pg_catalog.oidvector
 AND p.proargnames IS NULL AND p.proargmodes IS NULL AND p.proallargtypes IS NULL AND p.provariadic=0
 AND p.pronargdefaults=0 AND p.proargdefaults IS NULL AND p.prorettype='trigger'::pg_catalog.regtype AND p.prokind='f'
 AND p.lanname='plpgsql' AND p.prosecdef=s.definer AND p.proconfig=ARRAY['search_path=""']::text[]
 AND p.provolatile='v' AND p.proparallel='u' AND NOT p.proisstrict AND NOT p.proleakproof AND NOT p.proretset AND p.procost=100 AND p.prorows=0),
 'Zero-arg private trigger/plpgsql/empty search_path/VOLATILE/UNSAFE/called on NULL/non-leakproof/COST100; DEFINER='||s.definer FROM sources s
 UNION ALL SELECT 'function.'||name||'.exact_body',ok,'Complete approved final body; symmetric CR removal only; never invoked' FROM body_matches
 UNION ALL SELECT 'function.'||s.name||'.single_overload',(SELECT pg_catalog.count(*)=1 AND COALESCE(pg_catalog.bool_and(
 p.oid=pg_catalog.to_regprocedure(s.signature) AND n.nspname='private'),false) FROM pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private')
 AND p.proname=pg_catalog.split_part(pg_catalog.split_part(s.signature,'.',2),'(',1)),
 'One exact private signature, no public/private overload' FROM sources s
 UNION ALL SELECT 'function.marker.contract.'||e.name,b.ok,e.details FROM body_matches b CROSS JOIN (VALUES
 ('b4b_preserved','Exact body retains mapping/game immutability/layer lookup/changes/protection/B4b hydration'),
 ('insert_category','STRICT legacy category lookup + parent context; caller UUID always overridden'),
 ('update_category','Unchanged category protects UUID/NULL and detects drift; changed accepts old/NULL/destination, rejects contradiction and forces destination'),
 ('hydration','Only category_uuid differs before touch, exact destination required; NOT NULL ends normal transition'),
 ('layer_category_together','Independent layer/category changes share immutable game context')) e(name,details) WHERE b.name='marker'
 UNION ALL SELECT 'function.audit.contract.'||e.name,b.ok,e.details FROM body_matches b CROSS JOIN (VALUES
 ('insert_legacy','INSERT legacy branch intact; no INSERT early-return'),
 ('technical_guard','Genuine UPDATE difference ignoring updated_at, then equality removing exactly updated_at/game_uuid/layer_uuid/category_uuid before audit UPSERT'),
 ('semantic_content','Content projection removes exactly updated_at/is_published/game_uuid/layer_uuid/category_uuid; category_id and all editorial fields remain real content'),
 ('no_op_publication','Legacy no-op/publication/approval/attribution behavior retained')) e(name,details) WHERE b.name='audit'
 UNION ALL SELECT 'acl.resolver.'||e.name||'.owner_only',EXISTS(SELECT 1 FROM functions WHERE contract=e.name)
 AND NOT EXISTS(SELECT 1 FROM function_acl WHERE contract=e.name AND (grantee<>proowner OR privilege_type<>'EXECUTE')),
 'Raw ACL owner-only EXECUTE; no PUBLIC/API/service_role/other non-owner grant' FROM (VALUES ('marker'),('category'),('group')) e(name)
 UNION ALL SELECT 'acl.function.'||name||'.trusted_owner',ok,'Actual owner is not anon/authenticated/service_role and is not inherited by anon/authenticated; no historical OID/name fixed'
 FROM trusted_function_owners WHERE name IN ('marker','audit','category','group')
 UNION ALL SELECT 'acl.audit.no_untrusted_direct_execute',EXISTS(SELECT 1 FROM functions WHERE contract='audit')
 AND NOT EXISTS(SELECT 1 FROM function_acl a LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
 WHERE a.contract='audit' AND (a.grantee=0 OR r.rolname IN ('anon','authenticated'))),
 'No PUBLIC/anon/authenticated direct EXECUTE; existing trusted backend grants are not forced owner-only'
 UNION ALL SELECT 'acl.private.no_untrusted_create',(SELECT pg_catalog.count(*) FROM api_roles WHERE rolname IN ('anon','authenticated'))=2
 AND NOT EXISTS(SELECT 1 FROM api_roles WHERE rolname IN ('anon','authenticated') AND pg_catalog.has_schema_privilege(oid,'private','CREATE')),
 'anon/authenticated cannot replace private functions'
 UNION ALL SELECT 'acl.marker.category_uuid.no_separate_column_acl',EXISTS(SELECT 1 FROM attributes
 WHERE attrelid=pg_catalog.to_regclass('public.marcadores') AND attname='category_uuid' AND attacl IS NULL),
 'No category_uuid-specific column ACL; table-wide writers are controlled by the exact resolver'
 UNION ALL SELECT 'trigger.marker.'||e.name,EXISTS(SELECT 1 FROM triggers t WHERE t.tgrelid=pg_catalog.to_regclass('public.marcadores')
 AND t.tgname=e.name AND t.tgtype=e.bits AND t.tgfoid=pg_catalog.to_regprocedure(e.signature) AND t.tgenabled='O'
 AND t.tgnargs=0 AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL),
 'Exact ROW/BEFORE-or-AFTER/events/function/origin/zero args/no WHEN/no UPDATE OF' FROM (VALUES
 ('deepmap_marcadores_identity',23,'private.deepmap_resolve_marker_identity()'),
 ('deepmap_marcadores_touch_updated_at',19,'private.deepmap_touch_updated_at()'),
 ('deepmap_marker_editor_audit',21,'private.deepmap_stamp_marker_audit()')) e(name,bits,signature)
 UNION ALL SELECT 'trigger.marker.exact_set',pg_catalog.count(*)=3 AND COALESCE(pg_catalog.bool_and(tgname IN
 ('deepmap_marcadores_identity','deepmap_marcadores_touch_updated_at','deepmap_marker_editor_audit')),false),
 'Exactly three user triggers; FK internal RI triggers excluded' FROM triggers WHERE tgrelid=pg_catalog.to_regclass('public.marcadores')
 UNION ALL SELECT 'trigger.marker.before_update_name_order',(SELECT pg_catalog.array_agg(tgname::text ORDER BY tgname COLLATE "C")
 FROM triggers WHERE tgrelid=pg_catalog.to_regclass('public.marcadores') AND (tgtype & 2)=2 AND (tgtype & 16)=16)
 IS NOT DISTINCT FROM ARRAY['deepmap_marcadores_identity','deepmap_marcadores_touch_updated_at']::text[],
 'PostgreSQL alphabetical BEFORE UPDATE order: identity then touch; no OID ordering'
 UNION ALL SELECT 'trigger.audit.no_user_triggers',pg_catalog.to_regclass('private.marker_editor_audit') IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM triggers WHERE tgrelid=pg_catalog.to_regclass('private.marker_editor_audit')),
 'Current audit has no user triggers; historical audit preservation belongs to migration snapshots'
 UNION ALL SELECT 'policy.'||rel||'.public_read',public_ok,'Exact permissive anon/authenticated SELECT with legacy public predicate' FROM policy_contracts
 UNION ALL SELECT 'policy.'||rel||'.admin_all',admin_ok,'Exact permissive authenticated ALL Admin USING/WITH CHECK, including inactive parents' FROM policy_contracts
 UNION ALL SELECT 'policy.'||rel||'.exact_set',exact_set,'Exactly two approved legacy policies; no B6c additions' FROM policy_contracts
 UNION ALL SELECT 'mapping.admin_read_contract',ok,'Exact permissive authenticated SELECT role=admin and no restrictive SELECT/ALL' FROM mapping_contract
 UNION ALL SELECT 'mapping.role_helper.exact_contract',ok,'Final role helper attributes and full source matched; never invoked' FROM role_helper_contract
 UNION ALL SELECT 'mapping.acl.authenticated_lookup',EXISTS(SELECT 1 FROM api_roles r WHERE r.rolname='authenticated'
 AND pg_catalog.has_schema_privilege(r.oid,'private','USAGE') AND pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('private.game_legacy_identifiers'),'SELECT')
 AND pg_catalog.has_function_privilege(r.oid,pg_catalog.to_regprocedure('public.get_deepmap_role()'),'EXECUTE')),
 'Effective authenticated mapping SELECT/private USAGE/role helper EXECUTE'
 UNION ALL SELECT 'mapping.acl.approved_current_contract',pg_catalog.to_regclass('private.game_legacy_identifiers') IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM mapping_acl a WHERE a.grantee<>a.relowner AND NOT EXISTS(SELECT 1 FROM api_roles r
 WHERE r.oid=a.grantee AND NOT a.is_grantable AND ((r.rolname='authenticated' AND a.privilege_type IN ('SELECT','INSERT'))
 OR (r.rolname='service_role' AND a.privilege_type='SELECT' AND a.grantor=a.relowner
 AND (EXISTS(SELECT 1 FROM writers w WHERE w.oid=r.oid)
 OR pg_catalog.has_any_column_privilege(r.oid,pg_catalog.to_regclass('public.marker_categories'),'INSERT')
 OR pg_catalog.has_any_column_privilege(r.oid,pg_catalog.to_regclass('public.marker_categories'),'UPDATE'))))))
 AND NOT EXISTS(SELECT 1 FROM attributes a CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) x
 WHERE a.attrelid=pg_catalog.to_regclass('private.game_legacy_identifiers') AND x.grantee<>(SELECT c.relowner FROM relations c
 WHERE c.name='private.game_legacy_identifiers')),
 'Current B6b mapping ACL permits owner, authenticated SELECT/INSERT and approved service writer SELECT; no claim B6c created it'
 UNION ALL SELECT 'acl.category.anon_select',EXISTS(SELECT 1 FROM api_roles r WHERE r.rolname='anon'
 AND pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('public.marker_categories'),'SELECT')),'Legacy anon category table SELECT'
 UNION ALL SELECT 'acl.category.authenticated.'||e.privilege,EXISTS(SELECT 1 FROM api_roles r WHERE r.rolname='authenticated'
 AND pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('public.marker_categories'),e.privilege)),
 'Legacy authenticated category table privilege '||e.privilege FROM (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE')) e(privilege)
 UNION ALL SELECT 'writer.invoker.'||rolname||'.'||parent,usage_ok AND select_ok AND rls_ok,
 'Effective writer; RPC owner='||rpc_owner||'; schema USAGE='||usage_ok||'; table SELECT='||select_ok||'; unconditional-or-authorized-Admin RLS='||rls_ok FROM writer_access
 UNION ALL SELECT 'writer.invoker.all_parents',EXISTS(SELECT 1 FROM writers)
 AND (SELECT pg_catalog.count(*) FROM writer_access)=3*(SELECT pg_catalog.count(*) FROM writers)
 AND NOT EXISTS(SELECT 1 FROM writer_access WHERE NOT (usage_ok AND select_ok AND rls_ok)),
 'All effective non-pg_* direct writers and real review DEFINER owners can resolve mapping/layer/category; no grant changes'
 UNION ALL SELECT 'writer.review.owner.'||signature,oid IS NOT NULL AND rolname IS NOT NULL AND prosecdef AND proconfig=ARRAY['search_path=""']::text[]
 AND (SELECT pg_catalog.count(*) FROM writer_access WHERE writer_access.oid=rpc_owners.proowner AND rpc_owner)=3
 AND NOT EXISTS(SELECT 1 FROM writer_access w WHERE w.oid=rpc_owners.proowner AND NOT (usage_ok AND select_ok AND rls_ok)),
 'Actual review owner='||COALESCE(rolname,'missing')||'; all three parent lookups require unconditional visibility, not inherited Admin policy' FROM rpc_owners
 UNION ALL SELECT 'writer.baseline.'||e.signature,EXISTS(SELECT 1 FROM pg_catalog.pg_proc p
 WHERE p.oid=pg_catalog.to_regprocedure(e.signature) AND p.prosecdef AND p.proconfig=ARRAY['search_path=""']::text[]
 AND pg_catalog.md5(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),''))=e.digest),
 'Exact final B6c-protected B5b digest/DEFINER/search_path contract; never invoked' FROM expected_side_bodies e
 UNION ALL SELECT 'writer.baseline.single_overload.'||e.signature,(SELECT pg_catalog.count(*)=1
 AND COALESCE(pg_catalog.bool_and(p.oid=pg_catalog.to_regprocedure(e.signature)),false)
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','private') AND p.proname=pg_catalog.split_part(pg_catalog.split_part(e.signature,'.',2),'(',1)),
 'Only the known final public/private writer signature; no added overload' FROM expected_side_bodies e
 UNION ALL SELECT 'writer.no_unreviewed_marker_functions',NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','private') AND p.prosrc ~* '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public[.])?marcadores([[:space:]]|[(])'
 AND p.oid NOT IN (pg_catalog.to_regprocedure('public.review_marker_submission(bigint,text,text)'),
 pg_catalog.to_regprocedure('public.review_marker_submission_v2(bigint,text,text,jsonb)'))),
 'No additional identifiable direct marker-writing function outside the two reviewed RPCs'
 UNION ALL SELECT 'data.marker.category_uuid.non_null',null_category=0,'NULL category UUID rows='||null_category FROM data_stats
 UNION ALL SELECT 'data.marker.category_context.exact',category_invalid=0,'Rows without exactly one full legacy+game+category UUID parent='||category_invalid FROM data_stats
 UNION ALL SELECT 'data.marker.game_context.exact',game_invalid=0,'Rows without exactly one legacy mapping/UUID/game parent='||game_invalid FROM data_stats
 UNION ALL SELECT 'data.marker.layer_context.exact',layer_invalid=0,'Rows without exact legacy layer/UUID/game/game-map parent='||layer_invalid FROM data_stats
 UNION ALL SELECT 'data.marker.timestamps.non_null',timestamp_null=0,'Current NULL created_at/updated_at='||timestamp_null||'; no historical touch/monotonicity claim' FROM data_stats
 UNION ALL SELECT 'data.marker.legacy_identity.non_null',legacy_null=0,'Current NULL id/game_id/category_id/map_layer='||legacy_null FROM data_stats
 UNION ALL SELECT 'data.marker.id.unique',NOT EXISTS(SELECT 1 FROM marker_data GROUP BY id HAVING pg_catalog.count(*)>1),'No duplicate marker BIGINT IDs; no fixed row count'
 UNION ALL SELECT 'data.marker.legacy_category.exact',legacy_category_invalid=0,'Rows without exactly one legacy category parent='||legacy_category_invalid FROM data_stats
 UNION ALL SELECT 'data.marker.legacy_layer.exact',legacy_layer_invalid=0,'Rows without exactly one legacy layer parent='||legacy_layer_invalid FROM data_stats
 UNION ALL SELECT 'data.audit.no_orphans',NOT EXISTS(SELECT 1 FROM private.marker_editor_audit a WHERE NOT EXISTS(SELECT 1 FROM public.marcadores m WHERE m.id=a.marker_id)),
 'Current audit has no orphan rows; markers need not have audit rows; no historical audit delta claim'
 UNION ALL SELECT 'data.category.group_context.exact',NOT EXISTS(SELECT 1 FROM public.marker_categories c
 WHERE (c.group_id IS NULL) IS DISTINCT FROM (c.group_uuid IS NULL)
 OR (c.group_id IS NOT NULL AND (SELECT pg_catalog.count(*) FROM public.marker_category_groups g WHERE g.game_id=c.game_id
 AND g.id=c.group_id AND g.game_uuid=c.game_uuid AND g.group_uuid=c.group_uuid)<>1)),
 'Current B6b optional group pair and complete group context; full group visibility required'
 UNION ALL SELECT 'scope.pre_b7.columns.'||e.rel,pg_catalog.to_regclass(e.rel) IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM attributes WHERE attrelid=pg_catalog.to_regclass(e.rel) AND attname IN ('category_uuid','group_uuid')),
 'No category_uuid/group_uuid consumer columns yet' FROM (VALUES ('public.marker_submissions'),('private.marker_submission_revisions'),
 ('public.user_notifications'),('public.marker_images'),('public.marker_sections'),('public.marker_section_rows')) e(rel)
 UNION ALL SELECT 'scope.pre_b7.no_identifiable_resolvers',NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','private') AND (p.proname ~ '^deepmap_resolve_(marker|submission|notification|revision)_(category|group)_identity$'
 OR (p.proname ~ '^deepmap_resolve_marker.*identity$' AND p.oid<>pg_catalog.to_regprocedure('private.deepmap_resolve_marker_identity()')))),
 'No identifiable separate category/group consumer resolver; cannot prove frontend code from SQL catalog'
 UNION ALL SELECT 'scope.pre_b7.no_identifiable_rpc_uuid_contracts',NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private')
 AND (p.proname ~* '(^b7_|_b7_|(marker|submission|revision|notification).*(category|group)_uuid)'
 OR (p.proname ~* '(marker|submission|revision|notification)'
 AND p.proargnames && ARRAY['category_uuid','p_category_uuid','group_uuid','p_group_uuid']::text[]))),
 'No identifiable B7 marker/consumer RPC name or category/group UUID argument; arbitrary hidden JSON/code contracts require repo review'
 UNION ALL SELECT 'scope.pre_b7.no_consumer_uuid_constraints',NOT EXISTS(SELECT 1 FROM constraints c
 WHERE c.conrelid IN (pg_catalog.to_regclass('public.marker_submissions'),pg_catalog.to_regclass('private.marker_submission_revisions'),
 pg_catalog.to_regclass('public.user_notifications'),pg_catalog.to_regclass('public.marker_images'),pg_catalog.to_regclass('public.marker_sections'),
 pg_catalog.to_regclass('public.marker_section_rows')) AND (c.columns && ARRAY['category_uuid','group_uuid']::text[]
 OR c.parent_columns && ARRAY['category_uuid','group_uuid']::text[] OR c.conname ~* '(category_uuid|group_uuid|b7)')),
 'No identifiable later consumer category/group UUID constraint; B6c marker bridge is expected'
 UNION ALL SELECT 'scope.marker_audit.no_rules_or_inheritance',NOT EXISTS(SELECT 1 FROM pg_catalog.pg_rewrite
 WHERE ev_class IN (pg_catalog.to_regclass('public.marcadores'),pg_catalog.to_regclass('private.marker_editor_audit')))
 AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_inherits WHERE inhrelid IN (pg_catalog.to_regclass('public.marcadores'),pg_catalog.to_regclass('private.marker_editor_audit'))
 OR inhparent IN (pg_catalog.to_regclass('public.marcadores'),pg_catalog.to_regclass('private.marker_editor_audit'))),
 'No unknown marker/audit rules or inheritance, matching migration preflight'
)
SELECT check_name,CASE WHEN ok IS TRUE AND (check_name NOT LIKE 'data.%' OR (SELECT ok FROM full_visibility))
 THEN 'PASS' ELSE 'FAIL' END AS status,
 details||CASE WHEN check_name LIKE 'data.%' AND NOT (SELECT ok FROM full_visibility)
 THEN '; INVALID DATA RESULT: incomplete maintenance visibility' ELSE '' END AS details
FROM checks
ORDER BY check_name;
