-- DeepMap post-B5a / pre-B5b. Execute manually after applying B5a.
-- ONE read-only WITH ... SELECT. Function literals below are inert, never invoked.
-- Errors (missing relations/permissions) invalidate verification; never treat them as PASS.
-- No historical baseline: row/ACL/OID preservation was proved transactionally by B5a.
WITH
source AS (
 SELECT pg_catalog.replace($expected_body$
begin
    -- Only a real UUID-shadow change may bypass the legacy timestamp touch.
    -- Safe before expand: JSONB subtraction tolerates an absent game_uuid key.
    if tg_op = 'UPDATE'
       and to_jsonb(new) is distinct from to_jsonb(old)
       and (to_jsonb(new) - 'game_uuid') is not distinct from
           (to_jsonb(old) - 'game_uuid') then
        new.updated_at := old.updated_at;
        return new;
    end if;

    new.updated_at := now();
    return new;
end;
$expected_body$,pg_catalog.chr(13),'') AS expected_body
),
relations(name) AS (VALUES ('public.marker_submissions'),('private.marker_submission_revisions'),('public.user_notifications'),('public.marcadores')),
visibility AS (
 SELECT e.name,EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
 WHERE c.oid=pg_catalog.to_regclass(e.name) AND c.relkind='r'
 AND pg_catalog.has_table_privilege(c.oid,'SELECT') AND pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
 AND (r.rolsuper OR r.rolbypassrls OR (r.oid=c.relowner AND NOT c.relforcerowsecurity))) AS ok
 FROM (VALUES ('public.marker_submissions'),('public.marcadores')) e(name)
),
attributes AS (
 SELECT a.*,pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS default_expr FROM pg_catalog.pg_attribute a
 LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
 WHERE a.attnum>0 AND NOT a.attisdropped
),
expected_columns(rel,name,type_name,nn,identity_kind,default_expr) AS (VALUES
 ('public.marker_submissions','id','bigint',true,'d',NULL),
 ('public.marker_submissions','game_id','text',true,'',NULL),
 ('public.marker_submissions','marker_id','bigint',false,'',NULL),
 ('public.marker_submissions','submission_type','text',true,'',NULL),
 ('public.marker_submissions','correction_kind','text',false,'',NULL),
 ('public.marker_submissions','status','text',true,'','''pending''::text'),
 ('public.marker_submissions','submitted_by','uuid',true,'',NULL),
 ('public.marker_submissions','payload','jsonb',true,'','''{}''::jsonb'),
 ('public.marker_submissions','note','text',false,'',NULL),
 ('public.marker_submissions','reviewed_by','uuid',false,'',NULL),
 ('public.marker_submissions','reviewed_at','timestamp with time zone',false,'',NULL),
 ('public.marker_submissions','review_note','text',false,'',NULL),
 ('public.marker_submissions','created_at','timestamp with time zone',true,'','now()'),
 ('public.marker_submissions','updated_at','timestamp with time zone',true,'','now()'),
 ('private.marker_submission_revisions','id','bigint',true,'d',NULL),
 ('private.marker_submission_revisions','submission_id','bigint',true,'',NULL),
 ('private.marker_submission_revisions','revision_no','integer',true,'',NULL),
 ('private.marker_submission_revisions','edited_by','uuid',false,'',NULL),
 ('private.marker_submission_revisions','payload','jsonb',true,'','''{}''::jsonb'),
 ('private.marker_submission_revisions','note','text',false,'',NULL),
 ('private.marker_submission_revisions','created_at','timestamp with time zone',true,'','now()')
),
constraints AS (
 SELECT c.*,
 ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,ord)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.ord) AS columns,
 ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num,ord)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.ord) AS parent_columns
 FROM pg_catalog.pg_constraint c
),
expected_checks(name,expression) AS (VALUES
 ('marker_submissions_submission_type_check','submission_type = ANY (ARRAY[''create''::text, ''correction''::text])'),
 ('marker_submissions_correction_kind_check','correction_kind IS NULL OR correction_kind = ANY (ARRAY[''text''::text, ''location''::text, ''image''::text, ''other''::text])'),
 ('marker_submissions_status_check','status = ANY (ARRAY[''pending''::text, ''approved''::text, ''rejected''::text, ''cancelled''::text])'),
 ('marker_submissions_target_required','submission_type <> ''correction''::text OR marker_id IS NOT NULL')
),
indexes AS (
 SELECT i.*,c.relname,
 ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(i.indkey::smallint[]) WITH ORDINALITY k(num,ord)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.num ORDER BY k.ord) AS columns,
 ARRAY(SELECT k.opt::integer FROM pg_catalog.unnest(i.indoption::smallint[]) WITH ORDINALITY k(opt,ord) ORDER BY k.ord) AS options,
 pg_catalog.regexp_replace(pg_catalog.pg_get_expr(i.indpred,i.indrelid),'[[:space:]()]','','g') AS predicate
 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid
),
expected_indexes(name,columns,options,is_unique,predicate) AS (VALUES
 ('marker_submissions_game_status_idx',ARRAY['game_id','status','created_at'],ARRAY[0,0,3],false,NULL),
 ('marker_submissions_user_status_idx',ARRAY['submitted_by','status','created_at'],ARRAY[0,0,3],false,NULL),
 ('marker_submissions_marker_idx',ARRAY['marker_id','created_at'],ARRAY[0,3],false,'marker_idISNOTNULL'),
 ('marker_submissions_one_pending_correction_per_marker_idx',ARRAY['game_id','marker_id','submitted_by'],ARRAY[0,0,0],true,'status=''pending''::textANDsubmission_type=''correction''::textANDmarker_idISNOTNULL')
),
expected_triggers(name,signature,bits,columns,condition) AS (VALUES
 ('deepmap_marker_submissions_touch_updated_at','private.deepmap_touch_submission_updated_at()',19,ARRAY[]::text[],NULL::text),
 ('deepmap_marker_submission_revision','private.deepmap_capture_submission_revision()',21,ARRAY['payload','note','correction_kind'],NULL),
 ('deepmap_materialize_submission_content','private.deepmap_materialize_submission_content()',17,ARRAY['status'],'old.statusisdistinctfromnew.status'),
 ('deepmap_notify_admin_submission_received','private.deepmap_notify_admin_submission_received()',5,ARRAY[]::text[],NULL),
 ('deepmap_notify_submission_review','private.deepmap_notify_submission_review()',17,ARRAY['status','marker_id','review_note','reviewed_by'],'old.statusisdistinctfromnew.status'),
 ('marker_submissions_autoapprove_moderator_insert','private.deepmap_autoapprove_moderator_submission()',5,ARRAY[]::text[],NULL),
 ('marker_submissions_autoapprove_moderator_update','private.deepmap_autoapprove_moderator_submission()',17,ARRAY['payload','note','correction_kind'],'new.status=''pending''::text')
),
touch AS (
 SELECT p.*,l.lanname,pg_catalog.replace(p.prosrc,pg_catalog.chr(13),'') AS body
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
 WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_touch_submission_updated_at()')
),
body_match AS (
 SELECT EXISTS (SELECT 1 FROM touch p CROSS JOIN source s WHERE p.body=s.expected_body) AS ok
),
policies AS (
 SELECT p.*,
 pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'[[:space:]()]','','g'),'public.','') AS qual,
 pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),'[[:space:]()]','','g'),'public.','') AS with_check
 FROM pg_catalog.pg_policy p WHERE p.polrelid=pg_catalog.to_regclass('public.marker_submissions')
),
expected_policies(name,command,qual,with_check) AS (VALUES
 ('marker_submissions_read_own_or_staff','r','submitted_by=SELECTauth.uidASuidANDNOTprivate.is_deepmap_bannedORprivate.can_moderate_deepmap',NULL),
 -- Round 10A supersedes the earlier insert policy: profile username is mandatory.
 ('marker_submissions_insert_own','a',NULL,'can_deepmap_interactANDsubmitted_by=SELECTauth.uidASuidANDstatus=''pending''::textANDreviewed_byISNULLANDreviewed_atISNULLANDreview_noteISNULLANDEXISTSSELECT1FROMprofilespWHEREp.id=SELECTauth.uidASuidANDNULLIFbtrimp.username,''''::textISNOTNULL'),
 ('marker_submissions_update_own_pending','w','NOTprivate.is_deepmap_bannedANDsubmitted_by=SELECTauth.uidASuidANDstatus=''pending''::text','NOTprivate.is_deepmap_bannedANDsubmitted_by=SELECTauth.uidASuidANDstatus=''pending''::text')
),
authenticated AS (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated'),
checks AS (
 SELECT 'table.rls.'||e.name AS check_name,EXISTS (SELECT 1 FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass(e.name)
 AND c.relkind='r' AND c.relrowsecurity) AS ok,'Ordinary table exists with RLS enabled' AS details FROM relations e
 UNION ALL SELECT 'visibility.full.'||name,ok,'Maintenance SELECT/schema USAGE and superuser/BYPASSRLS/owner without FORCE RLS required' FROM visibility
 UNION ALL SELECT 'schema.column.'||e.rel||'.'||e.name,EXISTS (SELECT 1 FROM attributes a
 WHERE a.attrelid=pg_catalog.to_regclass(e.rel) AND a.attname=e.name AND a.atttypid=pg_catalog.to_regtype(e.type_name)
 AND a.attnotnull=e.nn AND a.attidentity::text=e.identity_kind AND a.attgenerated=''
 AND a.atthasdef=(e.default_expr IS NOT NULL) AND a.default_expr IS NOT DISTINCT FROM e.default_expr),
 pg_catalog.format('%s; NOT NULL=%s identity=%s default=%s; no generated expression',e.type_name,e.nn,e.identity_kind,COALESCE(e.default_expr,'none')) FROM expected_columns e
 UNION ALL SELECT 'schema.exact_columns.'||e.rel,(SELECT count(*) FROM attributes WHERE attrelid=pg_catalog.to_regclass(e.rel))=e.expected_count
 AND NOT EXISTS (SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass(e.rel) AND NOT EXISTS (SELECT 1 FROM expected_columns c WHERE c.rel=e.rel AND c.name=a.attname)),
 'Exact column set; count='||e.expected_count FROM (VALUES ('public.marker_submissions',14),('private.marker_submission_revisions',7)) e(rel,expected_count)
 UNION ALL SELECT 'check.legacy.'||e.name,EXISTS (SELECT 1 FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass('public.marker_submissions')
 AND c.conname=e.name AND c.contype='c' AND c.convalidated
 AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(c.conbin,c.conrelid),'[[:space:]()]','','g')=pg_catalog.regexp_replace(e.expression,'[[:space:]()]','','g')),
 'Validated legacy expression: '||e.expression FROM expected_checks e
 UNION ALL SELECT 'check.legacy.exact_set',count(*)=4 AND bool_and(conname IN (SELECT name FROM expected_checks)),
 'Exactly four legacy CHECKs; actual='||count(*) FROM constraints WHERE conrelid=pg_catalog.to_regclass('public.marker_submissions') AND contype='c'
 UNION ALL SELECT 'key.'||e.rel||'.'||e.name,EXISTS (SELECT 1 FROM constraints c JOIN indexes i ON i.indexrelid=c.conindid
 WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND (e.name='revisions_unique' OR c.conname=e.name) AND c.contype::text=e.kind AND c.columns=e.columns
 AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred AND i.indrelid=c.conrelid
 AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive AND i.indexprs IS NULL AND i.indpred IS NULL
 AND i.indnatts=i.indnkeyatts AND i.columns=e.columns
 AND (e.kind<>'p' OR (SELECT count(*) FROM constraints q WHERE q.conrelid=c.conrelid AND q.contype='p')=1)),
 'Exact validated immediate key with UNIQUE valid/ready/live index, no predicate/expression/INCLUDE'
 FROM (VALUES ('public.marker_submissions','marker_submissions_pkey','p',ARRAY['id']),
 ('private.marker_submission_revisions','marker_submission_revisions_pkey','p',ARRAY['id']),
 ('private.marker_submission_revisions','revisions_unique','u',ARRAY['submission_id','revision_no'])) e(rel,name,kind,columns)
 UNION ALL SELECT 'fk.'||e.name,EXISTS (SELECT 1 FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND c.conname=e.name
 AND c.contype='f' AND c.confrelid=pg_catalog.to_regclass(e.parent) AND c.columns=e.columns AND c.parent_columns=ARRAY['id']::text[]
 AND c.confmatchtype='s' AND c.confupdtype='a' AND c.confdeltype='c' AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred),
 'MATCH SIMPLE, UPDATE NO ACTION / DELETE CASCADE, validated/immediate; exact source/parent columns'
 FROM (VALUES ('public.marker_submissions','marker_submissions_marker_id_fkey',ARRAY['marker_id'],'public.marcadores'),
 ('private.marker_submission_revisions','marker_submission_revisions_submission_id_fkey',ARRAY['submission_id'],'public.marker_submissions')) e(rel,name,columns,parent)
 UNION ALL SELECT 'fk.submissions.exact_legacy_set',count(*)=1 AND bool_and(conname='marker_submissions_marker_id_fkey'),
 'Only the legacy marker FK; actual='||count(*) FROM constraints WHERE conrelid=pg_catalog.to_regclass('public.marker_submissions') AND contype='f'
 UNION ALL SELECT 'index.legacy.'||e.name,EXISTS (SELECT 1 FROM indexes i JOIN pg_catalog.pg_class ic ON ic.oid=i.indexrelid
 JOIN pg_catalog.pg_am am ON am.oid=ic.relam WHERE i.indrelid=pg_catalog.to_regclass('public.marker_submissions') AND i.relname=e.name
 AND i.columns=e.columns AND i.options=e.options AND i.indisunique=e.is_unique AND i.indisvalid AND i.indisready AND i.indislive
 AND i.indexprs IS NULL AND i.indnatts=i.indnkeyatts AND i.predicate IS NOT DISTINCT FROM e.predicate AND am.amname='btree'),
 'Exact legacy key order/sort/null ordering, uniqueness and partial predicate; valid/ready/live; no expression/INCLUDE' FROM expected_indexes e
 UNION ALL SELECT 'policy.'||e.name,EXISTS (SELECT 1 FROM policies p CROSS JOIN authenticated r WHERE p.polname=e.name AND p.polcmd::text=e.command
 AND p.polpermissive AND p.polroles=ARRAY[r.oid]::oid[] AND p.qual IS NOT DISTINCT FROM e.qual AND p.with_check IS NOT DISTINCT FROM e.with_check
 -- Read is exactly (own AND not banned) OR staff; also verify the boolean AST grouping.
 AND (e.command<>'r' OR p.polqual::text ~ '^\{BOOLEXPR :boolop or :args \(\{BOOLEXPR :boolop and')),
 'Exact legacy command/authenticated role/clauses; final insert includes contributor profile username guard' FROM expected_policies e
 UNION ALL SELECT 'policy.exact_set',count(*)=3 AND bool_and(polname IN (SELECT name FROM expected_policies)),
 'Exactly the three known final policies; actual='||count(*) FROM policies
 UNION ALL SELECT 'acl.authenticated.table_select',EXISTS (SELECT 1 FROM authenticated r
 WHERE pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('public.marker_submissions'),'SELECT')),
 'Authenticated SELECT table'
 UNION ALL SELECT 'acl.authenticated.columns.'||e.privilege,EXISTS (SELECT 1 FROM authenticated)
 AND NOT EXISTS (SELECT 1 FROM attributes a CROSS JOIN authenticated r WHERE a.attrelid=pg_catalog.to_regclass('public.marker_submissions')
 AND pg_catalog.has_column_privilege(r.oid,a.attrelid,a.attnum,e.privilege) IS DISTINCT FROM (a.attname::text=ANY(e.allowed))),
 'Effective column grants exactly: '||array_to_string(e.allowed,',')
 FROM (VALUES ('INSERT',ARRAY['game_id','marker_id','submission_type','correction_kind','status','submitted_by','payload','note']),
 ('UPDATE',ARRAY['payload','note','correction_kind'])) e(privilege,allowed)
 UNION ALL SELECT 'acl.authenticated.no_other_table_writes',EXISTS (SELECT 1 FROM authenticated)
 AND NOT EXISTS (SELECT 1 FROM authenticated r CROSS JOIN (VALUES ('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER')) p(privilege)
 WHERE pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('public.marker_submissions'),p.privilege)),
 'No full-table DML/DDL-style grants; only approved column writes'
 UNION ALL SELECT 'acl.authenticated.identity_sequence',EXISTS (SELECT 1 FROM authenticated r JOIN pg_catalog.pg_class c
 ON c.oid=pg_catalog.to_regclass(pg_catalog.pg_get_serial_sequence('public.marker_submissions','id'))
 WHERE c.oid=pg_catalog.to_regclass('public.marker_submissions_id_seq') AND c.relkind='S'
 AND pg_catalog.has_sequence_privilege(r.oid,c.oid,'USAGE') AND pg_catalog.has_sequence_privilege(r.oid,c.oid,'SELECT')
 AND NOT pg_catalog.has_sequence_privilege(r.oid,c.oid,'UPDATE')),
 'Expected identity sequence: authenticated effective USAGE=true SELECT=true UPDATE=false'
 UNION ALL SELECT 'acl.anon.identity_sequence',EXISTS (SELECT 1 FROM pg_catalog.pg_roles r JOIN pg_catalog.pg_class c
 ON c.oid=pg_catalog.to_regclass(pg_catalog.pg_get_serial_sequence('public.marker_submissions','id'))
 WHERE r.rolname='anon' AND c.oid=pg_catalog.to_regclass('public.marker_submissions_id_seq') AND c.relkind='S'
 AND NOT pg_catalog.has_sequence_privilege(r.oid,c.oid,'USAGE')
 AND NOT pg_catalog.has_sequence_privilege(r.oid,c.oid,'SELECT')
 AND NOT pg_catalog.has_sequence_privilege(r.oid,c.oid,'UPDATE')),
 'Expected identity sequence: anon effective USAGE=false SELECT=false UPDATE=false'
 UNION ALL SELECT 'acl.public.identity_sequence',EXISTS (SELECT 1 FROM pg_catalog.pg_class c
 WHERE c.oid=pg_catalog.to_regclass(pg_catalog.pg_get_serial_sequence('public.marker_submissions','id'))
 AND c.oid=pg_catalog.to_regclass('public.marker_submissions_id_seq') AND c.relkind='S'
 AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('s',c.relowner))) a
 WHERE a.grantee=0 AND a.privilege_type IN ('USAGE','SELECT','UPDATE'))),
 'Expected identity sequence: PUBLIC USAGE=false SELECT=false UPDATE=false; owner/service_role ACL not constrained'
 UNION ALL SELECT 'acl.no_public_anon_column_writes',NOT EXISTS (SELECT 1 FROM attributes a
 CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) x LEFT JOIN pg_catalog.pg_roles r ON r.oid=x.grantee
 WHERE a.attrelid=pg_catalog.to_regclass('public.marker_submissions') AND (x.grantee=0 OR r.rolname='anon') AND x.privilege_type<>'SELECT')
 AND NOT EXISTS (SELECT 1 FROM attributes a JOIN pg_catalog.pg_roles r ON r.rolname='anon'
 WHERE a.attrelid=pg_catalog.to_regclass('public.marker_submissions')
 AND (pg_catalog.has_column_privilege(r.oid,a.attrelid,a.attnum,'INSERT') OR pg_catalog.has_column_privilege(r.oid,a.attrelid,a.attnum,'UPDATE')
 OR pg_catalog.has_column_privilege(r.oid,a.attrelid,a.attnum,'REFERENCES'))),
 'No direct PUBLIC/anon or inherited anon column write privileges'
 UNION ALL SELECT 'acl.no_public_anon_table_writes',NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
 CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
 LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE c.oid=pg_catalog.to_regclass('public.marker_submissions')
 AND (a.grantee=0 OR r.rolname='anon') AND a.privilege_type<>'SELECT')
 AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r CROSS JOIN (VALUES ('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER')) p(privilege)
 WHERE r.rolname='anon' AND pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('public.marker_submissions'),p.privilege)),
 'No direct PUBLIC/anon or inherited anon full-table writes'
 UNION ALL SELECT 'function.touch.exact_body',ok,'Complete B5a prosrc equality; only CRLF/LF normalized, no keyword-only test' FROM body_match
 UNION ALL SELECT 'function.touch.guard.'||e.name,ok,e.details FROM body_match CROSS JOIN (VALUES
 ('uuid_only','Exact body: real NEW/OLD difference, equal after removing game_uuid only, preserves OLD.updated_at then RETURN'),
 ('legacy_noop','Exact body: NEW=OLD fails real-difference guard; legacy now() assignment remains'),
 ('legacy_fields','Any difference in all 14 legacy fields, including updated_at, prevents bypass'),
 ('pre_expand','JSONB subtraction of absent key is safe; no direct NEW/OLD.game_uuid references; pre-expand updates remain legacy')) e(name,details)
 UNION ALL SELECT 'function.touch.attributes',EXISTS (SELECT 1 FROM touch p WHERE p.pronargs=0 AND p.prokind='f'
 AND p.prorettype='trigger'::pg_catalog.regtype AND p.lanname='plpgsql' AND NOT p.prosecdef AND NOT p.proretset
 AND p.proconfig=ARRAY['search_path=""']::text[] AND p.provolatile='v' AND p.proparallel='u'
 AND NOT p.proleakproof AND NOT p.proisstrict AND p.procost=100 AND p.prorows=0),
 'trigger(), zero args, INVOKER, empty search_path, VOLATILE/UNSAFE, non-leakproof/non-strict, COST 100, rows 0'
 UNION ALL SELECT 'function.touch.no_overloads',count(*)=1,'Exactly one private touch function; actual='||count(*)
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname='deepmap_touch_submission_updated_at'
 UNION ALL SELECT 'function.touch.legacy_acl',EXISTS (SELECT 1 FROM touch)
 AND NOT EXISTS (SELECT 1 FROM touch p CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
 LEFT JOIN pg_catalog.pg_roles r ON r.oid=a.grantee WHERE a.privilege_type='EXECUTE' AND (a.grantee=0 OR r.rolname IN ('anon','authenticated'))),
 'Historical revoke PUBLIC/anon/authenticated preserved; no assumed owner/OID or invented service_role restriction'
 UNION ALL SELECT 'trigger.'||e.name,EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
 WHERE t.tgrelid=pg_catalog.to_regclass('public.marker_submissions') AND t.tgname=e.name AND t.tgfoid=pg_catalog.to_regprocedure(e.signature)
 AND t.tgtype=e.bits AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgnargs=0
 AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(t.tgattr::smallint[]) WITH ORDINALITY k(num,ord)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=t.tgrelid AND a.attnum=k.num ORDER BY k.ord)=e.columns
 AND pg_catalog.lower(pg_catalog.regexp_replace(pg_catalog.substring(pg_catalog.pg_get_triggerdef(t.oid,true),' WHEN [(](.*)[)] EXECUTE FUNCTION '),
 '[[:space:]()]','','g')) IS NOT DISTINCT FROM e.condition),
 'Exact timing/events/row bits, target, UPDATE OF order and WHEN; origin enabled, no args' FROM expected_triggers e
 UNION ALL SELECT 'trigger.exact_user_set',count(*)=7 AND bool_and(tgname IN (SELECT name FROM expected_triggers)),
 'Exactly seven user triggers; internal FK triggers ignored; actual='||count(*) FROM pg_catalog.pg_trigger
 WHERE tgrelid=pg_catalog.to_regclass('public.marker_submissions') AND NOT tgisinternal
 UNION ALL SELECT 'function.side_effect.'||e.signature,EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
 WHERE p.oid=pg_catalog.to_regprocedure(e.signature) AND p.prokind='f'
 AND (SELECT count(*) FROM pg_catalog.pg_proc q WHERE q.pronamespace=p.pronamespace AND q.proname=p.proname)=1),
 'Required exact signature exists with no overloads; never invoked; historical body preservation requires B5a snapshot'
 FROM (VALUES ('private.deepmap_capture_submission_revision()'),('private.deepmap_materialize_submission_content()'),
 ('private.deepmap_notify_admin_submission_received()'),('private.deepmap_notify_submission_review()'),
 ('private.deepmap_autoapprove_moderator_submission()'),('private.deepmap_replace_quick_marker_content(bigint,jsonb)'),
 ('public.review_marker_submission(bigint,text,text)'),('public.review_marker_submission_v2(bigint,text,text,jsonb)')) e(signature)
 UNION ALL SELECT 'data.submissions.duplicate_ids',count(*)=0,'Duplicate id groups='||count(*)
 FROM (SELECT id FROM public.marker_submissions GROUP BY id HAVING count(*)>1) d
 UNION ALL SELECT 'data.submissions.required_non_nulls',count(*)=0,'Rows with NULL id/game_id/updated_at='||count(*)
 FROM public.marker_submissions WHERE id IS NULL OR game_id IS NULL OR updated_at IS NULL
 UNION ALL SELECT 'data.submissions.marker_orphans',count(*)=0,'Non-NULL marker_id without legacy parent='||count(*)
 FROM public.marker_submissions s WHERE s.marker_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.marcadores m WHERE m.id=s.marker_id)
 UNION ALL SELECT 'dependency.b4b.column.'||e.name,EXISTS (SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass('public.marcadores')
 AND a.attname=e.name AND a.atttypid='uuid'::pg_catalog.regtype AND a.attnotnull),
 'B4b UUID NOT NULL column' FROM (VALUES ('game_uuid'),('layer_uuid')) e(name)
 UNION ALL SELECT 'dependency.b4b.resolver',pg_catalog.to_regprocedure('private.deepmap_resolve_marker_identity()') IS NOT NULL,
 'B4b marker resolver exists; no repetition of full B4b verifier'
 UNION ALL SELECT 'dependency.b4b.fk.'||e.name,EXISTS (SELECT 1 FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass('public.marcadores')
 AND c.conname=e.name AND c.contype='f' AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred),
 'B4b FK validated/non-deferrable' FROM (VALUES ('marcadores_legacy_game_uuid_fk'),('marcadores_legacy_uuid_layer_fk')) e(name)
 UNION ALL SELECT 'scope.pre_b5b_b6.no_uuid_columns.'||e.rel,pg_catalog.to_regclass(e.rel) IS NOT NULL
 AND NOT EXISTS (SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass(e.rel)
 AND a.attname IN ('game_uuid','layer_uuid','category_uuid','group_uuid','game_map_id')),
 'No premature identity columns' FROM (VALUES ('public.marker_submissions'),('private.marker_submission_revisions'),('public.user_notifications')) e(rel)
 UNION ALL SELECT 'scope.pre_b5b_b6.no_identity_resolvers',count(*)=0,'Premature submission/notification identity functions='||count(*)
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('private','public') AND (p.proname='deepmap_resolve_submission_identity' OR p.proname ~ '^deepmap_resolve_.*(submission|notification).*identity$')
 UNION ALL SELECT 'scope.pre_b6.no_marker_extra_uuid_identity',pg_catalog.to_regclass('public.marcadores') IS NOT NULL
 AND NOT EXISTS (SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass('public.marcadores')
 AND a.attname IN ('category_uuid','group_uuid','game_map_id')),
 'No later-phase marker category/group/map UUID columns; B4b game/layer UUIDs remain expected'
 UNION ALL SELECT 'scope.pre_b5b_b6.no_uuid_fks',count(*)=0,'Premature UUID FKs='||count(*) FROM constraints
 WHERE conrelid IN (pg_catalog.to_regclass('public.marker_submissions'),pg_catalog.to_regclass('private.marker_submission_revisions'),pg_catalog.to_regclass('public.user_notifications'))
 AND contype='f' AND (conname ~* 'uuid' OR columns && ARRAY['game_uuid','layer_uuid','category_uuid','group_uuid','game_map_id'])
 UNION ALL SELECT 'scope.pre_b5b_b6.no_uuid_indexes',count(*)=0,'Premature UUID indexes='||count(*) FROM indexes
 WHERE indrelid IN (pg_catalog.to_regclass('public.marker_submissions'),pg_catalog.to_regclass('private.marker_submission_revisions'),pg_catalog.to_regclass('public.user_notifications'))
 AND (relname ~* 'uuid' OR columns && ARRAY['game_uuid','layer_uuid','category_uuid','group_uuid','game_map_id']
 OR COALESCE(pg_catalog.pg_get_expr(indexprs,indrelid),'') ~ '(game_uuid|layer_uuid|category_uuid|group_uuid)'
 OR COALESCE(pg_catalog.pg_get_expr(indpred,indrelid),'') ~ '(game_uuid|layer_uuid|category_uuid|group_uuid)')
)
SELECT check_name,
 CASE WHEN ok IS TRUE AND (check_name NOT LIKE 'data.%' OR (SELECT bool_and(ok) FROM visibility)) THEN 'PASS' ELSE 'FAIL' END AS status,
 details || CASE WHEN check_name LIKE 'data.%' AND NOT (SELECT bool_and(ok) FROM visibility)
 THEN '; INVALID DATA RESULT: incomplete maintenance visibility' ELSE '' END AS details
FROM checks ORDER BY check_name;
