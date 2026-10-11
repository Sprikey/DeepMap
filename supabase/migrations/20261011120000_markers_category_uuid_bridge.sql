-- DeepMap B6c: marker category UUID shadow and technical audit compatibility.
-- Manual review/application only. Legacy TEXT authority; no B7 consumer switch.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = pg_catalog;

DO $dependencies$
BEGIN
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.games'),('public.game_maps'),('private.game_legacy_identifiers'),
        ('public.marker_category_groups'),('public.map_layers'),('public.marker_categories'),
        ('public.marcadores'),('private.marker_editor_audit'),('public.marker_submissions'),
        ('private.marker_submission_revisions'),('public.user_notifications'),
        ('public.marker_images'),('public.marker_sections'),('public.marker_section_rows')) e(name)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
            WHERE c.oid=pg_catalog.to_regclass(e.name) AND c.relkind='r' AND c.relrowsecurity)) THEN
        RAISE EXCEPTION 'B6C_ORDINARY_RLS_TABLES_REQUIRED';
    END IF;
END;
$dependencies$;

-- Parent-first, final modes acquired once and retained to COMMIT.
-- SHARE stabilizes parent rows against INSERT/UPDATE/DELETE, permits reads.
-- Categories SHARE ROW EXCLUSIVE additionally satisfies ADD FK's parent lock.
-- Markers ACCESS EXCLUSIVE is required for ADD COLUMN/SET NOT NULL.
-- Audit SHARE excludes independent audit writers throughout the exact proof.
-- No submissions/revisions/notifications/images/sections/rows locks.
LOCK TABLE public.games IN SHARE MODE;
LOCK TABLE public.game_maps IN SHARE MODE;
LOCK TABLE private.game_legacy_identifiers IN SHARE MODE;
LOCK TABLE public.marker_category_groups IN SHARE MODE;
LOCK TABLE public.map_layers IN SHARE MODE;
LOCK TABLE public.marker_categories IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.marcadores IN ACCESS EXCLUSIVE MODE;
LOCK TABLE private.marker_editor_audit IN SHARE MODE;

DO $bridge$
DECLARE
    -- Full literals copied from the final B4b/B6a/B6b sources, CRLF-safe.
    v_audit_old text := pg_catalog.replace($audit_b4a$
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
    v_resolver_old text := pg_catalog.replace($resolver_b4b$
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
    $resolver_b4b$,pg_catalog.chr(13),'');
    v_category_body text := pg_catalog.replace($category_b6b$
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
$category_b6b$,pg_catalog.chr(13),'');
    v_group_body text := pg_catalog.replace($group_b6a$
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
$group_b6a$,pg_catalog.chr(13),'');
    v_touch_body text := pg_catalog.replace($touch$
begin
    new.updated_at := now();
    return new;
end;
$touch$,pg_catalog.chr(13),'');
    v_audit_new text;
    v_resolver_new text;
    v_audit_fn oid := pg_catalog.to_regprocedure('private.deepmap_stamp_marker_audit()');
    v_resolver_fn oid := pg_catalog.to_regprocedure('private.deepmap_resolve_marker_identity()');
    v_audit_before jsonb;
    v_resolver_before jsonb;
    v_before jsonb;
    v_after jsonb;
    v_data_before jsonb := '{}'::jsonb;
    v_data_after jsonb := '{}'::jsonb;
    v_data jsonb;
    v_rows bigint;
    v_affected bigint;
    v_relation text;
    v_name text;
    v_role record;
    v_parent record;
    v_admin_contract boolean;
    v_rpc_owner boolean;
    v_catalog text := $catalog$
        WITH rels AS (SELECT pg_catalog.to_regclass(e.name) AS oid FROM (VALUES
            ('public.games'),('public.game_maps'),('private.game_legacy_identifiers'),
            ('public.marker_category_groups'),('public.map_layers'),('public.marker_categories'),
            ('public.marcadores'),('private.marker_editor_audit'),('public.marker_submissions'),
            ('private.marker_submission_revisions'),('public.user_notifications'),
            ('public.marker_images'),('public.marker_sections'),('public.marker_section_rows')) e(name)),
        added AS (SELECT c.oid FROM pg_catalog.pg_constraint c
            WHERE c.conrelid='public.marcadores'::pg_catalog.regclass
              AND c.conname='marcadores_legacy_uuid_category_fk')
        SELECT pg_catalog.jsonb_build_object(
            'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attrelid,a.attnum)
                FROM pg_catalog.pg_attribute a WHERE a.attrelid IN (SELECT oid FROM rels) AND a.attnum>0
                AND NOT (a.attrelid='public.marcadores'::pg_catalog.regclass AND a.attname='category_uuid')),
            'defaults',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.adrelid,d.adnum)
                FROM pg_catalog.pg_attrdef d WHERE d.adrelid IN (SELECT oid FROM rels)),
            'constraints',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid)
                FROM pg_catalog.pg_constraint c WHERE (c.conrelid IN (SELECT oid FROM rels) OR c.confrelid IN (SELECT oid FROM rels))
                AND c.oid NOT IN (SELECT oid FROM added)
                -- PostgreSQL versions with catalog NOT NULL constraints.
                AND NOT (c.conrelid='public.marcadores'::pg_catalog.regclass AND c.contype='n'
                    AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute
                        WHERE attrelid=c.conrelid AND attname='category_uuid' AND NOT attisdropped)]::smallint[])),
            'indexes',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.indexrelid)
                FROM pg_catalog.pg_index i WHERE i.indrelid IN (SELECT oid FROM rels)),
            'index_objects',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('oid',c.oid,'name',c.relname,
                'namespace',c.relnamespace,'owner',c.relowner,'acl',c.relacl,'am',c.relam,'options',c.reloptions,
                'definition',pg_catalog.pg_get_indexdef(c.oid)) ORDER BY c.oid)
                FROM pg_catalog.pg_class c JOIN pg_catalog.pg_index i ON i.indexrelid=c.oid WHERE i.indrelid IN (SELECT oid FROM rels)),
            'security',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('oid',c.oid,'name',c.relname,
                'namespace',c.relnamespace,'owner',c.relowner,'acl',c.relacl,'kind',c.relkind,'persistence',c.relpersistence,
                'rls',c.relrowsecurity,'force',c.relforcerowsecurity,'options',c.reloptions,'replica_identity',c.relreplident)
                ORDER BY c.oid) FROM pg_catalog.pg_class c WHERE c.oid IN (SELECT oid FROM rels)),
            'policies',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid)
                FROM pg_catalog.pg_policy p WHERE p.polrelid IN (SELECT oid FROM rels)),
            'triggers',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY t.oid)
                FROM pg_catalog.pg_trigger t WHERE t.tgrelid IN (SELECT oid FROM rels)
                -- Only RI triggers belonging to the one new FK may appear,
                -- including its unavoidable parent-side category RI triggers.
                AND NOT (t.tgisinternal AND t.tgconstraint IN (SELECT oid FROM added))),
            'rules',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) ORDER BY r.oid)
                FROM pg_catalog.pg_rewrite r WHERE r.ev_class IN (SELECT oid FROM rels)),
            'inheritance',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.inhrelid,i.inhseqno)
                FROM pg_catalog.pg_inherits i WHERE i.inhrelid IN (SELECT oid FROM rels) OR i.inhparent IN (SELECT oid FROM rels)),
            'namespaces',(SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(n) ORDER BY n.oid)
                FROM pg_catalog.pg_namespace n WHERE n.nspname IN ('public','private')),
            'functions',(SELECT pg_catalog.jsonb_agg(CASE WHEN p.oid IN ($1,$2)
                THEN pg_catalog.to_jsonb(p)-'prosrc' ELSE pg_catalog.to_jsonb(p) END ORDER BY p.oid)
                FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private')))
    $catalog$;
BEGIN
    -- Full maintenance visibility, never partial snapshots hidden by RLS.
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
        WHERE c.oid IN ('public.games'::pg_catalog.regclass,'public.game_maps'::pg_catalog.regclass,
            'private.game_legacy_identifiers'::pg_catalog.regclass,'public.marker_category_groups'::pg_catalog.regclass,
            'public.map_layers'::pg_catalog.regclass,'public.marker_categories'::pg_catalog.regclass,
            'public.marcadores'::pg_catalog.regclass,'private.marker_editor_audit'::pg_catalog.regclass)
        AND (NOT pg_catalog.has_table_privilege(c.oid,'SELECT') OR NOT pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
            OR NOT (r.rolsuper OR r.rolbypassrls OR (r.oid=c.relowner AND NOT c.relforcerowsecurity)))) THEN
        RAISE EXCEPTION 'B6C_FULL_MAINTENANCE_VISIBILITY_REQUIRED';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r JOIN pg_catalog.pg_class m ON m.oid='public.marcadores'::pg_catalog.regclass
        JOIN pg_catalog.pg_proc a ON a.oid=v_audit_fn JOIN pg_catalog.pg_proc f ON f.oid=v_resolver_fn
        WHERE r.rolname=CURRENT_USER AND (r.rolsuper OR pg_catalog.pg_has_role(r.oid,m.relowner,'USAGE'))
        AND (r.rolsuper OR pg_catalog.pg_has_role(r.oid,a.proowner,'USAGE'))
        AND (r.rolsuper OR pg_catalog.pg_has_role(r.oid,f.proowner,'USAGE')))
       OR NOT pg_catalog.has_table_privilege('public.marcadores','UPDATE')
       OR NOT pg_catalog.has_table_privilege('public.marker_categories','REFERENCES') THEN
        RAISE EXCEPTION 'B6C_DDL_FUNCTION_OWNERSHIP_OR_FILL_PRIVILEGES_REQUIRED';
    END IF;
    -- Exact 24-column post-B4b shape. Historical defaults are only inspected;
    -- no game/layer/category/count is hardcoded in identity resolution or fill.
    IF EXISTS (WITH expected(name,type_name,nn,identity_kind,default_expr) AS (VALUES
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
        ), actual AS (SELECT a.*,pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS default_expr
            FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
            WHERE a.attrelid='public.marcadores'::pg_catalog.regclass AND a.attnum>0 AND NOT a.attisdropped)
        SELECT 1 FROM expected e FULL JOIN actual a ON a.attname=e.name WHERE e.name IS NULL OR a.attname IS NULL
            OR a.atttypid<>pg_catalog.to_regtype(e.type_name) OR a.attnotnull IS DISTINCT FROM e.nn
            OR a.attidentity::text<>e.identity_kind OR a.attgenerated<>'' OR a.default_expr IS DISTINCT FROM e.default_expr
            OR a.atthasdef IS DISTINCT FROM (e.default_expr IS NOT NULL)) THEN
        RAISE EXCEPTION 'B6C_MARKER_COLUMNS_DRIFT_OR_PARTIAL_STATE';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_constraint WHERE conrelid='public.marcadores'::pg_catalog.regclass AND contype='c')<>7
       OR EXISTS (SELECT 1 FROM (VALUES
        ('marcadores_slug_format','slug ~ ''^[a-z0-9]+(?:-[a-z0-9]+)*$''::text'),
        ('marcadores_color_override_format','color_override IS NULL OR color_override ~ ''^#[0-9A-Fa-f]{6}$''::text'),
        ('marcadores_icon_source_override_valid','icon_source_override IS NULL OR icon_source_override = ANY (ARRAY[''none''::text, ''static''::text, ''r2''::text, ''external''::text])'),
        ('marcadores_icon_override_ref_required','icon_source_override IS NULL OR icon_source_override = ''none''::text OR NULLIF(btrim(icon_ref_override), ''''::text) IS NOT NULL'),
        ('marcadores_marker_width_override_valid','marker_width_override IS NULL OR marker_width_override > 0'),
        ('marcadores_marker_height_override_valid','marker_height_override IS NULL OR marker_height_override > 0'),
        ('marcadores_symbol_size_override_valid','symbol_size_override IS NULL OR symbol_size_override > 0')
        ) e(name,expression) WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            WHERE c.conrelid='public.marcadores'::pg_catalog.regclass AND c.conname=e.name AND c.contype='c' AND c.convalidated
            AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(c.conbin,c.conrelid),'[[:space:]()]','','g')=
                pg_catalog.regexp_replace(e.expression,'[[:space:]()]','','g'))) THEN
        RAISE EXCEPTION 'B6C_MARKER_LEGACY_CHECK_DRIFT';
    END IF;
    -- Exact final B6b parent columns, including the owned category default.
    IF EXISTS (WITH expected(name,type_name,nn,def) AS (VALUES
        ('game_id','text',true,NULL::text),('id','text',true,NULL),('group_id','text',false,NULL),
        ('name_en','text',true,NULL),('name_pt','text',true,NULL),('icon_source','text',true,'''none''::text'),
        ('icon_ref','text',false,NULL),('color','text',true,'''#777777''::text'),('marker_width','integer',false,NULL),
        ('marker_height','integer',false,NULL),('symbol_size','integer',false,NULL),('sort_order','integer',true,'0'),
        ('is_active','boolean',true,'true'),('created_at','timestamptz',true,'now()'),('updated_at','timestamptz',true,'now()'),('game_uuid','uuid',true,NULL),
        ('category_uuid','uuid',true,'gen_random_uuid()'),('group_uuid','uuid',false,NULL)
        ), actual AS (SELECT a.*,pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS def
            FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
            WHERE a.attrelid='public.marker_categories'::pg_catalog.regclass AND a.attnum>0 AND NOT a.attisdropped)
        SELECT 1 FROM expected e FULL JOIN actual a ON a.attname=e.name WHERE e.name IS NULL OR a.attname IS NULL
            OR a.atttypid<>pg_catalog.to_regtype(e.type_name) OR a.attnotnull IS DISTINCT FROM e.nn
            OR a.def IS DISTINCT FROM e.def OR a.attidentity<>'' OR a.attgenerated<>'') THEN
        RAISE EXCEPTION 'B6C_B6B_CATEGORY_COLUMNS_REQUIRED';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname='marcadores_legacy_uuid_category_fk')
       OR pg_catalog.to_regclass('public.marcadores_legacy_uuid_category_fk') IS NOT NULL
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname IN ('public','private') AND p.proname ~ '^deepmap_resolve_marker.*identity$' AND p.oid<>v_resolver_fn)
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_inherits WHERE inhrelid IN ('public.marcadores'::pg_catalog.regclass,
            'private.marker_editor_audit'::pg_catalog.regclass) OR inhparent IN ('public.marcadores'::pg_catalog.regclass,
            'private.marker_editor_audit'::pg_catalog.regclass))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_rewrite WHERE ev_class IN ('public.marcadores'::pg_catalog.regclass,
            'private.marker_editor_audit'::pg_catalog.regclass)) THEN RAISE EXCEPTION 'B6C_PARTIAL_OR_UNEXPECTED_MARKER_OBJECTS'; END IF;
    -- Baseline keys, including the B5b submission support key. No new index.
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.marcadores','marcadores_pkey','p',ARRAY['id']::text[]),
        ('public.marcadores','marcadores_id_game_identity_unique','u',ARRAY['id','game_id','game_uuid']),
        ('private.marker_editor_audit','marker_editor_audit_pkey','p',ARRAY['marker_id']),
        ('public.marker_categories','marker_categories_pkey','p',ARRAY['game_id','id']),
        ('public.marker_categories','marker_categories_category_uuid_unique','u',ARRAY['category_uuid']),
        ('public.marker_categories','marker_categories_legacy_uuid_identity_unique','u',ARRAY['game_id','id','game_uuid','category_uuid']),
        ('public.map_layers','map_layers_legacy_uuid_identity_unique','u',ARRAY['game_id','id','game_uuid','layer_uuid']),
        ('private.game_legacy_identifiers','game_legacy_identifiers_identifier_game_unique','u',ARRAY['legacy_identifier','game_id'])
        ) e(rel,name,kind,cols) WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid JOIN pg_catalog.pg_class x ON x.oid=i.indexrelid
            JOIN pg_catalog.pg_am am ON am.oid=x.relam
            WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND c.conname=e.name AND c.contype::text=e.kind
            AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred AND i.indrelid=c.conrelid
            AND i.indisunique AND i.indimmediate AND i.indisvalid AND i.indisready AND i.indislive AND am.amname='btree'
            AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnatts=i.indnkeyatts AND i.indnkeyatts=pg_catalog.cardinality(e.cols)
            AND ARRAY(SELECT k FROM pg_catalog.unnest(i.indkey) k)=c.conkey
            AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos)
                JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=e.cols)) THEN
        RAISE EXCEPTION 'B6C_REQUIRED_LEGACY_OR_UUID_SUPPORT_KEY_DRIFT';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_constraint WHERE conrelid='public.marker_categories'::pg_catalog.regclass
            AND contype IN ('p','c','f','u','x'))<>14
       OR (SELECT count(*) FROM pg_catalog.pg_index WHERE indrelid='public.marker_categories'::pg_catalog.regclass)<>3
       OR EXISTS (SELECT 1 FROM (VALUES
        ('marker_categories_id_format',$expr$(id ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'::text)$expr$),
        ('marker_categories_icon_source_check',$expr$(icon_source = ANY (ARRAY['none'::text, 'static'::text, 'r2'::text, 'external'::text]))$expr$),
        ('marker_categories_color_check',$expr$(color ~ '^#[0-9A-Fa-f]{6}$'::text)$expr$),
        ('marker_categories_marker_width_check',$expr$((marker_width IS NULL) OR (marker_width > 0))$expr$),
        ('marker_categories_marker_height_check',$expr$((marker_height IS NULL) OR (marker_height > 0))$expr$),
        ('marker_categories_symbol_size_check',$expr$((symbol_size IS NULL) OR (symbol_size > 0))$expr$),
        ('marker_categories_icon_ref_required',$expr$((icon_source = 'none'::text) OR (NULLIF(btrim(icon_ref), ''::text) IS NOT NULL))$expr$),
        ('marker_categories_group_uuid_pair_check',$expr$(((group_id IS NULL) AND (group_uuid IS NULL)) OR ((group_id IS NOT NULL) AND (group_uuid IS NOT NULL)))$expr$)
        ) e(name,expression) WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            WHERE c.conrelid='public.marker_categories'::pg_catalog.regclass AND c.conname=e.name AND c.contype='c'
            AND c.convalidated AND pg_catalog.pg_get_expr(c.conbin,c.conrelid)=e.expression)) THEN
        RAISE EXCEPTION 'B6C_B6B_CATEGORY_CONSTRAINT_OR_INDEX_SET_DRIFT';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_index WHERE indrelid='public.marcadores'::pg_catalog.regclass)<>4
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class x ON x.oid=i.indexrelid
            WHERE i.indrelid='public.marcadores'::pg_catalog.regclass AND x.relname NOT IN
                ('marcadores_pkey','marcadores_game_slug_unique','marcadores_map_lookup_idx','marcadores_id_game_identity_unique'))
       OR EXISTS (SELECT 1 FROM (VALUES
            ('marcadores_game_slug_unique',true,ARRAY['game_id','slug']::text[]),
            ('marcadores_map_lookup_idx',false,ARRAY['game_id','map_layer','is_published','category_id'])) e(name,uq,cols)
            WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class x ON x.oid=i.indexrelid
                WHERE i.indrelid='public.marcadores'::pg_catalog.regclass AND x.relname=e.name AND i.indisunique=e.uq
                AND i.indisvalid AND i.indisready AND i.indislive AND i.indimmediate AND i.indpred IS NULL AND i.indexprs IS NULL
                AND i.indnatts=i.indnkeyatts AND i.indnkeyatts=pg_catalog.cardinality(e.cols)
                AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(i.indkey) WITH ORDINALITY k(num,pos)
                    JOIN pg_catalog.pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.num ORDER BY k.pos)=e.cols)) THEN
        RAISE EXCEPTION 'B6C_MARKER_BASELINE_INDEX_SET_REQUIRES_REVIEW';
    END IF;
    -- Exact legacy/UUID marker relations and B5b incoming marker support FK.
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.marcadores','marcadores_category_fk','public.marker_categories',ARRAY['game_id','category_id']::text[],ARRAY['game_id','id']::text[],'c','a'),
        ('public.marcadores','marcadores_layer_fk','public.map_layers',ARRAY['game_id','map_layer'],ARRAY['game_id','id'],'c','a'),
        ('public.marcadores','marcadores_legacy_game_uuid_fk','private.game_legacy_identifiers',ARRAY['game_id','game_uuid'],ARRAY['legacy_identifier','game_id'],'a','r'),
        ('public.marcadores','marcadores_legacy_uuid_layer_fk','public.map_layers',ARRAY['game_id','map_layer','game_uuid','layer_uuid'],ARRAY['game_id','id','game_uuid','layer_uuid'],'a','r'),
        ('private.marker_editor_audit','marker_editor_audit_marker_id_fkey','public.marcadores',ARRAY['marker_id'],ARRAY['id'],'a','c'),
        ('public.marker_submissions','marker_submissions_marker_game_uuid_fk','public.marcadores',ARRAY['marker_id','game_id','game_uuid'],ARRAY['id','game_id','game_uuid'],'a','c'),
        ('private.game_legacy_identifiers','game_legacy_identifiers_game_id_fkey','public.games',ARRAY['game_id'],ARRAY['id'],'a','r'),
        ('public.marker_categories','marker_categories_legacy_game_uuid_fk','private.game_legacy_identifiers',ARRAY['game_id','game_uuid'],ARRAY['legacy_identifier','game_id'],'a','r'),
        ('public.marker_categories','marker_categories_group_fk','public.marker_category_groups',ARRAY['game_id','group_id'],ARRAY['game_id','id'],'c','n'),
        ('public.marker_categories','marker_categories_legacy_uuid_group_fk','public.marker_category_groups',ARRAY['game_id','group_id','game_uuid','group_uuid'],ARRAY['game_id','id','game_uuid','group_uuid'],'c','r')
        ) e(rel,name,parent,cols,parent_cols,upd,del) WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND c.conname=e.name AND c.contype='f'
            AND c.confrelid=pg_catalog.to_regclass(e.parent) AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
            AND c.confmatchtype='s' AND c.confupdtype::text=e.upd AND c.confdeltype::text=e.del
            AND pg_catalog.to_jsonb(c)->>'confdelsetcols' IS NULL
            AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos)
                JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=e.cols
            AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num,pos)
                JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)=e.parent_cols)) THEN
        RAISE EXCEPTION 'B6C_BASELINE_MARKER_OR_PARENT_FK_DRIFT';
    END IF;
    -- Audit schema does not require a row or completed metadata for each marker.
    IF EXISTS (WITH expected(name,type_name,nn) AS (VALUES
        ('marker_id','bigint',true),('created_by','uuid',false),('created_at','timestamptz',false),
        ('updated_by','uuid',false),('updated_at','timestamptz',false),('published_by','uuid',false),
        ('published_at','timestamptz',false),('approved_by','uuid',false),('approved_at','timestamptz',false)),
        actual AS (SELECT * FROM pg_catalog.pg_attribute WHERE attrelid='private.marker_editor_audit'::pg_catalog.regclass AND attnum>0 AND NOT attisdropped)
        SELECT 1 FROM expected e FULL JOIN actual a ON a.attname=e.name WHERE e.name IS NULL OR a.attname IS NULL
            OR a.atttypid<>pg_catalog.to_regtype(e.type_name) OR a.attnotnull IS DISTINCT FROM e.nn
            OR a.atthasdef OR a.attidentity<>'' OR a.attgenerated<>'') THEN RAISE EXCEPTION 'B6C_AUDIT_SCHEMA_DRIFT'; END IF;
    -- Both functions must be exactly their final pre-B6c bodies/attributes.
    FOR v_name IN SELECT unnest(ARRAY['deepmap_stamp_marker_audit','deepmap_resolve_marker_identity']) LOOP
        IF (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname IN ('public','private') AND p.proname=v_name)<>1
           OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
            WHERE p.oid=CASE WHEN v_name='deepmap_stamp_marker_audit' THEN v_audit_fn ELSE v_resolver_fn END
            AND p.pronargs=0 AND p.proargtypes=''::pg_catalog.oidvector AND p.proargnames IS NULL
            AND p.proargmodes IS NULL AND p.proallargtypes IS NULL AND p.provariadic=0
            AND p.pronargdefaults=0 AND p.proargdefaults IS NULL AND p.prorettype='trigger'::pg_catalog.regtype
            AND p.prokind='f' AND l.lanname='plpgsql' AND NOT p.proretset
            AND p.prosecdef=(v_name='deepmap_stamp_marker_audit') AND p.proconfig=ARRAY['search_path=""']::text[]
            AND p.provolatile='v' AND p.proparallel='u' AND NOT p.proisstrict AND NOT p.proleakproof
            AND p.procost=100 AND p.prorows=0 AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=
                CASE WHEN v_name='deepmap_stamp_marker_audit' THEN v_audit_old ELSE v_resolver_old END) THEN
            RAISE EXCEPTION 'B6C_FUNCTION_BASELINE_BODY_ATTRIBUTES_OR_OVERLOAD_DRIFT: %',v_name;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
        LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
        WHERE (p.oid=v_resolver_fn AND a.grantee<>p.proowner)
           OR (p.oid=v_audit_fn AND a.grantee<>p.proowner AND (a.grantee=0 OR r.rolname IN ('anon','authenticated')))) THEN
        RAISE EXCEPTION 'B6C_UNEXPECTED_DIRECT_FUNCTION_ACL';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('private.deepmap_resolve_category_identity()')
            AND pg_catalog.replace(prosrc,pg_catalog.chr(13),'')=v_category_body)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('private.deepmap_resolve_category_group_identity()')
            AND pg_catalog.replace(prosrc,pg_catalog.chr(13),'')=v_group_body)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
            AND NOT prosecdef AND prorettype='trigger'::pg_catalog.regtype AND pg_catalog.replace(prosrc,pg_catalog.chr(13),'')=v_touch_body)
       OR (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgrelid='public.marcadores'::pg_catalog.regclass AND NOT tgisinternal)<>3
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgrelid='private.marker_editor_audit'::pg_catalog.regclass AND NOT tgisinternal)
       OR EXISTS (SELECT 1 FROM (VALUES
            ('deepmap_marcadores_identity',23,'private.deepmap_resolve_marker_identity()'),
            ('deepmap_marcadores_touch_updated_at',19,'private.deepmap_touch_updated_at()'),
            ('deepmap_marker_editor_audit',21,'private.deepmap_stamp_marker_audit()')) e(name,bits,fn)
            WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.marcadores'::pg_catalog.regclass
                AND t.tgname=e.name AND t.tgtype=e.bits AND t.tgfoid=pg_catalog.to_regprocedure(e.fn) AND NOT t.tgisinternal
                AND t.tgenabled='O' AND t.tgnargs=0 AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL)) THEN
        RAISE EXCEPTION 'B6C_PARENT_RESOLVER_TOUCH_OR_MARKER_TRIGGER_DRIFT';
    END IF;
    IF EXISTS (SELECT 1 FROM (VALUES ('private.deepmap_resolve_category_identity()'),
            ('private.deepmap_resolve_category_group_identity()')) e(signature)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
            WHERE p.oid=pg_catalog.to_regprocedure(e.signature) AND p.pronargs=0 AND p.prokind='f'
            AND p.prorettype='trigger'::pg_catalog.regtype AND l.lanname='plpgsql' AND NOT p.prosecdef
            AND p.proconfig=ARRAY['search_path=""']::text[] AND p.provolatile='v' AND p.proparallel='u'
            AND NOT p.proisstrict AND NOT p.proleakproof AND NOT p.proretset AND p.procost=100 AND p.prorows=0)) THEN
        RAISE EXCEPTION 'B6C_CATEGORY_GROUP_RESOLVER_ATTRIBUTES_DRIFT';
    END IF;
    -- Unchanged B5b-final writer/review/materialization contracts (CRLF-safe).
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.cancel_marker_submission(bigint)','32db8c8d8de026e6ef2220c752544a06'),
        ('private.deepmap_capture_submission_revision()','d3ff5f69ceb1cd15cf09cf72b26f55ce'),
        ('private.deepmap_autoapprove_moderator_submission()','9c7c5a38258ea603f205fcddb5b48861'),
        ('private.deepmap_notify_admin_submission_received()','c0ec4567cd4efa473e393a5e1e3f6016'),
        ('private.deepmap_notify_submission_review()','a423d83f1c880b7fcb81217d99e8c96d'),
        ('private.deepmap_materialize_submission_content()','09fdd39ed4b0565d21b1f51e6494c4eb'),
        ('private.deepmap_replace_quick_marker_content(bigint,jsonb)','74c611df1824cd9e78d76b98ca6f9920'),
        ('public.review_marker_submission(bigint,text,text)','c2d611f6339f023f3c2b43891f56af29'),
        ('public.review_marker_submission_v2(bigint,text,text,jsonb)','10327cfdf171ec2e3ba17380a909d644')
        ) e(signature,digest) WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
            WHERE p.oid=pg_catalog.to_regprocedure(e.signature) AND p.prosecdef AND p.proconfig=ARRAY['search_path=""']::text[]
            AND pg_catalog.md5(pg_catalog.replace(p.prosrc,pg_catalog.chr(13),''))=e.digest)) THEN
        RAISE EXCEPTION 'B6C_REVIEW_OR_MATERIALIZATION_BASELINE_DRIFT';
    END IF;
    -- Unknown catalog marker-writing functions require review, not an ACL repair.
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname IN ('public','private') AND p.prosrc ~* '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public[.])?marcadores([[:space:]]|[(])'
        AND p.oid NOT IN (pg_catalog.to_regprocedure('public.review_marker_submission(bigint,text,text)'),
            pg_catalog.to_regprocedure('public.review_marker_submission_v2(bigint,text,text,jsonb)'))) THEN
        RAISE EXCEPTION 'B6C_UNREVIEWED_MARKER_WRITER_FUNCTION';
    END IF;
    -- Authenticated marker writes require Admin; the same category predicate
    -- authorizes reads even for inactive categories. Public active-only is insufficient.
    IF EXISTS (SELECT 1 FROM (VALUES ('public.marcadores','marcadores','is_published'),
        ('public.marker_categories','marker_categories','is_active'),('public.map_layers','map_layers','is_active')) e(rel,prefix,flag)
        WHERE (SELECT count(*) FROM pg_catalog.pg_policy WHERE polrelid=pg_catalog.to_regclass(e.rel))<>2
        OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid=pg_catalog.to_regclass(e.rel)
            AND p.polname=e.prefix||'_public_read' AND p.polcmd='r' AND p.polpermissive AND p.polwithcheck IS NULL
            AND pg_catalog.pg_get_expr(p.polqual,p.polrelid)='('||e.flag||' = true)'
            AND ARRAY(SELECT r.rolname::text FROM pg_catalog.unnest(p.polroles) x(oid) JOIN pg_catalog.pg_roles r ON r.oid=x.oid
                ORDER BY r.rolname COLLATE "C")=ARRAY['anon','authenticated']::text[])
        OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid=pg_catalog.to_regclass(e.rel)
            AND p.polname=e.prefix||'_admin_all' AND p.polcmd='*' AND p.polpermissive
            AND p.polroles=ARRAY['authenticated'::pg_catalog.regrole::oid]
            AND pg_catalog.pg_get_expr(p.polqual,p.polrelid)='private.is_deepmap_admin()'
            AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)='private.is_deepmap_admin()')) THEN
        RAISE EXCEPTION 'B6C_AUTHENTICATED_ADMIN_CATEGORY_VISIBILITY_CONTRACT_DRIFT';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_deepmap_role()')
        AND lower(regexp_replace(p.prosrc,'[[:space:]]','','g'))=
            'selectcasewhenprivate.is_deepmap_banned()then''banned''whenprivate.is_deepmap_admin()then''admin''whenprivate.is_deepmap_moderator()then''moderator''else''user''end;')
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='private.game_legacy_identifiers'::pg_catalog.regclass
            AND p.polname='game_legacy_identifiers_admin_read' AND p.polcmd='r' AND p.polpermissive
            AND p.polroles=ARRAY['authenticated'::pg_catalog.regrole::oid]
            AND regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'[[:space:]()]','','g') IN
                ('SELECTpublic.get_deepmap_roleASget_deepmap_role=''admin''::text','SELECTget_deepmap_roleASget_deepmap_role=''admin''::text'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='private.game_legacy_identifiers'::pg_catalog.regclass
            AND NOT polpermissive AND polcmd IN ('r','*')) THEN RAISE EXCEPTION 'B6C_ADMIN_MAPPING_READ_CONTRACT_DRIFT'; END IF;
    IF NOT pg_catalog.has_table_privilege('anon','public.marker_categories','SELECT')
       OR EXISTS (SELECT 1 FROM (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE')) e(privilege)
            WHERE NOT pg_catalog.has_table_privilege('authenticated','public.marker_categories',e.privilege)) THEN
        RAISE EXCEPTION 'B6C_B6B_LEGACY_CATEGORY_GRANTS_REQUIRED';
    END IF;
    -- Effective writers include column grants/inherited grants, service_role if
    -- it is a writer, and the actual DEFINER owners (never an invented owner).
    FOR v_role IN
        SELECT DISTINCT r.* FROM pg_catalog.pg_roles r WHERE r.rolname !~ '^pg_'
        AND (pg_catalog.has_any_column_privilege(r.oid,'public.marcadores','INSERT')
            OR pg_catalog.has_any_column_privilege(r.oid,'public.marcadores','UPDATE')
            OR r.oid IN (SELECT p.proowner FROM pg_catalog.pg_proc p WHERE p.oid IN (
                pg_catalog.to_regprocedure('public.review_marker_submission(bigint,text,text)'),
                pg_catalog.to_regprocedure('public.review_marker_submission_v2(bigint,text,text,jsonb)'))))
    LOOP
        v_rpc_owner := EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.proowner=v_role.oid AND p.oid IN (
            pg_catalog.to_regprocedure('public.review_marker_submission(bigint,text,text)'),
            pg_catalog.to_regprocedure('public.review_marker_submission_v2(bigint,text,text,jsonb)')));
        v_admin_contract := pg_catalog.pg_has_role(v_role.oid,'authenticated','USAGE')
            AND pg_catalog.has_function_privilege(v_role.oid,'private.is_deepmap_admin()','EXECUTE')
            AND pg_catalog.has_function_privilege(v_role.oid,'public.get_deepmap_role()','EXECUTE');
        FOR v_parent IN SELECT c.* FROM pg_catalog.pg_class c WHERE c.oid IN (
            'private.game_legacy_identifiers'::pg_catalog.regclass,'public.map_layers'::pg_catalog.regclass,
            'public.marker_categories'::pg_catalog.regclass)
        LOOP
            IF NOT pg_catalog.has_schema_privilege(v_role.oid,v_parent.relnamespace,'USAGE') THEN
                RAISE EXCEPTION 'B6C_WRITER_PARENT_SCHEMA_USAGE_REQUIRED: role=%, parent=%',v_role.rolname,v_parent.oid::regclass;
            END IF;
            IF NOT pg_catalog.has_table_privilege(v_role.oid,v_parent.oid,'SELECT') THEN
                RAISE EXCEPTION 'B6C_WRITER_PARENT_SELECT_REQUIRED: role=%, parent=%',v_role.rolname,v_parent.oid::regclass;
            END IF;
            IF NOT (v_role.rolsuper OR v_role.rolbypassrls OR (v_role.oid=v_parent.relowner AND NOT v_parent.relforcerowsecurity)
                -- Review can run for moderators whose JWT is not Admin.
                -- DEFINER owners therefore need unconditional full visibility,
                -- exactly as in B4b, rather than an inherited Admin predicate.
                OR (NOT v_rpc_owner AND v_admin_contract)) THEN
                RAISE EXCEPTION 'B6C_WRITER_PARENT_RLS_VISIBILITY_REQUIRED: role=%, parent=%',v_role.rolname,v_parent.oid::regclass;
            END IF;
        END LOOP;
    END LOOP;
    -- All legacy category parents and all B4b game/layer contexts must be exact.
    IF EXISTS (SELECT 1 FROM public.marcadores m WHERE
        (SELECT count(*) FROM public.marker_categories c WHERE c.game_id=m.game_id AND c.id=m.category_id)<>1
        OR (SELECT count(*) FROM public.marker_categories c WHERE c.game_id=m.game_id AND c.id=m.category_id
            AND c.game_uuid=m.game_uuid AND c.category_uuid IS NOT NULL)<>1
        OR (SELECT count(*) FROM private.game_legacy_identifiers i JOIN public.games g ON g.id=i.game_id
            JOIN public.map_layers l ON l.game_id=i.legacy_identifier AND l.game_uuid=i.game_id
            JOIN public.game_maps gm ON gm.id=l.game_map_id AND gm.game_id=l.game_uuid
            WHERE i.legacy_identifier=m.game_id AND i.game_id=m.game_uuid AND l.id=m.map_layer AND l.layer_uuid=m.layer_uuid)<>1) THEN
        RAISE EXCEPTION 'B6C_EXISTING_MARKER_CATEGORY_GAME_LAYER_CONTEXT_INVALID';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid IN (
        'public.marker_submissions'::pg_catalog.regclass,'private.marker_submission_revisions'::pg_catalog.regclass,
        'public.user_notifications'::pg_catalog.regclass,'public.marker_images'::pg_catalog.regclass,
        'public.marker_sections'::pg_catalog.regclass,'public.marker_section_rows'::pg_catalog.regclass)
        AND attnum>0 AND NOT attisdropped AND attname IN ('category_uuid','group_uuid')) THEN
        RAISE EXCEPTION 'B6C_PRE_B7_SCOPE_VIOLATION';
    END IF;
    -- After locks, before the first persistent mutation: now() is transaction
    -- time. Never move a timestamp backwards after waiting for another writer.
    IF EXISTS (SELECT 1 FROM public.marcadores WHERE updated_at>pg_catalog.now()) THEN
        RAISE EXCEPTION 'B6C_MARKER_UPDATED_AT_AFTER_TRANSACTION_TIMESTAMP';
    END IF;
    SELECT count(*) INTO v_rows FROM public.marcadores;
    SELECT pg_catalog.to_jsonb(p) INTO STRICT v_audit_before FROM pg_catalog.pg_proc p WHERE p.oid=v_audit_fn;
    SELECT pg_catalog.to_jsonb(p) INTO STRICT v_resolver_before FROM pg_catalog.pg_proc p WHERE p.oid=v_resolver_fn;
    EXECUTE v_catalog INTO v_before USING v_resolver_fn,v_audit_fn;
    FOREACH v_relation IN ARRAY ARRAY['public.games','public.game_maps','private.game_legacy_identifiers',
        'public.marker_category_groups','public.map_layers','public.marker_categories','public.marcadores','private.marker_editor_audit'] LOOP
        EXECUTE pg_catalog.format('SELECT COALESCE(pg_catalog.jsonb_agg(%s ORDER BY %s),''[]''::jsonb) FROM %s t',
            CASE WHEN v_relation='public.marcadores' THEN 'pg_catalog.to_jsonb(t)-ARRAY[''category_uuid'',''updated_at'']::text[]' ELSE 'pg_catalog.to_jsonb(t)' END,
            CASE WHEN v_relation='public.marcadores' THEN 't.id' ELSE 'pg_catalog.to_jsonb(t)' END,
            pg_catalog.to_regclass(v_relation)) INTO v_data;
        v_data_before:=v_data_before||pg_catalog.jsonb_build_object(v_relation,v_data);
    END LOOP;
    -- Save the complete pre-mutation marker rows too, including old updated_at.
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(m) ORDER BY m.id),'[]'::jsonb)
        INTO v_data FROM public.marcadores m;
    v_data_before:=v_data_before||pg_catalog.jsonb_build_object('marker_full_snapshot',v_data);

    -- Only the two authorized array expansions. The INSERT branch, genuine
    -- difference predicate, legacy no-op/publication/content logic stay exact.
    v_audit_new:=pg_catalog.replace(v_audit_old,
        'ARRAY[''updated_at'',''game_uuid'',''layer_uuid'']::text[]',
        'ARRAY[''updated_at'',''game_uuid'',''layer_uuid'',''category_uuid'']::text[]');
    v_audit_new:=pg_catalog.replace(v_audit_new,
        'ARRAY[''updated_at'',''is_published'',''game_uuid'',''layer_uuid'']::text[]',
        'ARRAY[''updated_at'',''is_published'',''game_uuid'',''layer_uuid'',''category_uuid'']::text[]');
    IF v_audit_new=v_audit_old OR pg_catalog.replace(pg_catalog.replace(v_audit_new,
        'ARRAY[''updated_at'',''game_uuid'',''layer_uuid'',''category_uuid'']::text[]',
        'ARRAY[''updated_at'',''game_uuid'',''layer_uuid'']::text[]'),
        'ARRAY[''updated_at'',''is_published'',''game_uuid'',''layer_uuid'',''category_uuid'']::text[]',
        'ARRAY[''updated_at'',''is_published'',''game_uuid'',''layer_uuid'']::text[]')<>v_audit_old THEN
        RAISE EXCEPTION 'B6C_AUDIT_EXACT_TRANSFORMATION_FAILED';
    END IF;
    -- Preserve the entire B4b body; add declarations and independent category
    -- resolution/validation after the existing game/layer checks, before RETURN.
    v_resolver_new:=pg_catalog.replace(v_resolver_old,'        v_layer_changed boolean := false;',
        $declarations$        v_layer_changed boolean := false;
        v_category_uuid uuid;
        v_category_game_uuid uuid;
        v_category_changed boolean := false;
        v_category_hydrating boolean := false;$declarations$);
    v_resolver_new:=pg_catalog.replace(v_resolver_new,'        RETURN NEW;',
        $category_resolution$        IF TG_OP='UPDATE' THEN
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
        RETURN NEW;$category_resolution$);
    IF v_resolver_new=v_resolver_old THEN RAISE EXCEPTION 'B6C_RESOLVER_TRANSFORMATION_FAILED'; END IF;

    -- Canonicalize after all replacements: multiline literals may contain CRLF.
    v_audit_new := pg_catalog.replace(v_audit_new, pg_catalog.chr(13), '');
    v_resolver_new := pg_catalog.replace(v_resolver_new, pg_catalog.chr(13), '');

    -- First persistent mutation: teach audit the technical key before hydration.
    EXECUTE pg_catalog.format('CREATE OR REPLACE FUNCTION private.deepmap_stamp_marker_audit()
        RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER VOLATILE PARALLEL UNSAFE
        CALLED ON NULL INPUT COST 100 SET search_path = %L AS %L','',v_audit_new);
    ALTER TABLE public.marcadores ADD COLUMN category_uuid uuid;
    EXECUTE pg_catalog.format('CREATE OR REPLACE FUNCTION private.deepmap_resolve_marker_identity()
        RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER VOLATILE PARALLEL UNSAFE
        CALLED ON NULL INPUT COST 100 SET search_path = %L AS %L','',v_resolver_new);
    UPDATE public.marcadores m SET category_uuid=c.category_uuid
        FROM public.marker_categories c WHERE m.category_uuid IS NULL
        AND c.game_id=m.game_id AND c.id=m.category_id AND c.game_uuid=m.game_uuid;
    GET DIAGNOSTICS v_affected=ROW_COUNT;
    IF v_affected<>v_rows THEN RAISE EXCEPTION 'B6C_CATEGORY_FILL_COUNT_MISMATCH'; END IF;
    ALTER TABLE public.marcadores ADD CONSTRAINT marcadores_legacy_uuid_category_fk
        FOREIGN KEY(game_id,category_id,game_uuid,category_uuid)
        REFERENCES public.marker_categories(game_id,id,game_uuid,category_uuid)
        MATCH SIMPLE ON UPDATE CASCADE ON DELETE NO ACTION NOT DEFERRABLE;
    ALTER TABLE public.marcadores ALTER COLUMN category_uuid SET NOT NULL;

    EXECUTE v_catalog INTO v_after USING v_resolver_fn,v_audit_fn;
    IF v_after IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'B6C_UNAPPROVED_CATALOG_CHANGE'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_resolver_fn
            AND pg_catalog.to_jsonb(p)-'prosrc'=v_resolver_before-'prosrc'
            AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=pg_catalog.replace(v_resolver_new,pg_catalog.chr(13),''))
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_audit_fn
            AND pg_catalog.to_jsonb(p)-'prosrc'=v_audit_before-'prosrc'
            AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=pg_catalog.replace(v_audit_new,pg_catalog.chr(13),'')) THEN
        RAISE EXCEPTION 'B6C_FUNCTION_OID_OWNER_ACL_ATTRIBUTES_OR_BODY_CHANGED';
    END IF;
    FOREACH v_relation IN ARRAY ARRAY['public.games','public.game_maps','private.game_legacy_identifiers',
        'public.marker_category_groups','public.map_layers','public.marker_categories','public.marcadores','private.marker_editor_audit'] LOOP
        EXECUTE pg_catalog.format('SELECT COALESCE(pg_catalog.jsonb_agg(%s ORDER BY %s),''[]''::jsonb) FROM %s t',
            CASE WHEN v_relation='public.marcadores' THEN 'pg_catalog.to_jsonb(t)-ARRAY[''category_uuid'',''updated_at'']::text[]' ELSE 'pg_catalog.to_jsonb(t)' END,
            CASE WHEN v_relation='public.marcadores' THEN 't.id' ELSE 'pg_catalog.to_jsonb(t)' END,
            pg_catalog.to_regclass(v_relation)) INTO v_data;
        v_data_after:=v_data_after||pg_catalog.jsonb_build_object(v_relation,v_data);
    END LOOP;
    IF v_data_after IS DISTINCT FROM (v_data_before-'marker_full_snapshot') THEN
        RAISE EXCEPTION 'B6C_MARKER_LEGACY_AUDIT_OR_PARENT_DATA_CHANGED';
    END IF;
    IF (SELECT count(*) FROM public.marcadores)<>v_rows
       OR EXISTS (SELECT 1 FROM public.marcadores WHERE category_uuid IS NULL OR updated_at IS DISTINCT FROM pg_catalog.now())
       OR EXISTS (SELECT 1 FROM public.marcadores m WHERE
            (SELECT count(*) FROM public.marker_categories c WHERE c.game_id=m.game_id AND c.id=m.category_id
                AND c.game_uuid=m.game_uuid AND c.category_uuid=m.category_uuid)<>1
            OR (SELECT count(*) FROM private.game_legacy_identifiers i JOIN public.games g ON g.id=i.game_id
                JOIN public.map_layers l ON l.game_id=i.legacy_identifier AND l.game_uuid=i.game_id
                JOIN public.game_maps gm ON gm.id=l.game_map_id AND gm.game_id=l.game_uuid
                WHERE i.legacy_identifier=m.game_id AND i.game_id=m.game_uuid AND l.id=m.map_layer AND l.layer_uuid=m.layer_uuid)<>1) THEN
        RAISE EXCEPTION 'B6C_FINAL_MARKER_IDENTITY_COUNT_OR_TECHNICAL_TOUCH_INVALID';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_attribute WHERE attrelid='public.marcadores'::pg_catalog.regclass AND attnum>0 AND NOT attisdropped)<>25
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.marcadores'::pg_catalog.regclass
            AND a.attname='category_uuid' AND a.atttypid='uuid'::pg_catalog.regtype AND a.attnotnull AND NOT a.atthasdef
            AND a.attidentity='' AND a.attgenerated='' AND a.attacl IS NULL AND NOT a.attisdropped)
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid='public.marcadores'::pg_catalog.regclass
            AND attnum>0 AND NOT attisdropped AND attname='group_uuid') THEN RAISE EXCEPTION 'B6C_FINAL_MARKER_COLUMN_INVALID'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.marcadores'::pg_catalog.regclass
        AND c.conname='marcadores_legacy_uuid_category_fk' AND c.contype='f' AND c.confrelid='public.marker_categories'::pg_catalog.regclass
        AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred AND c.confmatchtype='s' AND c.confupdtype='c' AND c.confdeltype='a'
        AND pg_catalog.to_jsonb(c)->>'confdelsetcols' IS NULL
        AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos)
            JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=ARRAY['game_id','category_id','game_uuid','category_uuid']::text[]
        AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num,pos)
            JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)=ARRAY['game_id','id','game_uuid','category_uuid']::text[]) THEN
        RAISE EXCEPTION 'B6C_FINAL_CATEGORY_FK_INVALID';
    END IF;
    -- Baseline indexes/user triggers/policies/ACLs/other functions and every
    -- pre-B7 relation column are already proved identical by v_catalog.
    IF (SELECT count(*) FROM pg_catalog.pg_index WHERE indrelid='public.marcadores'::pg_catalog.regclass)<>4
       OR (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgrelid='public.marcadores'::pg_catalog.regclass AND NOT tgisinternal)<>3
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid IN (
            'public.marker_submissions'::pg_catalog.regclass,'private.marker_submission_revisions'::pg_catalog.regclass,
            'public.user_notifications'::pg_catalog.regclass,'public.marker_images'::pg_catalog.regclass,
            'public.marker_sections'::pg_catalog.regclass,'public.marker_section_rows'::pg_catalog.regclass)
            AND attnum>0 AND NOT attisdropped AND attname IN ('category_uuid','group_uuid')) THEN
        RAISE EXCEPTION 'B6C_FINAL_INDEX_TRIGGER_OR_PRE_B7_SCOPE_INVALID';
    END IF;
END;
$bridge$;
COMMIT;
