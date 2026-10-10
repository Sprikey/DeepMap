-- DeepMap B6a post-application verifier; one read-only statement, never invokes writers.
-- Historical row/timestamp/ACL/OID preservation requires the migration snapshots.
WITH
sources AS (
 SELECT pg_catalog.replace($resolver_body$
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
$resolver_body$,pg_catalog.chr(13),'') AS resolver_body,
 pg_catalog.replace($touch_body$
begin
    new.updated_at := now();
    return new;
end;
$touch_body$,pg_catalog.chr(13),'') AS touch_body
),
relations AS (
 SELECT e.name,c.* FROM (VALUES ('public.games'),('private.game_legacy_identifiers'),
 ('public.marker_category_groups'),('public.marker_categories')) e(name)
 LEFT JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass(e.name)
),
visibility AS (
 SELECT c.name,COALESCE(c.relkind='r' AND c.relrowsecurity
 AND pg_catalog.has_table_privilege(c.oid,'SELECT') AND pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
 AND (r.rolsuper OR r.rolbypassrls OR (r.oid=c.relowner AND NOT c.relforcerowsecurity)),false) AS ok
 FROM relations c JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
),
full_visibility AS (SELECT pg_catalog.count(*)=4 AND COALESCE(pg_catalog.bool_and(ok),false) AS ok FROM visibility),
attributes AS (
 SELECT a.*,pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS default_expr
 FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
 WHERE a.attnum>0 AND NOT a.attisdropped
),
expected_columns(name,type_name,default_expr) AS (VALUES
 ('game_id','text',NULL::text),('id','text',NULL),('name_en','text',NULL),('name_pt','text',NULL),
 ('sort_order','integer','0'),('is_active','boolean','true'),('created_at','timestamptz','now()'),
 ('updated_at','timestamptz','now()'),('game_uuid','uuid',NULL),('group_uuid','uuid','gen_random_uuid()')
),
constraints AS (
 SELECT c.*,ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(n,pos)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.n ORDER BY k.pos) AS columns,
 ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(n,pos)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.n ORDER BY k.pos) AS parent_columns
 FROM pg_catalog.pg_constraint c
),
indexes AS (
 SELECT i.*,c.relname,am.amname,
 ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(i.indkey) WITH ORDINALITY k(n,pos)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.n ORDER BY k.pos) AS columns
 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid JOIN pg_catalog.pg_am am ON am.oid=c.relam
),
expected_keys(name,kind,columns) AS (VALUES
 ('marker_category_groups_pkey','p',ARRAY['game_id','id']::text[]),
 ('marker_category_groups_group_uuid_unique','u',ARRAY['group_uuid']),
 ('marker_category_groups_legacy_uuid_identity_unique','u',ARRAY['game_id','id','game_uuid','group_uuid'])
),
expected_fks(rel,name,parent,columns,parent_columns,upd,del) AS (VALUES
 ('public.marker_category_groups','marker_category_groups_legacy_game_uuid_fk','private.game_legacy_identifiers',ARRAY['game_id','game_uuid']::text[],ARRAY['legacy_identifier','game_id']::text[],'a','r'),
 ('public.marker_categories','marker_categories_group_fk','public.marker_category_groups',ARRAY['game_id','group_id'],ARRAY['game_id','id'],'c','n'),
 ('private.game_legacy_identifiers','game_legacy_identifiers_game_id_fkey','public.games',ARRAY['game_id'],ARRAY['id'],'a','r')
),
resolver AS (
 SELECT p.*,l.lanname FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
 WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_category_group_identity()')
),
touch AS (
 SELECT p.*,l.lanname FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
 WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_touch_updated_at()')
),
body_match AS (
 SELECT EXISTS(SELECT 1 FROM resolver p CROSS JOIN sources s WHERE pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=s.resolver_body) AS ok
),
api_roles AS (SELECT * FROM pg_catalog.pg_roles WHERE rolname IN ('anon','authenticated','service_role')),
resolver_acl AS (
 SELECT p.proowner,a.* FROM resolver p CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
),
group_acl AS (
 SELECT c.relowner,a.* FROM pg_catalog.pg_class c CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
 WHERE c.oid=pg_catalog.to_regclass('public.marker_category_groups')
),
triggers AS (SELECT * FROM pg_catalog.pg_trigger WHERE tgrelid=pg_catalog.to_regclass('public.marker_category_groups') AND NOT tgisinternal),
policies AS (
 SELECT p.*,ARRAY(SELECT r.rolname::text FROM pg_catalog.unnest(p.polroles) x(oid)
 JOIN pg_catalog.pg_roles r ON r.oid=x.oid ORDER BY r.rolname COLLATE "C") AS roles,
 pg_catalog.pg_get_expr(p.polqual,p.polrelid) AS qual,pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) AS with_check
 FROM pg_catalog.pg_policy p WHERE p.polrelid=pg_catalog.to_regclass('public.marker_category_groups')
),
group_data AS MATERIALIZED (
 SELECT g.*,
 (SELECT pg_catalog.count(*) FROM private.game_legacy_identifiers i WHERE i.legacy_identifier=g.game_id) AS mapping_count,
 (SELECT pg_catalog.count(*) FROM private.game_legacy_identifiers i WHERE i.legacy_identifier=g.game_id AND i.game_id=g.game_uuid) AS exact_mapping_count,
 (SELECT pg_catalog.count(*) FROM public.games p WHERE p.id=g.game_uuid) AS parent_count
 FROM public.marker_category_groups g
),
data_stats AS (
 SELECT pg_catalog.count(*) AS total,pg_catalog.count(DISTINCT group_uuid) AS distinct_uuid,
 pg_catalog.count(*) FILTER(WHERE group_uuid IS NULL) AS null_uuid,
 pg_catalog.count(*) FILTER(WHERE mapping_count=0) AS missing_mapping,
 pg_catalog.count(*) FILTER(WHERE mapping_count>1) AS ambiguous_mapping,
 pg_catalog.count(*) FILTER(WHERE exact_mapping_count<>1) AS uuid_mismatch,
 pg_catalog.count(*) FILTER(WHERE parent_count<>1) AS missing_parent FROM group_data
),
checks AS (
 SELECT 'maintenance.visibility.'||name AS check_name,ok,'SELECT/schema USAGE plus superuser/BYPASSRLS or actual owner without FORCE RLS; ordinary RLS table'::text AS details FROM visibility
 UNION ALL SELECT 'schema.object.'||name,oid IS NOT NULL AND relkind='r' AND relrowsecurity,'Existing ordinary table with RLS' FROM relations
 UNION ALL SELECT 'schema.groups.column.'||e.name,EXISTS(SELECT 1 FROM attributes a
 WHERE a.attrelid=pg_catalog.to_regclass('public.marker_category_groups') AND a.attname=e.name
 AND a.atttypid=pg_catalog.to_regtype(e.type_name) AND a.attnotnull AND a.attidentity='' AND a.attgenerated=''
 AND a.default_expr IS NOT DISTINCT FROM e.default_expr),
 'Exact type/NOT NULL/default/no identity/no generated: '||e.type_name||'; default='||COALESCE(e.default_expr,'none') FROM expected_columns e
 UNION ALL SELECT 'schema.groups.exact_columns',pg_catalog.count(*)=10 AND COALESCE(pg_catalog.bool_and(attname IN(SELECT name FROM expected_columns)),false),
 'Exactly ten non-dropped columns; actual='||pg_catalog.count(*) FROM attributes WHERE attrelid=pg_catalog.to_regclass('public.marker_category_groups')
 UNION ALL SELECT 'constraint.key.'||e.name,EXISTS(SELECT 1 FROM constraints c JOIN indexes i ON i.indexrelid=c.conindid
 WHERE c.conrelid=pg_catalog.to_regclass('public.marker_category_groups') AND c.conname=e.name AND c.contype::text=e.kind
 AND c.columns=e.columns AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
 AND i.indrelid=c.conrelid AND i.relname=e.name AND i.columns=e.columns AND i.indisunique AND i.indimmediate
 AND i.indisvalid AND i.indisready AND i.indislive AND i.amname='btree'
 AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnkeyatts=pg_catalog.cardinality(e.columns) AND i.indnatts=i.indnkeyatts
 AND ARRAY(SELECT k FROM pg_catalog.unnest(i.indkey) k)=c.conkey),
 'Real validated immediate constraint plus exact UNIQUE B-tree backing index; no predicate/expression/INCLUDE' FROM expected_keys e
 UNION ALL SELECT 'constraint.groups.id_format',EXISTS(SELECT 1 FROM constraints c
 WHERE c.conrelid=pg_catalog.to_regclass('public.marker_category_groups') AND c.conname='marker_category_groups_id_format'
 AND c.contype='c' AND c.convalidated AND pg_catalog.pg_get_expr(c.conbin,c.conrelid)='(id ~ ''^[a-z0-9]+(?:[_-][a-z0-9]+)*$''::text)'),
 'Exact catalog CHECK expression; regex semantics unchanged'
 UNION ALL SELECT 'constraint.groups.exact_set',pg_catalog.count(*)=5 AND COALESCE(pg_catalog.bool_and(conname IN
 ('marker_category_groups_pkey','marker_category_groups_id_format','marker_category_groups_legacy_game_uuid_fk',
 'marker_category_groups_group_uuid_unique','marker_category_groups_legacy_uuid_identity_unique')),false),
 'Exactly legacy PK/CHECK/game FK and two B6a UNIQUEs; catalog NOT NULL constraints excluded across PostgreSQL versions'
 FROM constraints WHERE conrelid=pg_catalog.to_regclass('public.marker_category_groups') AND contype<>'n'
 UNION ALL SELECT 'constraint.fk.'||e.name,EXISTS(SELECT 1 FROM constraints c
 WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND c.conname=e.name AND c.contype='f' AND c.confrelid=pg_catalog.to_regclass(e.parent)
 AND c.columns=e.columns AND c.parent_columns=e.parent_columns AND c.confmatchtype='s'
 AND c.confupdtype::text=e.upd AND c.confdeltype::text=e.del AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred),
 'Exact legacy FK columns/parent/SIMPLE/actions/validated/immediate; category SET NULL legacy behavior is retained' FROM expected_fks e
 UNION ALL SELECT 'index.groups.exact_set',pg_catalog.count(*)=3 AND COALESCE(pg_catalog.bool_and(relname IN(SELECT name FROM expected_keys)),false),
 'Exactly the three approved constraint backing indexes; actual='||pg_catalog.count(*) FROM indexes WHERE indrelid=pg_catalog.to_regclass('public.marker_category_groups')
 UNION ALL SELECT 'function.resolver.attributes',EXISTS(SELECT 1 FROM resolver p
 WHERE p.pronamespace=pg_catalog.to_regnamespace('private') AND p.pronargs=0 AND p.proargtypes=''::pg_catalog.oidvector
 AND p.proargnames IS NULL AND p.proargmodes IS NULL AND p.proallargtypes IS NULL AND p.provariadic=0
 AND p.pronargdefaults=0 AND p.proargdefaults IS NULL AND p.prorettype='trigger'::pg_catalog.regtype AND p.prokind='f'
 AND p.lanname='plpgsql' AND NOT p.prosecdef AND p.proconfig=ARRAY['search_path=""']::text[]
 AND p.provolatile='v' AND p.proparallel='u' AND NOT p.proisstrict AND NOT p.proleakproof AND NOT p.proretset
 AND p.procost=100 AND p.prorows=0),
 'Exact zero-argument private plpgsql trigger INVOKER; empty search_path, VOLATILE/UNSAFE, called on NULL, COST100'
 UNION ALL SELECT 'function.resolver.exact_body',ok,'Full final literal extracted from approved B6a; symmetric CR removal only; never invoked' FROM body_match
 UNION ALL SELECT 'function.resolver.contract.'||e.name,ok,e.details FROM body_match CROSS JOIN (VALUES
 ('insert_generation','Exact body unconditionally overwrites explicit/default/NULL INSERT group_uuid with DB-generated UUID'),
 ('update_immutable','Exact body rejects OLD NULL, NEW NULL or changed group_uuid with B6A_GROUP_UUID_IS_IMMUTABLE'),
 ('b2a_preserved','Exact body retains B2a mapping lookup/game identity hydration and immutability/mismatch rejection'),
 ('editorial_untouched','Exact body does not change id/names/order/active, read categories, write recursively or use dynamic SQL')) e(name,details)
 UNION ALL SELECT 'function.resolver.single_overload',pg_catalog.count(*)=1 AND COALESCE(pg_catalog.bool_and(n.nspname='private'
 AND p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_category_group_identity()')),false),
 'Single private signature, no public convenience version or overload' FROM pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private') AND p.proname='deepmap_resolve_category_group_identity'
 UNION ALL SELECT 'acl.resolver.owner_only',EXISTS(SELECT 1 FROM resolver)
 AND NOT EXISTS(SELECT 1 FROM resolver_acl WHERE grantee<>proowner OR privilege_type<>'EXECUTE'),
 'B2a raw owner-only ACL; no PUBLIC/anon/authenticated/service_role or unexpected new EXECUTE'
 UNION ALL SELECT 'acl.resolver.trusted_owner',EXISTS(SELECT 1 FROM resolver p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
 WHERE r.rolname NOT IN('anon','authenticated','service_role')
 AND EXISTS(SELECT 1 FROM api_roles WHERE rolname='anon') AND EXISTS(SELECT 1 FROM api_roles WHERE rolname='authenticated')
 AND NOT EXISTS(SELECT 1 FROM api_roles a WHERE a.rolname IN('anon','authenticated') AND pg_catalog.pg_has_role(a.oid,r.oid,'MEMBER'))),
 'Real owner exists and is not an API role or inherited by untrusted callers; no fixed owner/OID; historical OID/ACL equality belongs to migration snapshots'
 UNION ALL SELECT 'acl.private.no_untrusted_create',EXISTS(SELECT 1 FROM api_roles WHERE rolname='anon')
 AND EXISTS(SELECT 1 FROM api_roles WHERE rolname='authenticated') AND NOT EXISTS(SELECT 1 FROM api_roles r
 WHERE r.rolname IN('anon','authenticated') AND pg_catalog.has_schema_privilege(r.oid,'private','CREATE')),
 'Untrusted callers cannot replace the private resolver'
 UNION ALL SELECT 'trigger.groups.exact_set',pg_catalog.count(*)=2 AND COALESCE(pg_catalog.bool_and(tgname IN
 ('deepmap_category_groups_identity','deepmap_category_groups_touch_updated_at')),false),'Exactly two user triggers; FK internal triggers excluded' FROM triggers
 UNION ALL SELECT 'trigger.groups.'||e.name,EXISTS(SELECT 1 FROM triggers t WHERE t.tgname=e.name AND t.tgtype=e.kind
 AND t.tgfoid=pg_catalog.to_regprocedure(e.signature) AND t.tgenabled='O' AND t.tgnargs=0 AND t.tgattr=''::pg_catalog.int2vector AND t.tgqual IS NULL),
 'Exact ROW/events/timing/target/origin/zero args; no UPDATE OF or WHEN' FROM (VALUES
 ('deepmap_category_groups_identity',23,'private.deepmap_resolve_category_group_identity()'),
 ('deepmap_category_groups_touch_updated_at',19,'private.deepmap_touch_updated_at()')) e(name,kind,signature)
 UNION ALL SELECT 'trigger.before_update.order',(SELECT pg_catalog.array_agg(tgname::text ORDER BY tgname COLLATE "C")
 FROM triggers WHERE (tgtype & 2)=2 AND (tgtype & 16)=16) IS NOT DISTINCT FROM
 ARRAY['deepmap_category_groups_identity','deepmap_category_groups_touch_updated_at']::text[],
 'PostgreSQL trigger name order: identity precedes touch, never OID order'
 UNION ALL SELECT 'function.touch.exact_legacy',EXISTS(SELECT 1 FROM touch p CROSS JOIN sources s
 WHERE p.pronargs=0 AND p.prorettype='trigger'::pg_catalog.regtype AND p.lanname='plpgsql' AND NOT p.prosecdef
 AND p.proconfig=ARRAY['search_path=""']::text[] AND pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'')=s.touch_body),
 'Exact legacy touch body after symmetric CR removal; INVOKER trigger; never invoked'
 UNION ALL SELECT 'policy.groups.exact_set',pg_catalog.count(*)=2 AND COALESCE(pg_catalog.bool_and(polname IN
 ('marker_category_groups_public_read','marker_category_groups_admin_all')),false),'Exactly two existing group policies' FROM policies
 UNION ALL SELECT 'policy.groups.public_read',EXISTS(SELECT 1 FROM policies WHERE polname='marker_category_groups_public_read'
 AND polcmd='r' AND polpermissive AND roles=ARRAY['anon','authenticated']::text[] AND qual='(is_active = true)' AND with_check IS NULL),
 'Permissive SELECT anon/authenticated USING is_active=true'
 UNION ALL SELECT 'policy.groups.admin_all',EXISTS(SELECT 1 FROM policies WHERE polname='marker_category_groups_admin_all'
 AND polcmd='*' AND polpermissive AND roles=ARRAY['authenticated']::text[] AND qual='private.is_deepmap_admin()' AND with_check='private.is_deepmap_admin()'),
 'Permissive authenticated ALL with exact existing Admin USING/WITH CHECK'
 UNION ALL SELECT 'acl.groups.anon_select',EXISTS(SELECT 1 FROM api_roles r WHERE r.rolname='anon'
 AND pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('public.marker_category_groups'),'SELECT')),'Legacy anon SELECT'
 UNION ALL SELECT 'acl.groups.authenticated.'||e.privilege,EXISTS(SELECT 1 FROM api_roles r WHERE r.rolname='authenticated'
 AND pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('public.marker_category_groups'),e.privilege)),
 'Legacy authenticated table privilege retained: '||e.privilege FROM (VALUES('SELECT'),('INSERT'),('UPDATE'),('DELETE')) e(privilege)
 UNION ALL SELECT 'acl.groups.no_unexpected_grants',pg_catalog.to_regclass('public.marker_category_groups') IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM group_acl a WHERE a.grantee<>a.relowner
 AND NOT EXISTS(SELECT 1 FROM api_roles r WHERE r.oid=a.grantee AND (r.rolname='service_role'
 OR (NOT a.is_grantable AND ((r.rolname='anon' AND a.privilege_type='SELECT')
 OR (r.rolname='authenticated' AND a.privilege_type IN('SELECT','INSERT','UPDATE','DELETE')))))))
 AND NOT EXISTS(SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass('public.marker_category_groups') AND a.attacl IS NOT NULL),
 'Current owner/service ACL permitted; no PUBLIC/unexpected API/table or separate column ACL escalation; historical equality requires snapshots'
 UNION ALL SELECT 'acl.groups.group_uuid.table_wide_defense',EXISTS(SELECT 1 FROM api_roles r JOIN attributes a
 ON a.attrelid=pg_catalog.to_regclass('public.marker_category_groups') AND a.attname='group_uuid'
 WHERE r.rolname='authenticated' AND pg_catalog.has_column_privilege(r.oid,a.attrelid,a.attnum,'INSERT')
 AND pg_catalog.has_column_privilege(r.oid,a.attrelid,a.attnum,'UPDATE') AND a.attacl IS NULL) AND (SELECT ok FROM body_match),
 'Inherited table-wide write capability; exact resolver overwrites INSERT and freezes UPDATE, without dedicated new grants'
 UNION ALL SELECT 'function.uuid_generator.attributes',EXISTS(SELECT 1 FROM pg_catalog.pg_proc p
 WHERE p.oid=pg_catalog.to_regprocedure('pg_catalog.gen_random_uuid()') AND p.pronargs=0 AND p.prorettype='uuid'::pg_catalog.regtype
 AND p.provolatile='v' AND NOT p.prosecdef AND NOT p.proretset),
 'Core generator exists/zero args/UUID/VOLATILE/INVOKER/non-set-returning; never called'
 UNION ALL SELECT 'schema.group_uuid.default_reference',EXISTS(SELECT 1 FROM attributes a
 JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
 WHERE a.attrelid=pg_catalog.to_regclass('public.marker_category_groups') AND a.attname='group_uuid'
 AND a.default_expr='gen_random_uuid()' AND pg_catalog.to_regprocedure('pg_catalog.gen_random_uuid()') IS NOT NULL),
 'Exact built-in default expression with core UUID generator present; no generation performed'
 UNION ALL SELECT 'acl.uuid_generator.writers',pg_catalog.to_regprocedure('pg_catalog.gen_random_uuid()') IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM api_roles r WHERE r.rolname IN('authenticated','service_role')
 AND (pg_catalog.has_any_column_privilege(r.oid,pg_catalog.to_regclass('public.marker_category_groups'),'INSERT')
 OR pg_catalog.has_any_column_privilege(r.oid,pg_catalog.to_regclass('public.marker_category_groups'),'UPDATE'))
 AND (NOT pg_catalog.has_schema_privilege(r.oid,'pg_catalog','USAGE')
 OR NOT pg_catalog.has_function_privilege(r.oid,'pg_catalog.gen_random_uuid()','EXECUTE'))),
 'Effective legacy writers can access core generator; no function executed'
 UNION ALL SELECT 'data.group_uuid.non_null',null_uuid=0,'NULL group UUID rows='||null_uuid FROM data_stats
 UNION ALL SELECT 'data.group_uuid.no_duplicates',NOT EXISTS(SELECT 1 FROM group_data GROUP BY group_uuid HAVING pg_catalog.count(*)>1),'No duplicate group UUIDs'
 UNION ALL SELECT 'data.group_uuid.distinct_count',distinct_uuid=total,'Distinct UUIDs='||distinct_uuid||'; groups='||total FROM data_stats
 UNION ALL SELECT 'data.game_context.mapping_present',missing_mapping=0,'Missing mappings='||missing_mapping FROM data_stats
 UNION ALL SELECT 'data.game_context.mapping_unambiguous',ambiguous_mapping=0,'Ambiguous mappings='||ambiguous_mapping FROM data_stats
 UNION ALL SELECT 'data.game_context.uuid_exact',uuid_mismatch=0,'Rows without exactly one legacy/game UUID mapping='||uuid_mismatch FROM data_stats
 UNION ALL SELECT 'data.game_context.game_parent',missing_parent=0,'Rows without exactly one game parent='||missing_parent FROM data_stats
 UNION ALL SELECT 'data.category_group.coherence',pg_catalog.count(*)=0,'Non-NULL group_id categories without exactly one same-game legacy group='||pg_catalog.count(*)
 FROM public.marker_categories c WHERE c.group_id IS NOT NULL AND
 (SELECT pg_catalog.count(*) FROM public.marker_category_groups g WHERE g.game_id=c.game_id AND g.id=c.group_id AND g.game_uuid=c.game_uuid)<>1
 UNION ALL SELECT 'scope.categories.b2b_game_uuid',EXISTS(SELECT 1 FROM attributes WHERE attrelid=pg_catalog.to_regclass('public.marker_categories')
 AND attname='game_uuid' AND atttypid='uuid'::pg_catalog.regtype AND attnotnull),'Category B2b game UUID retained, no group UUID required'
 UNION ALL SELECT 'scope.no_later_uuid_columns.'||e.rel,pg_catalog.to_regclass(e.rel) IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM attributes WHERE attrelid=pg_catalog.to_regclass(e.rel) AND attname::text=ANY(e.forbidden)),
 'Later entity UUID columns absent: '||pg_catalog.array_to_string(e.forbidden,',') FROM (VALUES
 ('public.marker_categories',ARRAY['category_uuid','group_uuid']::text[]),('public.marcadores',ARRAY['category_uuid','group_uuid']),
 ('public.marker_submissions',ARRAY['category_uuid','group_uuid']),('private.marker_submission_revisions',ARRAY['category_uuid','group_uuid']),
 ('public.user_notifications',ARRAY['category_uuid','group_uuid']),('public.marker_category_groups',ARRAY['category_uuid'])) e(rel,forbidden)
 UNION ALL SELECT 'scope.no_later_uuid_constraints',NOT EXISTS(SELECT 1 FROM constraints c
 WHERE c.conrelid IN(pg_catalog.to_regclass('public.marker_categories'),pg_catalog.to_regclass('public.marcadores'),
 pg_catalog.to_regclass('public.marker_submissions'),pg_catalog.to_regclass('private.marker_submission_revisions'),pg_catalog.to_regclass('public.user_notifications'))
 AND (c.columns && ARRAY['category_uuid','group_uuid']::text[] OR c.parent_columns && ARRAY['category_uuid','group_uuid']::text[]
 OR c.conname ~* '(group_uuid|category_uuid|legacy_uuid_identity|b6[b-c])')),
 'No identifiable B6b/B6c constraints by entity UUID columns or known names; support UNIQUE in groups is B6a only'
 UNION ALL SELECT 'scope.no_identifiable_later_functions',NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private') AND
 (p.proname ~ '^deepmap_resolve_marker_(category|group)_identity$'
 OR p.proname ~ '^deepmap_resolve_(submission|notification|revision)_(category|group)_identity$')),
 'No clearly identifiable later-phase identity functions; no assertion about undocumented B7 consumer work'
)
SELECT check_name,CASE WHEN ok IS TRUE AND (check_name NOT LIKE 'data.%' OR (SELECT ok FROM full_visibility))
 THEN 'PASS' ELSE 'FAIL' END AS status,
 details||CASE WHEN check_name LIKE 'data.%' AND NOT(SELECT ok FROM full_visibility)
 THEN '; INVALID DATA RESULT: incomplete maintenance visibility' ELSE '' END AS details
FROM checks ORDER BY check_name;
