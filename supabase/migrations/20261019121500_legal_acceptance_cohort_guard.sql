-- Migration C: MANUAL application after A, before B. A is already applied.
-- Preserve every existing row/evidence; only prevent future out-of-cohort writes.
BEGIN;
SET LOCAL lock_timeout = '5s';

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
          AND pg_catalog.regexp_replace(p.prosrc, '[[:space:]]', '', 'g') =
              pg_catalog.regexp_replace($baseline$
BEGIN
    IF (SELECT auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED';
    END IF;
    IF p_terms_version IS DISTINCT FROM '2026-10-18'
       OR p_privacy_version IS DISTINCT FROM '2026-10-19' THEN
        RAISE EXCEPTION 'LEGAL_VERSION_MISMATCH';
    END IF;
    INSERT INTO private.legal_onboarding(user_id, terms_version, privacy_version, accepted_at)
    VALUES ((SELECT auth.uid()), p_terms_version, p_privacy_version, pg_catalog.now())
    ON CONFLICT (user_id) DO UPDATE
        SET accepted_at = COALESCE(legal_onboarding.accepted_at, EXCLUDED.accepted_at)
        WHERE legal_onboarding.terms_version = EXCLUDED.terms_version
          AND legal_onboarding.privacy_version = EXCLUDED.privacy_version;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGAL_VERSION_MISMATCH'; END IF;
END;
$baseline$, '[[:space:]]', '', 'g')
    ) THEN RAISE EXCEPTION 'LEGAL_ACCEPTANCE_COHORT_BASELINE_DRIFT';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_legal_documents(p_terms_version text, p_privacy_version text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $cohort_guard$
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
$cohort_guard$;
REVOKE ALL ON FUNCTION public.accept_legal_documents(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_legal_documents(text, text) TO authenticated;
COMMIT;
