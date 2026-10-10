-- DeepMap post-B5b / pre-B6. Run manually AFTER applying the approved B5b migration.
-- ONE read-only WITH ... SELECT. Function literals below are inert, never invoked.
-- Errors (missing relations/permissions) invalidate verification; never treat them as PASS.
-- No historical PASS: before/after legacy and related-row snapshots belong to B5b.
-- This verifier cannot detect temporary changes restored before its execution.
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
$expected_body$,pg_catalog.chr(13)||pg_catalog.chr(10),pg_catalog.chr(10)) AS expected_body
),
relations(name) AS (VALUES ('public.games'),('private.game_legacy_identifiers'),('public.marcadores'),
 ('public.marker_submissions'),('private.marker_submission_revisions'),('public.user_notifications'),
 ('private.marker_editor_audit'),('public.marker_images'),('public.marker_sections'),('public.marker_section_rows')),
visibility AS (
 SELECT e.name,EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.rolname=CURRENT_USER
 WHERE c.oid=pg_catalog.to_regclass(e.name) AND c.relkind='r' AND c.relrowsecurity
 AND pg_catalog.has_table_privilege(c.oid,'SELECT') AND pg_catalog.has_schema_privilege(c.relnamespace,'USAGE')
 AND (r.rolsuper OR r.rolbypassrls OR (r.oid=c.relowner AND NOT c.relforcerowsecurity))) AS ok
 FROM relations e
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
 ('public.marker_submissions','game_uuid','uuid',true,'',NULL),
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
 SELECT i.*,c.relname,c.relam AS access_method,
 ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(i.indkey::smallint[]) WITH ORDINALITY k(num,ord)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.num ORDER BY k.ord) AS columns,
 ARRAY(SELECT k.opt::integer FROM pg_catalog.unnest(i.indoption::smallint[]) WITH ORDINALITY k(opt,ord) ORDER BY k.ord) AS options,
 pg_catalog.regexp_replace(pg_catalog.pg_get_expr(i.indpred,i.indrelid),'[[:space:]()]','','g') AS predicate
 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid
),
expected_indexes(name,columns,options,is_unique,predicate) AS (VALUES
 ('marker_submissions_pkey',ARRAY['id'],ARRAY[0],true,NULL),
 ('marker_submissions_game_status_idx',ARRAY['game_id','status','created_at'],ARRAY[0,0,3],false,NULL),
 ('marker_submissions_user_status_idx',ARRAY['submitted_by','status','created_at'],ARRAY[0,0,3],false,NULL),
 ('marker_submissions_marker_idx',ARRAY['marker_id','created_at'],ARRAY[0,3],false,'marker_idISNOTNULL'),
 ('marker_submissions_one_pending_correction_per_marker_idx',ARRAY['game_id','marker_id','submitted_by'],ARRAY[0,0,0],true,'status=''pending''::textANDsubmission_type=''correction''::textANDmarker_idISNOTNULL')
),
expected_triggers(name,signature,bits,columns,condition) AS (VALUES
 ('deepmap_marker_submissions_identity','private.deepmap_resolve_submission_identity()',23,ARRAY[]::text[],NULL::text),
 ('deepmap_marker_submissions_touch_updated_at','private.deepmap_touch_submission_updated_at()',19,ARRAY[]::text[],NULL::text),
 ('deepmap_marker_submission_revision','private.deepmap_capture_submission_revision()',21,ARRAY['payload','note','correction_kind'],NULL),
 ('deepmap_materialize_submission_content','private.deepmap_materialize_submission_content()',17,ARRAY['status'],'old.statusisdistinctfromnew.status'),
 ('deepmap_notify_admin_submission_received','private.deepmap_notify_admin_submission_received()',5,ARRAY[]::text[],NULL),
 ('deepmap_notify_submission_review','private.deepmap_notify_submission_review()',17,ARRAY['status','marker_id','review_note','reviewed_by'],'old.statusisdistinctfromnew.status'),
 ('marker_submissions_autoapprove_moderator_insert','private.deepmap_autoapprove_moderator_submission()',5,ARRAY[]::text[],NULL),
 ('marker_submissions_autoapprove_moderator_update','private.deepmap_autoapprove_moderator_submission()',17,ARRAY['payload','note','correction_kind'],'new.status=''pending''::text')
),
touch AS (
 SELECT p.*,l.lanname,pg_catalog.replace(p.prosrc,pg_catalog.chr(13)||pg_catalog.chr(10),pg_catalog.chr(10)) AS body
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
api_roles AS (SELECT oid,rolname FROM pg_catalog.pg_roles WHERE rolname IN ('anon','authenticated','service_role')),
service AS (
 SELECT r.oid,pg_catalog.has_any_column_privilege(r.oid,pg_catalog.to_regclass('public.marker_submissions'),'INSERT')
 OR pg_catalog.has_any_column_privilege(r.oid,pg_catalog.to_regclass('public.marker_submissions'),'UPDATE') AS writer
 FROM api_roles r WHERE r.rolname='service_role'
),
new_sources AS (
 SELECT pg_catalog.replace($expected_helper$
DECLARE
    v_game uuid;
BEGIN
    IF p_identifier IS NULL OR pg_catalog.btrim(p_identifier) = '' THEN
        RAISE EXCEPTION 'B5B_GAME_IDENTIFIER_REQUIRED';
    END IF;
    BEGIN
        SELECT i.game_id INTO STRICT v_game
        FROM private.game_legacy_identifiers AS i
        WHERE i.legacy_identifier = p_identifier;
    EXCEPTION
        WHEN no_data_found THEN RAISE EXCEPTION 'B5B_UNKNOWN_GAME_IDENTIFIER';
        WHEN too_many_rows THEN RAISE EXCEPTION 'B5B_AMBIGUOUS_GAME_IDENTIFIER';
    END;
    IF v_game IS NULL THEN RAISE EXCEPTION 'B5B_INVALID_GAME_MAPPING'; END IF;
    RETURN v_game;
END;
$expected_helper$,pg_catalog.chr(13)||pg_catalog.chr(10),pg_catalog.chr(10)) AS helper_body,
 pg_catalog.replace($expected_resolver$
DECLARE
    v_game uuid;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.game_uuid IS NULL THEN
            IF (pg_catalog.to_jsonb(NEW) - 'game_uuid') IS DISTINCT FROM
               (pg_catalog.to_jsonb(OLD) - 'game_uuid') THEN
                RAISE EXCEPTION 'B5B_HYDRATION_MUST_PRESERVE_ALL_LEGACY_FIELDS';
            END IF;
            v_game := private.deepmap_game_uuid_from_legacy_identifier(OLD.game_id);
            IF NEW.game_uuid IS DISTINCT FROM v_game THEN
                RAISE EXCEPTION 'B5B_HYDRATION_REQUIRES_EXACT_GAME_UUID';
            END IF;
            RETURN NEW;
        END IF;
        IF NEW.game_id IS DISTINCT FROM OLD.game_id OR
           NEW.game_uuid IS DISTINCT FROM OLD.game_uuid THEN
            RAISE EXCEPTION 'B5B_SUBMISSION_GAME_IDENTITY_IS_IMMUTABLE';
        END IF;
    ELSIF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'B5B_UNSUPPORTED_SUBMISSION_TRIGGER_EVENT';
    END IF;
    v_game := private.deepmap_game_uuid_from_legacy_identifier(NEW.game_id);
    IF NEW.game_uuid IS NULL THEN
        NEW.game_uuid := v_game;
    ELSIF NEW.game_uuid IS DISTINCT FROM v_game THEN
        RAISE EXCEPTION 'B5B_SUBMISSION_GAME_MAPPING_MISMATCH';
    END IF;
    -- marker_id remains mutable. Declarative FKs enforce coherence without RLS reads.
    RETURN NEW;
END;
$expected_resolver$,pg_catalog.chr(13)||pg_catalog.chr(10),pg_catalog.chr(10)) AS resolver_body
),
helper AS (
 SELECT p.*,l.lanname,pg_catalog.replace(p.prosrc,pg_catalog.chr(13)||pg_catalog.chr(10),pg_catalog.chr(10)) AS body
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
 WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_game_uuid_from_legacy_identifier(text)')
),
resolver AS (
 SELECT p.*,l.lanname,pg_catalog.replace(p.prosrc,pg_catalog.chr(13)||pg_catalog.chr(10),pg_catalog.chr(10)) AS body
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
 WHERE p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_submission_identity()')
),
new_body_matches AS (
 SELECT EXISTS (SELECT 1 FROM helper p CROSS JOIN new_sources s WHERE p.body=s.helper_body) AS helper_ok,
 EXISTS (SELECT 1 FROM resolver p CROSS JOIN new_sources s WHERE p.body=s.resolver_body) AS resolver_ok
),
helper_acl AS (
 SELECT p.oid,p.proowner,a.* FROM helper p
 CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
),
resolver_acl AS (
 SELECT p.oid,p.proowner,a.* FROM resolver p
 CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
),
expected_identity_fks(rel,name,columns,parent,parent_columns,delete_action) AS (VALUES
 ('public.marker_submissions','marker_submissions_legacy_game_uuid_fk',ARRAY['game_id','game_uuid'],
  'private.game_legacy_identifiers',ARRAY['legacy_identifier','game_id'],'r'),
 ('public.marker_submissions','marker_submissions_marker_game_uuid_fk',ARRAY['marker_id','game_id','game_uuid'],
  'public.marcadores',ARRAY['id','game_id','game_uuid'],'c'),
 ('private.game_legacy_identifiers','game_legacy_identifiers_game_id_fkey',ARRAY['game_id'],
  'public.games',ARRAY['id'],'r')
),
expected_side_bodies(signature,body_digest) AS (VALUES
        ('public.cancel_marker_submission(bigint)','32db8c8d8de026e6ef2220c752544a06'),
        ('private.deepmap_stamp_marker_audit()','233b6905e98f7b74ca01068488bb57c0'),
        ('private.deepmap_capture_submission_revision()','d3ff5f69ceb1cd15cf09cf72b26f55ce'),
        ('private.deepmap_autoapprove_moderator_submission()','9c7c5a38258ea603f205fcddb5b48861'),
        ('private.deepmap_notify_admin_submission_received()','c0ec4567cd4efa473e393a5e1e3f6016'),
        ('private.deepmap_notify_submission_review()','a423d83f1c880b7fcb81217d99e8c96d'),
        ('private.deepmap_materialize_submission_content()','09fdd39ed4b0565d21b1f51e6494c4eb'),
        ('private.deepmap_replace_quick_marker_content(bigint,jsonb)','74c611df1824cd9e78d76b98ca6f9920'),
        ('public.review_marker_submission(bigint,text,text)','c2d611f6339f023f3c2b43891f56af29'),
        ('public.review_marker_submission_v2(bigint,text,text,jsonb)','10327cfdf171ec2e3ba17380a909d644')
),
mapping_policies AS (
 SELECT p.*,
 pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'[[:space:]()]','','g'),'public.','') AS qual,
 pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),'[[:space:]()]','','g'),'public.','') AS with_check
 FROM pg_catalog.pg_policy p WHERE p.polrelid=pg_catalog.to_regclass('private.game_legacy_identifiers')
),
expected_mapping_policies(name,command,qual,with_check) AS (VALUES
 ('game_legacy_identifiers_admin_read','r','SELECTget_deepmap_roleASget_deepmap_role=''admin''::text',NULL),
 ('game_legacy_identifiers_admin_insert','a',NULL,'SELECTget_deepmap_roleASget_deepmap_role=''admin''::text')
),
mapping_acl AS (
 SELECT c.relowner,a.* FROM pg_catalog.pg_class c
 CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
 WHERE c.oid=pg_catalog.to_regclass('private.game_legacy_identifiers')
),
submission_data AS MATERIALIZED (
 SELECT s.id,s.marker_id,s.submission_type,
 (s.id IS NULL OR s.game_id IS NULL OR s.game_uuid IS NULL OR s.submission_type IS NULL OR s.status IS NULL
  OR s.submitted_by IS NULL OR s.payload IS NULL OR s.created_at IS NULL OR s.updated_at IS NULL) AS required_null,
 s.game_uuid IS NULL AS game_uuid_null,
 (SELECT pg_catalog.count(*) FROM private.game_legacy_identifiers i WHERE i.legacy_identifier=s.game_id) AS mapping_count,
 (SELECT pg_catalog.count(*) FROM private.game_legacy_identifiers i WHERE i.legacy_identifier=s.game_id AND i.game_id=s.game_uuid) AS identity_count,
 (SELECT pg_catalog.count(*) FROM private.game_legacy_identifiers i JOIN public.games g ON g.id=i.game_id
  WHERE i.legacy_identifier=s.game_id AND i.game_id=s.game_uuid) AS game_parent_count,
 CASE WHEN s.marker_id IS NULL THEN NULL ELSE (SELECT pg_catalog.count(*) FROM public.marcadores m
  WHERE m.id=s.marker_id AND m.game_id=s.game_id AND m.game_uuid=s.game_uuid) END AS marker_identity_count
 FROM public.marker_submissions s
),
data_stats AS (
 SELECT pg_catalog.count(*) AS row_count,
 pg_catalog.count(*) FILTER (WHERE required_null) AS required_null_count,
 pg_catalog.count(*) FILTER (WHERE game_uuid_null) AS uuid_null_count,
 pg_catalog.count(*) FILTER (WHERE mapping_count=0) AS unknown_mapping_count,
 pg_catalog.count(*) FILTER (WHERE mapping_count>1) AS ambiguous_mapping_count,
 pg_catalog.count(*) FILTER (WHERE identity_count<>1) AS identity_mismatch_count,
 pg_catalog.count(*) FILTER (WHERE game_parent_count<>1) AS game_parent_mismatch_count,
 pg_catalog.count(*) FILTER (WHERE marker_id IS NOT NULL AND marker_identity_count<>1) AS marker_mismatch_count,
 pg_catalog.count(*) FILTER (WHERE marker_id IS NULL AND submission_type='create') AS unmaterialized_create_count
 FROM submission_data
),
checks AS (
 SELECT 'table.rls.'||e.name AS check_name,EXISTS (SELECT 1 FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass(e.name)
 AND c.relkind='r' AND c.relrowsecurity) AS ok,'Ordinary table exists with RLS enabled' AS details FROM relations e
 UNION ALL SELECT 'visibility.full.'||name,ok,'Maintenance SELECT/schema USAGE and superuser/BYPASSRLS/owner without FORCE RLS required' FROM visibility
 UNION ALL SELECT 'schema.column.'||e.rel||'.'||e.name,EXISTS (SELECT 1 FROM attributes a
 WHERE a.attrelid=pg_catalog.to_regclass(e.rel) AND a.attname=e.name AND a.atttypid=pg_catalog.to_regtype(e.type_name)
 AND a.attnotnull=e.nn AND a.attidentity::text=e.identity_kind AND a.attgenerated=''
 AND a.atthasdef=(e.default_expr IS NOT NULL) AND a.default_expr IS NOT DISTINCT FROM e.default_expr),
 pg_catalog.format('%s; NOT NULL=%s identity=%s default=%s; no generated expression',e.type_name,e.nn,e.identity_kind,COALESCE(e.default_expr,'none')) FROM expected_columns e
 UNION ALL SELECT 'schema.exact_columns.'||e.rel,(SELECT pg_catalog.count(*) FROM attributes WHERE attrelid=pg_catalog.to_regclass(e.rel))=e.expected_count
 AND NOT EXISTS (SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass(e.rel) AND NOT EXISTS (SELECT 1 FROM expected_columns c WHERE c.rel=e.rel AND c.name=a.attname)),
 'Exact column set; count='||e.expected_count FROM (VALUES ('public.marker_submissions',15),('private.marker_submission_revisions',7)) e(rel,expected_count)
 UNION ALL SELECT 'check.legacy.'||e.name,EXISTS (SELECT 1 FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass('public.marker_submissions')
 AND c.conname=e.name AND c.contype='c' AND c.convalidated
 AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(c.conbin,c.conrelid),'[[:space:]()]','','g')=pg_catalog.regexp_replace(e.expression,'[[:space:]()]','','g')),
 'Validated legacy expression: '||e.expression FROM expected_checks e
 UNION ALL SELECT 'check.legacy.exact_set',pg_catalog.count(*)=4 AND pg_catalog.bool_and(conname IN (SELECT name FROM expected_checks)),
 'Exactly four legacy CHECKs; actual='||pg_catalog.count(*) FROM constraints WHERE conrelid=pg_catalog.to_regclass('public.marker_submissions') AND contype='c'
 UNION ALL SELECT 'key.'||e.rel||'.'||e.name,EXISTS (SELECT 1 FROM constraints c JOIN indexes i ON i.indexrelid=c.conindid
 WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND (e.name='revisions_unique' OR c.conname=e.name) AND c.contype::text=e.kind AND c.columns=e.columns
 AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred AND i.indrelid=c.conrelid
 AND i.indisunique AND i.indimmediate AND i.indisvalid AND i.indisready AND i.indislive AND i.indexprs IS NULL AND i.indpred IS NULL
 AND i.access_method=(SELECT oid FROM pg_catalog.pg_am WHERE amname='btree')
 AND i.indnatts=i.indnkeyatts AND i.indnkeyatts=pg_catalog.cardinality(e.columns) AND i.columns=e.columns
 AND (e.kind<>'p' OR (SELECT pg_catalog.count(*) FROM constraints q WHERE q.conrelid=c.conrelid AND q.contype='p')=1)),
 'Exact validated immediate key with UNIQUE valid/ready/live index, no predicate/expression/INCLUDE'
 FROM (VALUES ('public.marker_submissions','marker_submissions_pkey','p',ARRAY['id']),
 ('public.marcadores','marcadores_pkey','p',ARRAY['id']),
 ('public.marcadores','marcadores_id_game_identity_unique','u',ARRAY['id','game_id','game_uuid']),
 ('private.game_legacy_identifiers','game_legacy_identifiers_identifier_unique','u',ARRAY['legacy_identifier']),
 ('private.game_legacy_identifiers','game_legacy_identifiers_identifier_game_unique','u',ARRAY['legacy_identifier','game_id']),
 ('public.games','games_pkey','p',ARRAY['id']),
 ('private.marker_submission_revisions','marker_submission_revisions_pkey','p',ARRAY['id']),
 ('private.marker_submission_revisions','revisions_unique','u',ARRAY['submission_id','revision_no'])) e(rel,name,kind,columns)
 UNION ALL SELECT 'fk.'||e.name,EXISTS (SELECT 1 FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND c.conname=e.name
 AND c.contype='f' AND c.confrelid=pg_catalog.to_regclass(e.parent) AND c.columns=e.columns AND c.parent_columns=ARRAY['id']::text[]
 AND c.confmatchtype='s' AND c.confupdtype='a' AND c.confdeltype='c' AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred),
 'MATCH SIMPLE, UPDATE NO ACTION / DELETE CASCADE, validated/immediate; exact source/parent columns'
 FROM (VALUES ('public.marker_submissions','marker_submissions_marker_id_fkey',ARRAY['marker_id'],'public.marcadores'),
 ('private.marker_submission_revisions','marker_submission_revisions_submission_id_fkey',ARRAY['submission_id'],'public.marker_submissions')) e(rel,name,columns,parent)
 UNION ALL SELECT 'fk.submissions.exact_set',pg_catalog.count(*)=3 AND pg_catalog.bool_and(conname IN ('marker_submissions_marker_id_fkey','marker_submissions_legacy_game_uuid_fk','marker_submissions_marker_game_uuid_fk')),
 'Exactly legacy marker, game mapping and composite marker identity FKs; actual='||pg_catalog.count(*) FROM constraints WHERE conrelid=pg_catalog.to_regclass('public.marker_submissions') AND contype='f'
 UNION ALL SELECT 'index.legacy.'||e.name,EXISTS (SELECT 1 FROM indexes i JOIN pg_catalog.pg_class ic ON ic.oid=i.indexrelid
 JOIN pg_catalog.pg_am am ON am.oid=ic.relam WHERE i.indrelid=pg_catalog.to_regclass('public.marker_submissions') AND i.relname=e.name
 AND i.columns=e.columns AND i.options=e.options AND i.indisunique=e.is_unique AND i.indisvalid AND i.indisready AND i.indislive
 AND i.indexprs IS NULL AND i.indnatts=i.indnkeyatts AND i.indnkeyatts=pg_catalog.cardinality(e.columns)
 AND i.indimmediate AND i.predicate IS NOT DISTINCT FROM e.predicate AND am.amname='btree'
 AND NOT EXISTS (SELECT 1 FROM pg_catalog.unnest(i.indclass::oid[]) k(opclass)
 JOIN pg_catalog.pg_opclass op ON op.oid=k.opclass WHERE NOT op.opcdefault OR op.opcnamespace<>'pg_catalog'::pg_catalog.regnamespace)
 AND ARRAY(SELECT k.coll FROM pg_catalog.unnest(i.indcollation::oid[]) WITH ORDINALITY k(coll,ord) ORDER BY k.ord)
 =ARRAY(SELECT a.attcollation FROM pg_catalog.unnest(i.indkey::smallint[]) WITH ORDINALITY k(num,ord)
 JOIN pg_catalog.pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.num ORDER BY k.ord)),
 'Exact legacy key order/sort/null ordering, uniqueness and partial predicate; valid/ready/live; no expression/INCLUDE' FROM expected_indexes e
 UNION ALL SELECT 'policy.'||e.name,EXISTS (SELECT 1 FROM policies p CROSS JOIN authenticated r WHERE p.polname=e.name AND p.polcmd::text=e.command
 AND p.polpermissive AND p.polroles=ARRAY[r.oid]::oid[] AND p.qual IS NOT DISTINCT FROM e.qual AND p.with_check IS NOT DISTINCT FROM e.with_check
 -- Read is exactly (own AND not banned) OR staff; also verify the boolean AST grouping.
 AND (e.command<>'r' OR p.polqual::text ~ '^\{BOOLEXPR :boolop or :args \(\{BOOLEXPR :boolop and')),
 'Exact legacy command/authenticated role/clauses; final insert includes contributor profile username guard' FROM expected_policies e
 UNION ALL SELECT 'policy.exact_set',pg_catalog.count(*)=3 AND pg_catalog.bool_and(polname IN (SELECT name FROM expected_policies)),
 'Exactly the three known final policies; actual='||pg_catalog.count(*) FROM policies
 UNION ALL SELECT 'acl.authenticated.table_select',EXISTS (SELECT 1 FROM authenticated r
 WHERE pg_catalog.has_table_privilege(r.oid,pg_catalog.to_regclass('public.marker_submissions'),'SELECT')),
 'Authenticated SELECT table'
 UNION ALL SELECT 'acl.authenticated.columns.'||e.privilege,EXISTS (SELECT 1 FROM authenticated)
 AND NOT EXISTS (SELECT 1 FROM attributes a CROSS JOIN authenticated r WHERE a.attrelid=pg_catalog.to_regclass('public.marker_submissions')
 AND pg_catalog.has_column_privilege(r.oid,a.attrelid,a.attnum,e.privilege) IS DISTINCT FROM (a.attname::text=ANY(e.allowed))),
 'Effective column grants exactly: '||pg_catalog.array_to_string(e.allowed,',')
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
 AND p.proargtypes=''::pg_catalog.oidvector AND p.provariadic=0 AND p.pronargdefaults=0
 AND p.proargdefaults IS NULL AND p.proargmodes IS NULL AND p.proallargtypes IS NULL
 AND NOT p.proleakproof AND NOT p.proisstrict AND p.procost=100 AND p.prorows=0),
 'trigger(), zero args, INVOKER, empty search_path, VOLATILE/UNSAFE, non-leakproof/non-strict, COST 100, rows 0'
 UNION ALL SELECT 'function.touch.no_overloads',pg_catalog.count(*)=1,'Exactly one private touch function; actual='||pg_catalog.count(*)
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
 UNION ALL SELECT 'trigger.exact_user_set',pg_catalog.count(*)=8 AND pg_catalog.bool_and(tgname IN (SELECT name FROM expected_triggers)),
 'Exactly eight user triggers; internal FK triggers ignored; actual='||pg_catalog.count(*) FROM pg_catalog.pg_trigger
 WHERE tgrelid=pg_catalog.to_regclass('public.marker_submissions') AND NOT tgisinternal
 UNION ALL SELECT 'function.side_effect.'||e.signature,EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
 WHERE p.oid=pg_catalog.to_regprocedure(e.signature) AND p.prokind='f'
 AND (SELECT pg_catalog.count(*) FROM pg_catalog.pg_proc q WHERE q.pronamespace=p.pronamespace AND q.proname=p.proname)=1),
 'Required exact signature exists with no overloads; never invoked; historical preservation requires B5b snapshots; body digests are checked separately'
 FROM (VALUES ('public.cancel_marker_submission(bigint)'),('private.deepmap_stamp_marker_audit()'),('private.deepmap_capture_submission_revision()'),('private.deepmap_materialize_submission_content()'),
 ('private.deepmap_notify_admin_submission_received()'),('private.deepmap_notify_submission_review()'),
 ('private.deepmap_autoapprove_moderator_submission()'),('private.deepmap_replace_quick_marker_content(bigint,jsonb)'),
 ('public.review_marker_submission(bigint,text,text)'),('public.review_marker_submission_v2(bigint,text,text,jsonb)')) e(signature)
 UNION ALL SELECT 'data.submissions.duplicate_ids',pg_catalog.count(*)=0,'Duplicate id groups='||pg_catalog.count(*)
 FROM (SELECT id FROM public.marker_submissions GROUP BY id HAVING pg_catalog.count(*)>1) d
 UNION ALL SELECT 'data.submissions.required_non_nulls',pg_catalog.count(*)=0,'Rows with NULL in any required submission field='||pg_catalog.count(*)
 FROM public.marker_submissions WHERE id IS NULL OR game_id IS NULL OR game_uuid IS NULL OR submission_type IS NULL OR status IS NULL
 OR submitted_by IS NULL OR payload IS NULL OR created_at IS NULL OR updated_at IS NULL
 UNION ALL SELECT 'data.submissions.marker_orphans',pg_catalog.count(*)=0,'Non-NULL marker_id without legacy parent='||pg_catalog.count(*)
 FROM public.marker_submissions s WHERE s.marker_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.marcadores m WHERE m.id=s.marker_id)
 UNION ALL SELECT 'dependency.b4b.column.'||e.name,EXISTS (SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass('public.marcadores')
 AND a.attname=e.name AND a.atttypid='uuid'::pg_catalog.regtype AND a.attnotnull),
 'B4b UUID NOT NULL column' FROM (VALUES ('game_uuid'),('layer_uuid')) e(name)
 UNION ALL SELECT 'dependency.b4b.resolver',pg_catalog.to_regprocedure('private.deepmap_resolve_marker_identity()') IS NOT NULL,
 'B4b marker resolver exists; no repetition of full B4b verifier'
 UNION ALL SELECT 'dependency.b4b.fk.'||e.name,EXISTS (SELECT 1 FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass('public.marcadores')
 AND c.conname=e.name AND c.contype='f' AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred),
 'B4b FK validated/non-deferrable' FROM (VALUES ('marcadores_legacy_game_uuid_fk'),('marcadores_legacy_uuid_layer_fk')) e(name)

 UNION ALL SELECT 'visibility.full.all_data_tables',(SELECT pg_catalog.count(*)=10 AND COALESCE(pg_catalog.bool_and(ok),false) FROM visibility),
 'All ten ordinary RLS tables must have full maintenance SELECT/schema USAGE and RLS bypass/owner visibility'
 UNION ALL SELECT 'role.api_required',EXISTS (SELECT 1 FROM api_roles WHERE rolname='anon')
 AND EXISTS (SELECT 1 FROM api_roles WHERE rolname='authenticated'),
 'anon/authenticated must exist; service_role is checked conditionally without inventing roles'
 UNION ALL SELECT 'fk.identity.'||e.name,EXISTS (SELECT 1 FROM constraints c
 WHERE c.conrelid=pg_catalog.to_regclass(e.rel) AND c.conname=e.name AND c.contype='f'
 AND c.confrelid=pg_catalog.to_regclass(e.parent) AND c.columns=e.columns AND c.parent_columns=e.parent_columns
 AND c.confmatchtype='s' AND c.confupdtype='a' AND c.confdeltype::text=e.delete_action
 AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred),
 'Exact source/parent columns; MATCH SIMPLE, UPDATE NO ACTION, DELETE='||e.delete_action||'; validated NOT DEFERRABLE'
 FROM expected_identity_fks e
 UNION ALL SELECT 'schema.marker_id_nullable',EXISTS (SELECT 1 FROM attributes a
 WHERE a.attrelid=pg_catalog.to_regclass('public.marker_submissions') AND a.attname='marker_id'
 AND a.atttypid='bigint'::pg_catalog.regtype AND NOT a.attnotnull),
 'Nullable marker_id supports unmaterialized create; no cascade test or DML'
 UNION ALL SELECT 'key.marker_support_columns',NOT EXISTS (SELECT 1 FROM (VALUES
 ('id','bigint'),('game_id','text'),('game_uuid','uuid')) e(name,type_name)
 WHERE NOT EXISTS (SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass('public.marcadores')
 AND a.attname=e.name AND a.atttypid=pg_catalog.to_regtype(e.type_name) AND a.attnotnull)),
 'Parent support key retains BIGINT id / TEXT game_id / UUID game_uuid, all NOT NULL'
 UNION ALL SELECT 'index.submissions.exact_legacy_set',pg_catalog.count(*)=5 AND pg_catalog.bool_and(relname IN (SELECT name FROM expected_indexes)),
 'Exactly five legacy indexes; actual='||pg_catalog.count(*) FROM indexes WHERE indrelid=pg_catalog.to_regclass('public.marker_submissions')
 UNION ALL SELECT 'index.submissions.no_game_uuid',pg_catalog.to_regclass('public.marker_submissions') IS NOT NULL
 AND NOT EXISTS (SELECT 1 FROM indexes WHERE indrelid=pg_catalog.to_regclass('public.marker_submissions')
 AND (columns && ARRAY['game_uuid']::text[] OR COALESCE(pg_catalog.pg_get_expr(indexprs,indrelid),'') ~ '\mgame_uuid\M'
 OR COALESCE(pg_catalog.pg_get_expr(indpred,indrelid),'') ~ '\mgame_uuid\M')),
 'No child index key/INCLUDE/expression/predicate references game_uuid; no isolated UUID index'
 UNION ALL SELECT 'function.helper.attributes',EXISTS (SELECT 1 FROM helper p
 WHERE p.pronargs=1 AND p.proargtypes='25'::pg_catalog.oidvector AND p.proargnames=ARRAY['p_identifier']::text[]
 AND p.prorettype='uuid'::pg_catalog.regtype AND p.lanname='plpgsql' AND p.prosecdef
 AND p.provolatile='s' AND p.proparallel='u' AND p.prokind='f' AND NOT p.proretset
 AND p.provariadic=0 AND p.pronargdefaults=0 AND p.proargdefaults IS NULL
 AND p.proargmodes IS NULL AND p.proallargtypes IS NULL
 AND NOT p.proleakproof AND NOT p.proisstrict AND p.procost=100 AND p.prorows=0
 AND p.proconfig=ARRAY['search_path=""']::text[]),
 'Exactly (p_identifier TEXT)->UUID, plpgsql STABLE DEFINER, empty search_path, UNSAFE, called on NULL, COST 100, no defaults/variadic/OUT/set return'
 UNION ALL SELECT 'function.helper.exact_body',helper_ok,
 'Complete literal prosrc equality to approved B5b; only CRLF/LF normalized, never invoked' FROM new_body_matches
 UNION ALL SELECT 'function.helper.contract.'||e.name,helper_ok,e.details FROM new_body_matches CROSS JOIN (VALUES
 ('errors','Exact body rejects NULL/blank/unknown/ambiguous/NULL UUID'),
 ('strict_mapping_only','Exact body SELECT INTO STRICT only private.game_legacy_identifiers WHERE legacy_identifier=p_identifier; returns UUID only'),
 ('no_privileged_marker_lookup','Exact body has no marker/games read, no dynamic SQL and no writing')) e(name,details)
 UNION ALL SELECT 'function.helper.owner_trusted',EXISTS (SELECT 1 FROM helper p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
 JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass('private.game_legacy_identifiers')
 WHERE r.rolname NOT IN ('anon','authenticated','service_role')
 AND pg_catalog.has_table_privilege(r.oid,c.oid,'SELECT') AND pg_catalog.has_schema_privilege(r.oid,c.relnamespace,'USAGE')
 AND (r.rolsuper OR r.rolbypassrls OR (r.oid=c.relowner AND NOT c.relforcerowsecurity))
 AND NOT EXISTS (SELECT 1 FROM api_roles a WHERE a.rolname IN ('anon','authenticated')
 AND pg_catalog.pg_has_role(a.oid,r.oid,'MEMBER'))),
 'Actual owner exists, is not an API role, has full mapping visibility, and anon/authenticated cannot inherit it; no fixed owner/OID'
 UNION ALL SELECT 'function.helper.no_overloads',pg_catalog.count(*)=1 AND pg_catalog.bool_and(n.nspname='private' AND p.oid=pg_catalog.to_regprocedure('private.deepmap_game_uuid_from_legacy_identifier(text)')),
 'Exactly one private helper with exact text signature; no public convenience version or overload; actual='||pg_catalog.count(*)
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','private') AND p.proname='deepmap_game_uuid_from_legacy_identifier'
 UNION ALL SELECT 'acl.helper.public_no_execute',EXISTS (SELECT 1 FROM helper)
 AND NOT EXISTS (SELECT 1 FROM helper_acl WHERE grantee=0 AND privilege_type='EXECUTE'),
 'Literal PUBLIC ACL has no EXECUTE'
 UNION ALL SELECT 'acl.helper.anon_no_execute',EXISTS (SELECT 1 FROM helper p JOIN api_roles r ON r.rolname='anon'
 WHERE NOT pg_catalog.has_function_privilege(r.oid,p.oid,'EXECUTE')),
 'anon effective EXECUTE=false, including inheritance'
 UNION ALL SELECT 'acl.helper.authenticated_execute',EXISTS (SELECT 1 FROM helper p JOIN api_roles r ON r.rolname='authenticated'
 WHERE pg_catalog.has_function_privilege(r.oid,p.oid,'EXECUTE') AND pg_catalog.has_schema_privilege(r.oid,'private','USAGE')),
 'authenticated effective EXECUTE=true and pre-existing private schema USAGE'
 UNION ALL SELECT 'acl.helper.service_writer',EXISTS (SELECT 1 FROM helper)
 AND NOT EXISTS (SELECT 1 FROM helper p CROSS JOIN service r WHERE r.writer
 AND (NOT pg_catalog.has_function_privilege(r.oid,p.oid,'EXECUTE') OR NOT pg_catalog.has_schema_privilege(r.oid,'private','USAGE')
 OR pg_catalog.has_schema_privilege(r.oid,'private','CREATE'))),
 'Effective service writer requires helper EXECUTE, private USAGE and no CREATE; no artificial USAGE/EXECUTE required otherwise'
 UNION ALL SELECT 'acl.private.service_writer_usage',
 EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname='private')
 AND NOT EXISTS (SELECT 1 FROM service r WHERE r.writer AND NOT pg_catalog.has_schema_privilege(r.oid,'private','USAGE')),
 'Current effective service writer must have private USAGE; prior-state ACL delta is proved only by migration snapshots'
 UNION ALL SELECT 'acl.private.service_no_create',
 EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname='private')
 AND NOT EXISTS (SELECT 1 FROM service r WHERE pg_catalog.has_schema_privilege(r.oid,'private','CREATE')),
 'Existing service_role cannot CREATE in private, whether or not it is a submissions writer'
 UNION ALL SELECT 'acl.helper.no_unexpected_grants',EXISTS (SELECT 1 FROM helper)
 AND NOT EXISTS (SELECT 1 FROM helper_acl a WHERE a.privilege_type<>'EXECUTE'
 OR (a.grantee<>a.proowner AND a.is_grantable)
 OR (a.grantee<>a.proowner AND NOT EXISTS (SELECT 1 FROM api_roles r WHERE r.rolname='authenticated' AND r.oid=a.grantee)
 AND NOT EXISTS (SELECT 1 FROM service r WHERE r.writer AND r.oid=a.grantee))),
 'Only actual owner, authenticated and current service writer may have raw EXECUTE; non-owner grant options forbidden'
 UNION ALL SELECT 'acl.private.no_untrusted_create',EXISTS (SELECT 1 FROM api_roles WHERE rolname='anon')
 AND EXISTS (SELECT 1 FROM api_roles WHERE rolname='authenticated')
 AND NOT EXISTS (SELECT 1 FROM api_roles r WHERE r.rolname IN ('anon','authenticated')
 AND pg_catalog.has_schema_privilege(r.oid,'private','CREATE')),
 'anon/authenticated cannot CREATE/replace functions in private; their schema grants remain unchanged by B5b'
 UNION ALL SELECT 'function.resolver.attributes',EXISTS (SELECT 1 FROM resolver p
 WHERE p.pronargs=0 AND p.proargtypes=''::pg_catalog.oidvector AND p.proargnames IS NULL
 AND p.prorettype='trigger'::pg_catalog.regtype AND p.lanname='plpgsql' AND NOT p.prosecdef
 AND p.provolatile='v' AND p.proparallel='u' AND p.prokind='f' AND NOT p.proretset
 AND p.provariadic=0 AND p.pronargdefaults=0 AND p.proargdefaults IS NULL
 AND p.proargmodes IS NULL AND p.proallargtypes IS NULL
 AND NOT p.proleakproof AND NOT p.proisstrict AND p.procost=100 AND p.prorows=0
 AND p.proconfig=ARRAY['search_path=""']::text[]),
 'trigger(), zero args, plpgsql INVOKER, empty search_path, VOLATILE/UNSAFE, non-leakproof/called on NULL, COST 100'
 UNION ALL SELECT 'function.resolver.exact_body',resolver_ok,
 'Complete literal prosrc equality to approved B5b; only CRLF/LF normalized; trigger function never invoked' FROM new_body_matches
 UNION ALL SELECT 'function.resolver.contract.'||e.name,resolver_ok,e.details FROM new_body_matches CROSS JOIN (VALUES
 ('insert','Exact body resolves helper, fills NULL game_uuid and rejects explicit incompatible UUID'),
 ('hydration','Exact body: OLD UUID NULL, complete JSONB legacy projection equality, exact resolved UUID; no combined legacy change'),
 ('normal_update','Exact body freezes only game_id/game_uuid; marker_id remains mutable; no payload/status/review mutation'),
 ('no_marker_select','Exact body contains no marker SELECT, procedural marker_id validation or dynamic SQL')) e(name,details)
 UNION ALL SELECT 'function.resolver.no_overloads',pg_catalog.count(*)=1 AND pg_catalog.bool_and(n.nspname='private' AND p.oid=pg_catalog.to_regprocedure('private.deepmap_resolve_submission_identity()')),
 'Exactly one private zero-argument resolver; no public variant/overload; actual='||pg_catalog.count(*)
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','private') AND p.proname='deepmap_resolve_submission_identity'
 UNION ALL SELECT 'acl.resolver.owner_only',EXISTS (SELECT 1 FROM resolver)
 AND NOT EXISTS (SELECT 1 FROM resolver_acl WHERE grantee<>proowner OR privilege_type<>'EXECUTE'),
 'No raw/direct EXECUTE to PUBLIC/anon/authenticated/service_role or other non-owner roles; callers need no direct trigger-function EXECUTE'
 UNION ALL SELECT 'function.resolver.owner_matches_helper',EXISTS (SELECT 1 FROM resolver r CROSS JOIN helper h WHERE r.proowner=h.proowner),
 'Resolver and narrow helper have the same actual creator/owner; trusted owner checked separately, no fixed role/OID'
 UNION ALL SELECT 'function.writer.lookup_authorization',EXISTS (SELECT 1 FROM helper)
 AND NOT EXISTS (SELECT 1 FROM (VALUES ('public.review_marker_submission(bigint,text,text)'),
 ('public.review_marker_submission_v2(bigint,text,text,jsonb)'),('public.cancel_marker_submission(bigint)'),
 ('private.deepmap_autoapprove_moderator_submission()')) e(signature)
 WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN helper h
 WHERE p.oid=pg_catalog.to_regprocedure(e.signature) AND p.prosecdef
 AND pg_catalog.has_schema_privilege(p.proowner,'private','USAGE')
 AND pg_catalog.has_function_privilege(p.proowner,h.oid,'EXECUTE'))),
 'Existing DEFINER review/cancel/autoapproval owners can call lookup, without invoking any path'
 UNION ALL SELECT 'trigger.before_update.order',
 (SELECT pg_catalog.array_agg(t.tgname::text ORDER BY t.tgname COLLATE "C") FROM pg_catalog.pg_trigger t
 WHERE t.tgrelid=pg_catalog.to_regclass('public.marker_submissions') AND NOT t.tgisinternal
 AND (t.tgtype & 2)=2 AND (t.tgtype & 16)=16)
 IS NOT DISTINCT FROM ARRAY['deepmap_marker_submissions_identity','deepmap_marker_submissions_touch_updated_at']::text[],
 'Exactly identity then touch for user BEFORE UPDATE; PostgreSQL name order, never OID order'
 UNION ALL SELECT 'function.side_effect.baseline.'||e.signature,EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
 WHERE p.oid=pg_catalog.to_regprocedure(e.signature) AND p.prokind='f' AND p.prosecdef
 AND p.proconfig=ARRAY['search_path=""']::text[]
 AND pg_catalog.md5(pg_catalog.replace(p.prosrc,pg_catalog.chr(13)||pg_catalog.chr(10),pg_catalog.chr(10)))=e.body_digest
 AND (SELECT pg_catalog.count(*) FROM pg_catalog.pg_proc q WHERE q.pronamespace=p.pronamespace AND q.proname=p.proname)=1),
 'Exact B5b baseline source digest='||e.body_digest||'; never invoked; historical effects require migration snapshots' FROM expected_side_bodies e
 UNION ALL SELECT 'mapping.policy.'||e.name,EXISTS (SELECT 1 FROM mapping_policies p CROSS JOIN authenticated r
 WHERE p.polname=e.name AND p.polcmd::text=e.command AND p.polpermissive AND p.polroles=ARRAY[r.oid]::oid[]
 AND p.qual IS NOT DISTINCT FROM e.qual AND p.with_check IS NOT DISTINCT FROM e.with_check),
 'Exact authenticated Admin-only mapping policy command/USING/WITH CHECK' FROM expected_mapping_policies e
 UNION ALL SELECT 'mapping.policy.exact_set',pg_catalog.count(*)=2 AND pg_catalog.bool_and(polname IN (SELECT name FROM expected_mapping_policies)),
 'Exactly the two Admin-only mapping policies; no general/public read; actual='||pg_catalog.count(*) FROM mapping_policies
 UNION ALL SELECT 'mapping.acl.authenticated_legacy',EXISTS (SELECT 1 FROM authenticated r JOIN pg_catalog.pg_class c
 ON c.oid=pg_catalog.to_regclass('private.game_legacy_identifiers')
 WHERE pg_catalog.has_table_privilege(r.oid,c.oid,'SELECT') AND pg_catalog.has_table_privilege(r.oid,c.oid,'INSERT')
 AND NOT EXISTS (SELECT 1 FROM (VALUES ('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER')) e(privilege)
 WHERE pg_catalog.has_table_privilege(r.oid,c.oid,e.privilege))
 AND NOT EXISTS (SELECT 1 FROM attributes a WHERE a.attrelid=c.oid
 AND (pg_catalog.has_column_privilege(r.oid,c.oid,a.attnum,'UPDATE') OR pg_catalog.has_column_privilege(r.oid,c.oid,a.attnum,'REFERENCES')))),
 'Current baseline authenticated mapping SELECT+INSERT only; RLS remains Admin-only; no claimed historical ACL comparison'
 UNION ALL SELECT 'mapping.acl.no_extra_public_read',pg_catalog.to_regclass('private.game_legacy_identifiers') IS NOT NULL
 AND EXISTS (SELECT 1 FROM api_roles WHERE rolname='anon')
 AND NOT EXISTS (SELECT 1 FROM mapping_acl a WHERE a.grantee<>a.relowner
 AND NOT EXISTS (SELECT 1 FROM api_roles r WHERE r.oid=a.grantee AND
 (r.rolname='service_role' OR (r.rolname='authenticated' AND a.privilege_type IN ('SELECT','INSERT') AND NOT a.is_grantable))))
 AND NOT EXISTS (SELECT 1 FROM attributes a CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) x
 WHERE a.attrelid=pg_catalog.to_regclass('private.game_legacy_identifiers') AND x.grantee<>0
 AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c WHERE c.oid=a.attrelid AND c.relowner=x.grantee)
 AND NOT EXISTS (SELECT 1 FROM api_roles r WHERE r.rolname='service_role' AND r.oid=x.grantee))
 AND NOT EXISTS (SELECT 1 FROM attributes a CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) x
 WHERE a.attrelid=pg_catalog.to_regclass('private.game_legacy_identifiers') AND x.grantee=0)
 AND NOT EXISTS (SELECT 1 FROM api_roles r WHERE r.rolname='anon'
 AND (pg_catalog.has_any_column_privilege(r.oid,pg_catalog.to_regclass('private.game_legacy_identifiers'),'SELECT')
 OR pg_catalog.has_any_column_privilege(r.oid,pg_catalog.to_regclass('private.game_legacy_identifiers'),'INSERT')
 OR pg_catalog.has_any_column_privilege(r.oid,pg_catalog.to_regclass('private.game_legacy_identifiers'),'UPDATE'))),
 'No PUBLIC/anon/additional untrusted direct mapping grants; existing owner/service grants permitted; no new SELECT for lookup'
 UNION ALL SELECT 'acl.authenticated.game_uuid.'||e.privilege,EXISTS (SELECT 1 FROM authenticated r JOIN attributes a
 ON a.attrelid=pg_catalog.to_regclass('public.marker_submissions') AND a.attname='game_uuid'
 WHERE NOT pg_catalog.has_column_privilege(r.oid,a.attrelid,a.attnum,e.privilege)),
 'Authenticated direct/effective game_uuid '||e.privilege||'=false' FROM (VALUES ('INSERT'),('UPDATE')) e(privilege)
 UNION ALL SELECT 'acl.authenticated.no_column_references',EXISTS (SELECT 1 FROM authenticated)
 AND NOT EXISTS (SELECT 1 FROM authenticated r CROSS JOIN attributes a
 WHERE a.attrelid=pg_catalog.to_regclass('public.marker_submissions') AND pg_catalog.has_column_privilege(r.oid,a.attrelid,a.attnum,'REFERENCES')),
 'No unexpected REFERENCES column grants'
 UNION ALL SELECT 'acl.authenticated.no_unexpected_table_privileges',EXISTS (SELECT 1 FROM authenticated)
 AND NOT EXISTS (SELECT 1 FROM authenticated r JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass('public.marker_submissions')
 CROSS JOIN LATERAL (SELECT DISTINCT a.privilege_type FROM pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a) e
 WHERE e.privilege_type<>'SELECT' AND pg_catalog.has_table_privilege(r.oid,c.oid,e.privilege_type)),
 'Only SELECT is allowed at table level, including any server-version-specific privilege actually present in its ACL'
 UNION ALL SELECT 'sequence.identity_dependency',EXISTS (SELECT 1 FROM pg_catalog.pg_class q
 JOIN attributes a ON a.attrelid=pg_catalog.to_regclass('public.marker_submissions') AND a.attname='id' AND a.attidentity='d'
 WHERE q.oid=pg_catalog.to_regclass('public.marker_submissions_id_seq') AND q.relkind='S'
 AND EXISTS (SELECT 1 FROM pg_catalog.pg_sequence x WHERE x.seqrelid=q.oid)
 AND (SELECT pg_catalog.count(*) FROM pg_catalog.pg_depend d WHERE d.classid='pg_catalog.pg_class'::pg_catalog.regclass AND d.objid=q.oid AND d.deptype='i')=1
 AND EXISTS (SELECT 1 FROM pg_catalog.pg_depend d WHERE d.classid='pg_catalog.pg_class'::pg_catalog.regclass AND d.objid=q.oid
 AND d.objsubid=0 AND d.refclassid='pg_catalog.pg_class'::pg_catalog.regclass AND d.refobjid=a.attrelid AND d.refobjsubid=a.attnum AND d.deptype='i')),
 'Real sequence retains its single internal identity dependency on submissions.id; no value read or sequence invocation'
 UNION ALL SELECT 'mapping.required_column.'||e.rel||'.'||e.name,EXISTS (SELECT 1 FROM attributes a
 WHERE a.attrelid=pg_catalog.to_regclass(e.rel) AND a.attname=e.name AND a.atttypid=pg_catalog.to_regtype(e.type_name) AND a.attnotnull),
 'Mapping/game identity parent column type and NOT NULL: '||e.type_name FROM (VALUES
 ('private.game_legacy_identifiers','legacy_identifier','text'),('private.game_legacy_identifiers','game_id','uuid'),('public.games','id','uuid')) e(rel,name,type_name)
 UNION ALL SELECT 'data.game_uuid.non_null',uuid_null_count=0,'NULL game_uuid rows='||uuid_null_count FROM data_stats
 UNION ALL SELECT 'data.game_identity.unknown_mapping',unknown_mapping_count=0,'Unknown legacy mapping rows='||unknown_mapping_count FROM data_stats
 UNION ALL SELECT 'data.game_identity.ambiguity',ambiguous_mapping_count=0,'Ambiguous legacy mapping rows='||ambiguous_mapping_count FROM data_stats
 UNION ALL SELECT 'data.game_identity.exact_uuid',identity_mismatch_count=0,'Rows without exactly one (legacy_identifier,UUID) mapping='||identity_mismatch_count FROM data_stats
 UNION ALL SELECT 'data.game_identity.games_parent',game_parent_mismatch_count=0,'Rows without exactly one mapping to existing game='||game_parent_mismatch_count FROM data_stats
 UNION ALL SELECT 'data.marker_identity.coherence',marker_mismatch_count=0,'Non-NULL marker rows without exactly one id/game_id/game_uuid parent='||marker_mismatch_count FROM data_stats
 UNION ALL SELECT 'data.create_null_marker.structurally_supported',
 EXISTS (SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass('public.marker_submissions') AND a.attname='marker_id' AND NOT a.attnotnull)
 AND EXISTS (SELECT 1 FROM constraints c WHERE c.conrelid=pg_catalog.to_regclass('public.marker_submissions')
 AND c.conname='marker_submissions_marker_game_uuid_fk' AND c.contype='f' AND c.confmatchtype='s' AND c.convalidated)
 AND EXISTS (SELECT 1 FROM constraints c CROSS JOIN expected_checks e
 WHERE c.conrelid=pg_catalog.to_regclass('public.marker_submissions') AND c.conname='marker_submissions_target_required'
 AND e.name=c.conname AND c.convalidated
 AND pg_catalog.regexp_replace(pg_catalog.pg_get_expr(c.conbin,c.conrelid),'[[:space:]()]','','g')
 =pg_catalog.regexp_replace(e.expression,'[[:space:]()]','','g')),
 'Create rows with marker_id NULL='||unmaterialized_create_count||'; nullable/MATCH SIMPLE and legacy target CHECK permit them; no INSERT test' FROM data_stats
 UNION ALL SELECT 'data.revisions.submission_orphans',pg_catalog.count(*)=0,'Legacy revisions without submission parent='||pg_catalog.count(*)
 FROM private.marker_submission_revisions r WHERE NOT EXISTS (SELECT 1 FROM public.marker_submissions s WHERE s.id=r.submission_id)
 UNION ALL SELECT 'scope.b5b.game_uuid_present',EXISTS (SELECT 1 FROM attributes a
 WHERE a.attrelid=pg_catalog.to_regclass('public.marker_submissions') AND a.attname='game_uuid'
 AND a.atttypid='uuid'::pg_catalog.regtype AND a.attnotnull),
 'B5b game_uuid is present; this is not a declaration that B5/B6 are complete'
 UNION ALL SELECT 'scope.pre_b6.no_extra_columns.'||e.rel,pg_catalog.to_regclass(e.rel) IS NOT NULL
 AND NOT EXISTS (SELECT 1 FROM attributes a WHERE a.attrelid=pg_catalog.to_regclass(e.rel) AND a.attname::text=ANY(e.forbidden)),
 'Forbidden later-phase columns absent: '||pg_catalog.array_to_string(e.forbidden,',') FROM (VALUES
 ('public.marker_submissions',ARRAY['layer_uuid','category_uuid','group_uuid','game_map_id']),
 ('private.marker_submission_revisions',ARRAY['game_uuid','layer_uuid','category_uuid','group_uuid','game_map_id']),
 ('public.user_notifications',ARRAY['game_uuid','layer_uuid','category_uuid','group_uuid','game_map_id']),
 ('public.marcadores',ARRAY['category_uuid','group_uuid','game_map_id'])) e(rel,forbidden)
 UNION ALL SELECT 'scope.pre_b6.no_identifiable_extra_functions',pg_catalog.count(*)=0,
 'Clearly identified later-phase marker category/group or related UUID identity functions='||pg_catalog.count(*)||'; no claim about undocumented B6 designs'
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','private') AND
 (p.proname ~ '^deepmap_resolve_marker_(category|group)_identity$'
 OR p.proname ~ '^deepmap_resolve_(submission|notification|revision)_(layer|category|group)_identity$'
 OR p.proname ~ '^deepmap_resolve_(notification|revision)_identity$')
 UNION ALL SELECT 'scope.pre_b6.no_extra_identity_constraints',pg_catalog.count(*)=0,'Unexpected later-phase identity constraints='||pg_catalog.count(*)
 FROM constraints c WHERE (c.conrelid IN (pg_catalog.to_regclass('public.marker_submissions'),pg_catalog.to_regclass('public.marcadores'))
 AND (c.columns && ARRAY['category_uuid','group_uuid','game_map_id']::text[]
 OR (c.conrelid=pg_catalog.to_regclass('public.marker_submissions') AND c.columns && ARRAY['layer_uuid']::text[])))
 OR (c.conrelid IN (pg_catalog.to_regclass('private.marker_submission_revisions'),pg_catalog.to_regclass('public.user_notifications'))
 AND (c.columns && ARRAY['game_uuid','layer_uuid','category_uuid','group_uuid','game_map_id']::text[] OR c.conname ~* 'uuid'))
 UNION ALL SELECT 'scope.pre_b6.no_extra_identity_indexes',pg_catalog.count(*)=0,'Unexpected later-phase identity indexes='||pg_catalog.count(*)
 FROM indexes i WHERE i.indrelid IN (pg_catalog.to_regclass('public.marker_submissions'),pg_catalog.to_regclass('public.marcadores'),
 pg_catalog.to_regclass('private.marker_submission_revisions'),pg_catalog.to_regclass('public.user_notifications'))
 AND (i.columns && ARRAY['category_uuid','group_uuid','game_map_id']::text[]
 OR COALESCE(pg_catalog.pg_get_expr(i.indexprs,i.indrelid),'') ~ '\m(category_uuid|group_uuid|game_map_id)\M'
 OR COALESCE(pg_catalog.pg_get_expr(i.indpred,i.indrelid),'') ~ '\m(category_uuid|group_uuid|game_map_id)\M'
 OR (i.indrelid IN (pg_catalog.to_regclass('private.marker_submission_revisions'),pg_catalog.to_regclass('public.user_notifications'))
 AND (i.relname ~* 'uuid' OR i.columns && ARRAY['game_uuid','layer_uuid']::text[]
 OR COALESCE(pg_catalog.pg_get_expr(i.indexprs,i.indrelid),'') ~ '\m(game_uuid|layer_uuid)\M'
 OR COALESCE(pg_catalog.pg_get_expr(i.indpred,i.indrelid),'') ~ '\m(game_uuid|layer_uuid)\M')))

)
SELECT check_name,
 CASE WHEN ok IS TRUE AND (check_name NOT LIKE 'data.%' OR (SELECT pg_catalog.count(*)=10 AND COALESCE(pg_catalog.bool_and(ok),false) FROM visibility)) THEN 'PASS' ELSE 'FAIL' END AS status,
 details || CASE WHEN check_name LIKE 'data.%' AND NOT (SELECT pg_catalog.count(*)=10 AND COALESCE(pg_catalog.bool_and(ok),false) FROM visibility)
 THEN '; INVALID DATA RESULT: incomplete maintenance visibility' ELSE '' END AS details
FROM checks ORDER BY check_name;
