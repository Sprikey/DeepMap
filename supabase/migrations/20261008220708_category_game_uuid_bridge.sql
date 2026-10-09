-- DeepMap B2b: generic game UUID bridge for legacy categories.
-- Review before manual execution. No fixed game, UUID or category-count baseline.
-- Existing group FK, text keys, RPCs, table grants and policies stay intact.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = pg_catalog;

DO $dependencies$
DECLARE
    v_relation text;
BEGIN
    FOREACH v_relation IN ARRAY ARRAY[
        'public.marker_categories', 'private.game_legacy_identifiers',
        'public.games', 'public.marker_category_groups'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_class AS c
            WHERE c.oid = pg_catalog.to_regclass(v_relation)
              AND c.relkind = 'r' AND c.relrowsecurity
        ) THEN
            RAISE EXCEPTION 'B2B_REQUIRES_ORDINARY_RLS_TABLE: %', v_relation;
        END IF;
    END LOOP;
    FOREACH v_relation IN ARRAY ARRAY[
        'public.marcadores', 'public.map_labels', 'public.marker_submissions',
        'public.user_notifications', 'public.marker_images', 'public.marker_sections',
        'public.marker_section_rows'
    ] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class
            WHERE oid=pg_catalog.to_regclass(v_relation) AND relkind='r') THEN
            RAISE EXCEPTION 'B2B_MISSING_ADJACENT_TABLE: %', v_relation;
        END IF;
    END LOOP;
    IF pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()') IS NULL
       OR pg_catalog.to_regprocedure('public.get_deepmap_role()') IS NULL THEN
        RAISE EXCEPTION 'B2B_REQUIRED_FUNCTION_MISSING';
    END IF;
END;
$dependencies$;

-- Match the parent-first order used by B1. The parent needs this mode for the
-- new FK anyway; it blocks alias writes, but permits ordinary reads.
-- No explicit group lock: the validated legacy FK plus B2a bridge/immutability
-- establish group context. Group checks use statement snapshots; normal group
-- edits need not be blocked. Parent key cascades must acquire the child lock.
LOCK TABLE private.game_legacy_identifiers IN SHARE ROW EXCLUSIVE MODE;
-- Required by ADD COLUMN / NOT NULL. Also serializes all category writers.
LOCK TABLE public.marker_categories IN ACCESS EXCLUSIVE MODE;

DO $preflight$
BEGIN
    IF EXISTS (
        WITH expected(name, type_oid, not_null) AS (
            VALUES
                ('game_id', 'text'::pg_catalog.regtype, true),
                ('id', 'text'::pg_catalog.regtype, true),
                ('group_id', 'text'::pg_catalog.regtype, false),
                ('name_en', 'text'::pg_catalog.regtype, true),
                ('name_pt', 'text'::pg_catalog.regtype, true),
                ('icon_source', 'text'::pg_catalog.regtype, true),
                ('icon_ref', 'text'::pg_catalog.regtype, false),
                ('color', 'text'::pg_catalog.regtype, true),
                ('marker_width', 'integer'::pg_catalog.regtype, false),
                ('marker_height', 'integer'::pg_catalog.regtype, false),
                ('symbol_size', 'integer'::pg_catalog.regtype, false),
                ('sort_order', 'integer'::pg_catalog.regtype, true),
                ('is_active', 'boolean'::pg_catalog.regtype, true),
                ('created_at', 'timestamptz'::pg_catalog.regtype, true),
                ('updated_at', 'timestamptz'::pg_catalog.regtype, true)
        ), actual AS (
            SELECT a.attname::text AS name, a.atttypid, a.attnotnull,
                   a.attgenerated, a.attidentity
            FROM pg_catalog.pg_attribute AS a
            WHERE a.attrelid = 'public.marker_categories'::pg_catalog.regclass
              AND a.attnum > 0 AND NOT a.attisdropped
        )
        SELECT 1 FROM expected AS e FULL JOIN actual AS a USING (name)
        WHERE e.name IS NULL OR a.name IS NULL OR a.atttypid <> e.type_oid
           OR a.attnotnull IS DISTINCT FROM e.not_null OR a.attgenerated <> '' OR a.attidentity <> ''
    ) THEN
        RAISE EXCEPTION 'B2B_UNEXPECTED_CATEGORY_COLUMNS_OR_PARTIAL_STATE';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS c
        WHERE c.conrelid = 'public.marker_categories'::pg_catalog.regclass
          AND c.contype = 'p' AND c.convalidated AND NOT c.condeferrable
          AND ARRAY(
              SELECT a.attname::text
              FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY AS k(attnum, position)
              JOIN pg_catalog.pg_attribute AS a
                ON a.attrelid = c.conrelid AND a.attnum = k.attnum
              ORDER BY k.position
          ) = ARRAY['game_id', 'id']::text[]
    ) THEN
        RAISE EXCEPTION 'B2B_UNEXPECTED_CATEGORY_PRIMARY_KEY';
    END IF;

    IF EXISTS (
        SELECT 1 FROM (VALUES
            ('private.game_legacy_identifiers', 'legacy_identifier', 'text'::pg_catalog.regtype),
            ('private.game_legacy_identifiers', 'game_id', 'uuid'::pg_catalog.regtype),
            ('public.games', 'id', 'uuid'::pg_catalog.regtype)
        ) AS e(relation_name, column_name, type_oid)
        LEFT JOIN pg_catalog.pg_attribute AS a
          ON a.attrelid = pg_catalog.to_regclass(e.relation_name)
         AND a.attname = e.column_name AND a.attnum > 0 AND NOT a.attisdropped
        WHERE a.attname IS NULL OR a.atttypid <> e.type_oid OR NOT a.attnotnull
    ) THEN
        RAISE EXCEPTION 'B2B_UNEXPECTED_MAPPING_OR_GAME_COLUMNS';
    END IF;

    -- Require B1's exact support key; do not recreate or adopt another key.
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS c
        JOIN pg_catalog.pg_index AS i ON i.indexrelid = c.conindid
        WHERE c.conrelid = 'private.game_legacy_identifiers'::pg_catalog.regclass
          AND c.conname = 'game_legacy_identifiers_identifier_game_unique'
          AND c.contype = 'u' AND c.convalidated AND NOT c.condeferrable
          AND i.indisvalid AND i.indisready
          AND ARRAY(
              SELECT a.attname::text
              FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY AS k(attnum, position)
              JOIN pg_catalog.pg_attribute AS a
                ON a.attrelid = c.conrelid AND a.attnum = k.attnum
              ORDER BY k.position
          ) = ARRAY['legacy_identifier', 'game_id']::text[]
    ) THEN
        RAISE EXCEPTION 'B2B_REQUIRES_VALID_B1_MAPPING_SUPPORT_KEY';
    END IF;

    -- The existing mapping FK permanently establishes a valid games parent.
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS c
        WHERE c.conrelid = 'private.game_legacy_identifiers'::pg_catalog.regclass
          AND c.confrelid = 'public.games'::pg_catalog.regclass
          AND c.contype = 'f' AND c.convalidated AND NOT c.condeferrable
          AND c.confdeltype = 'r' AND c.confupdtype = 'a'
          AND c.conkey = ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute
              WHERE attrelid = c.conrelid AND attname = 'game_id' AND NOT attisdropped)]::smallint[]
          AND c.confkey = ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute
              WHERE attrelid = c.confrelid AND attname = 'id' AND NOT attisdropped)]::smallint[]
    ) THEN
        RAISE EXCEPTION 'B2B_REQUIRES_VALID_MAPPING_GAME_FOREIGN_KEY';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS c
        WHERE c.conrelid = 'public.marker_categories'::pg_catalog.regclass
          AND c.conname = 'marker_categories_legacy_game_uuid_fk'
    ) OR EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger AS t
        WHERE t.tgrelid = 'public.marker_categories'::pg_catalog.regclass
          AND t.tgname = 'deepmap_categories_identity'
    ) OR EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc AS p
        JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
        WHERE n.nspname = 'private' AND p.proname = 'deepmap_resolve_category_identity'
    ) THEN
        RAISE EXCEPTION 'B2B_OBJECT_ALREADY_EXISTS_REVIEW_PARTIAL_STATE';
    END IF;

    -- An unknown user trigger could audit the hydration or write other tables.
    -- Abort rather than disable, replace, or run such an unreviewed trigger.
    IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_trigger
        WHERE tgrelid = 'public.marker_categories'::pg_catalog.regclass
          AND NOT tgisinternal) <> 1
       OR NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_trigger AS t
           WHERE t.tgrelid = 'public.marker_categories'::pg_catalog.regclass
             AND t.tgname = 'deepmap_marker_categories_touch_updated_at'
             AND t.tgtype = 19 AND t.tgenabled = 'O' AND NOT t.tgisinternal
             AND t.tgfoid = pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
             AND t.tgnargs = 0 AND t.tgattr = ''::pg_catalog.int2vector AND t.tgqual IS NULL
       ) OR EXISTS (
           SELECT 1 FROM pg_catalog.pg_proc AS p
           WHERE p.oid = pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
             AND (p.prosecdef OR p.prorettype <> 'trigger'::pg_catalog.regtype
                  OR pg_catalog.lower(pg_catalog.regexp_replace(p.prosrc, '[[:space:]]', '', 'g'))
                     <> 'beginnew.updated_at:=now();returnnew;end;')
       ) OR EXISTS (
           SELECT 1 FROM pg_catalog.pg_rewrite
           WHERE ev_class = 'public.marker_categories'::pg_catalog.regclass
       ) OR EXISTS (
           SELECT 1 FROM pg_catalog.pg_inherits
           WHERE inhrelid = 'public.marker_categories'::pg_catalog.regclass
              OR inhparent = 'public.marker_categories'::pg_catalog.regclass
       ) THEN
        RAISE EXCEPTION 'B2B_UNEXPECTED_CATEGORY_TRIGGER_RULE_OR_INHERITANCE';
    END IF;

    -- Exact maintenance visibility is necessary for a generic full-table fill.
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_class AS c
        CROSS JOIN pg_catalog.pg_roles AS r
        WHERE r.rolname = CURRENT_USER AND c.oid IN (
            'public.marker_categories'::pg_catalog.regclass,
            'private.game_legacy_identifiers'::pg_catalog.regclass,
            'public.games'::pg_catalog.regclass,
            'public.marker_category_groups'::pg_catalog.regclass
        ) AND c.relrowsecurity
          AND NOT (r.rolsuper OR r.rolbypassrls
                   OR (c.relowner = r.oid AND NOT c.relforcerowsecurity))
    ) THEN
        RAISE EXCEPTION 'B2B_REQUIRES_FULL_MAINTENANCE_VISIBILITY';
    END IF;

    IF NOT pg_catalog.has_schema_privilege('authenticated', 'private', 'USAGE')
       OR NOT pg_catalog.has_table_privilege('authenticated', 'private.game_legacy_identifiers', 'SELECT')
       OR NOT pg_catalog.has_function_privilege('authenticated', 'public.get_deepmap_role()', 'EXECUTE')
       OR NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_policy AS p
           WHERE p.polrelid = 'private.game_legacy_identifiers'::pg_catalog.regclass
             AND p.polname = 'game_legacy_identifiers_admin_read' AND p.polcmd = 'r'
             AND p.polpermissive
             AND ('authenticated'::pg_catalog.regrole)::oid = ANY(p.polroles)
             AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),
                 '[[:space:]()]','','g') IN (
                 'SELECTpublic.get_deepmap_roleASget_deepmap_role=''admin''::text',
                 'SELECTget_deepmap_roleASget_deepmap_role=''admin''::text'
             )
       ) OR EXISTS (
           SELECT 1 FROM pg_catalog.pg_policy p
           WHERE p.polrelid='private.game_legacy_identifiers'::pg_catalog.regclass
             AND NOT p.polpermissive AND p.polcmd IN ('r','*')
       ) THEN
        RAISE EXCEPTION 'B2B_INVOKER_MAPPING_ACCESS_REQUIRES_REVIEW';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid IN (
            'public.marcadores'::pg_catalog.regclass,'public.map_labels'::pg_catalog.regclass,
            'public.marker_submissions'::pg_catalog.regclass,'public.user_notifications'::pg_catalog.regclass
        ) AND a.attname='game_uuid' AND a.attnum>0 AND NOT a.attisdropped
    ) THEN
        RAISE EXCEPTION 'B2B_UNEXPECTED_ADJACENT_UUID_PHASE_STATE';
    END IF;

    -- Count aliases per DISTINCT legacy game, not per category: any number of
    -- categories may belong to the same game. Check game existence as well.
    IF EXISTS (
        SELECT g.game_id
        FROM (SELECT DISTINCT game_id FROM public.marker_categories) AS g
        LEFT JOIN private.game_legacy_identifiers AS i ON i.legacy_identifier = g.game_id
        LEFT JOIN public.games AS p ON p.id = i.game_id
        GROUP BY g.game_id
        HAVING pg_catalog.count(i.legacy_identifier) <> 1 OR pg_catalog.count(p.id) <> 1
    ) THEN
        RAISE EXCEPTION 'B2B_CATEGORY_GAME_MAPPING_MISSING_AMBIGUOUS_OR_INVALID';
    END IF;


    -- B2a must already be present, complete and validated.
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute
        WHERE attrelid = 'public.marker_category_groups'::pg_catalog.regclass
          AND attname = 'game_uuid' AND atttypid = 'uuid'::pg_catalog.regtype
          AND attnotnull AND NOT atthasdef AND NOT attisdropped
          AND attidentity = '' AND attgenerated = ''
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS c
        WHERE c.conrelid = 'public.marker_category_groups'::pg_catalog.regclass
          AND c.conname = 'marker_category_groups_legacy_game_uuid_fk'
          AND c.contype = 'f' AND c.convalidated AND NOT c.condeferrable
          AND c.confrelid = 'private.game_legacy_identifiers'::pg_catalog.regclass
          AND c.confupdtype = 'a' AND c.confdeltype = 'r'
          AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos)
              JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)
              = ARRAY['game_id','game_uuid']::text[]
          AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num,pos)
              JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)
              = ARRAY['legacy_identifier','game_id']::text[]
    ) THEN
        RAISE EXCEPTION 'B2B_REQUIRES_COMPLETE_B2A_GROUP_BRIDGE';
    END IF;

    -- Preserve the existing category-to-group FK, including the pre-existing
    -- composite SET NULL behavior that can conflict with NOT NULL game_id.
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS c
        WHERE c.conrelid = 'public.marker_categories'::pg_catalog.regclass
          AND c.conname = 'marker_categories_group_fk' AND c.contype = 'f'
          AND c.convalidated AND NOT c.condeferrable
          AND c.confrelid = 'public.marker_category_groups'::pg_catalog.regclass
          AND c.confupdtype = 'c' AND c.confdeltype = 'n' AND c.confmatchtype = 's'
          AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos)
              JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)
              = ARRAY['game_id','group_id']::text[]
          AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num,pos)
              JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)
              = ARRAY['game_id','id']::text[]
    ) THEN
        RAISE EXCEPTION 'B2B_UNEXPECTED_LEGACY_CATEGORY_GROUP_FOREIGN_KEY';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.marker_categories AS c
        WHERE c.group_id IS NOT NULL AND (
            SELECT pg_catalog.count(*) FROM public.marker_category_groups AS g
            JOIN private.game_legacy_identifiers AS i
              ON i.legacy_identifier=g.game_id AND i.game_id=g.game_uuid
            WHERE g.game_id=c.game_id AND g.id=c.group_id
        ) <> 1
    ) THEN
        RAISE EXCEPTION 'B2B_CATEGORY_GROUP_CONTEXT_INVALID';
    END IF;

END;
$preflight$;

ALTER TABLE public.marker_categories ADD COLUMN game_uuid uuid;

-- No UUID index yet: current consumers filter by legacy game_id and the
-- existing PK already has that prefix. Revisit with UUID query consumers.
-- Group membership remains governed by the legacy FK and B2a mapping FK;
-- the normalizer intentionally does not duplicate group lookups.
CREATE FUNCTION private.deepmap_resolve_category_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_game_uuid uuid;
BEGIN
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
    RETURN NEW;
END;
$function$;

-- Alphabetically before deepmap_marker_categories_touch_updated_at; group_id
-- changes are deliberately allowed after hydration (the legacy FK checks them).
CREATE TRIGGER deepmap_categories_identity
BEFORE INSERT OR UPDATE ON public.marker_categories
FOR EACH ROW EXECUTE FUNCTION private.deepmap_resolve_category_identity();

-- Same trigger ACL pattern as B1; no table/schema grants change.
REVOKE ALL ON FUNCTION private.deepmap_resolve_category_identity()
    FROM PUBLIC, anon, authenticated;

DO $function_acl$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'service_role') THEN
        REVOKE ALL ON FUNCTION private.deepmap_resolve_category_identity() FROM service_role;
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc AS p
        CROSS JOIN LATERAL pg_catalog.aclexplode(
            COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
        ) AS a
        WHERE p.oid = pg_catalog.to_regprocedure('private.deepmap_resolve_category_identity()')
          AND a.privilege_type = 'EXECUTE' AND a.grantee <> p.proowner
    ) THEN
        RAISE EXCEPTION 'B2B_UNEXPECTED_DIRECT_FUNCTION_GRANTS';
    END IF;
END;
$function_acl$;

DO $bridge$
DECLARE
    v_rows_before bigint;
    v_needs_fill bigint;
    v_affected bigint;
    v_legacy_before jsonb;
    v_group_columns_before jsonb;
    v_group_constraints_before jsonb;
    v_pk_oid oid;
    v_touch_oid oid;
    v_group_fk_before jsonb;
    v_adjacent_columns_before jsonb;
    v_legacy_columns_before jsonb;
    v_legacy_constraints_before jsonb;
BEGIN
    SELECT pg_catalog.count(*),
           COALESCE(pg_catalog.jsonb_agg(
               pg_catalog.to_jsonb(g) - 'game_uuid' - 'updated_at'
               ORDER BY g.game_id, g.id
           ), '[]'::jsonb)
    INTO v_rows_before, v_legacy_before
    FROM public.marker_categories AS g;

    SELECT c.oid INTO STRICT v_pk_oid FROM pg_catalog.pg_constraint AS c
    WHERE c.conrelid = 'public.marker_categories'::pg_catalog.regclass AND c.contype = 'p';
    SELECT t.oid INTO STRICT v_touch_oid FROM pg_catalog.pg_trigger AS t
    WHERE t.tgrelid = 'public.marker_categories'::pg_catalog.regclass
      AND t.tgname = 'deepmap_marker_categories_touch_updated_at';

    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'number', a.attnum, 'name', a.attname, 'type', a.atttypid,
        'typmod', a.atttypmod, 'not_null', a.attnotnull,
        'identity', a.attidentity, 'generated', a.attgenerated,
        'collation', a.attcollation,
        'default', (SELECT pg_catalog.pg_get_expr(d.adbin, d.adrelid)
                    FROM pg_catalog.pg_attrdef AS d
                    WHERE d.adrelid = a.attrelid AND d.adnum = a.attnum)
    ) ORDER BY a.attnum), '[]'::jsonb)
    INTO v_group_columns_before FROM pg_catalog.pg_attribute AS a
    WHERE a.attrelid = 'public.marker_category_groups'::pg_catalog.regclass
      AND a.attnum > 0 AND NOT a.attisdropped;
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid), '[]'::jsonb)
    INTO v_group_constraints_before FROM pg_catalog.pg_constraint AS c
    WHERE c.conrelid = 'public.marker_category_groups'::pg_catalog.regclass;

    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid),'[]'::jsonb)
    INTO v_legacy_constraints_before FROM pg_catalog.pg_constraint c
    WHERE c.conrelid='public.marker_categories'::pg_catalog.regclass;

    SELECT pg_catalog.to_jsonb(c) INTO STRICT v_group_fk_before
    FROM pg_catalog.pg_constraint c
    WHERE c.conrelid='public.marker_categories'::pg_catalog.regclass
      AND c.conname='marker_categories_group_fk';

    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attnum),'[]'::jsonb)
    INTO v_legacy_columns_before FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.marker_categories'::pg_catalog.regclass
      AND a.attnum>0 AND NOT a.attisdropped AND a.attname<>'game_uuid';

    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attrelid,a.attnum),'[]'::jsonb)
    INTO v_adjacent_columns_before FROM pg_catalog.pg_attribute a
    WHERE a.attrelid IN (
        'public.marcadores'::pg_catalog.regclass,'public.map_labels'::pg_catalog.regclass,
        'public.marker_submissions'::pg_catalog.regclass,'public.user_notifications'::pg_catalog.regclass,
        'public.marker_images'::pg_catalog.regclass,'public.marker_sections'::pg_catalog.regclass,
        'public.marker_section_rows'::pg_catalog.regclass
    ) AND a.attnum>0 AND NOT a.attisdropped;

    -- Do not adopt any partially hydrated state, even one that looks correct.
    IF EXISTS (SELECT 1 FROM public.marker_categories WHERE game_uuid IS NOT NULL)
       OR EXISTS (
           SELECT g.game_id
           FROM (SELECT DISTINCT game_id FROM public.marker_categories) AS g
           LEFT JOIN private.game_legacy_identifiers AS i ON i.legacy_identifier = g.game_id
           LEFT JOIN public.games AS p ON p.id = i.game_id
           GROUP BY g.game_id
           HAVING pg_catalog.count(i.legacy_identifier) <> 1 OR pg_catalog.count(p.id) <> 1
       ) THEN
        RAISE EXCEPTION 'B2B_FILL_PRECONDITIONS_FAILED';
    END IF;

    SELECT pg_catalog.count(*) INTO v_needs_fill
    FROM public.marker_categories WHERE game_uuid IS NULL;

    UPDATE public.marker_categories AS g
    SET game_uuid = i.game_id
    FROM private.game_legacy_identifiers AS i
    WHERE i.legacy_identifier = g.game_id AND g.game_uuid IS NULL;

    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected <> v_needs_fill OR v_needs_fill <> v_rows_before
       OR EXISTS (
           SELECT 1 FROM public.marker_categories AS g
           WHERE g.game_uuid IS NULL OR NOT EXISTS (
               SELECT 1 FROM private.game_legacy_identifiers AS i
               WHERE i.legacy_identifier = g.game_id AND i.game_id = g.game_uuid
           )
       ) THEN
        RAISE EXCEPTION 'B2B_FILL_COUNT_OR_COVERAGE_MISMATCH';
    END IF;

    ALTER TABLE public.marker_categories
        ADD CONSTRAINT marker_categories_legacy_game_uuid_fk
        FOREIGN KEY (game_id, game_uuid)
        REFERENCES private.game_legacy_identifiers (legacy_identifier, game_id)
        ON UPDATE NO ACTION ON DELETE RESTRICT NOT DEFERRABLE;
    ALTER TABLE public.marker_categories ALTER COLUMN game_uuid SET NOT NULL;

    -- Same rows, text identities and all legacy values except technical updated_at.
    IF (SELECT pg_catalog.count(*) FROM public.marker_categories) <> v_rows_before
       OR (SELECT COALESCE(pg_catalog.jsonb_agg(
                pg_catalog.to_jsonb(g) - 'game_uuid' - 'updated_at' ORDER BY g.game_id, g.id
            ), '[]'::jsonb) FROM public.marker_categories AS g) IS DISTINCT FROM v_legacy_before
       OR NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_constraint AS c
           WHERE c.oid = v_pk_oid AND c.conrelid = 'public.marker_categories'::pg_catalog.regclass
             AND c.contype = 'p' AND c.convalidated
             AND ARRAY(SELECT a.attname::text
                       FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY AS k(attnum, position)
                       JOIN pg_catalog.pg_attribute AS a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
                       ORDER BY k.position) = ARRAY['game_id', 'id']::text[]
       ) OR (SELECT pg_catalog.count(*) FROM pg_catalog.pg_attribute
             WHERE attrelid = 'public.marker_categories'::pg_catalog.regclass
               AND attname IN ('game_id', 'id') AND atttypid = 'text'::pg_catalog.regtype
               AND attnotnull AND NOT attisdropped) <> 2
       OR NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_attribute
           WHERE attrelid = 'public.marker_categories'::pg_catalog.regclass
             AND attname = 'game_uuid' AND atttypid = 'uuid'::pg_catalog.regtype
             AND attnotnull AND NOT atthasdef AND NOT attisdropped
       ) OR NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_constraint
           WHERE conrelid = 'public.marker_categories'::pg_catalog.regclass
             AND conname = 'marker_categories_legacy_game_uuid_fk'
             AND contype = 'f' AND convalidated AND NOT condeferrable
             AND confupdtype = 'a' AND confdeltype = 'r'
       ) THEN
        RAISE EXCEPTION 'B2B_FINAL_CATEGORY_INVARIANTS_FAILED';
    END IF;

    IF (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'number', a.attnum, 'name', a.attname, 'type', a.atttypid,
        'typmod', a.atttypmod, 'not_null', a.attnotnull,
        'identity', a.attidentity, 'generated', a.attgenerated,
        'collation', a.attcollation,
        'default', (SELECT pg_catalog.pg_get_expr(d.adbin, d.adrelid)
                    FROM pg_catalog.pg_attrdef d WHERE d.adrelid=a.attrelid AND d.adnum=a.attnum)
    ) ORDER BY a.attnum),'[]'::jsonb)
        FROM pg_catalog.pg_attribute a
        WHERE a.attrelid='public.marker_category_groups'::pg_catalog.regclass
          AND a.attnum>0 AND NOT a.attisdropped) IS DISTINCT FROM v_group_columns_before
       OR (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid),'[]'::jsonb)
           FROM pg_catalog.pg_constraint c
           WHERE c.conrelid='public.marker_category_groups'::pg_catalog.regclass)
          IS DISTINCT FROM v_group_constraints_before THEN
        RAISE EXCEPTION 'B2B_GROUP_SCHEMA_CHANGED';
    END IF;

    IF (SELECT pg_catalog.to_jsonb(c) FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.marker_categories'::pg_catalog.regclass
          AND c.conname='marker_categories_group_fk') IS DISTINCT FROM v_group_fk_before
       OR (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid),'[]'::jsonb)
           FROM pg_catalog.pg_constraint c
           WHERE c.conrelid='public.marker_categories'::pg_catalog.regclass
             AND c.conname<>'marker_categories_legacy_game_uuid_fk')
          IS DISTINCT FROM v_legacy_constraints_before
       OR (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attnum),'[]'::jsonb)
           FROM pg_catalog.pg_attribute a
           WHERE a.attrelid='public.marker_categories'::pg_catalog.regclass
             AND a.attnum>0 AND NOT a.attisdropped AND a.attname<>'game_uuid')
          IS DISTINCT FROM v_legacy_columns_before
       OR (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attrelid,a.attnum),'[]'::jsonb)
           FROM pg_catalog.pg_attribute a WHERE a.attrelid IN (
               'public.marcadores'::pg_catalog.regclass,'public.map_labels'::pg_catalog.regclass,
               'public.marker_submissions'::pg_catalog.regclass,'public.user_notifications'::pg_catalog.regclass,
               'public.marker_images'::pg_catalog.regclass,'public.marker_sections'::pg_catalog.regclass,
               'public.marker_section_rows'::pg_catalog.regclass
           ) AND a.attnum>0 AND NOT a.attisdropped) IS DISTINCT FROM v_adjacent_columns_before
       OR EXISTS (
           SELECT 1 FROM public.marker_categories c WHERE c.group_id IS NOT NULL AND (
               SELECT pg_catalog.count(*) FROM public.marker_category_groups g
               JOIN private.game_legacy_identifiers i
                 ON i.legacy_identifier=g.game_id AND i.game_id=g.game_uuid
               WHERE g.game_id=c.game_id AND g.id=c.group_id AND g.game_uuid=c.game_uuid
           )<>1
       ) THEN
        RAISE EXCEPTION 'B2B_LEGACY_COLUMNS_ADJACENT_SCHEMA_OR_GROUP_CONTEXT_CHANGED';
    END IF;


    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger
        WHERE oid = v_touch_oid AND tgname = 'deepmap_marker_categories_touch_updated_at'
          AND tgfoid = pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
          AND tgtype = 19 AND tgenabled = 'O'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger
        WHERE tgrelid = 'public.marker_categories'::pg_catalog.regclass
          AND tgname = 'deepmap_categories_identity' AND tgtype = 23 AND tgenabled = 'O'
          AND tgfoid = pg_catalog.to_regprocedure('private.deepmap_resolve_category_identity()')
    ) THEN
        RAISE EXCEPTION 'B2B_FINAL_TRIGGER_INVARIANTS_FAILED';
    END IF;
END;
$bridge$;

COMMIT;
