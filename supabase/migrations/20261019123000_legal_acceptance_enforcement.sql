-- Migration B: enforcement. MANUAL application only AFTER migrations A + C and
-- after the onboarding application is available and verified.
-- Do not batch A+B before deploying the onboarding code.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- Reject an incomplete preparation phase before changing permissions.
DO $$
BEGIN
    IF pg_catalog.to_regclass('private.legal_onboarding') IS NULL
       OR pg_catalog.to_regprocedure('private.require_legal_onboarding()') IS NULL
       OR pg_catalog.to_regprocedure('public.requires_legal_acceptance()') IS NULL
       OR pg_catalog.to_regprocedure('public.accept_legal_documents(text,text)') IS NULL THEN
        RAISE EXCEPTION 'LEGAL_ACCEPTANCE_PREPARATION_REQUIRED';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger
        WHERE tgrelid = 'auth.users'::pg_catalog.regclass
          AND tgname = 'deepmap_require_legal_onboarding'
          AND tgfoid = pg_catalog.to_regprocedure('private.require_legal_onboarding()')
          AND tgenabled = 'O' AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'LEGAL_ACCEPTANCE_PREPARATION_TRIGGER_REQUIRED';
    END IF;
END;
$$;

-- Require C's exact cohort-only RPC contract, not merely a matching signature.
-- A still has an upsert; accepting that definition here would permit cohort drift.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_language l ON l.oid = p.prolang
        JOIN pg_catalog.pg_roles r ON r.oid = p.proowner
        WHERE p.oid = pg_catalog.to_regprocedure('public.accept_legal_documents(text,text)')
          AND p.prosecdef AND p.proconfig = ARRAY['search_path=""']::text[]
          AND p.prorettype = 'pg_catalog.void'::pg_catalog.regtype
          AND p.provolatile = 'v' AND l.lanname = 'plpgsql'
          AND (r.rolsuper OR r.rolbypassrls)
          AND p.proargnames = ARRAY['p_terms_version', 'p_privacy_version']::text[]
          AND NOT pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
          AND pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
          AND pg_catalog.regexp_replace(p.prosrc, '[[:space:]]', '', 'g') =
              pg_catalog.regexp_replace($cohort_guard$
DECLARE
    v_user_id uuid := (SELECT auth.uid());
    v_row private.legal_onboarding%ROWTYPE;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED';
    END IF;
    IF p_terms_version IS DISTINCT FROM '2026-10-18'
       OR p_privacy_version IS DISTINCT FROM '2026-10-19' THEN
        RAISE EXCEPTION 'LEGAL_VERSION_MISMATCH';
    END IF;
    SELECT * INTO v_row FROM private.legal_onboarding
    WHERE user_id = v_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'LEGAL_ONBOARDING_NOT_REQUIRED';
    END IF;
    IF v_row.terms_version IS DISTINCT FROM p_terms_version
       OR v_row.privacy_version IS DISTINCT FROM p_privacy_version THEN
        RAISE EXCEPTION 'LEGAL_VERSION_MISMATCH';
    END IF;
    IF v_row.accepted_at IS NULL THEN
        UPDATE private.legal_onboarding SET accepted_at = pg_catalog.now()
        WHERE user_id = v_user_id;
    END IF;
END;
$cohort_guard$, '[[:space:]]', '', 'g')
    ) THEN RAISE EXCEPTION 'LEGAL_ACCEPTANCE_COHORT_GUARD_REQUIRED';
    END IF;
END;
$$;

-- Fail on an unexpected baseline rather than replace an unknown security helper.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc
        WHERE oid = pg_catalog.to_regprocedure('public.can_deepmap_interact()')
          AND prosecdef AND proconfig = ARRAY['search_path=""']::text[]
          AND pg_catalog.regexp_replace(prosrc, '[[:space:]]', '', 'g') =
              'select(selectauth.uid())isnotnullandnotprivate.is_deepmap_banned();'
    ) THEN
        RAISE EXCEPTION 'LEGAL_ACCEPTANCE_DEPENDENCY_DRIFT';
    END IF;
END;
$$;

-- Staff policies/RPCs also use these helpers directly, without the interaction
-- helper. Validate their reviewed baseline before extending those gates.
DO $$
DECLARE v record;
BEGIN
    FOR v IN SELECT * FROM (VALUES
        ('private.is_deepmap_admin()',
         'select(selectauth.uid())isnotnullandprivate.is_deepmap_banned()isfalseandexists(select1fromprivate.deepmap_adminsasawherea.user_id=(selectauth.uid()));'),
        ('private.is_deepmap_moderator()',
         'selectexists(select1fromprivate.deepmap_moderatorsasmwherem.user_id=(selectauth.uid()));'),
        ('private.can_moderate_deepmap()',
         'selectnotprivate.is_deepmap_banned()and(private.is_deepmap_admin()orprivate.is_deepmap_moderator());')
    ) AS expected(signature, body)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc p
            WHERE p.oid = pg_catalog.to_regprocedure(v.signature)
              AND p.prosecdef AND p.proconfig = ARRAY['search_path=""']::text[]
              AND pg_catalog.regexp_replace(p.prosrc, '[[:space:]]', '', 'g') = v.body
        ) THEN RAISE EXCEPTION 'LEGAL_ACCEPTANCE_STAFF_DEPENDENCY_DRIFT: %', v.signature;
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_deepmap_interact()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT (SELECT auth.uid()) IS NOT NULL
       AND NOT private.is_deepmap_banned()
       AND NOT public.requires_legal_acceptance();
$$;

-- No recursion: can_deepmap_interact checks only identity, bans and the private
-- acceptance row; it never calls role helpers. Existing owners/ACLs are retained.
CREATE OR REPLACE FUNCTION private.is_deepmap_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT public.can_deepmap_interact() AND EXISTS (
        SELECT 1 FROM private.deepmap_admins AS a
        WHERE a.user_id = (SELECT auth.uid())
    );
$$;

CREATE OR REPLACE FUNCTION private.is_deepmap_moderator()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT public.can_deepmap_interact() AND EXISTS (
        SELECT 1 FROM private.deepmap_moderators AS m
        WHERE m.user_id = (SELECT auth.uid())
    );
$$;

CREATE OR REPLACE FUNCTION private.can_moderate_deepmap()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT public.can_deepmap_interact()
       AND (private.is_deepmap_admin() OR private.is_deepmap_moderator());
$$;

-- Existing profile policies are preserved; these add an independent legal gate
-- to direct PostgREST writes as well as the RPC interaction guard above.
CREATE POLICY profiles_legal_insert ON public.profiles AS RESTRICTIVE
FOR INSERT TO authenticated WITH CHECK (NOT public.requires_legal_acceptance());
CREATE POLICY profiles_legal_update ON public.profiles AS RESTRICTIVE
FOR UPDATE TO authenticated USING (NOT public.requires_legal_acceptance())
WITH CHECK (NOT public.requires_legal_acceptance());

-- A pending account may have submitted content while A-only/old code was live.
-- The historical direct UPDATE policy checks bans, not legal acceptance.
CREATE POLICY marker_submissions_legal_update ON public.marker_submissions AS RESTRICTIVE
FOR UPDATE TO authenticated USING (NOT public.requires_legal_acceptance())
WITH CHECK (NOT public.requires_legal_acceptance());
COMMIT;
