-- DeepMap B7h2c: DB-only forward privacy/visibility/suspension reconciliation.
-- MANUAL REVIEW/APPLICATION ONLY. GUARDAR: SIM (versioned migration).
-- No business DML, historical edits, credential changes, quotas or storage config changes.
-- Requires the completed UUID bridges through 20261016120000, plus historical functions.
-- A fresh historical replay remains incomplete before this migration: see handoff.
BEGIN;
SET LOCAL search_path = pg_catalog;
SET LOCAL lock_timeout = '5s';

-- Bound maintenance locking. SHARE blocks concurrent business writes for digest equality;
-- auth.users is deliberately not locked or read for account data. Profile DDL below
-- upgrades its lock. Review timing on a busy project before manual application.
LOCK TABLE public.profiles, public.games, public.game_modules, public.game_maps, public.map_layers, public.marker_category_groups, public.marker_categories, public.marcadores, public.map_labels, public.marker_images, public.marker_sections, public.marker_section_rows, public.marker_submissions, storage.objects, storage.buckets IN SHARE ROW EXCLUSIVE MODE;

DO $b7h2c$
DECLARE
    v record;
    v_rel oid;
    v_relations oid[] := ARRAY['public.profiles'::pg_catalog.regclass::oid,'public.games'::pg_catalog.regclass::oid,'public.game_modules'::pg_catalog.regclass::oid,'public.game_maps'::pg_catalog.regclass::oid,'public.map_layers'::pg_catalog.regclass::oid,'public.marker_category_groups'::pg_catalog.regclass::oid,'public.marker_categories'::pg_catalog.regclass::oid,'public.marcadores'::pg_catalog.regclass::oid,'public.map_labels'::pg_catalog.regclass::oid,'public.marker_images'::pg_catalog.regclass::oid,'public.marker_sections'::pg_catalog.regclass::oid,'public.marker_section_rows'::pg_catalog.regclass::oid,'public.marker_submissions'::pg_catalog.regclass::oid,'storage.objects'::pg_catalog.regclass::oid,'storage.buckets'::pg_catalog.regclass::oid];
    v_catalog_before jsonb;
    v_catalog_after jsonb;
    v_data_before jsonb;
    v_data_now jsonb;
    v_rows jsonb;
    v_had_is_public boolean;
BEGIN

    -- Required ordinary RLS relations; full maintenance visibility is mandatory.
    FOR v IN SELECT * FROM (VALUES ('public.profiles'),('public.games'),('public.game_modules'),('public.game_maps'),('public.map_layers'),('public.marker_category_groups'),('public.marker_categories'),('public.marcadores'),('public.map_labels'),('public.marker_images'),('public.marker_sections'),('public.marker_section_rows'),('public.marker_submissions'),('storage.objects'),('storage.buckets')) e(rel) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.rolname = CURRENT_USER
            WHERE c.oid = pg_catalog.to_regclass(v.rel) AND c.relkind = 'r' AND c.relrowsecurity
              AND pg_catalog.has_table_privilege(c.oid, 'SELECT')
              AND (r.rolsuper OR r.rolbypassrls OR (r.oid = c.relowner AND NOT c.relforcerowsecurity))) THEN
            RAISE EXCEPTION 'B7H2C_RELATION_OR_MAINTENANCE_VISIBILITY: %',v.rel;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.profiles','id','uuid'),
        ('public.profiles','username','text'),
        ('public.profiles','public_display_name','text'),
        ('public.profiles','public_bio','text'),
        ('public.profiles','public_avatar_choice','text'),
        ('public.games','id','uuid'),
        ('public.games','status','text'),
        ('public.game_modules','game_id','uuid'),
        ('public.game_modules','module_key','text'),
        ('public.game_modules','enabled','boolean'),
        ('public.game_maps','id','uuid'),
        ('public.game_maps','game_id','uuid'),
        ('public.game_maps','status','text'),
        ('public.map_layers','game_uuid','uuid'),
        ('public.marker_category_groups','game_uuid','uuid'),
        ('public.marker_categories','game_uuid','uuid'),
        ('public.marcadores','game_uuid','uuid'),
        ('public.map_labels','game_uuid','uuid'),
        ('public.map_layers','layer_uuid','uuid'),
        ('public.map_layers','game_map_id','uuid'),
        ('public.map_layers','is_active','boolean'),
        ('public.marker_category_groups','is_active','boolean'),
        ('public.marker_categories','is_active','boolean'),
        ('public.marcadores','id','bigint'),
        ('public.marcadores','layer_uuid','uuid'),
        ('public.marcadores','is_published','boolean'),
        ('public.map_labels','layer_uuid','uuid'),
        ('public.map_labels','is_published','boolean'),
        ('public.marker_images','marker_id','bigint'),
        ('public.marker_sections','marker_id','bigint'),
        ('public.marker_section_rows','section_id','bigint'),
        ('auth.users','id','uuid')
    ) e(rel,col,typ) LEFT JOIN pg_catalog.pg_attribute a
      ON a.attrelid=pg_catalog.to_regclass(e.rel) AND a.attname=e.col AND a.attnum>0 AND NOT a.attisdropped
      WHERE a.attname IS NULL OR a.atttypid<>pg_catalog.to_regtype(e.typ) OR NOT a.attnotnull) THEN
        RAISE EXCEPTION 'B7H2C_REQUIRED_COLUMN_SHAPE';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.profiles'::pg_catalog.regclass AND c.contype='p'
          AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=c.conrelid AND attname='id')]::smallint[]
          AND c.convalidated AND NOT c.condeferrable)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.profiles'::pg_catalog.regclass AND c.contype='f'
          AND c.confrelid='auth.users'::pg_catalog.regclass AND c.convalidated AND NOT c.condeferrable
          AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=c.conrelid AND attname='id')]::smallint[]
          AND c.confkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=c.confrelid AND attname='id')]::smallint[]) THEN
        RAISE EXCEPTION 'B7H2C_PROFILE_IDENTITY_RELATIONSHIP';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d
        ON d.adrelid=a.attrelid AND d.adnum=a.attnum
        WHERE a.attrelid='public.profiles'::pg_catalog.regclass AND a.attname='is_public' AND NOT a.attisdropped
          AND (a.atttypid<>'boolean'::pg_catalog.regtype OR NOT a.attnotnull OR a.attgenerated<>'' OR a.attidentity<>''
            OR pg_catalog.pg_get_expr(d.adbin,d.adrelid) IS DISTINCT FROM 'true')) THEN
        RAISE EXCEPTION 'B7H2C_IS_PUBLIC_SHAPE_DEFAULT';
    END IF;
    IF (SELECT pg_catalog.pg_get_userbyid(c.relowner) FROM pg_catalog.pg_class c WHERE c.oid='public.profiles'::pg_catalog.regclass)<>'postgres'
       OR (SELECT c.relforcerowsecurity FROM pg_catalog.pg_class c WHERE c.oid='public.profiles'::pg_catalog.regclass) THEN
        RAISE EXCEPTION 'B7H2C_LIVE_PROFILE_OWNER_OR_FORCED_RLS_DRIFT';
    END IF;
    IF EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated')) e(role_name)
        WHERE NOT pg_catalog.has_table_privilege(e.role_name,'public.profiles','SELECT'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid='public.profiles'::pg_catalog.regclass AND NOT a.attisdropped AND a.attnum>0
          AND (a.attname ILIKE '%email%' OR a.attname IN ('raw_user_meta_data','raw_app_meta_data','encrypted_password'))) THEN
        RAISE EXCEPTION 'B7H2C_PROFILE_GRANTS_OR_PRIVATE_COLUMN_EXPOSURE';
    END IF;

    -- Nullable presentation projections and username result columns must already exist.
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public_avatar_path','text',false),('public_google_avatar_url','text',false),
        ('joined_at','timestamp with time zone',false),('username_changed_at','timestamp with time zone',false),
        ('username_is_generated','boolean',true)
    ) e(col,typ,nn) LEFT JOIN pg_catalog.pg_attribute a
      ON a.attrelid='public.profiles'::pg_catalog.regclass AND a.attname=e.col AND a.attnum>0 AND NOT a.attisdropped
      WHERE a.attname IS NULL OR a.atttypid<>pg_catalog.to_regtype(e.typ) OR a.attnotnull<>e.nn) THEN
        RAISE EXCEPTION 'B7H2C_PROFILE_PRESENTATION_OR_USERNAME_RESULT_SHAPE';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid='public.set_deepmap_username(text)'::pg_catalog.regprocedure
          AND p.proretset AND p.proargnames=ARRAY['p_username','username','username_changed_at','username_is_generated']::text[]
          AND p.proargmodes=ARRAY['i','t','t','t']::"char"[]
          AND p.proallargtypes=ARRAY['text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,
              'timestamp with time zone'::pg_catalog.regtype::oid,'boolean'::pg_catalog.regtype::oid])
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid='private.marker_is_public(bigint)'::pg_catalog.regprocedure
          AND NOT p.proretset AND p.proargnames=ARRAY['p_marker_id']::text[])
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid='private.sync_auth_public_profile()'::pg_catalog.regprocedure AND NOT p.proretset)
       OR pg_catalog.to_regprocedure('public.ensure_deepmap_profile()') IS NULL THEN
        RAISE EXCEPTION 'B7H2C_REPLACED_FUNCTION_SIGNATURE_OR_DEPENDENCY';
    END IF;
    -- Browser roles cannot bypass RLS or inherit privileged function execution.
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles r
        WHERE r.rolname IN ('anon','authenticated') AND (r.rolsuper OR r.rolbypassrls))
       OR EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated')) e(role_name)
        WHERE pg_catalog.has_any_column_privilege(e.role_name,'auth.users','SELECT')) THEN
        RAISE EXCEPTION 'B7H2C_BROWSER_ROLE_OR_AUTH_EXPOSURE';
    END IF;
    IF EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated')) roles(role_name)
        CROSS JOIN (VALUES ('public.games'),('public.game_modules'),('public.game_maps'),
          ('public.map_layers'),('public.marker_category_groups'),('public.marker_categories'),
          ('public.marcadores'),('public.map_labels'),('public.marker_images'),('public.marker_sections'),
          ('public.marker_section_rows')) rels(rel)
        WHERE NOT pg_catalog.has_table_privilege(roles.role_name,rels.rel,'SELECT')
          OR NOT pg_catalog.has_schema_privilege(roles.role_name,'public','USAGE')
          OR NOT pg_catalog.has_schema_privilege(roles.role_name,'private','USAGE')) THEN
        RAISE EXCEPTION 'B7H2C_PUBLIC_READ_DEPENDENCY_GRANTS';
    END IF;
    -- Structural UUID ownership: require the established validated composite FKs.
    FOR v IN SELECT * FROM (VALUES
        ('public.map_layers','public.game_maps',ARRAY['game_map_id','game_uuid']::text[],ARRAY['id','game_id']::text[]),
        ('public.marcadores','public.map_layers',ARRAY['game_id','map_layer','game_uuid','layer_uuid']::text[],ARRAY['game_id','id','game_uuid','layer_uuid']::text[]),
        ('public.map_labels','public.map_layers',ARRAY['game_id','map_layer','game_uuid','layer_uuid']::text[],ARRAY['game_id','id','game_uuid','layer_uuid']::text[]),
        ('public.game_maps','public.games',ARRAY['game_id']::text[],ARRAY['id']::text[]),
        ('public.game_modules','public.games',ARRAY['game_id']::text[],ARRAY['id']::text[])
    ) e(rel,parent,cols,parent_cols) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            WHERE c.conrelid=pg_catalog.to_regclass(v.rel) AND c.confrelid=pg_catalog.to_regclass(v.parent)
              AND c.contype='f' AND c.convalidated AND NOT c.condeferrable
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos)
                JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=v.cols
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num,pos)
                JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)=v.parent_cols) THEN
            RAISE EXCEPTION 'B7H2C_UUID_PARENT_FOREIGN_KEY: %',v.rel;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid='auth.users'::pg_catalog.regclass AND NOT t.tgisinternal
          AND (t.tgtype::integer & 16)<>0 AND t.tgname<>'deepmap_auth_public_profile_sync') THEN
        RAISE EXCEPTION 'B7H2C_UNKNOWN_AUTH_UPDATE_TRIGGER_REQUIRES_REVIEW';
    END IF;

    -- Exact bodies from repository, not loose substring checks. No unknown writer is replaced.
    FOR v IN SELECT * FROM (VALUES
        ('private.marker_is_public(bigint)', 'selectexists(select1frompublic.marcadoresasmwherem.id=p_marker_idandm.is_published=true);', 'sql', 'boolean', 's', true, ARRAY['anon','authenticated']::text[]),
        ('public.set_deepmap_username(text)', 'declarev_user_iduuid:=(selectauth.uid());v_candidatetext:=lower(btrim(coalesce(p_username,'''')));beginifv_user_idisnullthenraiseexception''auth_required''usingerrcode=''p0001'';endif;performpublic.ensure_deepmap_profile();ifv_candidate!~''^[a-z0-9_]{3,20}$''thenraiseexception''username_format''usingerrcode=''p0001'';endif;--thetabletriggeristheauthoritativevalidator/cooldownguard.updatepublic.profilespsetusername=v_candidatewherep.id=v_user_id;returnqueryselectp.username,p.username_changed_at,p.username_is_generatedfrompublic.profilespwherep.id=v_user_id;end;', 'plpgsql', 'record', 'v', true, ARRAY['authenticated']::text[]),
        ('private.sync_auth_public_profile()', 'declaresnapshotjsonb;beginsnapshot:=private.profile_public_snapshot(new.id,coalesce(new.raw_user_meta_data,''{}''::jsonb));updatepublic.profilessetpublic_display_name=snapshot->>''display_name'',public_bio=snapshot->>''bio'',public_avatar_choice=snapshot->>''avatar_choice'',public_avatar_path=snapshot->>''avatar_path'',public_google_avatar_url=snapshot->>''google_avatar_url''whereid=new.id;returnnew;end;', 'plpgsql', 'trigger', 'v', true, ARRAY[]::text[]),
        ('private.is_deepmap_banned(uuid)', 'selectexists(select1fromprivate.deepmap_bansasbwhereb.user_id=p_user_idandb.lifted_atisnulland(b.expires_atisnullorb.expires_at>now()));', 'sql', 'boolean', 's', true, ARRAY[]::text[]),
        ('private.is_deepmap_banned()', 'selectprivate.is_deepmap_banned((selectauth.uid()));', 'sql', 'boolean', 's', true, ARRAY['authenticated']::text[]),
        ('public.can_deepmap_interact()', 'select(selectauth.uid())isnotnullandnotprivate.is_deepmap_banned();', 'sql', 'boolean', 's', true, ARRAY['authenticated']::text[]),
        ('public.cancel_marker_submission(bigint)', 'beginupdatepublic.marker_submissionssetstatus=''cancelled'',updated_at=now()whereid=p_submission_idandsubmitted_by=(selectauth.uid())andstatus=''pending'';ifnotfoundthenraiseexception''submission_not_cancellable''usingerrcode=''p0001'';endif;end;', 'plpgsql', 'void', 'v', true, ARRAY['authenticated']::text[]),
        ('private.section_marker_id(bigint)', 'selects.marker_idfrompublic.marker_sectionsasswheres.id=p_section_id;', 'sql', 'bigint', 's', true, ARRAY['anon','authenticated']::text[]),
        ('private.profile_public_snapshot(uuid,jsonb)', 'selectpg_catalog.jsonb_build_object(''display_name'',pg_catalog.left(coalesce(nullif(pg_catalog.btrim(p_metadata->>''display_name''),''''),nullif(pg_catalog.btrim(p_metadata->>''full_name''),''''),nullif(pg_catalog.btrim(p_metadata->>''name''),''''),''explorer''),40),''bio'',pg_catalog.left(coalesce(p_metadata->>''bio'',''''),200),''avatar_choice'',casewhenp_metadata->>''avatar_choice''in(''explorador'',''cartografo'',''cavaleiro'',''feiticeiro'',''ladino'',''errante'',''custom'',''google'',''initial'')thenp_metadata->>''avatar_choice''whencoalesce(p_metadata->>''avatar_url'',p_metadata->>''picture'')~''^https://lh[0-9]+[.]googleusercontent[.]com/''then''google''else''initial''end,''avatar_path'',casewhenp_metadata->>''avatar_custom_path''~(''^''||p_user_id::text||''/avatar-[0-9a-f-]{36}[.]webp$'')thenp_metadata->>''avatar_custom_path''elsenullend,''google_avatar_url'',casewhencoalesce(p_metadata->>''avatar_url'',p_metadata->>''picture'')~''^https://lh[0-9]+[.]googleusercontent[.]com/''thencoalesce(p_metadata->>''avatar_url'',p_metadata->>''picture'')elsenullend);', 'sql', 'jsonb', 's', false, ARRAY[]::text[])
    ) e(sig,body,lang,ret,vol,definer,roles) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
            WHERE p.oid=pg_catalog.to_regprocedure(v.sig) AND p.prokind='f'
              AND l.lanname=v.lang AND p.prorettype=pg_catalog.to_regtype(v.ret)
              AND p.provolatile::text=v.vol AND p.prosecdef=v.definer
              AND p.proconfig=ARRAY['search_path=""']::text[]
              AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u'
              AND pg_catalog.lower(pg_catalog.regexp_replace(p.prosrc,'[[:space:]]','','g'))=v.body) THEN
            RAISE EXCEPTION 'B7H2C_FUNCTION_CONTRACT: %',v.sig;
        END IF;
        IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
            CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
            WHERE p.oid=pg_catalog.to_regprocedure(v.sig) AND a.privilege_type='EXECUTE'
              AND (a.grantee=0 OR (a.grantee<>p.proowner AND a.grantee<>COALESCE((SELECT oid FROM pg_catalog.pg_roles WHERE rolname='service_role'),0) AND
                NOT a.grantee=ANY(ARRAY(SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname=ANY(v.roles)))))
        ) OR EXISTS (SELECT 1 FROM pg_catalog.unnest(v.roles) allowed(role_name)
            WHERE NOT pg_catalog.has_function_privilege(allowed.role_name,v.sig,'EXECUTE'))
          OR EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated')) browser(role_name)
            WHERE NOT browser.role_name=ANY(v.roles)
              AND pg_catalog.has_function_privilege(browser.role_name,v.sig,'EXECUTE'))
          OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
            CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
            JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
            WHERE p.oid=pg_catalog.to_regprocedure(v.sig) AND r.rolname IN ('anon','authenticated') AND a.is_grantable) THEN
            RAISE EXCEPTION 'B7H2C_FUNCTION_EXECUTE_ACL: %',v.sig;
        END IF;
    END LOOP;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
        WHERE c.oid=pg_catalog.to_regclass('private.deepmap_bans') AND c.relkind='r' AND c.relrowsecurity)
       OR EXISTS (SELECT 1 FROM (VALUES ('user_id','uuid',true),
          ('lifted_at','timestamp with time zone',false),('expires_at','timestamp with time zone',false)) e(col,typ,nn)
        LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid=pg_catalog.to_regclass('private.deepmap_bans')
          AND a.attname=e.col AND a.attnum>0 AND NOT a.attisdropped
        WHERE a.attname IS NULL OR a.atttypid<>pg_catalog.to_regtype(e.typ) OR a.attnotnull<>e.nn)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
        WHERE p.oid='private.is_deepmap_banned(uuid)'::pg_catalog.regprocedure
          AND (r.rolsuper OR r.rolbypassrls)
          AND pg_catalog.has_table_privilege(p.proowner,'private.deepmap_bans','SELECT')) THEN
        RAISE EXCEPTION 'B7H2C_CANONICAL_BAN_DEPENDENCY';
    END IF;

    -- The marker helper must safely bypass marker RLS to avoid self-recursion.
    -- Both privileged writers must retain a trusted owner; no owner/ACL changes are made.
    FOR v IN SELECT p.* FROM pg_catalog.pg_proc p WHERE p.oid IN (
        'private.marker_is_public(bigint)'::pg_catalog.regprocedure,
        'public.set_deepmap_username(text)'::pg_catalog.regprocedure,
        'private.sync_auth_public_profile()'::pg_catalog.regprocedure) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.oid=v.proowner AND (r.rolsuper OR r.rolbypassrls)) THEN
            RAISE EXCEPTION 'B7H2C_PRIVILEGED_OWNER_REQUIRES_REVIEW: %',v.oid::pg_catalog.regprocedure;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        CROSS JOIN (VALUES ('public.marcadores'),('public.map_layers'),('public.game_maps'),('public.games'),('public.game_modules')) e(rel)
        WHERE p.oid='private.marker_is_public(bigint)'::pg_catalog.regprocedure
          AND NOT pg_catalog.has_table_privilege(p.proowner,pg_catalog.to_regclass(e.rel),'SELECT')) THEN
        RAISE EXCEPTION 'B7H2C_MARKER_HELPER_OWNER_READ_ACCESS';
    END IF;
    -- Normalize formatting/text casts, scalar auth.uid wrappers and generated aliases only.
    -- Exact command, role set and permissiveness are checked independently.
    FOR v IN SELECT * FROM (VALUES
        ('public.profiles','profiles_public_read','r',ARRAY['anon','authenticated']::text[],'true',NULL::text),
        ('public.profiles','profiles_insert_own','a',ARRAY['authenticated']::text[],'','auth.uid=id'),
        ('public.profiles','profiles_update_own','w',ARRAY['authenticated']::text[],'auth.uid=idandnotprivate.is_deepmap_banned','auth.uid=idandnotprivate.is_deepmap_banned'),
        ('public.games','games_public_read','r',ARRAY['anon','authenticated']::text[],'status=anyarray[''coming_soon'',''published'']',NULL::text),
        ('public.game_modules','game_modules_public_read','r',ARRAY['anon','authenticated']::text[],'enabledandexistsselect1frompublic.gamesgwhereg.id=game_modules.game_idandg.status=''published''',NULL::text),
        ('public.game_maps','game_maps_public_read','r',ARRAY['anon','authenticated']::text[],'status=''published''andexistsselect1frompublic.gamesgwhereg.id=game_maps.game_idandg.status=''published''andexistsselect1frompublic.game_modulesmwherem.game_id=game_maps.game_idandm.module_key=''map''andm.enabled',NULL::text),
        ('public.games','games_admin_all','*',ARRAY['authenticated']::text[],'selectpublic.get_deepmap_roleasget_deepmap_role=''admin''','selectpublic.get_deepmap_roleasget_deepmap_role=''admin'''),
        ('public.game_modules','game_modules_admin_all','*',ARRAY['authenticated']::text[],'selectpublic.get_deepmap_roleasget_deepmap_role=''admin''','selectpublic.get_deepmap_roleasget_deepmap_role=''admin'''),
        ('public.game_maps','game_maps_admin_all','*',ARRAY['authenticated']::text[],'selectpublic.get_deepmap_roleasget_deepmap_role=''admin''','selectpublic.get_deepmap_roleasget_deepmap_role=''admin'''),
        ('public.map_layers','map_layers_public_read','r',ARRAY['anon','authenticated']::text[],'is_active=true',NULL::text),
        ('public.map_layers','map_layers_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('public.marker_category_groups','marker_category_groups_public_read','r',ARRAY['anon','authenticated']::text[],'is_active=true',NULL::text),
        ('public.marker_category_groups','marker_category_groups_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('public.marker_categories','marker_categories_public_read','r',ARRAY['anon','authenticated']::text[],'is_active=true',NULL::text),
        ('public.marker_categories','marker_categories_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('public.marcadores','marcadores_public_read','r',ARRAY['anon','authenticated']::text[],'is_published=true',NULL::text),
        ('public.marcadores','marcadores_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('public.map_labels','map_labels_public_read','r',ARRAY['anon','authenticated']::text[],'is_published=true',NULL::text),
        ('public.map_labels','map_labels_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('public.marker_images','marker_images_public_read','r',ARRAY['anon','authenticated']::text[],'private.marker_is_publicmarker_id',NULL::text),
        ('public.marker_images','marker_images_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('public.marker_sections','marker_sections_public_read','r',ARRAY['anon','authenticated']::text[],'private.marker_is_publicmarker_id',NULL::text),
        ('public.marker_sections','marker_sections_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('public.marker_section_rows','marker_section_rows_public_read','r',ARRAY['anon','authenticated']::text[],'private.marker_is_publicprivate.section_marker_idsection_id',NULL::text),
        ('public.marker_section_rows','marker_section_rows_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('storage.objects','deepmap_avatars_select_own','r',ARRAY['authenticated']::text[],'bucket_id=''avatars''andstorage.foldernamename[1]=auth.uid',NULL::text),
        ('storage.objects','deepmap_avatars_insert_own','a',ARRAY['authenticated']::text[],'','bucket_id=''avatars''andstorage.foldernamename[1]=auth.uidandarray_lengthstorage.foldernamename,1=1andlowerstorage.extensionname=anyarray[''jpg'',''jpeg'',''png'',''webp'']'),
        ('storage.objects','deepmap_avatars_delete_own','d',ARRAY['authenticated']::text[],'bucket_id=''avatars''andstorage.foldernamename[1]=auth.uidandowner_id=auth.uid',NULL::text),
        ('public.marker_submissions','marker_submissions_insert_own','a',ARRAY['authenticated']::text[],'','public.can_deepmap_interactandsubmitted_by=auth.uidandstatus=''pending''andreviewed_byisnullandreviewed_atisnullandreview_noteisnullandexistsselect1frompublic.profilespwherep.id=auth.uidandnullifbtrimp.username,''''isnotnull'),
        ('public.marker_submissions','marker_submissions_update_own_pending','w',ARRAY['authenticated']::text[],'notprivate.is_deepmap_bannedandsubmitted_by=auth.uidandstatus=''pending''','notprivate.is_deepmap_bannedandsubmitted_by=auth.uidandstatus=''pending'''),
        ('public.marker_submissions','marker_submissions_read_own_or_staff','r',ARRAY['authenticated']::text[],'submitted_by=auth.uidandnotprivate.is_deepmap_bannedorprivate.can_moderate_deepmap',NULL::text)
    ) e(rel,name,cmd,roles,qual,chk) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p
            WHERE p.polrelid=pg_catalog.to_regclass(v.rel) AND p.polname=v.name
              AND p.polcmd::text=v.cmd AND p.polpermissive
              AND ARRAY(SELECT r.rolname::text FROM pg_catalog.unnest(p.polroles) u(id)
                JOIN pg_catalog.pg_roles r ON r.oid=u.id ORDER BY r.rolname)=v.roles
              AND pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'')), 'as (uid|can_deepmap_interact)\M', '', 'g'), '::text', ''), '[[:space:]()]', '', 'g'), 'selectauth.uid', 'auth.uid')=v.qual
              AND pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),'')), 'as (uid|can_deepmap_interact)\M', '', 'g'), '::text', ''), '[[:space:]()]', '', 'g'), 'selectauth.uid', 'auth.uid')=COALESCE(v.chk,'')
              AND (p.polqual IS NULL)=(v.qual='')
              AND (p.polwithcheck IS NULL)=(v.chk IS NULL)) THEN
            -- Two known profiles baselines only: historical true, or verified live privacy.
            IF v.name='profiles_public_read' AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p
                WHERE p.polrelid='public.profiles'::pg_catalog.regclass AND p.polname=v.name
                  AND p.polcmd='r' AND p.polpermissive AND p.polwithcheck IS NULL
                  AND ARRAY(SELECT r.rolname::text FROM pg_catalog.unnest(p.polroles) u(id)
                    JOIN pg_catalog.pg_roles r ON r.oid=u.id ORDER BY r.rolname)=v.roles
                  AND pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'')), 'as (uid|can_deepmap_interact)\M', '', 'g'), '::text', ''), '[[:space:]()]', '', 'g'), 'selectauth.uid', 'auth.uid')='is_public=trueorid=auth.uid') THEN
                CONTINUE;
            END IF;
            RAISE EXCEPTION 'B7H2C_POLICY_CONTRACT: %.%',v.rel,v.name;
        END IF;
    END LOOP;
    -- Fail closed on ALL unrecognized policies on protected public relations.
    -- This also rejects role-inherited/PUBLIC permissive bypasses, not just literal role names.
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid IN (
        'public.profiles'::pg_catalog.regclass,'public.games'::pg_catalog.regclass,'public.game_modules'::pg_catalog.regclass,'public.game_maps'::pg_catalog.regclass,'public.map_layers'::pg_catalog.regclass,'public.marker_category_groups'::pg_catalog.regclass,'public.marker_categories'::pg_catalog.regclass,'public.marcadores'::pg_catalog.regclass,'public.map_labels'::pg_catalog.regclass,'public.marker_images'::pg_catalog.regclass,'public.marker_sections'::pg_catalog.regclass,'public.marker_section_rows'::pg_catalog.regclass,'public.marker_submissions'::pg_catalog.regclass)
        AND NOT EXISTS (SELECT 1 FROM (VALUES ('public.profiles','profiles_public_read'),('public.profiles','profiles_insert_own'),('public.profiles','profiles_update_own'),('public.games','games_public_read'),('public.game_modules','game_modules_public_read'),('public.game_maps','game_maps_public_read'),('public.games','games_admin_all'),('public.game_modules','game_modules_admin_all'),('public.game_maps','game_maps_admin_all'),('public.map_layers','map_layers_public_read'),('public.map_layers','map_layers_admin_all'),('public.marker_category_groups','marker_category_groups_public_read'),('public.marker_category_groups','marker_category_groups_admin_all'),('public.marker_categories','marker_categories_public_read'),('public.marker_categories','marker_categories_admin_all'),('public.marcadores','marcadores_public_read'),('public.marcadores','marcadores_admin_all'),('public.map_labels','map_labels_public_read'),('public.map_labels','map_labels_admin_all'),('public.marker_images','marker_images_public_read'),('public.marker_images','marker_images_admin_all'),('public.marker_sections','marker_sections_public_read'),('public.marker_sections','marker_sections_admin_all'),('public.marker_section_rows','marker_section_rows_public_read'),('public.marker_section_rows','marker_section_rows_admin_all'),('public.marker_submissions','marker_submissions_insert_own'),('public.marker_submissions','marker_submissions_update_own_pending'),('public.marker_submissions','marker_submissions_read_own_or_staff')) e(rel,name)
            WHERE p.polrelid=pg_catalog.to_regclass(e.rel) AND p.polname=e.name)) THEN
        RAISE EXCEPTION 'B7H2C_UNEXPECTED_POLICY_POSSIBLE_PERMISSIVE_OR_BYPASS';
    END IF;
    -- Conservative storage baseline: unknown INSERT/UPDATE/DELETE/ALL policies require review,
    -- since arbitrary predicates cannot safely be assumed disjoint from the avatars bucket.
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_policy p
        WHERE p.polrelid='storage.objects'::pg_catalog.regclass AND p.polcmd<>'r'
          AND p.polname NOT IN ('deepmap_avatars_insert_own','deepmap_avatars_delete_own')) THEN
        RAISE EXCEPTION 'B7H2C_UNKNOWN_STORAGE_MUTATION_POLICY_REVIEW_REQUIRED';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM storage.buckets b WHERE b.id='avatars' AND b.public
        AND b.file_size_limit=2097152
        AND ARRAY(SELECT x FROM pg_catalog.unnest(b.allowed_mime_types) x ORDER BY x)
          =ARRAY['image/jpeg','image/png','image/webp']::text[]) THEN
        RAISE EXCEPTION 'B7H2C_AVATAR_BUCKET_SETTINGS';
    END IF;
    -- Exact existing AFTER UPDATE OF metadata trigger, including WHEN filter and target.
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid='auth.users'::pg_catalog.regclass AND t.tgname='deepmap_auth_public_profile_sync'
          AND t.tgfoid='private.sync_auth_public_profile()'::pg_catalog.regprocedure
          AND t.tgtype=17 AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgnargs=0
          AND t.tgattr::text=(SELECT a.attnum::text FROM pg_catalog.pg_attribute a
            WHERE a.attrelid=t.tgrelid AND a.attname='raw_user_meta_data' AND NOT a.attisdropped)
          AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_triggerdef(t.oid)),
            '[[:space:]()]','','g')='createtriggerdeepmap_auth_public_profile_syncafterupdateofraw_user_meta_dataonauth.usersforeachrowwhenold.raw_user_meta_dataisdistinctfromnew.raw_user_meta_dataexecutefunctionprivate.sync_auth_public_profile') THEN
        RAISE EXCEPTION 'B7H2C_AUTH_SYNC_TRIGGER_CONTRACT';
    END IF;

    SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid='public.profiles'::pg_catalog.regclass AND a.attname='is_public' AND NOT a.attisdropped)
        INTO v_had_is_public;
    -- Capture exact owners, signatures, raw ACL and all pg_proc attributes before replacement.
    FOR v IN SELECT p.oid::pg_catalog.regprocedure AS signature,
        pg_catalog.pg_get_userbyid(p.proowner) AS owner,p.proacl,p.prosecdef,p.proconfig
        FROM pg_catalog.pg_proc p WHERE p.oid IN (
          'private.marker_is_public(bigint)'::pg_catalog.regprocedure,
          'public.set_deepmap_username(text)'::pg_catalog.regprocedure,
          'private.sync_auth_public_profile()'::pg_catalog.regprocedure) LOOP
        RAISE NOTICE 'B7H2C_FUNCTION_BASELINE signature=% owner=% acl=% definer=% config=%',
            v.signature,v.owner,v.proacl,v.prosecdef,v.proconfig;
    END LOOP;
    SELECT pg_catalog.jsonb_build_object(
        'functions', (SELECT COALESCE(pg_catalog.jsonb_agg(
          CASE WHEN p.oid IN ('private.marker_is_public(bigint)'::pg_catalog.regprocedure,
            'public.set_deepmap_username(text)'::pg_catalog.regprocedure,
            'private.sync_auth_public_profile()'::pg_catalog.regprocedure)
          THEN pg_catalog.to_jsonb(p)-'prosrc' ELSE pg_catalog.to_jsonb(p) END ORDER BY p.oid),'[]'::jsonb)
          FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname IN ('public','private')),
        'policies', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid),'[]'::jsonb)
          FROM pg_catalog.pg_policy p WHERE NOT EXISTS (SELECT 1 FROM (VALUES
            ('public.profiles','profiles_public_read'),
            ('public.map_layers','map_layers_public_read'),
            ('public.marker_category_groups','marker_category_groups_public_read'),
            ('public.marker_categories','marker_categories_public_read'),
            ('public.marcadores','marcadores_public_read'),
            ('public.map_labels','map_labels_public_read'),
            ('storage.objects','deepmap_avatars_insert_own'),
            ('storage.objects','deepmap_avatars_delete_own')
          ) e(rel,name) WHERE p.polrelid=pg_catalog.to_regclass(e.rel) AND p.polname=e.name)),
        'relations', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c)-'relnatts'-'relpages'-'reltuples'-'relallvisible'-'relallfrozen'-'relfilenode' ORDER BY c.oid)
          FROM pg_catalog.pg_class c WHERE c.oid=ANY(v_relations)),
        'columns', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attrelid,a.attnum)
          FROM pg_catalog.pg_attribute a WHERE a.attrelid=ANY(v_relations) AND a.attnum>0 AND NOT a.attisdropped
            AND NOT (a.attrelid='public.profiles'::pg_catalog.regclass AND a.attname='is_public')),
        'defaults', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.oid),'[]'::jsonb)
          FROM pg_catalog.pg_attrdef d JOIN pg_catalog.pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
          WHERE d.adrelid=ANY(v_relations) AND NOT (d.adrelid='public.profiles'::pg_catalog.regclass AND a.attname='is_public')),
        'constraints', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid),'[]'::jsonb)
          FROM pg_catalog.pg_constraint c WHERE c.conrelid=ANY(v_relations)),
        'triggers', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY t.oid),'[]'::jsonb)
          FROM pg_catalog.pg_trigger t WHERE t.tgrelid=ANY(v_relations||ARRAY['auth.users'::pg_catalog.regclass::oid])),
        'namespaces', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(n) ORDER BY n.oid)
          FROM pg_catalog.pg_namespace n WHERE n.nspname IN ('public','private','auth','storage'))
    ) INTO v_catalog_before;
    v_data_now := '{}'::jsonb;
    FOREACH v_rel IN ARRAY v_relations LOOP
        -- Fixed, validated relation whitelist only. No exposed dynamic-SQL helper.
        -- Hashes stay in transaction memory and are never printed or persisted.
        EXECUTE pg_catalog.format(
            'SELECT pg_catalog.jsonb_build_object(''count'',pg_catalog.count(*),''digest'',pg_catalog.md5(COALESCE(pg_catalog.string_agg(h, '''' ORDER BY h),''''))) FROM (SELECT pg_catalog.md5((pg_catalog.to_jsonb(r) %s)::text) h FROM %s r) s',
            CASE WHEN v_rel='public.profiles'::pg_catalog.regclass AND NOT v_had_is_public THEN '- ''is_public''' ELSE '' END,
            v_rel::pg_catalog.regclass) INTO v_rows;
        v_data_now := v_data_now || pg_catalog.jsonb_build_object(v_rel::text,v_rows);
    END LOOP;
    v_data_before := v_data_now;

    -- The only column delta; existing private/public choices are never rewritten.
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid='public.profiles'::pg_catalog.regclass AND a.attname='is_public' AND NOT a.attisdropped) THEN
        ALTER TABLE public.profiles ADD COLUMN is_public boolean NOT NULL DEFAULT true;
    END IF;

create or replace function private.marker_is_public(p_marker_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.marcadores as m
        join public.map_layers as l
          on l.layer_uuid = m.layer_uuid and l.game_uuid = m.game_uuid
        join public.game_maps as gm
          on gm.id = l.game_map_id and gm.game_id = m.game_uuid
        join public.games as g on g.id = m.game_uuid
        where m.id = p_marker_id
          and m.is_published = true
          and l.is_active = true
          and gm.status = 'published'
          and g.status = 'published'
          and exists (
              select 1 from public.game_modules as mod
              where mod.game_id = g.id and mod.module_key = 'map' and mod.enabled
          )
    );
$$;

create or replace function public.set_deepmap_username(p_username text)
returns table (
    username text,
    username_changed_at timestamptz,
    username_is_generated boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := (select auth.uid());
    v_candidate text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_username, '')));
begin
    if v_user_id is null then
        raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
    end if;

    -- Fail closed before profile creation or username mutation.
    if public.can_deepmap_interact() is distinct from true then
        raise exception 'INTERACTION_NOT_ALLOWED' using errcode = 'P0001';
    end if;

    perform public.ensure_deepmap_profile();

    if v_candidate !~ '^[a-z0-9_]{3,20}$' then
        raise exception 'username_format' using errcode = 'P0001';
    end if;

    -- The table trigger is the authoritative validator/cooldown guard.
    update public.profiles p
       set username = v_candidate
     where p.id = v_user_id;

    return query
    select p.username, p.username_changed_at, p.username_is_generated
      from public.profiles p
     where p.id = v_user_id;
end;
$$;

create or replace function private.sync_auth_public_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    snapshot jsonb;
begin
    -- Use the affected account UUID, never the SQL Editor/service caller's uid.
    -- Preserve presentation without rejecting Auth security/provider updates.
    if private.is_deepmap_banned(new.id) is distinct from false then
        return new;
    end if;

    snapshot := private.profile_public_snapshot(
        new.id,
        coalesce(new.raw_user_meta_data, '{}'::jsonb)
    );

    update public.profiles
       set public_display_name = snapshot ->> 'display_name',
           public_bio = snapshot ->> 'bio',
           public_avatar_choice = snapshot ->> 'avatar_choice',
           public_avatar_path = snapshot ->> 'avatar_path',
           public_google_avatar_url = snapshot ->> 'google_avatar_url'
     where id = new.id;

    return new;
end;
$$;

ALTER POLICY profiles_public_read ON public.profiles TO anon, authenticated
USING (is_public = true OR id = (SELECT auth.uid()));

ALTER POLICY map_layers_public_read ON public.map_layers TO anon, authenticated
USING (is_active = true AND EXISTS (
    SELECT 1 FROM public.game_maps gm
    JOIN public.games g ON g.id = gm.game_id
    WHERE gm.id = map_layers.game_map_id AND gm.game_id = map_layers.game_uuid
      AND gm.status = 'published' AND g.status = 'published'
      AND EXISTS (SELECT 1 FROM public.game_modules mod
        WHERE mod.game_id = g.id AND mod.module_key = 'map' AND mod.enabled)
));

ALTER POLICY marker_category_groups_public_read ON public.marker_category_groups TO anon, authenticated
USING (is_active = true AND EXISTS (
    SELECT 1 FROM public.games g
    WHERE g.id = marker_category_groups.game_uuid AND g.status = 'published'
      AND EXISTS (SELECT 1 FROM public.game_modules mod
        WHERE mod.game_id = g.id AND mod.module_key = 'map' AND mod.enabled)
));

ALTER POLICY marker_categories_public_read ON public.marker_categories TO anon, authenticated
USING (is_active = true AND EXISTS (
    SELECT 1 FROM public.games g
    WHERE g.id = marker_categories.game_uuid AND g.status = 'published'
      AND EXISTS (SELECT 1 FROM public.game_modules mod
        WHERE mod.game_id = g.id AND mod.module_key = 'map' AND mod.enabled)
));

ALTER POLICY marcadores_public_read ON public.marcadores TO anon, authenticated
USING (private.marker_is_public(id));

ALTER POLICY map_labels_public_read ON public.map_labels TO anon, authenticated
USING (is_published = true AND EXISTS (
    SELECT 1 FROM public.map_layers l
    JOIN public.game_maps gm ON gm.id = l.game_map_id AND gm.game_id = l.game_uuid
    JOIN public.games g ON g.id = l.game_uuid
    WHERE l.layer_uuid = map_labels.layer_uuid AND l.game_uuid = map_labels.game_uuid
      AND l.is_active = true AND gm.status = 'published' AND g.status = 'published'
      AND EXISTS (SELECT 1 FROM public.game_modules mod
        WHERE mod.game_id = g.id AND mod.module_key = 'map' AND mod.enabled)
));

ALTER POLICY deepmap_avatars_insert_own ON storage.objects TO authenticated

WITH CHECK ((bucket_id = 'avatars' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text AND array_length(storage.foldername(name), 1) = 1 AND lower(storage.extension(name)) = ANY (ARRAY['jpg'::text,'jpeg'::text,'png'::text,'webp'::text])) AND (SELECT public.can_deepmap_interact()));

ALTER POLICY deepmap_avatars_delete_own ON storage.objects TO authenticated
USING ((bucket_id = 'avatars' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text AND owner_id = (SELECT auth.uid())::text) AND (SELECT public.can_deepmap_interact()));

    -- Cancellation is an explicit hygiene exception: its exact original body/ACL stays intact.

    -- Required ordinary RLS relations; full maintenance visibility is mandatory.
    FOR v IN SELECT * FROM (VALUES ('public.profiles'),('public.games'),('public.game_modules'),('public.game_maps'),('public.map_layers'),('public.marker_category_groups'),('public.marker_categories'),('public.marcadores'),('public.map_labels'),('public.marker_images'),('public.marker_sections'),('public.marker_section_rows'),('public.marker_submissions'),('storage.objects'),('storage.buckets')) e(rel) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.rolname = CURRENT_USER
            WHERE c.oid = pg_catalog.to_regclass(v.rel) AND c.relkind = 'r' AND c.relrowsecurity
              AND pg_catalog.has_table_privilege(c.oid, 'SELECT')
              AND (r.rolsuper OR r.rolbypassrls OR (r.oid = c.relowner AND NOT c.relforcerowsecurity))) THEN
            RAISE EXCEPTION 'B7H2C_RELATION_OR_MAINTENANCE_VISIBILITY: %',v.rel;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public.profiles','id','uuid'),
        ('public.profiles','username','text'),
        ('public.profiles','public_display_name','text'),
        ('public.profiles','public_bio','text'),
        ('public.profiles','public_avatar_choice','text'),
        ('public.games','id','uuid'),
        ('public.games','status','text'),
        ('public.game_modules','game_id','uuid'),
        ('public.game_modules','module_key','text'),
        ('public.game_modules','enabled','boolean'),
        ('public.game_maps','id','uuid'),
        ('public.game_maps','game_id','uuid'),
        ('public.game_maps','status','text'),
        ('public.map_layers','game_uuid','uuid'),
        ('public.marker_category_groups','game_uuid','uuid'),
        ('public.marker_categories','game_uuid','uuid'),
        ('public.marcadores','game_uuid','uuid'),
        ('public.map_labels','game_uuid','uuid'),
        ('public.map_layers','layer_uuid','uuid'),
        ('public.map_layers','game_map_id','uuid'),
        ('public.map_layers','is_active','boolean'),
        ('public.marker_category_groups','is_active','boolean'),
        ('public.marker_categories','is_active','boolean'),
        ('public.marcadores','id','bigint'),
        ('public.marcadores','layer_uuid','uuid'),
        ('public.marcadores','is_published','boolean'),
        ('public.map_labels','layer_uuid','uuid'),
        ('public.map_labels','is_published','boolean'),
        ('public.marker_images','marker_id','bigint'),
        ('public.marker_sections','marker_id','bigint'),
        ('public.marker_section_rows','section_id','bigint'),
        ('auth.users','id','uuid')
    ) e(rel,col,typ) LEFT JOIN pg_catalog.pg_attribute a
      ON a.attrelid=pg_catalog.to_regclass(e.rel) AND a.attname=e.col AND a.attnum>0 AND NOT a.attisdropped
      WHERE a.attname IS NULL OR a.atttypid<>pg_catalog.to_regtype(e.typ) OR NOT a.attnotnull) THEN
        RAISE EXCEPTION 'B7H2C_REQUIRED_COLUMN_SHAPE';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.profiles'::pg_catalog.regclass AND c.contype='p'
          AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=c.conrelid AND attname='id')]::smallint[]
          AND c.convalidated AND NOT c.condeferrable)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.profiles'::pg_catalog.regclass AND c.contype='f'
          AND c.confrelid='auth.users'::pg_catalog.regclass AND c.convalidated AND NOT c.condeferrable
          AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=c.conrelid AND attname='id')]::smallint[]
          AND c.confkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=c.confrelid AND attname='id')]::smallint[]) THEN
        RAISE EXCEPTION 'B7H2C_PROFILE_IDENTITY_RELATIONSHIP';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d
        ON d.adrelid=a.attrelid AND d.adnum=a.attnum
        WHERE a.attrelid='public.profiles'::pg_catalog.regclass AND a.attname='is_public' AND NOT a.attisdropped
          AND (a.atttypid<>'boolean'::pg_catalog.regtype OR NOT a.attnotnull OR a.attgenerated<>'' OR a.attidentity<>''
            OR pg_catalog.pg_get_expr(d.adbin,d.adrelid) IS DISTINCT FROM 'true'))
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.profiles'::pg_catalog.regclass
          AND a.attname='is_public' AND NOT a.attisdropped) THEN
        RAISE EXCEPTION 'B7H2C_IS_PUBLIC_SHAPE_DEFAULT';
    END IF;
    IF (SELECT pg_catalog.pg_get_userbyid(c.relowner) FROM pg_catalog.pg_class c WHERE c.oid='public.profiles'::pg_catalog.regclass)<>'postgres'
       OR (SELECT c.relforcerowsecurity FROM pg_catalog.pg_class c WHERE c.oid='public.profiles'::pg_catalog.regclass) THEN
        RAISE EXCEPTION 'B7H2C_LIVE_PROFILE_OWNER_OR_FORCED_RLS_DRIFT';
    END IF;
    IF EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated')) e(role_name)
        WHERE NOT pg_catalog.has_table_privilege(e.role_name,'public.profiles','SELECT'))
       OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid='public.profiles'::pg_catalog.regclass AND NOT a.attisdropped AND a.attnum>0
          AND (a.attname ILIKE '%email%' OR a.attname IN ('raw_user_meta_data','raw_app_meta_data','encrypted_password'))) THEN
        RAISE EXCEPTION 'B7H2C_PROFILE_GRANTS_OR_PRIVATE_COLUMN_EXPOSURE';
    END IF;

    -- Nullable presentation projections and username result columns must already exist.
    IF EXISTS (SELECT 1 FROM (VALUES
        ('public_avatar_path','text',false),('public_google_avatar_url','text',false),
        ('joined_at','timestamp with time zone',false),('username_changed_at','timestamp with time zone',false),
        ('username_is_generated','boolean',true)
    ) e(col,typ,nn) LEFT JOIN pg_catalog.pg_attribute a
      ON a.attrelid='public.profiles'::pg_catalog.regclass AND a.attname=e.col AND a.attnum>0 AND NOT a.attisdropped
      WHERE a.attname IS NULL OR a.atttypid<>pg_catalog.to_regtype(e.typ) OR a.attnotnull<>e.nn) THEN
        RAISE EXCEPTION 'B7H2C_PROFILE_PRESENTATION_OR_USERNAME_RESULT_SHAPE';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid='public.set_deepmap_username(text)'::pg_catalog.regprocedure
          AND p.proretset AND p.proargnames=ARRAY['p_username','username','username_changed_at','username_is_generated']::text[]
          AND p.proargmodes=ARRAY['i','t','t','t']::"char"[]
          AND p.proallargtypes=ARRAY['text'::pg_catalog.regtype::oid,'text'::pg_catalog.regtype::oid,
              'timestamp with time zone'::pg_catalog.regtype::oid,'boolean'::pg_catalog.regtype::oid])
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid='private.marker_is_public(bigint)'::pg_catalog.regprocedure
          AND NOT p.proretset AND p.proargnames=ARRAY['p_marker_id']::text[])
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid='private.sync_auth_public_profile()'::pg_catalog.regprocedure AND NOT p.proretset)
       OR pg_catalog.to_regprocedure('public.ensure_deepmap_profile()') IS NULL THEN
        RAISE EXCEPTION 'B7H2C_REPLACED_FUNCTION_SIGNATURE_OR_DEPENDENCY';
    END IF;
    -- Browser roles cannot bypass RLS or inherit privileged function execution.
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles r
        WHERE r.rolname IN ('anon','authenticated') AND (r.rolsuper OR r.rolbypassrls))
       OR EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated')) e(role_name)
        WHERE pg_catalog.has_any_column_privilege(e.role_name,'auth.users','SELECT')) THEN
        RAISE EXCEPTION 'B7H2C_BROWSER_ROLE_OR_AUTH_EXPOSURE';
    END IF;
    IF EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated')) roles(role_name)
        CROSS JOIN (VALUES ('public.games'),('public.game_modules'),('public.game_maps'),
          ('public.map_layers'),('public.marker_category_groups'),('public.marker_categories'),
          ('public.marcadores'),('public.map_labels'),('public.marker_images'),('public.marker_sections'),
          ('public.marker_section_rows')) rels(rel)
        WHERE NOT pg_catalog.has_table_privilege(roles.role_name,rels.rel,'SELECT')
          OR NOT pg_catalog.has_schema_privilege(roles.role_name,'public','USAGE')
          OR NOT pg_catalog.has_schema_privilege(roles.role_name,'private','USAGE')) THEN
        RAISE EXCEPTION 'B7H2C_PUBLIC_READ_DEPENDENCY_GRANTS';
    END IF;
    -- Structural UUID ownership: require the established validated composite FKs.
    FOR v IN SELECT * FROM (VALUES
        ('public.map_layers','public.game_maps',ARRAY['game_map_id','game_uuid']::text[],ARRAY['id','game_id']::text[]),
        ('public.marcadores','public.map_layers',ARRAY['game_id','map_layer','game_uuid','layer_uuid']::text[],ARRAY['game_id','id','game_uuid','layer_uuid']::text[]),
        ('public.map_labels','public.map_layers',ARRAY['game_id','map_layer','game_uuid','layer_uuid']::text[],ARRAY['game_id','id','game_uuid','layer_uuid']::text[]),
        ('public.game_maps','public.games',ARRAY['game_id']::text[],ARRAY['id']::text[]),
        ('public.game_modules','public.games',ARRAY['game_id']::text[],ARRAY['id']::text[])
    ) e(rel,parent,cols,parent_cols) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
            WHERE c.conrelid=pg_catalog.to_regclass(v.rel) AND c.confrelid=pg_catalog.to_regclass(v.parent)
              AND c.contype='f' AND c.convalidated AND NOT c.condeferrable
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num,pos)
                JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num ORDER BY k.pos)=v.cols
              AND ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num,pos)
                JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.num ORDER BY k.pos)=v.parent_cols) THEN
            RAISE EXCEPTION 'B7H2C_UUID_PARENT_FOREIGN_KEY: %',v.rel;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid='auth.users'::pg_catalog.regclass AND NOT t.tgisinternal
          AND (t.tgtype::integer & 16)<>0 AND t.tgname<>'deepmap_auth_public_profile_sync') THEN
        RAISE EXCEPTION 'B7H2C_UNKNOWN_AUTH_UPDATE_TRIGGER_REQUIRES_REVIEW';
    END IF;

    -- Exact bodies from repository, not loose substring checks. No unknown writer is replaced.
    FOR v IN SELECT * FROM (VALUES
        ('private.marker_is_public(bigint)', 'selectexists(select1frompublic.marcadoresasmjoinpublic.map_layersaslonl.layer_uuid=m.layer_uuidandl.game_uuid=m.game_uuidjoinpublic.game_mapsasgmongm.id=l.game_map_idandgm.game_id=m.game_uuidjoinpublic.gamesasgong.id=m.game_uuidwherem.id=p_marker_idandm.is_published=trueandl.is_active=trueandgm.status=''published''andg.status=''published''andexists(select1frompublic.game_modulesasmodwheremod.game_id=g.idandmod.module_key=''map''andmod.enabled));', 'sql', 'boolean', 's', true, ARRAY['anon','authenticated']::text[]),
        ('public.set_deepmap_username(text)', 'declarev_user_iduuid:=(selectauth.uid());v_candidatetext:=pg_catalog.lower(pg_catalog.btrim(coalesce(p_username,'''')));beginifv_user_idisnullthenraiseexception''AUTH_REQUIRED''usingerrcode=''P0001'';endif;--Failclosedbeforeprofilecreationorusernamemutation.ifpublic.can_deepmap_interact()isdistinctfromtruethenraiseexception''INTERACTION_NOT_ALLOWED''usingerrcode=''P0001'';endif;performpublic.ensure_deepmap_profile();ifv_candidate!~''^[a-z0-9_]{3,20}$''thenraiseexception''username_format''usingerrcode=''P0001'';endif;--Thetabletriggeristheauthoritativevalidator/cooldownguard.updatepublic.profilespsetusername=v_candidatewherep.id=v_user_id;returnqueryselectp.username,p.username_changed_at,p.username_is_generatedfrompublic.profilespwherep.id=v_user_id;end;', 'plpgsql', 'record', 'v', true, ARRAY['authenticated']::text[]),
        ('private.sync_auth_public_profile()', 'declaresnapshotjsonb;begin--usetheaffectedaccountuuid,neverthesqleditor/servicecaller''suid.--preservepresentationwithoutrejectingauthsecurity/providerupdates.ifprivate.is_deepmap_banned(new.id)isdistinctfromfalsethenreturnnew;endif;snapshot:=private.profile_public_snapshot(new.id,coalesce(new.raw_user_meta_data,''{}''::jsonb));updatepublic.profilessetpublic_display_name=snapshot->>''display_name'',public_bio=snapshot->>''bio'',public_avatar_choice=snapshot->>''avatar_choice'',public_avatar_path=snapshot->>''avatar_path'',public_google_avatar_url=snapshot->>''google_avatar_url''whereid=new.id;returnnew;end;', 'plpgsql', 'trigger', 'v', true, ARRAY[]::text[]),
        ('private.is_deepmap_banned(uuid)', 'selectexists(select1fromprivate.deepmap_bansasbwhereb.user_id=p_user_idandb.lifted_atisnulland(b.expires_atisnullorb.expires_at>now()));', 'sql', 'boolean', 's', true, ARRAY[]::text[]),
        ('private.is_deepmap_banned()', 'selectprivate.is_deepmap_banned((selectauth.uid()));', 'sql', 'boolean', 's', true, ARRAY['authenticated']::text[]),
        ('public.can_deepmap_interact()', 'select(selectauth.uid())isnotnullandnotprivate.is_deepmap_banned();', 'sql', 'boolean', 's', true, ARRAY['authenticated']::text[]),
        ('public.cancel_marker_submission(bigint)', 'beginupdatepublic.marker_submissionssetstatus=''cancelled'',updated_at=now()whereid=p_submission_idandsubmitted_by=(selectauth.uid())andstatus=''pending'';ifnotfoundthenraiseexception''submission_not_cancellable''usingerrcode=''p0001'';endif;end;', 'plpgsql', 'void', 'v', true, ARRAY['authenticated']::text[]),
        ('private.section_marker_id(bigint)', 'selects.marker_idfrompublic.marker_sectionsasswheres.id=p_section_id;', 'sql', 'bigint', 's', true, ARRAY['anon','authenticated']::text[]),
        ('private.profile_public_snapshot(uuid,jsonb)', 'selectpg_catalog.jsonb_build_object(''display_name'',pg_catalog.left(coalesce(nullif(pg_catalog.btrim(p_metadata->>''display_name''),''''),nullif(pg_catalog.btrim(p_metadata->>''full_name''),''''),nullif(pg_catalog.btrim(p_metadata->>''name''),''''),''explorer''),40),''bio'',pg_catalog.left(coalesce(p_metadata->>''bio'',''''),200),''avatar_choice'',casewhenp_metadata->>''avatar_choice''in(''explorador'',''cartografo'',''cavaleiro'',''feiticeiro'',''ladino'',''errante'',''custom'',''google'',''initial'')thenp_metadata->>''avatar_choice''whencoalesce(p_metadata->>''avatar_url'',p_metadata->>''picture'')~''^https://lh[0-9]+[.]googleusercontent[.]com/''then''google''else''initial''end,''avatar_path'',casewhenp_metadata->>''avatar_custom_path''~(''^''||p_user_id::text||''/avatar-[0-9a-f-]{36}[.]webp$'')thenp_metadata->>''avatar_custom_path''elsenullend,''google_avatar_url'',casewhencoalesce(p_metadata->>''avatar_url'',p_metadata->>''picture'')~''^https://lh[0-9]+[.]googleusercontent[.]com/''thencoalesce(p_metadata->>''avatar_url'',p_metadata->>''picture'')elsenullend);', 'sql', 'jsonb', 's', false, ARRAY[]::text[])
    ) e(sig,body,lang,ret,vol,definer,roles) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
            WHERE p.oid=pg_catalog.to_regprocedure(v.sig) AND p.prokind='f'
              AND l.lanname=v.lang AND p.prorettype=pg_catalog.to_regtype(v.ret)
              AND p.provolatile::text=v.vol AND p.prosecdef=v.definer
              AND p.proconfig=ARRAY['search_path=""']::text[]
              AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u'
              AND CASE WHEN v.sig='public.set_deepmap_username(text)'
                THEN pg_catalog.regexp_replace(p.prosrc,'[[:space:]]','','g')
                ELSE pg_catalog.lower(pg_catalog.regexp_replace(p.prosrc,'[[:space:]]','','g')) END=v.body) THEN
            RAISE EXCEPTION 'B7H2C_FUNCTION_CONTRACT: %',v.sig;
        END IF;
        IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
            CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
            WHERE p.oid=pg_catalog.to_regprocedure(v.sig) AND a.privilege_type='EXECUTE'
              AND (a.grantee=0 OR (a.grantee<>p.proowner AND a.grantee<>COALESCE((SELECT oid FROM pg_catalog.pg_roles WHERE rolname='service_role'),0) AND
                NOT a.grantee=ANY(ARRAY(SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname=ANY(v.roles)))))
        ) OR EXISTS (SELECT 1 FROM pg_catalog.unnest(v.roles) allowed(role_name)
            WHERE NOT pg_catalog.has_function_privilege(allowed.role_name,v.sig,'EXECUTE'))
          OR EXISTS (SELECT 1 FROM (VALUES ('anon'),('authenticated')) browser(role_name)
            WHERE NOT browser.role_name=ANY(v.roles)
              AND pg_catalog.has_function_privilege(browser.role_name,v.sig,'EXECUTE'))
          OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
            CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
            JOIN pg_catalog.pg_roles r ON r.oid=a.grantee
            WHERE p.oid=pg_catalog.to_regprocedure(v.sig) AND r.rolname IN ('anon','authenticated') AND a.is_grantable) THEN
            RAISE EXCEPTION 'B7H2C_FUNCTION_EXECUTE_ACL: %',v.sig;
        END IF;
    END LOOP;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
        WHERE c.oid=pg_catalog.to_regclass('private.deepmap_bans') AND c.relkind='r' AND c.relrowsecurity)
       OR EXISTS (SELECT 1 FROM (VALUES ('user_id','uuid',true),
          ('lifted_at','timestamp with time zone',false),('expires_at','timestamp with time zone',false)) e(col,typ,nn)
        LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid=pg_catalog.to_regclass('private.deepmap_bans')
          AND a.attname=e.col AND a.attnum>0 AND NOT a.attisdropped
        WHERE a.attname IS NULL OR a.atttypid<>pg_catalog.to_regtype(e.typ) OR a.attnotnull<>e.nn)
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
        WHERE p.oid='private.is_deepmap_banned(uuid)'::pg_catalog.regprocedure
          AND (r.rolsuper OR r.rolbypassrls)
          AND pg_catalog.has_table_privilege(p.proowner,'private.deepmap_bans','SELECT')) THEN
        RAISE EXCEPTION 'B7H2C_CANONICAL_BAN_DEPENDENCY';
    END IF;

    -- The marker helper must safely bypass marker RLS to avoid self-recursion.
    -- Both privileged writers must retain a trusted owner; no owner/ACL changes are made.
    FOR v IN SELECT p.* FROM pg_catalog.pg_proc p WHERE p.oid IN (
        'private.marker_is_public(bigint)'::pg_catalog.regprocedure,
        'public.set_deepmap_username(text)'::pg_catalog.regprocedure,
        'private.sync_auth_public_profile()'::pg_catalog.regprocedure) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.oid=v.proowner AND (r.rolsuper OR r.rolbypassrls)) THEN
            RAISE EXCEPTION 'B7H2C_PRIVILEGED_OWNER_REQUIRES_REVIEW: %',v.oid::pg_catalog.regprocedure;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        CROSS JOIN (VALUES ('public.marcadores'),('public.map_layers'),('public.game_maps'),('public.games'),('public.game_modules')) e(rel)
        WHERE p.oid='private.marker_is_public(bigint)'::pg_catalog.regprocedure
          AND NOT pg_catalog.has_table_privilege(p.proowner,pg_catalog.to_regclass(e.rel),'SELECT')) THEN
        RAISE EXCEPTION 'B7H2C_MARKER_HELPER_OWNER_READ_ACCESS';
    END IF;
    -- Normalize formatting/text casts, scalar auth.uid wrappers and generated aliases only.
    -- Exact command, role set and permissiveness are checked independently.
    FOR v IN SELECT * FROM (VALUES
        ('public.profiles','profiles_public_read','r',ARRAY['anon','authenticated']::text[],'is_public=trueorid=auth.uid',NULL::text),
        ('public.profiles','profiles_insert_own','a',ARRAY['authenticated']::text[],'','auth.uid=id'),
        ('public.profiles','profiles_update_own','w',ARRAY['authenticated']::text[],'auth.uid=idandnotprivate.is_deepmap_banned','auth.uid=idandnotprivate.is_deepmap_banned'),
        ('public.games','games_public_read','r',ARRAY['anon','authenticated']::text[],'status=anyarray[''coming_soon'',''published'']',NULL::text),
        ('public.game_modules','game_modules_public_read','r',ARRAY['anon','authenticated']::text[],'enabledandexistsselect1frompublic.gamesgwhereg.id=game_modules.game_idandg.status=''published''',NULL::text),
        ('public.game_maps','game_maps_public_read','r',ARRAY['anon','authenticated']::text[],'status=''published''andexistsselect1frompublic.gamesgwhereg.id=game_maps.game_idandg.status=''published''andexistsselect1frompublic.game_modulesmwherem.game_id=game_maps.game_idandm.module_key=''map''andm.enabled',NULL::text),
        ('public.games','games_admin_all','*',ARRAY['authenticated']::text[],'selectpublic.get_deepmap_roleasget_deepmap_role=''admin''','selectpublic.get_deepmap_roleasget_deepmap_role=''admin'''),
        ('public.game_modules','game_modules_admin_all','*',ARRAY['authenticated']::text[],'selectpublic.get_deepmap_roleasget_deepmap_role=''admin''','selectpublic.get_deepmap_roleasget_deepmap_role=''admin'''),
        ('public.game_maps','game_maps_admin_all','*',ARRAY['authenticated']::text[],'selectpublic.get_deepmap_roleasget_deepmap_role=''admin''','selectpublic.get_deepmap_roleasget_deepmap_role=''admin'''),
        ('public.map_layers','map_layers_public_read','r',ARRAY['anon','authenticated']::text[],'is_active=trueandexistsselect1frompublic.game_mapsgmjoinpublic.gamesgong.id=gm.game_idwheregm.id=map_layers.game_map_idandgm.game_id=map_layers.game_uuidandgm.status=''published''andg.status=''published''andexistsselect1frompublic.game_modulesmodwheremod.game_id=g.idandmod.module_key=''map''andmod.enabled',NULL::text),
        ('public.map_layers','map_layers_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('public.marker_category_groups','marker_category_groups_public_read','r',ARRAY['anon','authenticated']::text[],'is_active=trueandexistsselect1frompublic.gamesgwhereg.id=marker_category_groups.game_uuidandg.status=''published''andexistsselect1frompublic.game_modulesmodwheremod.game_id=g.idandmod.module_key=''map''andmod.enabled',NULL::text),
        ('public.marker_category_groups','marker_category_groups_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('public.marker_categories','marker_categories_public_read','r',ARRAY['anon','authenticated']::text[],'is_active=trueandexistsselect1frompublic.gamesgwhereg.id=marker_categories.game_uuidandg.status=''published''andexistsselect1frompublic.game_modulesmodwheremod.game_id=g.idandmod.module_key=''map''andmod.enabled',NULL::text),
        ('public.marker_categories','marker_categories_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('public.marcadores','marcadores_public_read','r',ARRAY['anon','authenticated']::text[],'private.marker_is_publicid',NULL::text),
        ('public.marcadores','marcadores_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('public.map_labels','map_labels_public_read','r',ARRAY['anon','authenticated']::text[],'is_published=trueandexistsselect1frompublic.map_layersljoinpublic.game_mapsgmongm.id=l.game_map_idandgm.game_id=l.game_uuidjoinpublic.gamesgong.id=l.game_uuidwherel.layer_uuid=map_labels.layer_uuidandl.game_uuid=map_labels.game_uuidandl.is_active=trueandgm.status=''published''andg.status=''published''andexistsselect1frompublic.game_modulesmodwheremod.game_id=g.idandmod.module_key=''map''andmod.enabled',NULL::text),
        ('public.map_labels','map_labels_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('public.marker_images','marker_images_public_read','r',ARRAY['anon','authenticated']::text[],'private.marker_is_publicmarker_id',NULL::text),
        ('public.marker_images','marker_images_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('public.marker_sections','marker_sections_public_read','r',ARRAY['anon','authenticated']::text[],'private.marker_is_publicmarker_id',NULL::text),
        ('public.marker_sections','marker_sections_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('public.marker_section_rows','marker_section_rows_public_read','r',ARRAY['anon','authenticated']::text[],'private.marker_is_publicprivate.section_marker_idsection_id',NULL::text),
        ('public.marker_section_rows','marker_section_rows_admin_all','*',ARRAY['authenticated']::text[],'private.is_deepmap_admin','private.is_deepmap_admin'),
        ('storage.objects','deepmap_avatars_select_own','r',ARRAY['authenticated']::text[],'bucket_id=''avatars''andstorage.foldernamename[1]=auth.uid',NULL::text),
        ('storage.objects','deepmap_avatars_insert_own','a',ARRAY['authenticated']::text[],'','bucket_id=''avatars''andstorage.foldernamename[1]=auth.uidandarray_lengthstorage.foldernamename,1=1andlowerstorage.extensionname=anyarray[''jpg'',''jpeg'',''png'',''webp'']andselectpublic.can_deepmap_interact'),
        ('storage.objects','deepmap_avatars_delete_own','d',ARRAY['authenticated']::text[],'bucket_id=''avatars''andstorage.foldernamename[1]=auth.uidandowner_id=auth.uidandselectpublic.can_deepmap_interact',NULL::text),
        ('public.marker_submissions','marker_submissions_insert_own','a',ARRAY['authenticated']::text[],'','public.can_deepmap_interactandsubmitted_by=auth.uidandstatus=''pending''andreviewed_byisnullandreviewed_atisnullandreview_noteisnullandexistsselect1frompublic.profilespwherep.id=auth.uidandnullifbtrimp.username,''''isnotnull'),
        ('public.marker_submissions','marker_submissions_update_own_pending','w',ARRAY['authenticated']::text[],'notprivate.is_deepmap_bannedandsubmitted_by=auth.uidandstatus=''pending''','notprivate.is_deepmap_bannedandsubmitted_by=auth.uidandstatus=''pending'''),
        ('public.marker_submissions','marker_submissions_read_own_or_staff','r',ARRAY['authenticated']::text[],'submitted_by=auth.uidandnotprivate.is_deepmap_bannedorprivate.can_moderate_deepmap',NULL::text)
    ) e(rel,name,cmd,roles,qual,chk) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p
            WHERE p.polrelid=pg_catalog.to_regclass(v.rel) AND p.polname=v.name
              AND p.polcmd::text=v.cmd AND p.polpermissive
              AND ARRAY(SELECT r.rolname::text FROM pg_catalog.unnest(p.polroles) u(id)
                JOIN pg_catalog.pg_roles r ON r.oid=u.id ORDER BY r.rolname)=v.roles
              AND pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'')), 'as (uid|can_deepmap_interact)\M', '', 'g'), '::text', ''), '[[:space:]()]', '', 'g'), 'selectauth.uid', 'auth.uid')=v.qual
              AND pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),'')), 'as (uid|can_deepmap_interact)\M', '', 'g'), '::text', ''), '[[:space:]()]', '', 'g'), 'selectauth.uid', 'auth.uid')=COALESCE(v.chk,'')
              AND (p.polqual IS NULL)=(v.qual='')
              AND (p.polwithcheck IS NULL)=(v.chk IS NULL)) THEN

            RAISE EXCEPTION 'B7H2C_POLICY_CONTRACT: %.%',v.rel,v.name;
        END IF;
    END LOOP;
    -- Fail closed on ALL unrecognized policies on protected public relations.
    -- This also rejects role-inherited/PUBLIC permissive bypasses, not just literal role names.
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid IN (
        'public.profiles'::pg_catalog.regclass,'public.games'::pg_catalog.regclass,'public.game_modules'::pg_catalog.regclass,'public.game_maps'::pg_catalog.regclass,'public.map_layers'::pg_catalog.regclass,'public.marker_category_groups'::pg_catalog.regclass,'public.marker_categories'::pg_catalog.regclass,'public.marcadores'::pg_catalog.regclass,'public.map_labels'::pg_catalog.regclass,'public.marker_images'::pg_catalog.regclass,'public.marker_sections'::pg_catalog.regclass,'public.marker_section_rows'::pg_catalog.regclass,'public.marker_submissions'::pg_catalog.regclass)
        AND NOT EXISTS (SELECT 1 FROM (VALUES ('public.profiles','profiles_public_read'),('public.profiles','profiles_insert_own'),('public.profiles','profiles_update_own'),('public.games','games_public_read'),('public.game_modules','game_modules_public_read'),('public.game_maps','game_maps_public_read'),('public.games','games_admin_all'),('public.game_modules','game_modules_admin_all'),('public.game_maps','game_maps_admin_all'),('public.map_layers','map_layers_public_read'),('public.map_layers','map_layers_admin_all'),('public.marker_category_groups','marker_category_groups_public_read'),('public.marker_category_groups','marker_category_groups_admin_all'),('public.marker_categories','marker_categories_public_read'),('public.marker_categories','marker_categories_admin_all'),('public.marcadores','marcadores_public_read'),('public.marcadores','marcadores_admin_all'),('public.map_labels','map_labels_public_read'),('public.map_labels','map_labels_admin_all'),('public.marker_images','marker_images_public_read'),('public.marker_images','marker_images_admin_all'),('public.marker_sections','marker_sections_public_read'),('public.marker_sections','marker_sections_admin_all'),('public.marker_section_rows','marker_section_rows_public_read'),('public.marker_section_rows','marker_section_rows_admin_all'),('public.marker_submissions','marker_submissions_insert_own'),('public.marker_submissions','marker_submissions_update_own_pending'),('public.marker_submissions','marker_submissions_read_own_or_staff')) e(rel,name)
            WHERE p.polrelid=pg_catalog.to_regclass(e.rel) AND p.polname=e.name)) THEN
        RAISE EXCEPTION 'B7H2C_UNEXPECTED_POLICY_POSSIBLE_PERMISSIVE_OR_BYPASS';
    END IF;
    -- Conservative storage baseline: unknown INSERT/UPDATE/DELETE/ALL policies require review,
    -- since arbitrary predicates cannot safely be assumed disjoint from the avatars bucket.
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_policy p
        WHERE p.polrelid='storage.objects'::pg_catalog.regclass AND p.polcmd<>'r'
          AND p.polname NOT IN ('deepmap_avatars_insert_own','deepmap_avatars_delete_own')) THEN
        RAISE EXCEPTION 'B7H2C_UNKNOWN_STORAGE_MUTATION_POLICY_REVIEW_REQUIRED';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM storage.buckets b WHERE b.id='avatars' AND b.public
        AND b.file_size_limit=2097152
        AND ARRAY(SELECT x FROM pg_catalog.unnest(b.allowed_mime_types) x ORDER BY x)
          =ARRAY['image/jpeg','image/png','image/webp']::text[]) THEN
        RAISE EXCEPTION 'B7H2C_AVATAR_BUCKET_SETTINGS';
    END IF;
    -- Exact existing AFTER UPDATE OF metadata trigger, including WHEN filter and target.
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid='auth.users'::pg_catalog.regclass AND t.tgname='deepmap_auth_public_profile_sync'
          AND t.tgfoid='private.sync_auth_public_profile()'::pg_catalog.regprocedure
          AND t.tgtype=17 AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgnargs=0
          AND t.tgattr::text=(SELECT a.attnum::text FROM pg_catalog.pg_attribute a
            WHERE a.attrelid=t.tgrelid AND a.attname='raw_user_meta_data' AND NOT a.attisdropped)
          AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_triggerdef(t.oid)),
            '[[:space:]()]','','g')='createtriggerdeepmap_auth_public_profile_syncafterupdateofraw_user_meta_dataonauth.usersforeachrowwhenold.raw_user_meta_dataisdistinctfromnew.raw_user_meta_dataexecutefunctionprivate.sync_auth_public_profile') THEN
        RAISE EXCEPTION 'B7H2C_AUTH_SYNC_TRIGGER_CONTRACT';
    END IF;

    SELECT pg_catalog.jsonb_build_object(
        'functions', (SELECT COALESCE(pg_catalog.jsonb_agg(
          CASE WHEN p.oid IN ('private.marker_is_public(bigint)'::pg_catalog.regprocedure,
            'public.set_deepmap_username(text)'::pg_catalog.regprocedure,
            'private.sync_auth_public_profile()'::pg_catalog.regprocedure)
          THEN pg_catalog.to_jsonb(p)-'prosrc' ELSE pg_catalog.to_jsonb(p) END ORDER BY p.oid),'[]'::jsonb)
          FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname IN ('public','private')),
        'policies', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.oid),'[]'::jsonb)
          FROM pg_catalog.pg_policy p WHERE NOT EXISTS (SELECT 1 FROM (VALUES
            ('public.profiles','profiles_public_read'),
            ('public.map_layers','map_layers_public_read'),
            ('public.marker_category_groups','marker_category_groups_public_read'),
            ('public.marker_categories','marker_categories_public_read'),
            ('public.marcadores','marcadores_public_read'),
            ('public.map_labels','map_labels_public_read'),
            ('storage.objects','deepmap_avatars_insert_own'),
            ('storage.objects','deepmap_avatars_delete_own')
          ) e(rel,name) WHERE p.polrelid=pg_catalog.to_regclass(e.rel) AND p.polname=e.name)),
        'relations', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c)-'relnatts'-'relpages'-'reltuples'-'relallvisible'-'relallfrozen'-'relfilenode' ORDER BY c.oid)
          FROM pg_catalog.pg_class c WHERE c.oid=ANY(v_relations)),
        'columns', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) ORDER BY a.attrelid,a.attnum)
          FROM pg_catalog.pg_attribute a WHERE a.attrelid=ANY(v_relations) AND a.attnum>0 AND NOT a.attisdropped
            AND NOT (a.attrelid='public.profiles'::pg_catalog.regclass AND a.attname='is_public')),
        'defaults', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.oid),'[]'::jsonb)
          FROM pg_catalog.pg_attrdef d JOIN pg_catalog.pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
          WHERE d.adrelid=ANY(v_relations) AND NOT (d.adrelid='public.profiles'::pg_catalog.regclass AND a.attname='is_public')),
        'constraints', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.oid),'[]'::jsonb)
          FROM pg_catalog.pg_constraint c WHERE c.conrelid=ANY(v_relations)),
        'triggers', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) ORDER BY t.oid),'[]'::jsonb)
          FROM pg_catalog.pg_trigger t WHERE t.tgrelid=ANY(v_relations||ARRAY['auth.users'::pg_catalog.regclass::oid])),
        'namespaces', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(n) ORDER BY n.oid)
          FROM pg_catalog.pg_namespace n WHERE n.nspname IN ('public','private','auth','storage'))
    ) INTO v_catalog_after;
    IF v_catalog_after IS DISTINCT FROM v_catalog_before THEN
        RAISE EXCEPTION 'B7H2C_UNINTENDED_CATALOG_DELTA_ROLLBACK';
    END IF;
    v_data_now := '{}'::jsonb;
    FOREACH v_rel IN ARRAY v_relations LOOP
        -- Fixed, validated relation whitelist only. No exposed dynamic-SQL helper.
        -- Hashes stay in transaction memory and are never printed or persisted.
        EXECUTE pg_catalog.format(
            'SELECT pg_catalog.jsonb_build_object(''count'',pg_catalog.count(*),''digest'',pg_catalog.md5(COALESCE(pg_catalog.string_agg(h, '''' ORDER BY h),''''))) FROM (SELECT pg_catalog.md5((pg_catalog.to_jsonb(r) %s)::text) h FROM %s r) s',
            CASE WHEN v_rel='public.profiles'::pg_catalog.regclass AND NOT v_had_is_public THEN '- ''is_public''' ELSE '' END,
            v_rel::pg_catalog.regclass) INTO v_rows;
        v_data_now := v_data_now || pg_catalog.jsonb_build_object(v_rel::text,v_rows);
    END LOOP;
    IF v_data_now IS DISTINCT FROM v_data_before THEN
        RAISE EXCEPTION 'B7H2C_BUSINESS_ROW_COUNT_OR_DIGEST_CHANGED_ROLLBACK';
    END IF;
    RAISE NOTICE 'B7H2C_SUCCESS: mandatory contracts verified; owners/ACLs/attributes, unrelated catalog and business row counts/digests preserved. No hashes or row contents emitted.';
END;
$b7h2c$;
COMMIT;
