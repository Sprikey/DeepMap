-- DeepMap post-B4a / pre-B4b. Execute MANUALLY after applying B4a.
-- ONE read-only WITH ... SELECT. Function source below is inert text, never run.
-- No trigger/RPC execution, dynamic SQL, explicit locks, DML, DDL or SET.
-- Maintenance SELECT/USAGE/full RLS visibility required. Failed visibility forces
-- data.* to FAIL/INVALID. Missing tables/permissions can abort: errors are not PASS.
-- No historical baseline: cannot prove unchanged rows/OIDs/owners/ACLs retrospectively.
WITH
source AS (
    -- Exact constants from 20261009184349_marker_audit_uuid_hydration_guard.sql.
    SELECT pg_catalog.replace($legacy_body$
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
$legacy_body$,pg_catalog.chr(13),'') AS legacy_body,
        pg_catalog.replace($guard$    -- B4a: only a genuine UUID-shadow-only UPDATE bypasses the audit UPSERT.
    -- is_published stays in both projections; missing JSONB keys are safe.
    if tg_op = 'UPDATE'
       and (pg_catalog.to_jsonb(new) - 'updated_at')
           is distinct from (pg_catalog.to_jsonb(old) - 'updated_at')
       and (pg_catalog.to_jsonb(new) - ARRAY['updated_at','game_uuid','layer_uuid']::text[])
           is not distinct from
           (pg_catalog.to_jsonb(old) - ARRAY['updated_at','game_uuid','layer_uuid']::text[]) then
        return new;
    end if;

$guard$,pg_catalog.chr(13),'') AS guard_body
),
with_guard AS (
    SELECT s.*,pg_catalog.replace(legacy_body,
        '    -- Publication toggles alone do not count as a content modification.',
        guard_body || '    -- Publication toggles alone do not count as a content modification.') AS guarded_body
    FROM source s
),
expected AS (
    SELECT s.*,pg_catalog.replace(pg_catalog.replace(guarded_body,
        '(to_jsonb(new) - ''updated_at'' - ''is_published'')',
        '(to_jsonb(new) - ARRAY[''updated_at'',''is_published'',''game_uuid'',''layer_uuid'']::text[])'),
        '(to_jsonb(old) - ''updated_at'' - ''is_published'')',
        '(to_jsonb(old) - ARRAY[''updated_at'',''is_published'',''game_uuid'',''layer_uuid'']::text[])') AS final_body
    FROM with_guard s
),
audit_function AS (
    SELECT p.*,pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'') AS body
    FROM pg_catalog.pg_proc p
    WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_stamp_marker_audit()')
),
body_match AS (
    SELECT EXISTS (SELECT 1 FROM audit_function p CROSS JOIN expected e
        WHERE p.body=e.final_body) AS ok
),
attributes AS (
    SELECT a.*,n.nspname,n.nspname||'.'||c.relname AS relation_name,
        pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS default_expr
    FROM pg_catalog.pg_attribute a JOIN pg_catalog.pg_class c ON c.oid=a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
    WHERE a.attnum>0 AND NOT a.attisdropped
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
expected_columns(name,type_oid,not_null) AS (VALUES
    ('marker_id','bigint'::pg_catalog.regtype,true),
    ('created_by','uuid'::pg_catalog.regtype,false),
    ('created_at','timestamptz'::pg_catalog.regtype,false),
    ('updated_by','uuid'::pg_catalog.regtype,false),
    ('updated_at','timestamptz'::pg_catalog.regtype,false),
    ('published_by','uuid'::pg_catalog.regtype,false),
    ('published_at','timestamptz'::pg_catalog.regtype,false),
    ('approved_by','uuid'::pg_catalog.regtype,false),
    ('approved_at','timestamptz'::pg_catalog.regtype,false)
),
expected_triggers(name,function_name,bits) AS (VALUES
    ('deepmap_marker_editor_audit','private.deepmap_stamp_marker_audit()',21),
    ('deepmap_marcadores_touch_updated_at','private.deepmap_touch_updated_at()',19)
),
visibility AS (
    SELECT e.name,EXISTS (SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
        WHERE c.oid=pg_catalog.to_regclass(e.name) AND c.relkind='r'
          AND pg_catalog.has_table_privilege(c.oid,'SELECT')
          AND pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
          AND (NOT c.relrowsecurity OR r.rolsuper OR r.rolbypassrls
              OR (c.relowner=r.oid AND NOT c.relforcerowsecurity))) AS ok
    FROM (VALUES ('public.marcadores'),('private.marker_editor_audit')) e(name)
),
checks AS (
    SELECT 'table.rls.'||v.name AS check_name,EXISTS (SELECT 1 FROM pg_catalog.pg_class c
        WHERE c.oid=pg_catalog.to_regclass(v.name) AND c.relkind='r' AND c.relrowsecurity) AS ok,
        'Expected ordinary table with RLS enabled' AS details FROM visibility v
    UNION ALL
    SELECT 'visibility.full.'||name,ok,'Maintenance SELECT/USAGE and full RLS visibility required' FROM visibility
    UNION ALL
    SELECT 'column.audit.'||e.name,EXISTS (SELECT 1 FROM attributes a
        WHERE a.relation_name='private.marker_editor_audit' AND a.attname=e.name AND a.atttypid=e.type_oid
          AND a.attnotnull=e.not_null AND NOT a.atthasdef AND a.default_expr IS NULL
          AND a.attidentity='' AND a.attgenerated=''),
        pg_catalog.format('Expected %s, NOT NULL=%s, no default/identity/generated',e.type_oid,e.not_null)
    FROM expected_columns e
    UNION ALL
    SELECT 'schema.audit.no_extra_columns',count(*)=0,
        'Unexpected columns='||COALESCE(pg_catalog.string_agg(a.attname,', '),'none')
    FROM attributes a WHERE a.relation_name='private.marker_editor_audit'
      AND NOT EXISTS (SELECT 1 FROM expected_columns e WHERE e.name=a.attname)
    UNION ALL
    SELECT 'key.audit_pk',(SELECT count(*) FROM constraints
        WHERE conrelid=pg_catalog.to_regclass('private.marker_editor_audit') AND contype='p')=1
        AND EXISTS (SELECT 1 FROM constraints c JOIN pg_catalog.pg_index i ON i.indexrelid=c.conindid
            WHERE c.conrelid=pg_catalog.to_regclass('private.marker_editor_audit') AND c.contype='p'
              AND c.source_columns=ARRAY['marker_id']::text[] AND c.convalidated
              AND NOT c.condeferrable AND NOT c.condeferred AND i.indrelid=c.conrelid
              AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
              AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnkeyatts=1 AND i.indnatts=1),
        'Exactly one validated non-deferrable PK (marker_id), valid/ready/live UNIQUE index'
    UNION ALL
    SELECT 'fk.audit_marker',EXISTS (SELECT 1 FROM constraints c
        WHERE c.conrelid=pg_catalog.to_regclass('private.marker_editor_audit') AND c.contype='f'
          AND c.confrelid=pg_catalog.to_regclass('public.marcadores')
          AND c.source_columns=ARRAY['marker_id']::text[] AND c.target_columns=ARRAY['id']::text[]
          AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
          AND c.confmatchtype='s' AND c.confupdtype='a' AND c.confdeltype='c'),
        'marker_id -> marcadores(id); validated/non-deferrable MATCH SIMPLE; UPDATE NO ACTION / DELETE CASCADE'
    UNION ALL
    SELECT 'data.audit.null_marker_id',count(*)=0,'NULL audit marker_id rows='||count(*)
    FROM private.marker_editor_audit WHERE marker_id IS NULL
    UNION ALL
    SELECT 'data.audit.orphan_rows',count(*)=0,'Orphan audit rows='||count(*)
    FROM private.marker_editor_audit a WHERE NOT EXISTS (SELECT 1 FROM public.marcadores m WHERE m.id=a.marker_id)
    UNION ALL
    SELECT 'data.audit.duplicate_marker_id',count(*)=0,'Duplicate marker_id groups='||count(*)
    FROM (SELECT marker_id FROM private.marker_editor_audit GROUP BY marker_id HAVING count(*)>1) d
    UNION ALL
    SELECT 'trigger.'||e.name,EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid=pg_catalog.to_regclass('public.marcadores') AND t.tgname=e.name
          AND t.tgfoid=pg_catalog.to_regprocedure(e.function_name) AND t.tgtype=e.bits
          AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgnargs=0
          AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL),
        pg_catalog.format('%s; %s FOR EACH ROW, enabled origin, no WHEN/args/column filter',e.function_name,
            CASE WHEN e.bits=21 THEN 'AFTER INSERT OR UPDATE' ELSE 'BEFORE UPDATE' END) FROM expected_triggers e
    UNION ALL
    SELECT 'trigger.markers.exact_user_triggers',count(*)=2 AND bool_and(tgname IN (
        'deepmap_marker_editor_audit','deepmap_marcadores_touch_updated_at')),
        'Expected two known user triggers; internal FK triggers excluded; actual='||count(*)
    FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass('public.marcadores') AND NOT tgisinternal
    UNION ALL
    SELECT 'trigger.audit.no_user_triggers',count(*)=0,'Audit user triggers='||count(*)
    FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass('private.marker_editor_audit') AND NOT tgisinternal
    UNION ALL
    SELECT 'function.audit.attributes',EXISTS (SELECT 1 FROM audit_function p
        JOIN pg_catalog.pg_language l ON l.oid=p.prolang
        WHERE p.pronargs=0 AND p.prorettype='trigger'::pg_catalog.regtype AND p.prokind='f'
          AND NOT p.proretset AND l.lanname='plpgsql' AND p.prosecdef
          AND p.proconfig=ARRAY['search_path=""']::text[] AND p.provolatile='v' AND p.proparallel='u'
          AND NOT p.proleakproof AND NOT p.proisstrict AND p.procost=100 AND p.prorows=0),
        'trigger(), PL/pgSQL, DEFINER, empty search_path, VOLATILE/UNSAFE, non-leakproof, CALLED ON NULL INPUT, COST 100'
    UNION ALL
    SELECT 'function.audit.no_overloads',count(*)=1,'Expected exactly one private audit function; actual='||count(*)
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='private' AND p.proname='deepmap_stamp_marker_audit'
    UNION ALL
    SELECT 'function.audit.exact_body',(SELECT ok FROM body_match),
        'Complete prosrc equals the exact three-step B4a transformation; only CRLF/LF normalized'
    UNION ALL
    SELECT 'function.audit.guard_exact_order',(SELECT ok FROM body_match) AND EXISTS (
        SELECT 1 FROM audit_function p CROSS JOIN expected e
        WHERE pg_catalog.strpos(p.body,e.guard_body)>0
          AND pg_catalog.strpos(p.body,e.guard_body)<pg_catalog.strpos(p.body,'    v_content_changed :=')),
        'Exact UUID-only UPDATE guard after INSERT return, before comparison and UPDATE audit UPSERT; publication stays in guard'
    UNION ALL
    SELECT 'function.audit.semantic_projection',(SELECT ok FROM body_match),
        'Exact OLD/NEW projections exclude only updated_at/is_published/game_uuid/layer_uuid; game_id/map_layer/category_id stay semantic'
    UNION ALL
    SELECT 'function.audit.insert_legacy_unchanged',(SELECT ok FROM body_match) AND EXISTS (
        SELECT 1 FROM audit_function p CROSS JOIN expected e
        WHERE pg_catalog.left(p.body,pg_catalog.strpos(e.legacy_body,
            '    -- Publication toggles alone do not count as a content modification.')-1)
            =pg_catalog.left(e.legacy_body,pg_catalog.strpos(e.legacy_body,
            '    -- Publication toggles alone do not count as a content modification.')-1)),
        'Entire legacy INSERT prefix is identical, including creation/update/publication/NULL approval and ON CONFLICT'
    UNION ALL
    SELECT 'function.audit.publication_approval_unchanged',(SELECT ok FROM body_match),
        'Exact body match proves unchanged legacy UPDATE UPSERT and updated/published/approved CASEs; not a keyword-presence test'
    UNION ALL
    SELECT 'function.audit.direct_acl.no_'||e.role_name,EXISTS (SELECT 1 FROM audit_function)
        AND NOT EXISTS (SELECT 1 FROM audit_function p CROSS JOIN LATERAL pg_catalog.aclexplode(
            COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
            LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
            WHERE a.privilege_type='EXECUTE' AND
                ((e.role_name='PUBLIC' AND a.grantee=0) OR (e.role_name<>'PUBLIC' AND r.rolname=e.role_name))),
        'No direct EXECUTE for '||e.role_name||'; historical service_role grants are permitted, not revoked'
    FROM (VALUES ('PUBLIC'),('anon'),('authenticated')) e(role_name)
    UNION ALL
    SELECT 'function.touch.invoker_body',EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
          AND NOT p.prosecdef AND p.prorettype='trigger'::pg_catalog.regtype
          AND pg_catalog.lower(pg_catalog.regexp_replace(p.prosrc,'[[:space:]]','','g'))
              ='beginnew.updated_at:=now();returnnew;end;'),
        'Existing invoker updated_at touch body intact'
    UNION ALL
    SELECT 'scope.pre_b4b.no_marker_column.'||e.name,
        pg_catalog.to_regclass('public.marcadores') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM attributes a
            WHERE a.relation_name='public.marcadores' AND a.attname=e.name),
        'Marker column must remain absent: '||e.name
    FROM (VALUES ('game_uuid'),('layer_uuid'),('game_map_id'),('category_uuid'),('group_uuid')) e(name)
    UNION ALL
    SELECT 'scope.pre_b4b.no_marker_uuid_normalizer',count(*)=0,
        'Known partial marker identity resolvers='||COALESCE(pg_catalog.string_agg(n.nspname||'.'||p.proname,', '),'none')
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='private' AND p.proname ~ '^deepmap_resolve_marker.*identity$'
    UNION ALL
    SELECT 'scope.pre_b4b.no_marker_uuid_fks',count(*)=0,
        'Marker UUID FKs='||COALESCE(pg_catalog.string_agg(c.conname,', '),'none')
    FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass('public.marcadores') AND c.contype='f'
      AND (pg_catalog.lower(c.conname) ~ 'uuid'
        OR EXISTS (SELECT 1 FROM pg_catalog.unnest(c.source_columns) k(name)
            WHERE k.name IN ('game_uuid','layer_uuid','game_map_id','category_uuid','group_uuid'))
        OR EXISTS (SELECT 1 FROM pg_catalog.unnest(c.target_columns) k(name)
            WHERE k.name IN ('game_uuid','layer_uuid')))
    UNION ALL
    SELECT 'scope.pre_b4b.no_marker_uuid_indexes',count(*)=0,
        'Marker UUID indexes='||COALESCE(pg_catalog.string_agg(c.relname,', '),'none')
    FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid
    WHERE i.indrelid=pg_catalog.to_regclass('public.marcadores')
      AND (pg_catalog.lower(c.relname) ~ 'uuid'
        OR EXISTS (SELECT 1 FROM pg_catalog.unnest(i.indkey::smallint[]) k(num)
            JOIN pg_catalog.pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.num
            WHERE a.attname IN ('game_uuid','layer_uuid','game_map_id','category_uuid','group_uuid'))
        OR COALESCE(pg_catalog.pg_get_expr(i.indexprs,i.indrelid),'') ~ '(game_uuid|layer_uuid)'
        OR COALESCE(pg_catalog.pg_get_expr(i.indpred,i.indrelid),'') ~ '(game_uuid|layer_uuid)')
)
SELECT check_name,
    CASE WHEN ok IS TRUE AND (check_name NOT LIKE 'data.%' OR (SELECT bool_and(ok) FROM visibility))
        THEN 'PASS' ELSE 'FAIL' END AS status,
    details || CASE WHEN check_name LIKE 'data.%' AND NOT (SELECT bool_and(ok) FROM visibility)
        THEN '; INVALID DATA RESULT: incomplete maintenance visibility' ELSE '' END AS details
FROM checks ORDER BY check_name;
