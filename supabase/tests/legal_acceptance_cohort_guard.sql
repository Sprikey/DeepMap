-- MANUAL test only, in an isolated Supabase test DB AFTER authorized A + C.
-- NOT executed by this task. Does not create users or remove existing evidence.
-- Run as a privileged test operator. Configure three distinct EXISTING fixture
-- UUIDs in this session with SET deepmap.test.grandfathered_user_id = '...';
-- SET deepmap.test.pending_user_id = '...'; SET deepmap.test.accepted_user_id = '...';
-- grandfathered must have no legal row; pending/accepted must have current versions.
-- All RPC writes below are rolled back; use ON_ERROR_STOP in the SQL client.
BEGIN;
SET LOCAL lock_timeout = '5s';
DO $$
DECLARE
    v_old uuid := nullif(current_setting('deepmap.test.grandfathered_user_id', true), '')::uuid;
    v_pending uuid := nullif(current_setting('deepmap.test.pending_user_id', true), '')::uuid;
    v_accepted uuid := nullif(current_setting('deepmap.test.accepted_user_id', true), '')::uuid;
    v_first timestamptz;
BEGIN
    IF v_old IS NULL OR v_pending IS NULL OR v_accepted IS NULL
       OR v_old = v_pending OR v_old = v_accepted OR v_pending = v_accepted THEN
        RAISE EXCEPTION 'TEST_REQUIRES_THREE_DISTINCT_EXISTING_FIXTURES';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_old)
       OR EXISTS (SELECT 1 FROM private.legal_onboarding WHERE user_id = v_old) THEN
        RAISE EXCEPTION 'TEST_GRANDFATHERED_FIXTURE_INVALID';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM private.legal_onboarding WHERE user_id = v_pending
        AND accepted_at IS NULL AND terms_version = '2026-10-18' AND privacy_version = '2026-10-19') THEN
        RAISE EXCEPTION 'TEST_PENDING_FIXTURE_INVALID';
    END IF;
    SELECT accepted_at INTO v_first FROM private.legal_onboarding WHERE user_id = v_accepted
        AND terms_version = '2026-10-18' AND privacy_version = '2026-10-19';
    IF v_first IS NULL THEN RAISE EXCEPTION 'TEST_ACCEPTED_FIXTURE_INVALID'; END IF;
    PERFORM set_config('deepmap.test.first_accepted_at', v_first::text, true);
END;
$$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('deepmap.test.grandfathered_user_id'), true);
DO $$
BEGIN
    IF public.requires_legal_acceptance() THEN RAISE EXCEPTION 'TEST_OLD_USER_NOT_EXEMPT'; END IF;
    BEGIN
        PERFORM public.accept_legal_documents('2026-10-18', '2026-10-19');
        RAISE EXCEPTION 'TEST_EXPECTED_COHORT_REJECTION';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'LEGAL_ONBOARDING_NOT_REQUIRED' THEN RAISE; END IF;
    END;
END;
$$;

SELECT set_config('request.jwt.claim.sub', current_setting('deepmap.test.pending_user_id'), true);
DO $$
BEGIN
    IF NOT public.requires_legal_acceptance() THEN RAISE EXCEPTION 'TEST_PENDING_USER_NOT_REQUIRED'; END IF;
    BEGIN
        PERFORM public.accept_legal_documents('stale', '2026-10-19');
        RAISE EXCEPTION 'TEST_EXPECTED_VERSION_REJECTION';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'LEGAL_VERSION_MISMATCH' THEN RAISE; END IF;
    END;
    PERFORM public.accept_legal_documents('2026-10-18', '2026-10-19');
    IF public.requires_legal_acceptance() THEN RAISE EXCEPTION 'TEST_PENDING_NOT_ACCEPTED'; END IF;
    PERFORM public.accept_legal_documents('2026-10-18', '2026-10-19');
END;
$$;

SELECT set_config('request.jwt.claim.sub', current_setting('deepmap.test.accepted_user_id'), true);
DO $$
BEGIN
    IF public.requires_legal_acceptance() THEN RAISE EXCEPTION 'TEST_ACCEPTED_USER_REQUIRED'; END IF;
    PERFORM public.accept_legal_documents('2026-10-18', '2026-10-19');
END;
$$;

RESET ROLE;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM private.legal_onboarding
        WHERE user_id = current_setting('deepmap.test.grandfathered_user_id')::uuid) THEN
        RAISE EXCEPTION 'TEST_OUT_OF_COHORT_ROW_CREATED';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM private.legal_onboarding
        WHERE user_id = current_setting('deepmap.test.pending_user_id')::uuid
          AND accepted_at = pg_catalog.now()) THEN
        RAISE EXCEPTION 'TEST_ACCEPTANCE_NOT_DB_TIMESTAMP';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM private.legal_onboarding
        WHERE user_id = current_setting('deepmap.test.accepted_user_id')::uuid
          AND accepted_at = current_setting('deepmap.test.first_accepted_at')::timestamptz) THEN
        RAISE EXCEPTION 'TEST_FIRST_ACCEPTANCE_CHANGED';
    END IF;
END;
$$;
ROLLBACK;
