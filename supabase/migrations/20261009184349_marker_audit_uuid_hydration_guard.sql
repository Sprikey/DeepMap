-- DeepMap B4a: strictly technical UUID-only UPDATEs never write marker audit.
-- Manual execution after review only. No B4b columns/normalizer/backfill here.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = pg_catalog;

DO $dependencies$
BEGIN
    IF EXISTS (SELECT 1 FROM (VALUES ('public.marcadores'),('private.marker_editor_audit')) e(name)
        WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
            WHERE c.oid=pg_catalog.to_regclass(e.name) AND c.relkind='r' AND c.relrowsecurity))
       OR pg_catalog.to_regprocedure('private.deepmap_stamp_marker_audit()') IS NULL
       OR pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()') IS NULL THEN
        RAISE EXCEPTION 'B4A_REQUIRED_TABLE_OR_FUNCTION_MISSING';
    END IF;
END;
$dependencies$;

-- SHARE blocks row writers, permits ordinary reads, and avoids ACCESS EXCLUSIVE.
-- Marker -> audit follows trigger write order. Retain both locks for snapshots;
-- 5s bounds acquisition waits, not the duration of scans/function replacement.
LOCK TABLE public.marcadores IN SHARE MODE;
LOCK TABLE private.marker_editor_audit IN SHARE MODE;

DO $compatibility$
DECLARE
    v_markers oid := 'public.marcadores'::pg_catalog.regclass;
    v_audit oid := 'private.marker_editor_audit'::pg_catalog.regclass;
    v_function oid := 'private.deepmap_stamp_marker_audit()'::pg_catalog.regprocedure;
    -- Final legacy body from map-community-contributions.sql.
    v_expected text := pg_catalog.replace($legacy_body$
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

    -- Publication toggles alone do not count as a content modification.
    v_content_changed :=
        (to_jsonb(new) - 'updated_at' - 'is_published')
        is distinct from
        (to_jsonb(old) - 'updated_at' - 'is_published');

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
$legacy_body$,pg_catalog.chr(13),'');
    v_guard text := pg_catalog.replace($guard$    -- B4a: only a genuine UUID-shadow-only UPDATE bypasses the audit UPSERT.
    -- is_published stays in both projections; missing JSONB keys are safe.
    if tg_op = 'UPDATE'
       and (pg_catalog.to_jsonb(new) - 'updated_at')
           is distinct from (pg_catalog.to_jsonb(old) - 'updated_at')
       and (pg_catalog.to_jsonb(new) - ARRAY['updated_at','game_uuid','layer_uuid']::text[])
           is not distinct from
           (pg_catalog.to_jsonb(old) - ARRAY['updated_at','game_uuid','layer_uuid']::text[]) then
        return new;
    end if;

$guard$,pg_catalog.chr(13),'');
    v_new_body text;
    v_attributes jsonb;
    v_before jsonb;
    v_after jsonb;
    -- Identical read-only snapshot query before/after; no temporary objects.
    -- Fixed table names, not user input. Full rows include all timestamps.
    v_snapshot_sql text := $snapshot$
        SELECT jsonb_build_object(
            'marker_count',(SELECT count(*) FROM public.marcadores),
            'audit_count',(SELECT count(*) FROM private.marker_editor_audit),
            'marker_rows',(SELECT COALESCE(jsonb_agg(to_jsonb(m) ORDER BY m.id),'[]'::jsonb)
                FROM public.marcadores m),
            'audit_rows',(SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.marker_id),'[]'::jsonb)
                FROM private.marker_editor_audit a),
            'columns',(SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.attrelid,a.attnum),'[]'::jsonb)
                FROM pg_catalog.pg_attribute a WHERE a.attnum>0 AND a.attrelid IN (
                    'public.marcadores'::pg_catalog.regclass,'private.marker_editor_audit'::pg_catalog.regclass)),
            'defaults',(SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.adrelid,d.adnum),'[]'::jsonb)
                FROM pg_catalog.pg_attrdef d WHERE d.adrelid IN (
                    'public.marcadores'::pg_catalog.regclass,'private.marker_editor_audit'::pg_catalog.regclass)),
            'constraints',(SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.oid),'[]'::jsonb)
                FROM pg_catalog.pg_constraint c WHERE c.conrelid IN (
                    'public.marcadores'::pg_catalog.regclass,'private.marker_editor_audit'::pg_catalog.regclass)),
            'indexes',(SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.indexrelid),'[]'::jsonb)
                FROM pg_catalog.pg_index i WHERE i.indrelid IN (
                    'public.marcadores'::pg_catalog.regclass,'private.marker_editor_audit'::pg_catalog.regclass)),
            'triggers',(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.oid),'[]'::jsonb)
                FROM pg_catalog.pg_trigger t WHERE t.tgrelid IN (
                    'public.marcadores'::pg_catalog.regclass,'private.marker_editor_audit'::pg_catalog.regclass)),
            'policies',(SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.oid),'[]'::jsonb)
                FROM pg_catalog.pg_policy p WHERE p.polrelid IN (
                    'public.marcadores'::pg_catalog.regclass,'private.marker_editor_audit'::pg_catalog.regclass)),
            'security',(SELECT jsonb_agg(jsonb_build_object('oid',c.oid,'acl',c.relacl,
                'owner',c.relowner,'rls',c.relrowsecurity,'force',c.relforcerowsecurity) ORDER BY c.oid)
                FROM pg_catalog.pg_class c WHERE c.oid IN (
                    'public.marcadores'::pg_catalog.regclass,'private.marker_editor_audit'::pg_catalog.regclass)),
            'touch',(SELECT to_jsonb(p) FROM pg_catalog.pg_proc p
                WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()'))
        )
    $snapshot$;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.oid=v_function AND p.pronargs=0 AND p.prorettype='trigger'::pg_catalog.regtype
          AND p.prokind='f' AND NOT p.proretset AND l.lanname='plpgsql' AND p.prosecdef
          AND p.proconfig=ARRAY['search_path=""']::text[]
          AND p.provolatile='v' AND p.proparallel='u' AND NOT p.proleakproof AND NOT p.proisstrict
          AND p.procost=100 AND p.prorows=0
          AND btrim(replace(p.prosrc,chr(13),''))=btrim(v_expected))
       OR (SELECT count(*) FROM pg_catalog.pg_proc p
           JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='private' AND p.proname='deepmap_stamp_marker_audit')<>1 THEN
        RAISE EXCEPTION 'B4A_AUDIT_FUNCTION_BODY_OR_ATTRIBUTES_DRIFT';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
        LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
        WHERE p.oid=v_function AND a.grantee<>p.proowner
          AND (a.grantee=0 OR r.rolname IN ('anon','authenticated'))) THEN
        RAISE EXCEPTION 'B4A_UNEXPECTED_PUBLIC_CLIENT_FUNCTION_GRANTS';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid=v_markers
        AND a.attnum>0 AND NOT a.attisdropped
        AND a.attname IN ('game_uuid','layer_uuid','game_map_id','category_uuid','group_uuid'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='private' AND p.proname ~ '^deepmap_resolve_marker.*identity$')
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_inherits
           WHERE inhrelid IN (v_markers,v_audit) OR inhparent IN (v_markers,v_audit))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_rewrite WHERE ev_class IN (v_markers,v_audit)) THEN
        RAISE EXCEPTION 'B4A_PREMATURE_BRIDGE_INHERITANCE_OR_RULES';
    END IF;
    IF EXISTS (
        WITH expected(name,type_oid,not_null) AS (VALUES
            ('marker_id','bigint'::pg_catalog.regtype,true),
            ('created_by','uuid'::pg_catalog.regtype,false),
            ('created_at','timestamptz'::pg_catalog.regtype,false),
            ('updated_by','uuid'::pg_catalog.regtype,false),
            ('updated_at','timestamptz'::pg_catalog.regtype,false),
            ('published_by','uuid'::pg_catalog.regtype,false),
            ('published_at','timestamptz'::pg_catalog.regtype,false),
            ('approved_by','uuid'::pg_catalog.regtype,false),
            ('approved_at','timestamptz'::pg_catalog.regtype,false)
        ), actual AS (
            SELECT attname::text AS name,atttypid,attnotnull,atthasdef,attidentity,attgenerated
            FROM pg_catalog.pg_attribute WHERE attrelid=v_audit AND attnum>0 AND NOT attisdropped
        ) SELECT 1 FROM expected e FULL JOIN actual a USING(name)
        WHERE e.name IS NULL OR a.name IS NULL OR a.atttypid<>e.type_oid
           OR a.attnotnull IS DISTINCT FROM e.not_null OR a.atthasdef
           OR a.attidentity<>'' OR a.attgenerated<>''
    ) THEN RAISE EXCEPTION 'B4A_UNEXPECTED_AUDIT_TABLE_SCHEMA'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
        JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
        WHERE c.conrelid=v_audit AND c.contype='p' AND c.convalidated AND NOT c.condeferrable
          AND i.indisvalid AND i.indisready AND i.indislive
          AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute
              WHERE attrelid=v_audit AND attname='marker_id' AND NOT attisdropped)]::smallint[])
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid=v_audit AND c.contype='f' AND c.confrelid=v_markers
          AND c.convalidated AND NOT c.condeferrable AND c.confupdtype='a' AND c.confdeltype='c'
          AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute
              WHERE attrelid=v_audit AND attname='marker_id' AND NOT attisdropped)]::smallint[]
          AND c.confkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute
              WHERE attrelid=v_markers AND attname='id' AND NOT attisdropped)]::smallint[]) THEN
        RAISE EXCEPTION 'B4A_UNEXPECTED_AUDIT_KEYS';
    END IF;
    IF (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgrelid=v_markers AND NOT tgisinternal)<>2
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgrelid=v_audit AND NOT tgisinternal)
       OR EXISTS (SELECT 1 FROM (VALUES
            ('deepmap_marker_editor_audit',v_function,21),
            ('deepmap_marcadores_touch_updated_at',pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')::oid,19)
        ) e(name,fn,bits) WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
            WHERE t.tgrelid=v_markers AND t.tgname=e.name AND t.tgfoid=e.fn
              AND t.tgtype=e.bits AND t.tgenabled='O' AND NOT t.tgisinternal
              AND t.tgnargs=0 AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL))
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
            WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
              AND NOT p.prosecdef AND p.prorettype='trigger'::pg_catalog.regtype
              AND lower(regexp_replace(p.prosrc,'[[:space:]]','','g'))='beginnew.updated_at:=now();returnnew;end;') THEN
        RAISE EXCEPTION 'B4A_UNEXPECTED_AUDIT_OR_TOUCH_TRIGGERS';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c CROSS JOIN pg_catalog.pg_roles r
        WHERE c.oid IN (v_markers,v_audit) AND r.rolname=CURRENT_USER
          AND (NOT pg_catalog.has_table_privilege(c.oid,'SELECT')
            OR NOT pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
            OR NOT (r.rolsuper OR r.rolbypassrls OR (c.relowner=r.oid AND NOT c.relforcerowsecurity)))) THEN
        RAISE EXCEPTION 'B4A_REQUIRES_FULL_MAINTENANCE_VISIBILITY';
    END IF;

    SELECT to_jsonb(p)-'prosrc' INTO v_attributes FROM pg_catalog.pg_proc p WHERE p.oid=v_function;
    EXECUTE v_snapshot_sql INTO v_before;

    -- Exactly three textual changes to the verified legacy body.
    v_new_body := replace(v_expected,
        '    -- Publication toggles alone do not count as a content modification.',
        v_guard || '    -- Publication toggles alone do not count as a content modification.');
    v_new_body := replace(v_new_body,
        '(to_jsonb(new) - ''updated_at'' - ''is_published'')',
        '(to_jsonb(new) - ARRAY[''updated_at'',''is_published'',''game_uuid'',''layer_uuid'']::text[])');
    v_new_body := replace(v_new_body,
        '(to_jsonb(old) - ''updated_at'' - ''is_published'')',
        '(to_jsonb(old) - ARRAY[''updated_at'',''is_published'',''game_uuid'',''layer_uuid'']::text[])');
    IF v_new_body=v_expected THEN RAISE EXCEPTION 'B4A_BODY_TRANSFORMATION_FAILED'; END IF;

    -- ONLY mutation executed here. No row writes, grants or table/trigger DDL.
    -- CREATE OR REPLACE preserves OID, owner and ACL; verify all pg_proc fields.
    EXECUTE pg_catalog.format(
        'CREATE OR REPLACE FUNCTION private.deepmap_stamp_marker_audit()
         RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER VOLATILE PARALLEL UNSAFE
         CALLED ON NULL INPUT COST 100 SET search_path = '''' AS %L',v_new_body);

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=v_function
        AND (to_jsonb(p)-'prosrc')=v_attributes
        AND replace(p.prosrc,chr(13),'')=v_new_body) THEN
        RAISE EXCEPTION 'B4A_FUNCTION_IDENTITY_ATTRIBUTES_ACL_OR_BODY_CHANGED_UNEXPECTEDLY';
    END IF;
    EXECUTE v_snapshot_sql INTO v_after;
    IF v_before IS DISTINCT FROM v_after
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=v_markers
           AND attnum>0 AND NOT attisdropped AND attname IN ('game_uuid','layer_uuid')) THEN
        RAISE EXCEPTION 'B4A_MARKER_AUDIT_ROWS_SCHEMA_OR_TRIGGERS_CHANGED';
    END IF;
END;
$compatibility$;
COMMIT;
