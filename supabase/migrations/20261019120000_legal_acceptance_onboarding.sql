-- Migration A: preparation only. MANUAL application before onboarding code.
-- Safe with the old application: pending rows do not enforce account access.
-- Existing auth.users remain exempt; no historical acceptance is inferred.
-- Apply B separately only when the onboarding code is available and verified.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE private.legal_onboarding (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    terms_version text NOT NULL,
    privacy_version text NOT NULL,
    accepted_at timestamptz
);
ALTER TABLE private.legal_onboarding ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.legal_onboarding FROM PUBLIC, anon, authenticated;
-- No public table access/policies: only narrowly scoped RPCs below.

CREATE FUNCTION private.require_legal_onboarding()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    INSERT INTO private.legal_onboarding(user_id, terms_version, privacy_version)
    VALUES (NEW.id, '2026-10-18', '2026-10-19');
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.require_legal_onboarding() FROM PUBLIC, anon, authenticated;
-- Transactional trigger installation defines the cohort boundary, without a
-- guessed date or a bulk change to existing users.
CREATE TRIGGER deepmap_require_legal_onboarding
AFTER INSERT ON auth.users FOR EACH ROW
EXECUTE FUNCTION private.require_legal_onboarding();

CREATE FUNCTION public.requires_legal_acceptance()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT EXISTS (
        SELECT 1 FROM private.legal_onboarding
        WHERE user_id = (SELECT auth.uid()) AND accepted_at IS NULL
    );
$$;
REVOKE ALL ON FUNCTION public.requires_legal_acceptance() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.requires_legal_acceptance() TO authenticated;

CREATE FUNCTION public.accept_legal_documents(p_terms_version text, p_privacy_version text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
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
$$;
REVOKE ALL ON FUNCTION public.accept_legal_documents(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_legal_documents(text, text) TO authenticated;

COMMIT;
