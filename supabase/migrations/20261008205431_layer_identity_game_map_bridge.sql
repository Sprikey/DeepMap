-- DeepMap Phase B1: parallel layer identity and conceptual-map ownership.
-- Review before manual execution. No legacy keys, children, RPCs or policies change.
-- Intentionally NOT rerunnable: unexpected/partially applied schemas must fail.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = pg_catalog;

-- Check existence before LOCK TABLE so missing dependencies get a useful error.
DO $dependencies$
DECLARE
    v_relation text;
BEGIN
    FOREACH v_relation IN ARRAY ARRAY[
        'public.map_layers', 'private.game_legacy_identifiers',
        'public.games', 'public.game_maps'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_class AS c
            WHERE c.oid = pg_catalog.to_regclass(v_relation)
              AND c.relkind = 'r' AND c.relrowsecurity
        ) THEN
            RAISE EXCEPTION 'B1_REQUIRES_ORDINARY_RLS_TABLE: %', v_relation;
        END IF;
    END LOOP;

    IF pg_catalog.to_regprocedure('pg_catalog.gen_random_uuid()') IS NULL
       OR pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()') IS NULL
       OR pg_catalog.to_regprocedure('public.get_deepmap_role()') IS NULL THEN
        RAISE EXCEPTION 'B1_REQUIRED_FUNCTION_MISSING';
    END IF;
END;
$dependencies$;

-- All three tables need ACCESS EXCLUSIVE for their DDL below anyway.
-- Acquire it once, in a fixed order, before inspecting data. This also prevents
-- concurrent map/alias inserts (a row lock alone would not prevent new maps).
-- Ordinary SELECTs on these tables wait until COMMIT; lock_timeout bounds waits
-- while acquiring locks, not the whole transaction's execution time.
LOCK TABLE private.game_legacy_identifiers, public.game_maps, public.map_layers
    IN ACCESS EXCLUSIVE MODE;

DO $preflight$
DECLARE
    v_game_uuid uuid;
    v_map_uuid uuid;
    v_game_name text;
    v_game_status text;
BEGIN
    -- Exact legacy column/type/nullability baseline; no hidden B1 shadow columns
    -- or unknown extensions are silently adopted.
    IF EXISTS (
        WITH expected(name, type_oid, required) AS (
            VALUES
                ('game_id', 'text'::pg_catalog.regtype, true),
                ('id', 'text'::pg_catalog.regtype, true),
                ('name_en', 'text'::pg_catalog.regtype, true),
                ('name_pt', 'text'::pg_catalog.regtype, true),
                ('image_source', 'text'::pg_catalog.regtype, true),
                ('image_ref', 'text'::pg_catalog.regtype, false),
                ('width', 'integer'::pg_catalog.regtype, true),
                ('height', 'integer'::pg_catalog.regtype, true),
                ('sort_order', 'integer'::pg_catalog.regtype, true),
                ('is_active', 'boolean'::pg_catalog.regtype, true),
                ('created_at', 'timestamp with time zone'::pg_catalog.regtype, true),
                ('updated_at', 'timestamp with time zone'::pg_catalog.regtype, true)
        ), actual AS (
            SELECT a.attname::text AS name, a.atttypid, a.attnotnull,
                   a.attgenerated, a.attidentity
            FROM pg_catalog.pg_attribute AS a
            WHERE a.attrelid = 'public.map_layers'::pg_catalog.regclass
              AND a.attnum > 0 AND NOT a.attisdropped
        )
        SELECT 1
        FROM expected AS e FULL JOIN actual AS a USING (name)
        WHERE e.name IS NULL OR a.name IS NULL
           OR a.atttypid <> e.type_oid OR a.attnotnull <> e.required
           OR a.attgenerated <> '' OR a.attidentity <> ''
    ) THEN
        RAISE EXCEPTION 'B1_UNEXPECTED_MAP_LAYERS_COLUMNS';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS c
        WHERE c.conrelid = 'public.map_layers'::pg_catalog.regclass
          AND c.contype = 'p' AND c.convalidated AND NOT c.condeferrable
          AND ARRAY(
              SELECT a.attname::text
              FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY AS k(attnum, position)
              JOIN pg_catalog.pg_attribute AS a
                ON a.attrelid = c.conrelid AND a.attnum = k.attnum
              ORDER BY k.position
          ) = ARRAY['game_id', 'id']::text[]
    ) THEN
        RAISE EXCEPTION 'B1_UNEXPECTED_MAP_LAYERS_PRIMARY_KEY';
    END IF;

    -- Essential parent columns and their types are required, not recreated.
    IF EXISTS (
        SELECT 1
        FROM (VALUES
            ('public.games', 'id', 'uuid'::pg_catalog.regtype),
            ('public.games', 'name', 'text'::pg_catalog.regtype),
            ('public.games', 'status', 'text'::pg_catalog.regtype),
            ('public.game_maps', 'id', 'uuid'::pg_catalog.regtype),
            ('public.game_maps', 'game_id', 'uuid'::pg_catalog.regtype),
            ('public.game_maps', 'slug', 'text'::pg_catalog.regtype),
            ('public.game_maps', 'name', 'text'::pg_catalog.regtype),
            ('public.game_maps', 'status', 'text'::pg_catalog.regtype),
            ('public.game_maps', 'is_default', 'boolean'::pg_catalog.regtype),
            ('private.game_legacy_identifiers', 'legacy_identifier', 'text'::pg_catalog.regtype),
            ('private.game_legacy_identifiers', 'game_id', 'uuid'::pg_catalog.regtype)
        ) AS e(relation_name, column_name, type_oid)
        LEFT JOIN pg_catalog.pg_attribute AS a
          ON a.attrelid = pg_catalog.to_regclass(e.relation_name)
         AND a.attname = e.column_name AND a.attnum > 0 AND NOT a.attisdropped
        WHERE a.attname IS NULL OR a.atttypid <> e.type_oid OR NOT a.attnotnull
    ) THEN
        RAISE EXCEPTION 'B1_UNEXPECTED_FOUNDATION_COLUMNS';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS c
        WHERE c.conrelid IN (
            'private.game_legacy_identifiers'::pg_catalog.regclass,
            'public.game_maps'::pg_catalog.regclass,
            'public.map_layers'::pg_catalog.regclass
        ) AND c.conname IN (
            'game_legacy_identifiers_identifier_game_unique',
            'game_maps_id_game_unique', 'map_layers_layer_uuid_unique',
            'map_layers_legacy_game_uuid_fk', 'map_layers_game_map_game_fk'
        )
    ) OR pg_catalog.to_regclass('private.game_legacy_identifiers_identifier_game_unique') IS NOT NULL
      OR pg_catalog.to_regclass('public.game_maps_id_game_unique') IS NOT NULL
      OR pg_catalog.to_regclass('public.map_layers_layer_uuid_unique') IS NOT NULL
      OR pg_catalog.to_regclass('public.map_layers_game_map_game_idx') IS NOT NULL
      OR EXISTS (
          SELECT 1 FROM pg_catalog.pg_proc AS p
          JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
          WHERE n.nspname = 'private' AND p.proname = 'deepmap_resolve_layer_identity'
      ) OR EXISTS (
          SELECT 1 FROM pg_catalog.pg_trigger AS t
          WHERE t.tgrelid = 'public.map_layers'::pg_catalog.regclass
            AND t.tgname = 'deepmap_map_layers_identity'
      ) THEN
        RAISE EXCEPTION 'B1_OBJECT_ALREADY_EXISTS_REVIEW_PARTIAL_STATE';
    END IF;

    -- Only the known legacy user trigger may run during the backfill.
    IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_trigger AS t
        WHERE t.tgrelid = 'public.map_layers'::pg_catalog.regclass
          AND NOT t.tgisinternal) <> 1
       OR NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_trigger AS t
           WHERE t.tgrelid = 'public.map_layers'::pg_catalog.regclass
             AND t.tgname = 'deepmap_map_layers_touch_updated_at'
             AND NOT t.tgisinternal AND t.tgenabled = 'O'
             AND t.tgtype = 19 -- ROW | BEFORE | UPDATE
             AND t.tgfoid = pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
             AND t.tgnargs = 0 AND t.tgattr = ''::pg_catalog.int2vector
             AND t.tgqual IS NULL
       ) OR EXISTS (
           SELECT 1 FROM pg_catalog.pg_proc AS p
           WHERE p.oid = pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
             AND (p.prosecdef OR p.prorettype <> 'trigger'::pg_catalog.regtype
                  OR pg_catalog.lower(pg_catalog.regexp_replace(
                      p.prosrc, '[[:space:]]', '', 'g'
                  )) <> 'beginnew.updated_at:=now();returnnew;end;')
       ) THEN
        RAISE EXCEPTION 'B1_UNEXPECTED_MAP_LAYERS_TRIGGER_CONFIGURATION';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_rewrite AS r
        WHERE r.ev_class = 'public.map_layers'::pg_catalog.regclass
    ) OR EXISTS (
        SELECT 1 FROM pg_catalog.pg_inherits AS i
        WHERE i.inhrelid = 'public.map_layers'::pg_catalog.regclass
           OR i.inhparent = 'public.map_layers'::pg_catalog.regclass
    ) THEN
        RAISE EXCEPTION 'B1_UNEXPECTED_LAYER_RULES_OR_INHERITANCE';
    END IF;

    -- Table/namespace privileges are necessary for an invoker trigger.
    -- Existing RLS still decides whether this particular caller is an Admin.
    IF NOT pg_catalog.has_schema_privilege('authenticated', 'private', 'USAGE')
       OR NOT pg_catalog.has_table_privilege('authenticated', 'private.game_legacy_identifiers', 'SELECT')
       OR NOT pg_catalog.has_table_privilege('authenticated', 'public.game_maps', 'SELECT')
       OR NOT pg_catalog.has_function_privilege('authenticated', 'public.get_deepmap_role()', 'EXECUTE')
       OR NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_policy AS p
           WHERE p.polrelid = 'private.game_legacy_identifiers'::pg_catalog.regclass
             AND p.polname = 'game_legacy_identifiers_admin_read'
             AND p.polcmd = 'r' AND p.polpermissive
             AND ('authenticated'::pg_catalog.regrole)::oid = ANY(p.polroles)
       ) OR NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_policy AS p
           WHERE p.polrelid = 'public.game_maps'::pg_catalog.regclass
             AND p.polname = 'game_maps_admin_all'
             AND p.polcmd = '*' AND p.polpermissive
             AND ('authenticated'::pg_catalog.regrole)::oid = ANY(p.polroles)
       ) THEN
        RAISE EXCEPTION 'B1_INVOKER_DEPENDENCIES_REQUIRE_REVIEW';
    END IF;

    BEGIN
        -- SHARE row lock protects this game's identity/status during resolution;
        -- ordinary public reads of games are not blocked.
        SELECT g.id, g.name, g.status
        INTO STRICT v_game_uuid, v_game_name, v_game_status
        FROM private.game_legacy_identifiers AS i
        JOIN public.games AS g ON g.id = i.game_id
        WHERE i.legacy_identifier = 'elden-ring'
        FOR SHARE OF g;
    EXCEPTION
        WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B1_ELDEN_RING_MAPPING_NOT_EXACTLY_ONE_VALID_GAME';
    END;

    IF (SELECT pg_catalog.count(*) FROM private.game_legacy_identifiers AS i
        WHERE i.legacy_identifier = 'elden-ring') <> 1
       OR v_game_name <> 'Elden Ring' OR v_game_status <> 'published' THEN
        RAISE EXCEPTION 'B1_UNEXPECTED_ELDEN_RING_GAME';
    END IF;

    BEGIN
        SELECT m.id INTO STRICT v_map_uuid
        FROM public.game_maps AS m
        WHERE m.game_id = v_game_uuid;
    EXCEPTION
        WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B1_ELDEN_RING_REQUIRES_EXACTLY_ONE_CONCEPTUAL_MAP';
    END;

    IF NOT EXISTS (
        SELECT 1 FROM public.game_maps AS m
        WHERE m.id = v_map_uuid AND m.game_id = v_game_uuid
          AND m.slug = 'world' AND m.is_default
          AND m.name = 'World Map' AND m.status = 'published'
    ) THEN
        RAISE EXCEPTION 'B1_WORLD_AND_DEFAULT_MUST_BE_THE_SAME_PUBLISHED_MAP';
    END IF;

    IF (SELECT pg_catalog.count(*) FROM public.map_layers) <> 3
       OR EXISTS (
           SELECT 1 FROM public.map_layers AS l
           WHERE l.game_id <> 'elden-ring' OR l.id NOT IN ('surface', 'underground', 'dlc')
       ) OR EXISTS (
           SELECT 1 FROM (VALUES ('surface'), ('underground'), ('dlc')) AS expected(id)
           WHERE (SELECT pg_catalog.count(*) FROM public.map_layers AS l
                  WHERE l.game_id = 'elden-ring' AND l.id = expected.id) <> 1
       ) THEN
        RAISE EXCEPTION 'B1_UNEXPECTED_LEGACY_LAYER_SET_REVIEW_REQUIRED';
    END IF;
END;
$preflight$;

ALTER TABLE private.game_legacy_identifiers
    ADD CONSTRAINT game_legacy_identifiers_identifier_game_unique
    UNIQUE (legacy_identifier, game_id);

ALTER TABLE public.game_maps
    ADD CONSTRAINT game_maps_id_game_unique UNIQUE (id, game_id);

-- No volatile default at ADD COLUMN time; do not rewrite legacy columns.
ALTER TABLE public.map_layers
    ADD COLUMN layer_uuid uuid,
    ADD COLUMN game_map_id uuid,
    ADD COLUMN game_uuid uuid;

CREATE FUNCTION private.deepmap_resolve_layer_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_game_uuid uuid;
    v_map_game_uuid uuid;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.layer_uuid IS NULL AND OLD.game_uuid IS NULL AND OLD.game_map_id IS NULL THEN
            -- The only hydration exception: a wholly unassigned old row, with
            -- every legacy field unchanged. Final NOT NULL makes this state
            -- impossible after the migration. The touch trigger runs later.
            IF (pg_catalog.to_jsonb(NEW) - ARRAY['layer_uuid', 'game_uuid', 'game_map_id']::text[])
               IS DISTINCT FROM
               (pg_catalog.to_jsonb(OLD) - ARRAY['layer_uuid', 'game_uuid', 'game_map_id']::text[]) THEN
                RAISE EXCEPTION 'B1_HYDRATION_MUST_PRESERVE_LEGACY_FIELDS';
            END IF;
        ELSIF OLD.layer_uuid IS NULL OR OLD.game_uuid IS NULL OR OLD.game_map_id IS NULL THEN
            RAISE EXCEPTION 'B1_PARTIAL_LAYER_IDENTITY_REQUIRES_REVIEW';
        ELSE
            IF NEW.layer_uuid IS DISTINCT FROM OLD.layer_uuid THEN
                RAISE EXCEPTION 'B1_LAYER_UUID_IS_IMMUTABLE';
            END IF;
            IF NEW.game_id IS DISTINCT FROM OLD.game_id
               OR NEW.game_uuid IS DISTINCT FROM OLD.game_uuid THEN
                RAISE EXCEPTION 'B1_LAYER_GAME_REASSIGNMENT_NOT_SUPPORTED';
            END IF;
            IF NEW.game_map_id IS DISTINCT FROM OLD.game_map_id THEN
                RAISE EXCEPTION 'B1_LAYER_MAP_REASSIGNMENT_NOT_SUPPORTED';
            END IF;
            -- NEW.id may change under the existing legacy key/FK rules.
        END IF;
    ELSIF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'B1_UNSUPPORTED_LAYER_TRIGGER_EVENT';
    END IF;

    BEGIN
        SELECT i.game_id INTO STRICT v_game_uuid
        FROM private.game_legacy_identifiers AS i
        WHERE i.legacy_identifier = NEW.game_id;
    EXCEPTION
        WHEN no_data_found OR too_many_rows THEN
            RAISE EXCEPTION 'B1_LAYER_GAME_MAPPING_NOT_EXACTLY_ONE_VISIBLE_ROW';
    END;

    IF NEW.game_uuid IS NULL THEN
        NEW.game_uuid := v_game_uuid;
    ELSIF NEW.game_uuid IS DISTINCT FROM v_game_uuid THEN
        RAISE EXCEPTION 'B1_LAYER_LEGACY_GAME_UUID_MISMATCH';
    END IF;

    IF NEW.layer_uuid IS NULL THEN
        NEW.layer_uuid := pg_catalog.gen_random_uuid();
    END IF;
    -- Supplied UUIDs are allowed on INSERT; the UNIQUE constraint rejects reuse.

    IF NEW.game_map_id IS NULL THEN
        BEGIN
            SELECT m.id INTO STRICT NEW.game_map_id
            FROM public.game_maps AS m
            WHERE m.game_id = v_game_uuid;
        EXCEPTION
            WHEN no_data_found OR too_many_rows THEN
                RAISE EXCEPTION 'B1_LAYER_MAP_MUST_BE_EXPLICIT_UNLESS_EXACTLY_ONE_VISIBLE_MAP';
        END;
    ELSE
        BEGIN
            SELECT m.game_id INTO STRICT v_map_game_uuid
            FROM public.game_maps AS m
            WHERE m.id = NEW.game_map_id;
        EXCEPTION
            WHEN no_data_found OR too_many_rows THEN
                RAISE EXCEPTION 'B1_LAYER_MAP_NOT_EXACTLY_ONE_VISIBLE_ROW';
        END;
        IF v_map_game_uuid IS DISTINCT FROM v_game_uuid THEN
            RAISE EXCEPTION 'B1_LAYER_MAP_GAME_UUID_MISMATCH';
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

CREATE TRIGGER deepmap_map_layers_identity
BEFORE INSERT OR UPDATE ON public.map_layers
FOR EACH ROW EXECUTE FUNCTION private.deepmap_resolve_layer_identity();

-- PostgreSQL checks function EXECUTE when creating the trigger, not on each
-- firing. Invocation still uses the writer's table privileges/RLS (INVOKER).
-- Follow the existing touch-trigger pattern; do not expose a new callable API.
REVOKE ALL ON FUNCTION private.deepmap_resolve_layer_identity()
    FROM PUBLIC, anon, authenticated;

DO $function_acl$
BEGIN
    -- Supabase default privileges may also grant service_role EXECUTE. It does
    -- not need direct invocation either. Do not require that optional role.
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'service_role') THEN
        REVOKE ALL ON FUNCTION private.deepmap_resolve_layer_identity() FROM service_role;
    END IF;
    -- Unknown custom default grants are a review condition, not silently kept
    -- or removed from unrelated roles. The owner retains implicit control.
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc AS p
        CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) AS a
        WHERE p.oid = pg_catalog.to_regprocedure('private.deepmap_resolve_layer_identity()')
          AND a.privilege_type = 'EXECUTE' AND a.grantee <> p.proowner
    ) THEN
        RAISE EXCEPTION 'B1_UNEXPECTED_DIRECT_FUNCTION_GRANTS';
    END IF;
END;
$function_acl$;

DO $backfill$
DECLARE
    v_game_uuid uuid;
    v_map_uuid uuid;
    v_affected bigint;
BEGIN
    -- Re-resolve from the protected relationships, never from a UUID literal or
    -- mutable games.slug. The locks/preflight above cover every legacy row.
    SELECT g.id INTO STRICT v_game_uuid
    FROM private.game_legacy_identifiers AS i
    JOIN public.games AS g ON g.id = i.game_id
    WHERE i.legacy_identifier = 'elden-ring';

    SELECT m.id INTO STRICT v_map_uuid
    FROM public.game_maps AS m
    WHERE m.game_id = v_game_uuid AND m.slug = 'world' AND m.is_default;

    UPDATE public.map_layers
    SET layer_uuid = pg_catalog.gen_random_uuid(),
        game_uuid = v_game_uuid,
        game_map_id = v_map_uuid
    WHERE game_id = 'elden-ring'
      AND id IN ('surface', 'underground', 'dlc')
      AND layer_uuid IS NULL AND game_uuid IS NULL AND game_map_id IS NULL;

    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected <> 3 THEN
        RAISE EXCEPTION 'B1_BACKFILL_DID_NOT_HYDRATE_EXACTLY_THREE_LAYERS';
    END IF;

    IF (SELECT pg_catalog.count(*) FROM public.map_layers) <> 3
       OR (SELECT pg_catalog.count(DISTINCT layer_uuid) FROM public.map_layers) <> 3
       OR EXISTS (
           SELECT 1 FROM public.map_layers AS l
           WHERE l.layer_uuid IS NULL OR l.game_uuid IS DISTINCT FROM v_game_uuid
              OR l.game_map_id IS DISTINCT FROM v_map_uuid
              OR l.game_id <> 'elden-ring' OR l.id NOT IN ('surface', 'underground', 'dlc')
       ) THEN
        RAISE EXCEPTION 'B1_BACKFILL_COVERAGE_OR_IDENTITY_MISMATCH';
    END IF;
END;
$backfill$;

-- Immediate validation is deliberate for three rows; no unvalidated integrity
-- gap remains after COMMIT. Keep legacy PK/FKs and every legacy column intact.
ALTER TABLE public.map_layers
    ADD CONSTRAINT map_layers_layer_uuid_unique UNIQUE (layer_uuid),
    ADD CONSTRAINT map_layers_legacy_game_uuid_fk
        FOREIGN KEY (game_id, game_uuid)
        REFERENCES private.game_legacy_identifiers (legacy_identifier, game_id)
        ON UPDATE NO ACTION ON DELETE RESTRICT,
    ADD CONSTRAINT map_layers_game_map_game_fk
        FOREIGN KEY (game_map_id, game_uuid)
        REFERENCES public.game_maps (id, game_id)
        ON UPDATE NO ACTION ON DELETE RESTRICT;

CREATE INDEX map_layers_game_map_game_idx
    ON public.map_layers (game_map_id, game_uuid);

ALTER TABLE public.map_layers
    ALTER COLUMN layer_uuid SET NOT NULL,
    ALTER COLUMN game_map_id SET NOT NULL,
    ALTER COLUMN game_uuid SET NOT NULL,
    ALTER COLUMN layer_uuid SET DEFAULT pg_catalog.gen_random_uuid();

COMMIT;
