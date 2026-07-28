SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: f1_authenticate_session(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_authenticate_session(p_session_id uuid) RETURNS TABLE(account_id uuid, organization_id uuid, status text, idle_expires_at timestamp with time zone, absolute_expires_at timestamp with time zone, authorization_context_version bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT s.account_id, s.organization_id, s.status, s.idle_expires_at,
         s.absolute_expires_at, s.authorization_context_version
  FROM sessions s
  WHERE s.id = p_session_id;
$$;


--
-- Name: f1_billing_entities_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_billing_entities_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  -- ":413 reserved `past_due`/`suspended` … MUST be unreachable" in the
  -- accepted baseline: no path may land on them.
  IF NEW.state IN ('past_due','suspended') THEN
    RAISE EXCEPTION 'billing_entity_reserved_state_unreachable %', NEW.state
      USING ERRCODE = 'raise_exception';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- Genesis identity is immutable.
    IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
       OR NEW.internal_contract_reference IS DISTINCT FROM OLD.internal_contract_reference THEN
      RAISE EXCEPTION 'billing_entity_genesis_immutable' USING ERRCODE = 'raise_exception';
    END IF;
    -- Baseline transitions only: pending -> active, active/pending -> closed.
    IF NOT (
         (OLD.state = 'pending'  AND NEW.state IN ('pending','active','closed')) OR
         (OLD.state = 'active'   AND NEW.state IN ('active','closed')) OR
         (OLD.state = 'closed'   AND NEW.state = 'closed')
       ) THEN
      RAISE EXCEPTION 'billing_entity_illegal_transition % -> %', OLD.state, NEW.state
        USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: f1_bootstrap_principal_uuid(bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_bootstrap_principal_uuid(p_digest bytea) RETURNS uuid
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE b bytea;
BEGIN
  IF p_digest IS NULL OR octet_length(p_digest) <> 32 THEN
    RAISE EXCEPTION 'bootstrap principal digest must be 32 bytes';
  END IF;
  b := substring(p_digest FROM 1 FOR 16);
  b := set_byte(b, 6, (get_byte(b, 6) & 15) | 128);  -- version 8
  b := set_byte(b, 8, (get_byte(b, 8) & 63) | 128);  -- variant 10xx
  RETURN encode(b, 'hex')::uuid;
END;
$$;


--
-- Name: f1_cancel_scheduled_action(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_cancel_scheduled_action(p_action_id uuid, p_reason text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_now timestamptz(6) := transaction_timestamp(); v_changed integer;
BEGIN
  UPDATE scheduled_actions a
  SET status = 'canceled', canceled_at = v_now, reason = coalesce(p_reason, a.reason),
      claim_owner = NULL, claimed_at = NULL, lease_expires_at = NULL,
      claim_phase = NULL, last_heartbeat_at = NULL,
      updated_at = v_now, state_version = a.state_version + 1
  WHERE a.id = p_action_id AND a.status IN ('pending','claimed');
  GET DIAGNOSTICS v_changed = ROW_COUNT;
  RETURN v_changed > 0;
END;
$$;


--
-- Name: f1_claim_due_scheduled_actions(uuid, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_claim_due_scheduled_actions(p_owner uuid, p_limit integer, p_lease_seconds integer) RETURNS TABLE(id uuid, action_kind text, action_schema_version text, organization_id uuid, project_id uuid, target_type text, target_id uuid, product_generation bigint, schedule_generation bigint, due_at timestamp with time zone, claim_generation bigint, correlation_id uuid, causation_id uuid, executing_service_identity_id uuid, payload_refs jsonb, work_id uuid)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
#variable_conflict use_column
DECLARE v_now timestamptz(6) := transaction_timestamp();
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT a.id FROM scheduled_actions a
    JOIN service_identities s ON s.id = a.executing_service_identity_id
    WHERE a.status = 'pending'
      AND a.due_at <= v_now
      AND (a.not_before_at IS NULL OR a.not_before_at <= v_now)
      AND (a.next_dispatch_at IS NULL OR a.next_dispatch_at <= v_now)
      AND s.status = 'active'
    ORDER BY a.due_at, a.id
    FOR UPDATE OF a SKIP LOCKED
    LIMIT greatest(p_limit, 0)
  ),
  claimed AS (
    UPDATE scheduled_actions a
    SET status = 'claimed', claim_owner = p_owner, claim_generation = a.claim_generation + 1,
        claimed_at = v_now, lease_expires_at = v_now + make_interval(secs => greatest(p_lease_seconds, 1)),
        claim_phase = 'scheduler', last_heartbeat_at = NULL, next_dispatch_at = NULL,
        updated_at = v_now, state_version = a.state_version + 1
    FROM due
    WHERE a.id = due.id
    RETURNING a.id, a.action_kind, a.action_schema_version, a.organization_id, a.project_id,
              a.target_type, a.target_id, a.product_generation, a.schedule_generation,
              a.due_at, a.claim_generation, a.correlation_id, a.causation_id,
              a.executing_service_identity_id, a.payload_refs
  ),
  bound AS (
    INSERT INTO work_dispatch_bindings
      (id, created_at, organization_id, source_action_id, source_claim_generation,
       action_kind, target_type, target_id, target_generation)
    SELECT gen_random_uuid(), v_now, c.organization_id, c.id, c.claim_generation,
           c.action_kind, 'scheduled_action', c.id, c.claim_generation
    FROM claimed c
    RETURNING id AS work_id, source_action_id
  )
  SELECT c.id, c.action_kind, c.action_schema_version, c.organization_id, c.project_id,
         c.target_type, c.target_id, c.product_generation, c.schedule_generation,
         c.due_at, c.claim_generation, c.correlation_id, c.causation_id,
         c.executing_service_identity_id, c.payload_refs, b.work_id
  FROM claimed c JOIN bound b ON b.source_action_id = c.id;
END;
$$;


--
-- Name: f1_consume_receipt_nonce(uuid, timestamp with time zone, uuid, bytea, uuid, timestamp with time zone, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_consume_receipt_nonce(p_id uuid, p_created_at timestamp with time zone, p_receipt_id uuid, p_receipt_digest bytea, p_command_execution_id uuid, p_consumed_at timestamp with time zone, p_outcome text, p_reason_code text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  INSERT INTO identity_receipt_consumptions
    (id, schema_version, created_at, receipt_id, receipt_digest,
     command_execution_id, consumed_at, outcome, reason_code)
  VALUES
    (p_id, '1.0', p_created_at, p_receipt_id, p_receipt_digest,
     p_command_execution_id, p_consumed_at, p_outcome, p_reason_code);
  RETURN p_outcome;
EXCEPTION WHEN unique_violation THEN
  RETURN 'already_consumed';
END;
$$;


--
-- Name: f1_context_proof(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_context_proof(p_principal_hex text, p_org text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT encode(
    hmac(
      convert_to(txid_current()::text || '|' || coalesce(p_principal_hex, '') || '|' || coalesce(p_org, ''), 'UTF8'),
      (SELECT key_bytes FROM f1_context_keys WHERE key_name = 'context_proof'),
      'sha256'
    ), 'hex');
$$;


--
-- Name: f1_crawl_policies_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_crawl_policies_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'crawl_policy_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  -- A superseded policy version is terminal: no field may change once it leaves active.
  IF OLD.state <> 'active' THEN
    RAISE EXCEPTION 'crawl_policy_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.schema_version IS DISTINCT FROM OLD.schema_version
     OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.project_id IS DISTINCT FROM OLD.project_id
     OR NEW.scope IS DISTINCT FROM OLD.scope
     OR NEW.policy_version IS DISTINCT FROM OLD.policy_version
     OR NEW.supersedes_id IS DISTINCT FROM OLD.supersedes_id
     OR NEW.activated_by_account_id IS DISTINCT FROM OLD.activated_by_account_id
     OR NEW.normalized_bounds IS DISTINCT FROM OLD.normalized_bounds
     OR NEW.content_sha256 IS DISTINCT FROM OLD.content_sha256
     OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'crawl_policy_facts_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  -- The only permitted transition of an active row is to superseded.
  IF NEW.state <> 'superseded' THEN
    RAISE EXCEPTION 'crawl_policy_transition_unavailable % -> %', OLD.state, NEW.state
      USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: f1_crawl_sources_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_crawl_sources_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  RAISE EXCEPTION 'crawl_source_immutable' USING ERRCODE = 'raise_exception';
END;
$$;


--
-- Name: f1_crawls_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_crawls_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'crawl_immutable' USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.project_id IS DISTINCT FROM OLD.project_id
     OR NEW.kind IS DISTINCT FROM OLD.kind
     OR NEW.parent_evaluation_id IS DISTINCT FROM OLD.parent_evaluation_id
     OR NEW.parent_crawl_id IS DISTINCT FROM OLD.parent_crawl_id
     OR NEW.requested_crawl_policy_id IS DISTINCT FROM OLD.requested_crawl_policy_id
     OR NEW.requested_crawl_policy_version IS DISTINCT FROM OLD.requested_crawl_policy_version
     OR NEW.requested_entitlement_policy_id IS DISTINCT FROM OLD.requested_entitlement_policy_id
     OR NEW.requested_entitlement_policy_version IS DISTINCT FROM OLD.requested_entitlement_policy_version
     OR NEW.trigger_kind IS DISTINCT FROM OLD.trigger_kind
     OR NEW.triggered_by_account_id IS DISTINCT FROM OLD.triggered_by_account_id
     OR NEW.queued_at IS DISTINCT FROM OLD.queued_at
     OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'crawl_facts_immutable' USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.state IS DISTINCT FROM OLD.state THEN
    RAISE EXCEPTION 'crawl_transition_unavailable % -> %', OLD.state, NEW.state USING ERRCODE = 'raise_exception';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: f1_current_bootstrap_principal(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_current_bootstrap_principal() RETURNS bytea
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_hex text; v_org text; v_proof text;
BEGIN
  v_hex   := current_setting('app.bootstrap_principal_digest', true);
  v_org   := current_setting('app.context_org', true);
  v_proof := current_setting('app.f1_proof', true);
  IF v_hex IS NULL OR v_hex = '' OR v_proof IS NULL OR v_proof = '' THEN
    RETURN NULL;
  END IF;
  IF v_proof <> f1_context_proof(v_hex, v_org) THEN RETURN NULL; END IF;
  RETURN decode(v_hex, 'hex');
EXCEPTION WHEN others THEN RETURN NULL;
END;
$$;


--
-- Name: f1_current_context_org(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_current_context_org() RETURNS uuid
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_hex text; v_org text; v_proof text;
BEGIN
  v_hex   := current_setting('app.bootstrap_principal_digest', true);
  v_org   := current_setting('app.context_org', true);
  v_proof := current_setting('app.f1_proof', true);
  IF v_org IS NULL OR v_org = '' OR v_proof IS NULL OR v_proof = '' THEN
    RETURN NULL;
  END IF;
  IF v_proof <> f1_context_proof(v_hex, v_org) THEN RETURN NULL; END IF;
  RETURN v_org::uuid;
EXCEPTION WHEN others THEN RETURN NULL;
END;
$$;


--
-- Name: f1_dispatch_scheduled_action(uuid, bigint, uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_dispatch_scheduled_action(p_work_id uuid, p_expected_generation bigint, p_worker_owner uuid, p_lease_seconds integer) RETURNS TABLE(id uuid, action_kind text, action_schema_version text, organization_id uuid, project_id uuid, target_type text, target_id uuid, product_generation bigint, schedule_generation bigint, due_at timestamp with time zone, claim_generation bigint, correlation_id uuid, causation_id uuid, executing_service_identity_id uuid, payload_refs jsonb, identity_sha256 bytea)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
#variable_conflict use_column
DECLARE
  v_now timestamptz(6) := transaction_timestamp();
  v_action_id uuid;
  v_generation bigint;
BEGIN
  SELECT b.source_action_id, b.source_claim_generation
    INTO v_action_id, v_generation
    FROM work_dispatch_bindings b WHERE b.id = p_work_id;
  IF v_action_id IS NULL OR v_generation <> p_expected_generation THEN
    RETURN;
  END IF;

  RETURN QUERY
  UPDATE scheduled_actions a
  SET status = 'dispatched',
      dispatched_at = coalesce(a.dispatched_at, v_now),
      claim_owner = p_worker_owner, claim_phase = 'worker',
      lease_expires_at = v_now + make_interval(secs => greatest(p_lease_seconds, 1)),
      dispatch_attempt_count = 0, next_dispatch_at = NULL,
      updated_at = v_now, state_version = a.state_version + 1
  WHERE a.id = v_action_id
    AND a.claim_generation = v_generation
    AND a.status IN ('claimed','dispatched')
    AND (a.claim_phase = 'scheduler'
         OR (a.claim_phase = 'worker' AND a.claim_owner = p_worker_owner))
  RETURNING a.id, a.action_kind, a.action_schema_version, a.organization_id, a.project_id,
            a.target_type, a.target_id, a.product_generation, a.schedule_generation,
            a.due_at, a.claim_generation, a.correlation_id, a.causation_id,
            a.executing_service_identity_id, a.payload_refs, a.identity_sha256;
END;
$$;


--
-- Name: f1_encrypted_record_destroy(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_encrypted_record_destroy(p_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_state text;
BEGIN
  UPDATE f1_encrypted_records
    SET envelope = NULL, state = 'destroyed', destroyed_at = now()
    WHERE id = p_id AND state = 'active'
    RETURNING state INTO v_state;
  IF v_state IS NOT NULL THEN
    RETURN 'destroyed';
  END IF;
  SELECT state INTO v_state FROM f1_encrypted_records WHERE id = p_id;
  RETURN CASE WHEN v_state = 'destroyed' THEN 'already_destroyed' ELSE 'unknown' END;
END;
$$;


--
-- Name: f1_encrypted_record_get(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_encrypted_record_get(p_id uuid) RETURNS TABLE(envelope_hex text, state text, content_digest_hex text, key_provider text, wrapping_key_version text, application text, record_type text, record_id text, purpose text, tenant text, aad_schema_version text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT encode(envelope, 'hex'), state, encode(content_digest, 'hex'),
         key_provider, wrapping_key_version,
         application, record_type, record_id, purpose, tenant, aad_schema_version
  FROM f1_encrypted_records
  WHERE p_id IS NOT NULL AND id = p_id;
$$;


--
-- Name: f1_encrypted_record_put(text, text, text, text, text, text, text, text, bytea, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_encrypted_record_put(p_application text, p_record_type text, p_record_id text, p_purpose text, p_tenant text, p_aad_schema_version text, p_key_provider text, p_wrapping_key_version text, p_envelope bytea, p_content_digest bytea) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_id uuid;
BEGIN
  IF p_envelope IS NULL OR octet_length(p_envelope) = 0 THEN
    RAISE EXCEPTION 'envelope is required';
  END IF;
  IF p_content_digest IS NULL OR octet_length(p_content_digest) <> 32 THEN
    RAISE EXCEPTION 'content_digest must be 32 bytes';
  END IF;
  INSERT INTO f1_encrypted_records
    (application, record_type, record_id, purpose, tenant, aad_schema_version,
     key_provider, wrapping_key_version, envelope, content_digest, state)
  VALUES (p_application, p_record_type, p_record_id, p_purpose, p_tenant, p_aad_schema_version,
     p_key_provider, p_wrapping_key_version, p_envelope, p_content_digest, 'active')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;


--
-- Name: f1_encrypted_record_rewrap(uuid, text, text, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_encrypted_record_rewrap(p_id uuid, p_expected_version text, p_new_version text, p_new_envelope bytea) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_rows int;
BEGIN
  IF p_new_envelope IS NULL OR octet_length(p_new_envelope) = 0 THEN
    RAISE EXCEPTION 'new envelope is required';
  END IF;
  UPDATE f1_encrypted_records
    SET envelope = p_new_envelope, wrapping_key_version = p_new_version
    WHERE id = p_id AND state = 'active' AND wrapping_key_version = p_expected_version;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 1 THEN RETURN 'rewrapped'; END IF;
  IF EXISTS (SELECT 1 FROM f1_encrypted_records WHERE id = p_id) THEN RETURN 'stale'; END IF;
  RETURN 'unknown';
END;
$$;


--
-- Name: f1_encryption_active_version(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_encryption_active_version(p_provider text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT version FROM f1_encryption_key_versions
  WHERE p_provider IS NOT NULL AND p_provider <> ''
    AND provider = p_provider AND state = 'active'
  LIMIT 1;
$$;


--
-- Name: f1_encryption_describe_version(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_encryption_describe_version(p_provider text, p_version text) RETURNS TABLE(state text, fingerprint_hex text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT state, encode(key_fingerprint, 'hex')
  FROM f1_encryption_key_versions
  WHERE p_provider IS NOT NULL AND p_provider <> ''
    AND p_version IS NOT NULL AND p_version <> ''
    AND provider = p_provider AND version = p_version;
$$;


--
-- Name: f1_encryption_destroy_version(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_encryption_destroy_version(p_provider text, p_version text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_state text;
BEGIN
  SELECT state INTO v_state FROM f1_encryption_key_versions
    WHERE provider = p_provider AND version = p_version;
  IF v_state IS NULL THEN RETURN 'unknown'; END IF;
  IF v_state = 'destroyed' THEN RETURN 'already_destroyed'; END IF;
  UPDATE f1_encryption_key_versions
    SET state = 'destroyed', key_fingerprint = NULL, destroyed_at = now()
    WHERE provider = p_provider AND version = p_version;
  RETURN 'destroyed';
END;
$$;


--
-- Name: f1_encryption_register_active_version(text, text, bytea, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_encryption_register_active_version(p_provider text, p_version text, p_fingerprint bytea, p_reference text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_state text;
BEGIN
  IF p_provider IS NULL OR p_provider = '' OR p_version IS NULL OR p_version = '' THEN
    RAISE EXCEPTION 'provider and version are required';
  END IF;
  IF p_fingerprint IS NULL OR octet_length(p_fingerprint) <> 32 THEN
    RAISE EXCEPTION 'fingerprint must be 32 bytes';
  END IF;

  SELECT state INTO v_state FROM f1_encryption_key_versions
    WHERE provider = p_provider AND version = p_version;
  IF v_state = 'destroyed' THEN
    RAISE EXCEPTION 'a destroyed key version cannot be reactivated';
  END IF;

  UPDATE f1_encryption_key_versions
    SET state = 'retired', retired_at = now()
    WHERE provider = p_provider AND state = 'active' AND version <> p_version;

  INSERT INTO f1_encryption_key_versions
      (provider, version, state, key_fingerprint, key_reference, activated_at)
    VALUES (p_provider, p_version, 'active', p_fingerprint, p_reference, now())
    ON CONFLICT (provider, version) DO UPDATE
      SET state = 'active', key_fingerprint = EXCLUDED.key_fingerprint,
          key_reference = EXCLUDED.key_reference, activated_at = now(), retired_at = NULL;
END;
$$;


--
-- Name: f1_encryption_retire_version(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_encryption_retire_version(p_provider text, p_version text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_state text;
BEGIN
  SELECT state INTO v_state FROM f1_encryption_key_versions
    WHERE provider = p_provider AND version = p_version;
  IF v_state IS NULL THEN RETURN 'unknown'; END IF;
  IF v_state = 'destroyed' THEN RAISE EXCEPTION 'a destroyed key version cannot be retired'; END IF;
  IF v_state = 'retired' THEN RETURN 'already_retired'; END IF;
  UPDATE f1_encryption_key_versions
    SET state = 'retired', retired_at = now()
    WHERE provider = p_provider AND version = p_version;
  RETURN 'retired';
END;
$$;


--
-- Name: f1_enter_bootstrap_context(bytea, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_enter_bootstrap_context(p_receipt_digest bytea, p_correlation_id uuid) RETURNS TABLE(receipt_id uuid, purpose text, validated_at timestamp with time zone, expires_at timestamp with time zone, email_verified boolean, issuer_key text, receipt_schema_version text, bootstrap_principal_digest bytea, context_org uuid)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE r identity_receipt_nonces%ROWTYPE;
        v_principal bytea; v_hex text; v_org uuid; v_proof text;
BEGIN
  SELECT * INTO r FROM identity_receipt_nonces WHERE receipt_digest = p_receipt_digest;
  IF NOT FOUND THEN RETURN; END IF;

  v_principal := coalesce(r.bootstrap_principal_digest, r.identity_principal_digest);
  v_hex := encode(v_principal, 'hex');
  v_org := f1_bootstrap_principal_uuid(v_principal);
  v_proof := f1_context_proof(v_hex, v_org::text);
  PERFORM set_config('app.bootstrap_principal_digest', v_hex, true);
  PERFORM set_config('app.context_org', v_org::text, true);
  PERFORM set_config('app.f1_proof', v_proof, true);

  RETURN QUERY SELECT r.id, r.purpose, r.validated_at, r.expires_at, r.email_verified,
                      r.issuer_key, r.receipt_schema_version, r.bootstrap_principal_digest, v_org;
END;
$$;


--
-- Name: f1_enter_context(bytea, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_enter_context(p_receipt_digest bytea, p_org uuid, p_correlation_id uuid) RETURNS TABLE(receipt_found boolean, receipt_id uuid, purpose text, validated_at timestamp with time zone, expires_at timestamp with time zone, email_verified boolean, issuer_key text, issuer_subject text, receipt_schema_version text, assurance_version text, mfa_satisfied boolean, identity_principal_digest bytea, normalized_email_sha256 bytea, normalized_email text, display_name text, context_org uuid)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE r identity_receipt_nonces%ROWTYPE; v_found boolean; v_proof text;
BEGIN
  SELECT * INTO r FROM identity_receipt_nonces WHERE receipt_digest = p_receipt_digest;
  v_found := FOUND;

  v_proof := f1_context_proof('', p_org::text);
  PERFORM set_config('app.bootstrap_principal_digest', '', true);
  PERFORM set_config('app.context_org', p_org::text, true);
  PERFORM set_config('app.f1_proof', v_proof, true);

  IF v_found THEN
    RETURN QUERY SELECT true, r.id, r.purpose, r.validated_at, r.expires_at, r.email_verified,
                        r.issuer_key, r.issuer_subject, r.receipt_schema_version,
                        r.assurance_version, r.mfa_satisfied, r.identity_principal_digest, r.normalized_email_sha256, r.normalized_email, r.display_name, p_org;
  ELSE
    RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::timestamptz(6), NULL::timestamptz(6),
                        NULL::boolean, NULL::text, NULL::text, NULL::text, NULL::text, NULL::boolean,
                        NULL::bytea, NULL::bytea, NULL::text, NULL::text, p_org;
  END IF;
END;
$$;


--
-- Name: f1_enter_org_context(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_enter_org_context(p_org uuid, p_correlation_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_proof text;
BEGIN
  v_proof := f1_context_proof('', p_org::text);
  PERFORM set_config('app.bootstrap_principal_digest', '', true);
  PERFORM set_config('app.context_org', p_org::text, true);
  PERFORM set_config('app.f1_proof', v_proof, true);
  RETURN p_org;
END;
$$;


--
-- Name: f1_enter_self_service_context(bytea, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_enter_self_service_context(p_receipt_digest bytea, p_org_id uuid, p_correlation_id uuid) RETURNS TABLE(receipt_id uuid, purpose text, validated_at timestamp with time zone, expires_at timestamp with time zone, email_verified boolean, mfa_satisfied boolean, issuer_key text, issuer_subject text, receipt_schema_version text, assurance_version text, bootstrap_principal_digest bytea, organization_id uuid)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE r identity_receipt_nonces%ROWTYPE; v_principal bytea; v_hex text; v_proof text;
BEGIN
  SELECT * INTO r FROM identity_receipt_nonces WHERE receipt_digest = p_receipt_digest;
  IF NOT FOUND THEN RETURN; END IF;

  v_principal := coalesce(r.bootstrap_principal_digest, r.identity_principal_digest);
  v_hex := encode(v_principal, 'hex');
  v_proof := f1_context_proof(v_hex, p_org_id::text);
  PERFORM set_config('app.bootstrap_principal_digest', v_hex, true);
  PERFORM set_config('app.context_org', p_org_id::text, true);
  PERFORM set_config('app.f1_proof', v_proof, true);

  RETURN QUERY SELECT r.id, r.purpose, r.validated_at, r.expires_at, r.email_verified,
                      r.mfa_satisfied, r.issuer_key, r.issuer_subject, r.receipt_schema_version,
                      r.assurance_version, v_principal, p_org_id;
END;
$$;


--
-- Name: f1_entitlement_commit_intents_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_entitlement_commit_intents_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'entitlement_commit_intent_immutable' USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.reservation_id IS DISTINCT FROM OLD.reservation_id
     OR NEW.durable_output_type IS DISTINCT FROM OLD.durable_output_type
     OR NEW.durable_output_id IS DISTINCT FROM OLD.durable_output_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id THEN
    RAISE EXCEPTION 'entitlement_commit_intent_facts_immutable' USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.state IS DISTINCT FROM OLD.state
     AND NOT (OLD.state = 'pending' AND NEW.state IN ('committed','released')) THEN
    RAISE EXCEPTION 'entitlement_commit_intent_transition_unavailable % -> %', OLD.state, NEW.state
      USING ERRCODE = 'raise_exception';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: f1_entitlement_counter_windows_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_entitlement_counter_windows_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'entitlement_counter_window_immutable' USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.counter_group IS DISTINCT FROM OLD.counter_group
     OR NEW.window_start IS DISTINCT FROM OLD.window_start
     OR NEW.window_end IS DISTINCT FROM OLD.window_end
     OR NEW.soft_limit IS DISTINCT FROM OLD.soft_limit
     OR NEW.hard_limit IS DISTINCT FROM OLD.hard_limit
     OR NEW.policy_version IS DISTINCT FROM OLD.policy_version
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id THEN
    RAISE EXCEPTION 'entitlement_counter_window_facts_immutable' USING ERRCODE = 'raise_exception';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: f1_entitlement_decisions_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_entitlement_decisions_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  RAISE EXCEPTION 'entitlement_decision_immutable' USING ERRCODE = 'raise_exception';
END;
$$;


--
-- Name: f1_entitlement_lease_heartbeats_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_entitlement_lease_heartbeats_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  RAISE EXCEPTION 'entitlement_lease_heartbeat_immutable' USING ERRCODE = 'raise_exception';
END;
$$;


--
-- Name: f1_entitlement_reservations_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_entitlement_reservations_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'entitlement_reservation_immutable' USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.decision_id IS DISTINCT FROM OLD.decision_id
     OR NEW.counter_window_id IS DISTINCT FROM OLD.counter_window_id
     OR NEW.units IS DISTINCT FROM OLD.units
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id THEN
    RAISE EXCEPTION 'entitlement_reservation_facts_immutable' USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.state IS DISTINCT FROM OLD.state
     AND NOT (
       (OLD.state = 'reserved'  AND NEW.state IN ('executing','released','expired')) OR
       (OLD.state = 'executing' AND NEW.state IN ('committed','released'))
     ) THEN
    RAISE EXCEPTION 'entitlement_reservation_transition_unavailable % -> %', OLD.state, NEW.state
      USING ERRCODE = 'raise_exception';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: f1_evaluations_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_evaluations_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'evaluation_immutable' USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.project_id IS DISTINCT FROM OLD.project_id
     OR NEW.kind IS DISTINCT FROM OLD.kind
     OR NEW.crawl_id IS DISTINCT FROM OLD.crawl_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'evaluation_facts_immutable' USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.state IS DISTINCT FROM OLD.state THEN
    RAISE EXCEPTION 'evaluation_transition_unavailable % -> %', OLD.state, NEW.state USING ERRCODE = 'raise_exception';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: f1_evidence_append_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_evidence_append_only() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  RAISE EXCEPTION 'evidence_is_immutable' USING ERRCODE = 'raise_exception';
END;
$$;


--
-- Name: f1_fail_scheduled_action_dispatch(uuid, uuid, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_fail_scheduled_action_dispatch(p_action_id uuid, p_owner uuid, p_generation bigint) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_now timestamptz(6) := transaction_timestamp();
  v_count bigint;
  v_intervals integer[] := ARRAY[1, 5, 30, 120, 600];
BEGIN
  SELECT dispatch_attempt_count INTO v_count
    FROM scheduled_actions
    WHERE id = p_action_id AND claim_owner = p_owner AND claim_generation = p_generation
      AND status = 'claimed' AND claim_phase = 'scheduler' AND dispatched_at IS NULL
    FOR UPDATE;
  IF NOT FOUND THEN
    RETURN 'noop';
  END IF;

  v_count := v_count + 1;
  IF v_count >= 6 THEN
    UPDATE scheduled_actions
    SET status = 'quarantined', quarantined_at = v_now, reason = 'redis_dispatch_exhausted',
        dispatch_attempt_count = v_count,
        claim_owner = NULL, claimed_at = NULL, lease_expires_at = NULL,
        claim_phase = NULL, last_heartbeat_at = NULL,
        updated_at = v_now, state_version = state_version + 1
    WHERE id = p_action_id;
    RETURN 'quarantined';
  END IF;

  UPDATE scheduled_actions
  SET status = 'pending', dispatch_attempt_count = v_count,
      next_dispatch_at = v_now + make_interval(secs => v_intervals[v_count]),
      reason = 'redis_dispatch_retry_scheduled',
      claim_owner = NULL, claimed_at = NULL, lease_expires_at = NULL,
      claim_phase = NULL, last_heartbeat_at = NULL,
      updated_at = v_now, state_version = state_version + 1
  WHERE id = p_action_id;
  RETURN 'rescheduled';
END;
$$;


--
-- Name: f1_find_invitation_acceptance_replay(bytea, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_find_invitation_acceptance_replay(p_reference_digest bytea, p_key_digest bytea) RETURNS TABLE(organization_id uuid, invitation_id uuid, request_hex text, result_id uuid, audit_record_id uuid, correlation_id uuid, authorized_payload jsonb, account_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT ce.organization_id, ce.target_id, encode(ce.request_sha256, 'hex'),
         cr.id, cr.audit_record_id, cr.correlation_id, cr.authorized_payload,
         (cr.authorized_payload->>'account_id')::uuid
  FROM command_executions ce
  JOIN command_results cr ON cr.command_execution_id = ce.id
  WHERE ce.command_type = 'wf001.accept_invitation'
    AND ce.idempotency_key_digest = p_key_digest
    AND ce.canonical_payload->>'invitation_reference_sha256' = encode(p_reference_digest, 'hex')
    AND cr.outcome = 'success'
  ORDER BY ce.created_at DESC
  LIMIT 1;
$$;


--
-- Name: f1_organizations_lifecycle_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_organizations_lifecycle_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE allowed text[];
BEGIN
  -- ":230 monotonically increasing authorization epoch". An epoch that could
  -- go backwards would let a previously issued authority become current
  -- again, so no path may decrease it.
  IF NEW.authorization_epoch < OLD.authorization_epoch THEN
    RAISE EXCEPTION 'organization_authorization_epoch_regressed' USING ERRCODE = 'raise_exception';
  END IF;

  -- The lifecycle status and the epoch move together. Suspension that did not
  -- advance the epoch, or an epoch advance that silently changed the status,
  -- would be exactly the split-brain result the transaction boundary forbids.
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.authorization_epoch = OLD.authorization_epoch THEN
    RAISE EXCEPTION 'organization_status_changed_without_epoch_advance' USING ERRCODE = 'raise_exception';
  END IF;

  -- 016 STATE_MODEL.md :97: pending to active; active to suspended; suspended
  -- to active; active to closed; suspended to closed. Nothing else, and
  -- closed never reopens.
  allowed := CASE OLD.status
               WHEN 'pending'   THEN ARRAY['pending','active']
               WHEN 'active'    THEN ARRAY['active','suspended','closed']
               WHEN 'suspended' THEN ARRAY['suspended','active','closed']
               ELSE ARRAY[OLD.status]
             END;
  IF NOT (NEW.status = ANY (allowed)) THEN
    RAISE EXCEPTION 'organization_illegal_transition % -> %', OLD.status, NEW.status
      USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: f1_projects_lifecycle_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_projects_lifecycle_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    RAISE EXCEPTION 'project_organization_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  -- S-03 permits exactly Project.Draft -> Project.Active (gated by the ActivateProject
  -- handler on >=1 active same-Project Source); pause/resume/archive remain refused
  -- (OD-014 pending).
  IF NEW.state IS DISTINCT FROM OLD.state THEN
  IF NOT (OLD.state = 'draft' AND NEW.state = 'active') THEN
    RAISE EXCEPTION 'project_lifecycle_transition_unavailable % -> %', OLD.state, NEW.state
      USING ERRCODE = 'raise_exception';
  END IF;
END IF;

  IF NEW.display_name IS DISTINCT FROM OLD.display_name
     OR NEW.locale IS DISTINCT FROM OLD.locale
     OR NEW.time_zone IS DISTINCT FROM OLD.time_zone
     OR NEW.objective IS DISTINCT FROM OLD.objective
     OR NEW.project_profile_schema_version IS DISTINCT FROM OLD.project_profile_schema_version
     OR NEW.local_presence_applicable IS DISTINCT FROM OLD.local_presence_applicable
     OR NEW.local_presence_reason IS DISTINCT FROM OLD.local_presence_reason
     OR NEW.local_business_profile IS DISTINCT FROM OLD.local_business_profile
     OR NEW.local_business_profile_content_sha256 IS DISTINCT FROM OLD.local_business_profile_content_sha256
     OR NEW.profile_attesting_account_id IS DISTINCT FROM OLD.profile_attesting_account_id
     OR NEW.profile_committed_at IS DISTINCT FROM OLD.profile_committed_at THEN
    RAISE EXCEPTION 'project_profile_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: f1_release_expired_scheduled_action_leases(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_release_expired_scheduled_action_leases(p_limit integer) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_now timestamptz(6) := transaction_timestamp(); v_changed integer;
BEGIN
  WITH expired AS (
    SELECT a.id FROM scheduled_actions a
    WHERE a.status IN ('claimed','dispatched') AND a.lease_expires_at <= v_now
    ORDER BY a.lease_expires_at, a.id
    FOR UPDATE SKIP LOCKED
    LIMIT greatest(p_limit, 0)
  )
  UPDATE scheduled_actions a
  SET status = 'pending', claim_owner = NULL, claimed_at = NULL, lease_expires_at = NULL,
      claim_phase = NULL, last_heartbeat_at = NULL, reason = 'transport_lease_expired',
      updated_at = v_now, state_version = a.state_version + 1
  FROM expired
  WHERE a.id = expired.id;
  GET DIAGNOSTICS v_changed = ROW_COUNT;
  RETURN v_changed;
END;
$$;


--
-- Name: f1_release_scheduled_action_claim(uuid, uuid, bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_release_scheduled_action_claim(p_action_id uuid, p_owner uuid, p_generation bigint, p_reason text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_now timestamptz(6) := transaction_timestamp(); v_changed integer;
BEGIN
  UPDATE scheduled_actions a
  SET status = 'pending', claim_owner = NULL, claimed_at = NULL, lease_expires_at = NULL,
      claim_phase = NULL, last_heartbeat_at = NULL, reason = coalesce(p_reason, a.reason),
      updated_at = v_now, state_version = a.state_version + 1
  WHERE a.id = p_action_id
    AND a.claim_owner = p_owner
    AND a.claim_generation = p_generation
    AND a.status IN ('claimed','dispatched');
  GET DIAGNOSTICS v_changed = ROW_COUNT;
  RETURN v_changed > 0;
END;
$$;


--
-- Name: f1_resolve_invitation_org(bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_resolve_invitation_org(p_reference_digest bytea) RETURNS TABLE(organization_id uuid, invitation_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT r.organization_id, r.invitation_id
  FROM invitation_reference_registry r
  WHERE r.opaque_reference_sha256 = p_reference_digest;
$$;


--
-- Name: f1_resolve_invitation_reference(bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_resolve_invitation_reference(p_reference_digest bytea) RETURNS TABLE(organization_id uuid, invitation_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT r.organization_id, r.invitation_id
  FROM invitation_reference_registry r
  WHERE r.opaque_reference_sha256 = p_reference_digest
    AND r.invitation_state = 'active'
    AND (r.expires_at IS NULL OR transaction_timestamp() < r.expires_at);
$$;


--
-- Name: f1_role_assignments_lifecycle_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_role_assignments_lifecycle_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE allowed text[];
BEGIN
  -- The approved protected authority is written once, by the transition that
  -- makes the grant effective, and is immutable from then on. Step 4 of the
  -- effective-permission algorithm reads it, so a later edit would silently
  -- re-authorize history.
  IF NEW.protected_permission_allowlist IS DISTINCT FROM OLD.protected_permission_allowlist THEN
    IF NOT (OLD.status = 'pending' AND NEW.status = 'active') THEN
      RAISE EXCEPTION 'role_assignment_allowlist_immutable' USING ERRCODE = 'raise_exception';
    END IF;
    IF jsonb_array_length(OLD.protected_permission_allowlist) <> 0 THEN
      RAISE EXCEPTION 'role_assignment_allowlist_immutable' USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  -- A pending Assignment "confers no permission while pending" (:316), so it
  -- may never carry approved protected authority.
  IF NEW.status = 'pending' AND jsonb_array_length(NEW.protected_permission_allowlist) <> 0 THEN
    RAISE EXCEPTION 'role_assignment_pending_confers_nothing' USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.bootstrap_admin_exception IS DISTINCT FROM OLD.bootstrap_admin_exception THEN
    RAISE EXCEPTION 'role_assignment_bootstrap_exception_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.account_id IS DISTINCT FROM OLD.account_id
     OR NEW.canonical_role IS DISTINCT FROM OLD.canonical_role
     OR NEW.permission_mode IS DISTINCT FROM OLD.permission_mode
     OR NEW.persona IS DISTINCT FROM OLD.persona
     OR NEW.scope_sha256 IS DISTINCT FROM OLD.scope_sha256
     OR NEW.requester_account_id IS DISTINCT FROM OLD.requester_account_id
     OR NEW.requested_at IS DISTINCT FROM OLD.requested_at THEN
    RAISE EXCEPTION 'role_assignment_grant_content_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  allowed := CASE OLD.status
               WHEN 'pending' THEN ARRAY['pending','active','rejected','expired']
               WHEN 'active'  THEN ARRAY['active','revoked','expired']
               ELSE ARRAY[OLD.status]
             END;
  IF NOT (NEW.status = ANY (allowed)) THEN
    RAISE EXCEPTION 'role_assignment_illegal_transition % -> %', OLD.status, NEW.status
      USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: f1_scheduled_actions_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_scheduled_actions_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE allowed text[];
BEGIN
  IF NEW.id <> OLD.id
     OR NEW.schema_version IS DISTINCT FROM OLD.schema_version
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
     OR NEW.causation_id IS DISTINCT FROM OLD.causation_id
     OR NEW.command_id IS DISTINCT FROM OLD.command_id
     OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.project_id IS DISTINCT FROM OLD.project_id
     OR NEW.executing_service_identity_id IS DISTINCT FROM OLD.executing_service_identity_id
     OR NEW.action_kind IS DISTINCT FROM OLD.action_kind
     OR NEW.action_schema_version IS DISTINCT FROM OLD.action_schema_version
     OR NEW.target_type IS DISTINCT FROM OLD.target_type
     OR NEW.target_id IS DISTINCT FROM OLD.target_id
     OR NEW.product_generation IS DISTINCT FROM OLD.product_generation
     OR NEW.schedule_generation IS DISTINCT FROM OLD.schedule_generation
     OR NEW.due_at IS DISTINCT FROM OLD.due_at
     OR NEW.not_before_at IS DISTINCT FROM OLD.not_before_at
     OR NEW.identity_preimage IS DISTINCT FROM OLD.identity_preimage
     OR NEW.identity_sha256 IS DISTINCT FROM OLD.identity_sha256
     OR NEW.collision_ordinal IS DISTINCT FROM OLD.collision_ordinal
     OR NEW.payload_refs IS DISTINCT FROM OLD.payload_refs THEN
    RAISE EXCEPTION 'scheduled_action_immutable_field_changed' USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.claim_generation < OLD.claim_generation THEN
    RAISE EXCEPTION 'scheduled_action_claim_generation_regressed' USING ERRCODE = 'raise_exception';
  END IF;

  IF (OLD.completed_at IS NOT NULL AND NEW.completed_at IS DISTINCT FROM OLD.completed_at)
     OR (OLD.canceled_at IS NOT NULL AND NEW.canceled_at IS DISTINCT FROM OLD.canceled_at)
     OR (OLD.quarantined_at IS NOT NULL AND NEW.quarantined_at IS DISTINCT FROM OLD.quarantined_at)
     OR (OLD.dispatched_at IS NOT NULL AND NEW.dispatched_at IS DISTINCT FROM OLD.dispatched_at) THEN
    RAISE EXCEPTION 'scheduled_action_terminal_timestamp_rewritten' USING ERRCODE = 'raise_exception';
  END IF;

  allowed := CASE OLD.status
               WHEN 'pending'    THEN ARRAY['pending','claimed','canceled','quarantined']
               WHEN 'claimed'    THEN ARRAY['claimed','dispatched','pending','canceled','quarantined']
               WHEN 'dispatched' THEN ARRAY['dispatched','completed','pending','quarantined']
               ELSE ARRAY[OLD.status]
             END;
  IF NOT (NEW.status = ANY (allowed)) THEN
    RAISE EXCEPTION 'scheduled_action_illegal_transition % -> %', OLD.status, NEW.status
      USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: f1_service_identity_active(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_service_identity_active(p_service_identity_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM service_identities s
    WHERE s.id = p_service_identity_id AND s.status = 'active'
  );
$$;


--
-- Name: f1_settle_scheduled_action(uuid, uuid, bigint, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_settle_scheduled_action(p_action_id uuid, p_owner uuid, p_generation bigint, p_status text, p_reason text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_now timestamptz(6) := transaction_timestamp(); v_changed integer;
BEGIN
  IF p_status NOT IN ('completed','quarantined') THEN
    RAISE EXCEPTION 'scheduled_action_settle_status_invalid' USING ERRCODE = 'raise_exception';
  END IF;
  UPDATE scheduled_actions a
  SET status = p_status,
      completed_at = CASE WHEN p_status = 'completed' THEN v_now ELSE a.completed_at END,
      quarantined_at = CASE WHEN p_status = 'quarantined' THEN v_now ELSE a.quarantined_at END,
      reason = coalesce(p_reason, a.reason),
      claim_owner = NULL, claimed_at = NULL, lease_expires_at = NULL,
      claim_phase = NULL, last_heartbeat_at = NULL,
      updated_at = v_now, state_version = a.state_version + 1
  WHERE a.id = p_action_id
    AND a.claim_owner = p_owner
    AND a.claim_generation = p_generation
    AND (a.status = 'dispatched' OR (a.status = 'claimed' AND p_status = 'quarantined'));
  GET DIAGNOSTICS v_changed = ROW_COUNT;
  RETURN v_changed > 0;
END;
$$;


--
-- Name: f1_source_scope_change_requests_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_source_scope_change_requests_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'source_scope_change_request_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  -- A terminal request is immutable: no field may change once it leaves pending.
  IF OLD.state <> 'pending' THEN
    RAISE EXCEPTION 'source_scope_change_request_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.project_id IS DISTINCT FROM OLD.project_id
     OR NEW.source_id IS DISTINCT FROM OLD.source_id THEN
    RAISE EXCEPTION 'source_scope_change_request_tenant_identity_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.schema_version IS DISTINCT FROM OLD.schema_version
     OR NEW.requester_account_id IS DISTINCT FROM OLD.requester_account_id
     OR NEW.expected_active_policy_version IS DISTINCT FROM OLD.expected_active_policy_version
     OR NEW.current_content_sha256 IS DISTINCT FROM OLD.current_content_sha256
     OR NEW.proposed_canonical_host IS DISTINCT FROM OLD.proposed_canonical_host
     OR NEW.proposed_allowed_schemes IS DISTINCT FROM OLD.proposed_allowed_schemes
     OR NEW.proposed_allowed_ports IS DISTINCT FROM OLD.proposed_allowed_ports
     OR NEW.proposed_include_prefixes IS DISTINCT FROM OLD.proposed_include_prefixes
     OR NEW.proposed_exclude_prefixes IS DISTINCT FROM OLD.proposed_exclude_prefixes
     OR NEW.proposed_query_handling IS DISTINCT FROM OLD.proposed_query_handling
     OR NEW.proposed_content_sha256 IS DISTINCT FROM OLD.proposed_content_sha256
     OR NEW.request_reason IS DISTINCT FROM OLD.request_reason
     OR NEW.requested_at_utc IS DISTINCT FROM OLD.requested_at_utc
     OR NEW.due_at_utc IS DISTINCT FROM OLD.due_at_utc
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
     OR NEW.idempotency_key_digest IS DISTINCT FROM OLD.idempotency_key_digest THEN
    RAISE EXCEPTION 'source_scope_change_request_facts_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  -- The only permitted change to a pending request is a transition to a terminal state
  -- (a decision or, from this tranche, an expiry); pending -> pending is refused.
  IF NOT (NEW.state IN ('approved','rejected','canceled','expired')) THEN
    RAISE EXCEPTION 'source_scope_change_request_transition_unavailable % -> %', OLD.state, NEW.state
      USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: f1_source_scope_policies_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_source_scope_policies_immutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  RAISE EXCEPTION 'source_scope_policy_immutable' USING ERRCODE = 'raise_exception';
END;
$$;


--
-- Name: f1_sources_lifecycle_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_sources_lifecycle_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.project_id IS DISTINCT FROM OLD.project_id THEN
    RAISE EXCEPTION 'source_tenant_identity_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.submitted_root_uri IS DISTINCT FROM OLD.submitted_root_uri
     OR NEW.canonical_root_uri IS DISTINCT FROM OLD.canonical_root_uri
     OR NEW.canonical_host IS DISTINCT FROM OLD.canonical_host
     OR NEW.registration_schema_version IS DISTINCT FROM OLD.registration_schema_version
     OR NEW.host_normalization_version IS DISTINCT FROM OLD.host_normalization_version
     OR NEW.registration_origin IS DISTINCT FROM OLD.registration_origin
     OR NEW.registering_account_id IS DISTINCT FROM OLD.registering_account_id
     OR NEW.registration_command_id IS DISTINCT FROM OLD.registration_command_id
     OR NEW.registration_idempotency_key_digest IS DISTINCT FROM OLD.registration_idempotency_key_digest
     OR NEW.registration_authorization_decision_id IS DISTINCT FROM OLD.registration_authorization_decision_id
     OR NEW.registered_at IS DISTINCT FROM OLD.registered_at THEN
    RAISE EXCEPTION 'source_registration_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.state IS DISTINCT FROM OLD.state THEN
  -- S-06-006 permits the four PRULE-006 lifecycle edges in addition to the S-05-006
  -- proposed -> verified edge; every other transition is refused and audited by the caller.
  IF NOT ((OLD.state = 'proposed' AND NEW.state = 'verified')
OR (OLD.state = 'verified' AND NEW.state = 'active')
OR (OLD.state = 'active'   AND NEW.state = 'disabled')
OR (OLD.state = 'disabled' AND NEW.state = 'active')
OR (OLD.state = 'disabled' AND NEW.state = 'removed')) THEN
    RAISE EXCEPTION 'source_lifecycle_transition_unavailable % -> %', OLD.state, NEW.state
      USING ERRCODE = 'raise_exception';
  END IF;
END IF;

  RETURN NEW;
END;
$$;


--
-- Name: f1_verification_attempts_lifecycle_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_verification_attempts_lifecycle_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.project_id IS DISTINCT FROM OLD.project_id
     OR NEW.verification_request_id IS DISTINCT FROM OLD.verification_request_id
     OR NEW.source_id IS DISTINCT FROM OLD.source_id THEN
    RAISE EXCEPTION 'verification_attempt_tenant_identity_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.schema_version IS DISTINCT FROM OLD.schema_version
     OR NEW.attempt_number IS DISTINCT FROM OLD.attempt_number
     OR NEW.origin IS DISTINCT FROM OLD.origin
     OR NEW.automated_slot_offset_minutes IS DISTINCT FROM OLD.automated_slot_offset_minutes
     OR NEW.reserved_at_utc IS DISTINCT FROM OLD.reserved_at_utc THEN
    RAISE EXCEPTION 'verification_attempt_reservation_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.state IS DISTINCT FROM OLD.state THEN
  -- S-05-005 relaxes exactly the reserved -> completed edge (observation
  -- recording); every other transition remains unavailable until its slice lands.
  IF NOT (OLD.state = 'reserved' AND NEW.state = 'completed') THEN
    RAISE EXCEPTION 'verification_attempt_transition_unavailable % -> %', OLD.state, NEW.state
      USING ERRCODE = 'raise_exception';
  END IF;
END IF;

  RETURN NEW;
END;
$$;


--
-- Name: f1_verification_requests_lifecycle_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_verification_requests_lifecycle_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.project_id IS DISTINCT FROM OLD.project_id
     OR NEW.source_id IS DISTINCT FROM OLD.source_id THEN
    RAISE EXCEPTION 'verification_request_tenant_identity_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.schema_version IS DISTINCT FROM OLD.schema_version
     OR NEW.request_initiator_account_id IS DISTINCT FROM OLD.request_initiator_account_id
     OR NEW.method IS DISTINCT FROM OLD.method
     OR NEW.canonical_host IS DISTINCT FROM OLD.canonical_host
     OR NEW.challenge_token_sha256 IS DISTINCT FROM OLD.challenge_token_sha256
     OR NEW.idempotency_key_digest IS DISTINCT FROM OLD.idempotency_key_digest
     OR NEW.initial_challenge_delivered_at_utc IS DISTINCT FROM OLD.initial_challenge_delivered_at_utc
     OR NEW.issued_at_utc IS DISTINCT FROM OLD.issued_at_utc
     OR NEW.expires_at_utc IS DISTINCT FROM OLD.expires_at_utc THEN
    RAISE EXCEPTION 'verification_request_issuance_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.request_status IS DISTINCT FROM OLD.request_status THEN
  -- S-05-002 relaxed pending -> expired; S-05-006 adds pending -> verified
  -- (matched success). Every other transition remains unavailable.
  IF NOT (OLD.request_status = 'pending' AND NEW.request_status IN ('expired','verified')) THEN
    RAISE EXCEPTION 'verification_request_transition_unavailable % -> %', OLD.request_status, NEW.request_status
      USING ERRCODE = 'raise_exception';
  END IF;
END IF;

  RETURN NEW;
END;
$$;


--
-- Name: f1_work_dispatch_bindings_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_work_dispatch_bindings_immutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  RAISE EXCEPTION 'work_dispatch_binding_is_immutable' USING ERRCODE = 'raise_exception';
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: access_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.access_policies (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    policy_type text NOT NULL,
    semantic_version text NOT NULL,
    status text NOT NULL,
    content_sha256 bytea,
    effective_at timestamp(6) with time zone,
    expires_at timestamp(6) with time zone,
    plan_scope text,
    CONSTRAINT access_policies_content_sha256_check CHECK (((content_sha256 IS NULL) OR (octet_length(content_sha256) = 32))),
    CONSTRAINT access_policies_policy_type_check CHECK ((policy_type = 'access'::text)),
    CONSTRAINT access_policies_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'superseded'::text, 'retired'::text])))
);

ALTER TABLE ONLY public.access_policies FORCE ROW LEVEL SECURITY;


--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    identity_issuer_key text NOT NULL,
    identity_subject text NOT NULL,
    normalized_email text NOT NULL,
    normalized_email_sha256 bytea NOT NULL,
    display_name text NOT NULL,
    status text NOT NULL,
    identity_receipt_digest bytea,
    activated_at timestamp(6) with time zone,
    suspended_at timestamp(6) with time zone,
    revoked_at timestamp(6) with time zone,
    terminal_reason text,
    CONSTRAINT accounts_identity_receipt_digest_check CHECK (((identity_receipt_digest IS NULL) OR (octet_length(identity_receipt_digest) = 32))),
    CONSTRAINT accounts_normalized_email_sha256_check CHECK ((octet_length(normalized_email_sha256) = 32)),
    CONSTRAINT accounts_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'suspended'::text, 'revoked'::text])))
);

ALTER TABLE ONLY public.accounts FORCE ROW LEVEL SECURITY;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_record_registry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_record_registry (
    id uuid NOT NULL,
    schema_version text NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    occurred_at timestamp(6) with time zone NOT NULL,
    partition_month date NOT NULL,
    organization_id uuid NOT NULL,
    workflow_id text NOT NULL,
    actor_id uuid,
    service_identity_id uuid,
    correlation_id uuid NOT NULL,
    causation_id uuid NOT NULL,
    command_id uuid,
    idempotency_key_digest bytea,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    from_state text,
    to_state text,
    outcome text NOT NULL,
    reason_code text,
    classification text NOT NULL,
    payload jsonb NOT NULL,
    content_sha256 bytea NOT NULL,
    retention_class text NOT NULL,
    CONSTRAINT audit_record_registry_content_sha256_check CHECK ((octet_length(content_sha256) = 32)),
    CONSTRAINT audit_record_registry_idempotency_key_digest_check CHECK (((idempotency_key_digest IS NULL) OR (octet_length(idempotency_key_digest) = 32))),
    CONSTRAINT audit_record_registry_retention_class_check CHECK ((retention_class = 'security_audit'::text)),
    CONSTRAINT audit_record_registry_workflow_id_check CHECK ((workflow_id ~ '^WF-[0-9]{3}$'::text)),
    CONSTRAINT exactly_one_actor_or_service CHECK (((actor_id IS NULL) <> (service_identity_id IS NULL))),
    CONSTRAINT partition_month_is_first_of_month CHECK ((partition_month = (date_trunc('month'::text, (occurred_at AT TIME ZONE 'UTC'::text)))::date))
);

ALTER TABLE ONLY public.audit_record_registry FORCE ROW LEVEL SECURITY;


--
-- Name: authorization_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.authorization_decisions (
    id uuid NOT NULL,
    schema_version text NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    organization_id uuid NOT NULL,
    correlation_id uuid NOT NULL,
    causation_id uuid NOT NULL,
    command_id uuid,
    subject_type text NOT NULL,
    subject_id uuid NOT NULL,
    action text NOT NULL,
    resource_type text NOT NULL,
    resource_id uuid,
    decision text NOT NULL,
    reason_code text NOT NULL,
    organization_epoch bigint NOT NULL,
    membership_snapshot jsonb NOT NULL,
    role_assignment_versions jsonb NOT NULL,
    policy_snapshot_id uuid,
    support_session_id uuid,
    classification_ceiling text,
    decided_at timestamp(6) with time zone NOT NULL,
    retention_class text NOT NULL,
    CONSTRAINT authorization_decisions_decision_check CHECK ((decision = ANY (ARRAY['allow'::text, 'deny'::text]))),
    CONSTRAINT authorization_decisions_retention_class_check CHECK ((retention_class = 'security_audit'::text)),
    CONSTRAINT authorization_decisions_subject_type_check CHECK ((subject_type = ANY (ARRAY['account'::text, 'service_identity'::text])))
);

ALTER TABLE ONLY public.authorization_decisions FORCE ROW LEVEL SECURITY;


--
-- Name: billing_entities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_entities (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    internal_contract_reference text NOT NULL,
    active_plan_assignment_id uuid,
    state text NOT NULL,
    effective_at timestamp(6) with time zone,
    activated_at timestamp(6) with time zone,
    closed_at timestamp(6) with time zone,
    lifecycle_reason text,
    last_billing_event_id uuid,
    CONSTRAINT billing_active_has_plan CHECK (((state <> 'active'::text) OR (active_plan_assignment_id IS NOT NULL))),
    CONSTRAINT billing_entities_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'active'::text, 'past_due'::text, 'suspended'::text, 'closed'::text]))),
    CONSTRAINT billing_pending_has_no_plan CHECK (((state <> 'pending'::text) OR (active_plan_assignment_id IS NULL)))
);

ALTER TABLE ONLY public.billing_entities FORCE ROW LEVEL SECURITY;


--
-- Name: bootstrap_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bootstrap_grants (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    causation_id uuid NOT NULL,
    command_id uuid,
    idempotency_key_digest bytea,
    content_sha256 bytea,
    bootstrap_principal_digest bytea NOT NULL,
    allowed_action text NOT NULL,
    issuer_service_identity_id uuid NOT NULL,
    policy_version text NOT NULL,
    issued_at timestamp(6) with time zone NOT NULL,
    expires_at timestamp(6) with time zone NOT NULL,
    state text NOT NULL,
    consuming_command_id uuid,
    organization_id uuid,
    reason_code text,
    CONSTRAINT bootstrap_grants_allowed_action_check CHECK ((allowed_action = 'organization.bootstrap'::text)),
    CONSTRAINT bootstrap_grants_bootstrap_principal_digest_check CHECK ((octet_length(bootstrap_principal_digest) = 32)),
    CONSTRAINT bootstrap_grants_content_sha256_check CHECK (((content_sha256 IS NULL) OR (octet_length(content_sha256) = 32))),
    CONSTRAINT bootstrap_grants_idempotency_key_digest_check CHECK (((idempotency_key_digest IS NULL) OR (octet_length(idempotency_key_digest) = 32))),
    CONSTRAINT bootstrap_grants_state_check CHECK ((state = ANY (ARRAY['issued'::text, 'consumed'::text, 'revoked'::text, 'expired'::text]))),
    CONSTRAINT grant_lifetime_is_fifteen_minutes CHECK ((expires_at = (issued_at + '00:15:00'::interval)))
);

ALTER TABLE ONLY public.bootstrap_grants FORCE ROW LEVEL SECURITY;


--
-- Name: command_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.command_executions (
    id uuid NOT NULL,
    schema_version text NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    causation_id uuid NOT NULL,
    command_id uuid NOT NULL,
    idempotency_key_digest bytea,
    content_sha256 bytea,
    command_type text NOT NULL,
    command_schema_version text NOT NULL,
    actor_id uuid,
    service_identity_id uuid,
    organization_id uuid,
    bootstrap_principal_digest bytea,
    project_id uuid,
    target_type text NOT NULL,
    target_id uuid,
    action text NOT NULL,
    expected_state_version bigint,
    requested_at timestamp(6) with time zone NOT NULL,
    client_requested_at timestamp(6) with time zone,
    authorization_check_at timestamp(6) with time zone NOT NULL,
    policy_versions jsonb NOT NULL,
    canonical_payload jsonb NOT NULL,
    request_sha256 bytea NOT NULL,
    CONSTRAINT command_executions_bootstrap_principal_digest_check CHECK (((bootstrap_principal_digest IS NULL) OR (octet_length(bootstrap_principal_digest) = 32))),
    CONSTRAINT command_executions_content_sha256_check CHECK (((content_sha256 IS NULL) OR (octet_length(content_sha256) = 32))),
    CONSTRAINT command_executions_idempotency_key_digest_check CHECK (((idempotency_key_digest IS NULL) OR (octet_length(idempotency_key_digest) = 32))),
    CONSTRAINT command_executions_request_sha256_check CHECK ((octet_length(request_sha256) = 32)),
    CONSTRAINT exactly_one_actor_or_service CHECK (((actor_id IS NULL) <> (service_identity_id IS NULL)))
);

ALTER TABLE ONLY public.command_executions FORCE ROW LEVEL SECURITY;


--
-- Name: command_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.command_results (
    id uuid NOT NULL,
    schema_version text NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    causation_id uuid NOT NULL,
    command_id uuid NOT NULL,
    idempotency_key_digest bytea,
    content_sha256 bytea,
    command_execution_id uuid NOT NULL,
    result_schema_version text NOT NULL,
    outcome text NOT NULL,
    organization_id uuid,
    project_id uuid,
    actor_id uuid,
    service_identity_id uuid,
    completed_at timestamp(6) with time zone NOT NULL,
    authorization_check_at timestamp(6) with time zone NOT NULL,
    target_refs jsonb NOT NULL,
    resulting_state_version bigint,
    governing_policy_versions jsonb NOT NULL,
    error_class text,
    error_code text,
    reason_code text,
    severity text,
    retryable boolean,
    recovery_action text,
    support_reference text,
    authorized_payload jsonb NOT NULL,
    audit_record_id uuid NOT NULL,
    CONSTRAINT command_results_content_sha256_check CHECK (((content_sha256 IS NULL) OR (octet_length(content_sha256) = 32))),
    CONSTRAINT command_results_idempotency_key_digest_check CHECK (((idempotency_key_digest IS NULL) OR (octet_length(idempotency_key_digest) = 32))),
    CONSTRAINT command_results_outcome_check CHECK ((outcome = ANY (ARRAY['success'::text, 'failure'::text]))),
    CONSTRAINT exactly_one_actor_or_service CHECK (((actor_id IS NULL) <> (service_identity_id IS NULL))),
    CONSTRAINT failure_tuple_present_only_on_failure CHECK ((((outcome = 'success'::text) AND (error_class IS NULL) AND (error_code IS NULL) AND (reason_code IS NULL) AND (severity IS NULL) AND (retryable IS NULL) AND (recovery_action IS NULL)) OR ((outcome = 'failure'::text) AND (error_class IS NOT NULL) AND (error_code IS NOT NULL) AND (reason_code IS NOT NULL) AND (severity IS NOT NULL) AND (retryable IS NOT NULL) AND (recovery_action IS NOT NULL))))
);

ALTER TABLE ONLY public.command_results FORCE ROW LEVEL SECURITY;


--
-- Name: crawl_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crawl_policies (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    schema_version text NOT NULL,
    organization_id uuid NOT NULL,
    project_id uuid,
    scope text NOT NULL,
    policy_version text NOT NULL,
    state text NOT NULL,
    supersedes_id uuid,
    activated_by_account_id uuid NOT NULL,
    normalized_bounds jsonb NOT NULL,
    content_sha256 bytea NOT NULL,
    superseded_at timestamp(6) with time zone,
    CONSTRAINT crawl_policies_content_sha256_check CHECK ((octet_length(content_sha256) = 32)),
    CONSTRAINT crawl_policies_normalized_bounds_check CHECK ((jsonb_typeof(normalized_bounds) = 'object'::text)),
    CONSTRAINT crawl_policies_schema_version_check CHECK ((schema_version = 'crawl-policy-v1'::text)),
    CONSTRAINT crawl_policies_scope_check CHECK ((scope = ANY (ARRAY['organization'::text, 'project'::text]))),
    CONSTRAINT crawl_policies_scope_project_agreement CHECK ((((scope = 'organization'::text) AND (project_id IS NULL)) OR ((scope = 'project'::text) AND (project_id IS NOT NULL)))),
    CONSTRAINT crawl_policies_state_check CHECK ((state = ANY (ARRAY['active'::text, 'superseded'::text]))),
    CONSTRAINT crawl_policies_terminal_shape CHECK ((((state = 'active'::text) AND (superseded_at IS NULL)) OR ((state = 'superseded'::text) AND (superseded_at IS NOT NULL))))
);

ALTER TABLE ONLY public.crawl_policies FORCE ROW LEVEL SECURITY;


--
-- Name: crawl_sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crawl_sources (
    id uuid NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    crawl_id uuid NOT NULL,
    source_id uuid NOT NULL,
    source_state_version bigint NOT NULL,
    scope_policy_id uuid NOT NULL,
    scope_policy_version text NOT NULL,
    canonical_root_uri text NOT NULL,
    source_order integer NOT NULL,
    CONSTRAINT crawl_sources_source_order_check CHECK ((source_order >= 0))
);

ALTER TABLE ONLY public.crawl_sources FORCE ROW LEVEL SECURITY;


--
-- Name: crawls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crawls (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    kind text NOT NULL,
    parent_evaluation_id uuid,
    parent_crawl_id uuid,
    requested_crawl_policy_id uuid,
    requested_crawl_policy_version text,
    requested_entitlement_policy_id uuid NOT NULL,
    requested_entitlement_policy_version text NOT NULL,
    entitlement_decision_id uuid,
    entitlement_reservation_id uuid,
    trigger_kind text NOT NULL,
    triggered_by_account_id uuid,
    queued_at timestamp(6) with time zone NOT NULL,
    started_at timestamp(6) with time zone,
    terminal_at timestamp(6) with time zone,
    deadline_at timestamp(6) with time zone,
    state text NOT NULL,
    coverage_status text,
    completion_reason text,
    limit_counters jsonb DEFAULT '{}'::jsonb NOT NULL,
    retry_generation bigint DEFAULT 0 NOT NULL,
    recovery_generation bigint DEFAULT 0 NOT NULL,
    recovery_of_id uuid,
    idempotency_key_digest bytea,
    CONSTRAINT crawls_coverage_status_check CHECK ((coverage_status = ANY (ARRAY['full'::text, 'partial'::text]))),
    CONSTRAINT crawls_idempotency_key_digest_check CHECK (((idempotency_key_digest IS NULL) OR (octet_length(idempotency_key_digest) = 32))),
    CONSTRAINT crawls_kind_check CHECK ((kind = ANY (ARRAY['root'::text, 'reassessment_child'::text]))),
    CONSTRAINT crawls_kind_parent_agreement CHECK ((((kind = 'root'::text) AND (parent_evaluation_id IS NULL)) OR ((kind = 'reassessment_child'::text) AND (parent_evaluation_id IS NOT NULL)))),
    CONSTRAINT crawls_state_check CHECK ((state = ANY (ARRAY['queued'::text, 'running'::text, 'completed'::text, 'failed'::text, 'canceled'::text]))),
    CONSTRAINT crawls_terminal_shape CHECK ((((state = ANY (ARRAY['queued'::text, 'running'::text])) AND (terminal_at IS NULL) AND (coverage_status IS NULL) AND (completion_reason IS NULL)) OR ((state = ANY (ARRAY['completed'::text, 'failed'::text, 'canceled'::text])) AND (terminal_at IS NOT NULL)))),
    CONSTRAINT crawls_trigger_kind_check CHECK ((trigger_kind = ANY (ARRAY['manual'::text, 'scheduled'::text])))
);

ALTER TABLE ONLY public.crawls FORCE ROW LEVEL SECURITY;


--
-- Name: entitlement_commit_intents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entitlement_commit_intents (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    reservation_id uuid NOT NULL,
    durable_output_type text NOT NULL,
    durable_output_id uuid NOT NULL,
    durable_output_sha256 bytea,
    state text NOT NULL,
    terminal_at timestamp(6) with time zone,
    terminal_reason text,
    CONSTRAINT entitlement_commit_intents_durable_output_sha256_check CHECK (((durable_output_sha256 IS NULL) OR (octet_length(durable_output_sha256) = 32))),
    CONSTRAINT entitlement_commit_intents_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'committed'::text, 'released'::text]))),
    CONSTRAINT entitlement_commit_intents_terminal_shape CHECK ((((state = 'pending'::text) AND (terminal_at IS NULL)) OR ((state = ANY (ARRAY['committed'::text, 'released'::text])) AND (terminal_at IS NOT NULL))))
);

ALTER TABLE ONLY public.entitlement_commit_intents FORCE ROW LEVEL SECURITY;


--
-- Name: entitlement_counter_windows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entitlement_counter_windows (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    counter_group text NOT NULL,
    window_start timestamp(6) with time zone NOT NULL,
    window_end timestamp(6) with time zone NOT NULL,
    soft_limit bigint NOT NULL,
    hard_limit bigint NOT NULL,
    reserved_units bigint DEFAULT 0 NOT NULL,
    committed_units bigint DEFAULT 0 NOT NULL,
    low_cost_units bigint DEFAULT 0 NOT NULL,
    policy_version text NOT NULL,
    reconciliation_state text DEFAULT 'authoritative'::text NOT NULL,
    CONSTRAINT entitlement_counter_windows_limits_ordered CHECK ((soft_limit < hard_limit)),
    CONSTRAINT entitlement_counter_windows_reconciliation_state_check CHECK ((reconciliation_state = ANY (ARRAY['authoritative'::text, 'reconciling'::text]))),
    CONSTRAINT entitlement_counter_windows_units_nonneg CHECK (((reserved_units >= 0) AND (committed_units >= 0) AND (low_cost_units >= 0))),
    CONSTRAINT entitlement_counter_windows_window_ordered CHECK ((window_end > window_start))
);

ALTER TABLE ONLY public.entitlement_counter_windows FORCE ROW LEVEL SECURITY;


--
-- Name: entitlement_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entitlement_decisions (
    id uuid NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    decided_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    account_id uuid,
    service_identity_id uuid,
    operation text NOT NULL,
    usage_unit text NOT NULL,
    requested_units bigint NOT NULL,
    counter_window_id uuid,
    window_start timestamp(6) with time zone,
    window_end timestamp(6) with time zone,
    policy_version text NOT NULL,
    plan_version text NOT NULL,
    soft_limit bigint,
    hard_limit bigint,
    committed_before bigint,
    committed_after bigint,
    active_reserved_before bigint,
    active_reserved_after bigint,
    reservation_id uuid,
    cached_snapshot_id uuid,
    cached_snapshot_age bigint,
    idempotency_key_digest bytea,
    retry_of_decision_id uuid,
    decision text NOT NULL,
    reason_code text NOT NULL,
    recovery_action text NOT NULL,
    CONSTRAINT entitlement_decisions_decision_check CHECK ((decision = ANY (ARRAY['allow'::text, 'allow_with_warning'::text, 'block'::text]))),
    CONSTRAINT entitlement_decisions_idempotency_key_digest_check CHECK (((idempotency_key_digest IS NULL) OR (octet_length(idempotency_key_digest) = 32))),
    CONSTRAINT entitlement_decisions_reason_code_check CHECK ((reason_code = ANY (ARRAY['within_limit'::text, 'soft_limit_reached'::text, 'hard_limit_exceeded'::text, 'organization_inactive'::text, 'actor_inactive'::text, 'service_unauthorized'::text, 'entitlement_inactive'::text, 'policy_unavailable'::text, 'counter_unavailable'::text, 'cached_policy_snapshot_used'::text, 'cached_counter_snapshot_used'::text, 'operation_unknown'::text, 'reservation_conflict'::text]))),
    CONSTRAINT entitlement_decisions_recovery_action_check CHECK ((recovery_action = ANY (ARRAY['none'::text, 'wait_for_window'::text, 'upgrade_plan'::text, 'reactivate_organization'::text, 'reactivate_actor'::text, 'restore_policy'::text, 'restore_counter'::text, 'submit_new_attempt'::text, 'contact_support'::text]))),
    CONSTRAINT entitlement_decisions_requested_positive CHECK ((requested_units > 0)),
    CONSTRAINT entitlement_decisions_reservation_iff_allowed CHECK (((reservation_id IS NULL) OR (decision = ANY (ARRAY['allow'::text, 'allow_with_warning'::text])))),
    CONSTRAINT entitlement_decisions_subject_xor CHECK (((account_id IS NOT NULL) <> (service_identity_id IS NOT NULL)))
);

ALTER TABLE ONLY public.entitlement_decisions FORCE ROW LEVEL SECURITY;


--
-- Name: entitlement_lease_heartbeats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entitlement_lease_heartbeats (
    id uuid NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    entitlement_reservation_id uuid NOT NULL,
    heartbeat_generation bigint NOT NULL,
    prior_lease_expires_at timestamp(6) with time zone NOT NULL,
    renewed_lease_expires_at timestamp(6) with time zone NOT NULL,
    renewed_at timestamp(6) with time zone NOT NULL,
    worker_process_identity text NOT NULL,
    worker_service_identity_id uuid NOT NULL,
    status text NOT NULL,
    input_sha256 bytea,
    output_sha256 bytea,
    CONSTRAINT entitlement_lease_heartbeats_advances CHECK ((renewed_lease_expires_at > prior_lease_expires_at)),
    CONSTRAINT entitlement_lease_heartbeats_heartbeat_generation_check CHECK ((heartbeat_generation > 0)),
    CONSTRAINT entitlement_lease_heartbeats_input_sha256_check CHECK (((input_sha256 IS NULL) OR (octet_length(input_sha256) = 32))),
    CONSTRAINT entitlement_lease_heartbeats_output_sha256_check CHECK (((output_sha256 IS NULL) OR (octet_length(output_sha256) = 32))),
    CONSTRAINT entitlement_lease_heartbeats_status_check CHECK ((status = 'renewed'::text))
);

ALTER TABLE ONLY public.entitlement_lease_heartbeats FORCE ROW LEVEL SECURITY;


--
-- Name: entitlement_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entitlement_policies (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    policy_type text NOT NULL,
    semantic_version text NOT NULL,
    plan_version text NOT NULL,
    status text NOT NULL,
    content_sha256 bytea,
    effective_at timestamp(6) with time zone,
    expires_at timestamp(6) with time zone,
    CONSTRAINT entitlement_policies_content_sha256_check CHECK (((content_sha256 IS NULL) OR (octet_length(content_sha256) = 32))),
    CONSTRAINT entitlement_policies_policy_type_check CHECK ((policy_type = 'entitlement'::text)),
    CONSTRAINT entitlement_policies_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'superseded'::text, 'retired'::text])))
);

ALTER TABLE ONLY public.entitlement_policies FORCE ROW LEVEL SECURITY;


--
-- Name: entitlement_reservations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entitlement_reservations (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    decision_id uuid NOT NULL,
    counter_window_id uuid NOT NULL,
    units bigint NOT NULL,
    lease_generation bigint DEFAULT 0 NOT NULL,
    lease_due timestamp(6) with time zone NOT NULL,
    last_heartbeat_at timestamp(6) with time zone,
    started_at timestamp(6) with time zone,
    state text NOT NULL,
    terminal_at timestamp(6) with time zone,
    terminal_reason text,
    CONSTRAINT entitlement_reservations_executing_started CHECK ((((state = 'reserved'::text) AND (started_at IS NULL)) OR (state <> 'reserved'::text))),
    CONSTRAINT entitlement_reservations_state_check CHECK ((state = ANY (ARRAY['reserved'::text, 'executing'::text, 'committed'::text, 'released'::text, 'expired'::text]))),
    CONSTRAINT entitlement_reservations_terminal_shape CHECK ((((state = ANY (ARRAY['reserved'::text, 'executing'::text])) AND (terminal_at IS NULL)) OR ((state = ANY (ARRAY['committed'::text, 'released'::text, 'expired'::text])) AND (terminal_at IS NOT NULL)))),
    CONSTRAINT entitlement_reservations_units_positive CHECK ((units > 0))
);

ALTER TABLE ONLY public.entitlement_reservations FORCE ROW LEVEL SECURITY;


--
-- Name: evaluations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evaluations (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    kind text NOT NULL,
    crawl_id uuid,
    prior_evaluation_id uuid,
    retry_of_evaluation_id uuid,
    input_snapshot_id uuid,
    applicability_snapshot_id uuid,
    policy_snapshot_id uuid,
    state text NOT NULL,
    started_at timestamp(6) with time zone,
    completed_at timestamp(6) with time zone,
    failed_at timestamp(6) with time zone,
    superseded_at timestamp(6) with time zone,
    deadline_at timestamp(6) with time zone,
    reason text,
    orchestration_slot_active boolean DEFAULT false NOT NULL,
    CONSTRAINT evaluations_initial_requires_crawl CHECK (((kind <> 'initial'::text) OR (crawl_id IS NOT NULL))),
    CONSTRAINT evaluations_kind_check CHECK ((kind = ANY (ARRAY['initial'::text, 'reassessment'::text, 'retry'::text]))),
    CONSTRAINT evaluations_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'running'::text, 'completed'::text, 'failed'::text, 'superseded'::text])))
);

ALTER TABLE ONLY public.evaluations FORCE ROW LEVEL SECURITY;


--
-- Name: event_registry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_registry (
    id uuid NOT NULL,
    schema_version text NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    event_type text NOT NULL,
    event_schema_version text NOT NULL,
    workflow_id text NOT NULL,
    event_profile text NOT NULL,
    occurred_at timestamp(6) with time zone NOT NULL,
    organization_id uuid NOT NULL,
    project_id uuid,
    aggregate_type text NOT NULL,
    aggregate_id uuid NOT NULL,
    aggregate_version bigint NOT NULL,
    partition_month date NOT NULL,
    correlation_id uuid NOT NULL,
    causation_id uuid NOT NULL,
    command_id uuid,
    idempotency_key_digest bytea,
    audit_record_id uuid NOT NULL,
    event_bytes bytea NOT NULL,
    event_byte_count bigint NOT NULL,
    event_sha256 bytea NOT NULL,
    CONSTRAINT event_registry_check CHECK ((event_byte_count = octet_length(event_bytes))),
    CONSTRAINT event_registry_check1 CHECK (((octet_length(event_sha256) = 32) AND (event_sha256 = public.digest(event_bytes, 'sha256'::text)))),
    CONSTRAINT event_registry_event_bytes_check CHECK (((octet_length(event_bytes) >= 2) AND (octet_length(event_bytes) <= 1048576))),
    CONSTRAINT event_registry_event_profile_check CHECK ((event_profile = ANY (ARRAY['created'::text, 'state_transition'::text, 'attempt'::text, 'decision'::text, 'policy_activation'::text, 'projection'::text, 'failure'::text, 'recovery'::text]))),
    CONSTRAINT event_registry_idempotency_key_digest_check CHECK (((idempotency_key_digest IS NULL) OR (octet_length(idempotency_key_digest) = 32))),
    CONSTRAINT event_registry_workflow_id_check CHECK ((workflow_id ~ '^WF-[0-9]{3}$'::text)),
    CONSTRAINT partition_month_is_first_of_month CHECK ((partition_month = (date_trunc('month'::text, (occurred_at AT TIME ZONE 'UTC'::text)))::date))
);

ALTER TABLE ONLY public.event_registry FORCE ROW LEVEL SECURITY;


--
-- Name: evidence; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evidence (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp(6) with time zone DEFAULT now() NOT NULL,
    schema_version text NOT NULL,
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    source_id uuid,
    evaluation_id uuid,
    evidence_type text NOT NULL,
    producer_id text NOT NULL,
    attempt_id text NOT NULL,
    payload_reference text NOT NULL,
    content_sha256 text NOT NULL,
    captured_at_utc timestamp(6) with time zone NOT NULL,
    observed_at_utc timestamp(6) with time zone NOT NULL,
    source_system text NOT NULL,
    collection_method text NOT NULL,
    collector_version text NOT NULL,
    validation_status text NOT NULL,
    validation_reason_code text,
    data_classification text NOT NULL,
    payload_retention_class text NOT NULL,
    correlation_id uuid NOT NULL,
    CONSTRAINT evidence_content_sha256_check CHECK ((content_sha256 ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT evidence_data_classification_check CHECK ((data_classification = ANY (ARRAY['public'::text, 'internal'::text, 'confidential'::text, 'restricted'::text]))),
    CONSTRAINT evidence_evidence_type_check CHECK ((evidence_type = ANY (ARRAY['source_document'::text, 'crawl_observation'::text, 'parsed_content'::text, 'external_measurement'::text, 'verification_observation'::text]))),
    CONSTRAINT evidence_payload_retention_class_check CHECK ((payload_retention_class = 'product_evidence_payload'::text)),
    CONSTRAINT evidence_validation_reason_consistency CHECK ((((validation_status = 'valid'::text) AND (validation_reason_code IS NULL)) OR ((validation_status <> 'valid'::text) AND (validation_reason_code IS NOT NULL)))),
    CONSTRAINT evidence_validation_status_check CHECK ((validation_status = ANY (ARRAY['valid'::text, 'invalid'::text, 'quarantined'::text])))
);

ALTER TABLE ONLY public.evidence FORCE ROW LEVEL SECURITY;


--
-- Name: f1_context_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.f1_context_keys (
    key_name text NOT NULL,
    key_bytes bytea NOT NULL,
    CONSTRAINT f1_context_keys_key_bytes_check CHECK ((octet_length(key_bytes) = 32))
);


--
-- Name: f1_encrypted_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.f1_encrypted_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    application text NOT NULL,
    record_type text NOT NULL,
    record_id text NOT NULL,
    purpose text NOT NULL,
    tenant text,
    aad_schema_version text NOT NULL,
    key_provider text NOT NULL,
    wrapping_key_version text NOT NULL,
    envelope bytea,
    content_digest bytea NOT NULL,
    state text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    destroyed_at timestamp with time zone,
    CONSTRAINT f1_encrypted_record_active_has_envelope CHECK (((state <> 'active'::text) OR (envelope IS NOT NULL))),
    CONSTRAINT f1_encrypted_record_destroyed_no_envelope CHECK (((state <> 'destroyed'::text) OR (envelope IS NULL))),
    CONSTRAINT f1_encrypted_record_digest_len CHECK ((octet_length(content_digest) = 32)),
    CONSTRAINT f1_encrypted_record_state_valid CHECK ((state = ANY (ARRAY['active'::text, 'destroyed'::text])))
);


--
-- Name: f1_encryption_key_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.f1_encryption_key_versions (
    provider text NOT NULL,
    version text NOT NULL,
    state text NOT NULL,
    key_fingerprint bytea,
    key_reference text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    activated_at timestamp with time zone,
    retired_at timestamp with time zone,
    destroyed_at timestamp with time zone,
    CONSTRAINT f1_encryption_key_active_has_fingerprint CHECK (((state <> 'active'::text) OR (key_fingerprint IS NOT NULL))),
    CONSTRAINT f1_encryption_key_destroyed_no_fingerprint CHECK (((state <> 'destroyed'::text) OR (key_fingerprint IS NULL))),
    CONSTRAINT f1_encryption_key_fingerprint_len CHECK (((key_fingerprint IS NULL) OR (octet_length(key_fingerprint) = 32))),
    CONSTRAINT f1_encryption_key_state_valid CHECK ((state = ANY (ARRAY['active'::text, 'retired'::text, 'destroyed'::text])))
);


--
-- Name: idempotency_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.idempotency_records (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    scope_kind text NOT NULL,
    organization_id uuid,
    bootstrap_principal_digest bytea,
    command_type text NOT NULL,
    target_type text NOT NULL,
    target_id uuid,
    key_digest bytea NOT NULL,
    request_sha256 bytea NOT NULL,
    command_execution_id uuid NOT NULL,
    command_result_id uuid,
    retain_until timestamp(6) with time zone NOT NULL,
    CONSTRAINT idempotency_records_bootstrap_principal_digest_check CHECK (((bootstrap_principal_digest IS NULL) OR (octet_length(bootstrap_principal_digest) = 32))),
    CONSTRAINT idempotency_records_key_digest_check CHECK ((octet_length(key_digest) = 32)),
    CONSTRAINT idempotency_records_request_sha256_check CHECK ((octet_length(request_sha256) = 32)),
    CONSTRAINT idempotency_records_scope_kind_check CHECK ((scope_kind = ANY (ARRAY['organization'::text, 'bootstrap_principal'::text]))),
    CONSTRAINT idempotency_scope_shape CHECK ((((scope_kind = 'bootstrap_principal'::text) AND (bootstrap_principal_digest IS NOT NULL) AND (organization_id IS NULL)) OR ((scope_kind = 'organization'::text) AND (organization_id IS NOT NULL) AND (bootstrap_principal_digest IS NULL))))
);

ALTER TABLE ONLY public.idempotency_records FORCE ROW LEVEL SECURITY;


--
-- Name: identity_receipt_consumptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.identity_receipt_consumptions (
    id uuid NOT NULL,
    schema_version text NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    receipt_id uuid NOT NULL,
    receipt_digest bytea NOT NULL,
    command_execution_id uuid NOT NULL,
    consumed_at timestamp(6) with time zone NOT NULL,
    outcome text NOT NULL,
    reason_code text,
    CONSTRAINT identity_receipt_consumptions_outcome_check CHECK ((outcome = ANY (ARRAY['consumed'::text, 'rejected'::text]))),
    CONSTRAINT identity_receipt_consumptions_receipt_digest_check CHECK ((octet_length(receipt_digest) = 32)),
    CONSTRAINT reason_null_only_when_consumed CHECK ((((outcome = 'consumed'::text) AND (reason_code IS NULL)) OR ((outcome = 'rejected'::text) AND (reason_code IS NOT NULL))))
);


--
-- Name: identity_receipt_nonces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.identity_receipt_nonces (
    id uuid NOT NULL,
    schema_version text NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    receipt_digest bytea NOT NULL,
    receipt_schema_version text NOT NULL,
    issuer_key text NOT NULL,
    issuer_subject text NOT NULL,
    normalized_email text NOT NULL,
    normalized_email_sha256 bytea NOT NULL,
    display_name text NOT NULL,
    email_verified boolean NOT NULL,
    purpose text NOT NULL,
    validated_at timestamp(6) with time zone NOT NULL,
    expires_at timestamp(6) with time zone NOT NULL,
    nonce_sha256 bytea NOT NULL,
    identity_principal_digest bytea NOT NULL,
    bootstrap_principal_digest bytea,
    assurance_version text,
    mfa_satisfied boolean,
    retention_class text NOT NULL,
    CONSTRAINT assurance_only_for_signin_family CHECK ((((purpose = ANY (ARRAY['existing_account_sign_in'::text, 'organization_reactivation'::text])) AND (assurance_version IS NOT NULL) AND (mfa_satisfied IS NOT NULL)) OR ((purpose <> ALL (ARRAY['existing_account_sign_in'::text, 'organization_reactivation'::text])) AND (assurance_version IS NULL) AND (mfa_satisfied IS NULL)))),
    CONSTRAINT bootstrap_digest_only_for_bootstrap_purposes CHECK ((((purpose = ANY (ARRAY['bootstrap_grant_request'::text, 'self_service_bootstrap'::text])) AND (bootstrap_principal_digest = identity_principal_digest)) OR ((purpose <> ALL (ARRAY['bootstrap_grant_request'::text, 'self_service_bootstrap'::text])) AND (bootstrap_principal_digest IS NULL)))),
    CONSTRAINT identity_receipt_nonces_bootstrap_principal_digest_check CHECK (((bootstrap_principal_digest IS NULL) OR (octet_length(bootstrap_principal_digest) = 32))),
    CONSTRAINT identity_receipt_nonces_email_verified_check CHECK (email_verified),
    CONSTRAINT identity_receipt_nonces_identity_principal_digest_check CHECK ((octet_length(identity_principal_digest) = 32)),
    CONSTRAINT identity_receipt_nonces_nonce_sha256_check CHECK ((octet_length(nonce_sha256) = 32)),
    CONSTRAINT identity_receipt_nonces_normalized_email_sha256_check CHECK ((octet_length(normalized_email_sha256) = 32)),
    CONSTRAINT identity_receipt_nonces_purpose_check CHECK ((purpose = ANY (ARRAY['bootstrap_grant_request'::text, 'self_service_bootstrap'::text, 'invitation_response'::text, 'existing_account_sign_in'::text, 'organization_reactivation'::text]))),
    CONSTRAINT identity_receipt_nonces_receipt_digest_check CHECK ((octet_length(receipt_digest) = 32)),
    CONSTRAINT identity_receipt_nonces_retention_class_check CHECK ((retention_class = 'security_audit'::text)),
    CONSTRAINT receipt_expiry_is_ten_minutes CHECK ((expires_at = (validated_at + '00:10:00'::interval)))
);


--
-- Name: invitation_reference_registry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitation_reference_registry (
    opaque_reference_sha256 bytea NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    organization_id uuid NOT NULL,
    invitation_id uuid NOT NULL,
    invitation_state text NOT NULL,
    activated_at timestamp(6) with time zone,
    expires_at timestamp(6) with time zone,
    terminal_at timestamp(6) with time zone,
    locator_sha256 bytea,
    retention_class text NOT NULL,
    CONSTRAINT invitation_reference_registry_invitation_state_check CHECK ((invitation_state = ANY (ARRAY['pending_approval'::text, 'active'::text, 'accepted'::text, 'declined'::text, 'rejected'::text, 'revoked'::text, 'expired'::text]))),
    CONSTRAINT invitation_reference_registry_locator_sha256_check CHECK (((locator_sha256 IS NULL) OR (octet_length(locator_sha256) = 32))),
    CONSTRAINT invitation_reference_registry_opaque_reference_sha256_check CHECK ((octet_length(opaque_reference_sha256) = 32)),
    CONSTRAINT invitation_reference_registry_retention_class_check CHECK ((retention_class = 'identity_commercial'::text))
);


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    opaque_reference_sha256 bytea NOT NULL,
    target_email text NOT NULL,
    target_email_sha256 bytea NOT NULL,
    target_identity_issuer_key text,
    target_identity_subject text,
    canonical_role text NOT NULL,
    permission_mode text NOT NULL,
    persona text,
    scope_sha256 bytea,
    protected_permission_preview jsonb,
    activated_at timestamp(6) with time zone,
    expires_at timestamp(6) with time zone,
    accepted_at timestamp(6) with time zone,
    declined_at timestamp(6) with time zone,
    terminated_at timestamp(6) with time zone,
    fulfilled_by_role_assignment_id uuid,
    state text NOT NULL,
    reason text,
    requester_account_id uuid,
    transition_reason_code text,
    requested_at timestamp(6) with time zone,
    approval_due_at timestamp(6) with time zone,
    security_approver_account_id uuid,
    intended_assignment_expires_at timestamp(6) with time zone,
    open_uniqueness_sha256 bytea,
    creation_idempotency_key_digest bytea,
    request_policy_version text,
    approval_policy_version text,
    CONSTRAINT invitation_active_expiry_is_seven_days CHECK (((activated_at IS NULL) OR (expires_at = (activated_at + '7 days'::interval)))),
    CONSTRAINT invitation_approval_due_is_24_hours CHECK (((approval_due_at IS NULL) OR (requested_at IS NULL) OR (approval_due_at = (requested_at + '24:00:00'::interval)))),
    CONSTRAINT invitation_approver_only_after_decision CHECK (((security_approver_account_id IS NULL) OR (state <> 'pending_approval'::text))),
    CONSTRAINT invitation_bound_identity_pairwise CHECK (((target_identity_issuer_key IS NULL) = (target_identity_subject IS NULL))),
    CONSTRAINT invitation_pending_approval_has_due_instant CHECK (((state <> 'pending_approval'::text) OR (approval_due_at IS NOT NULL))),
    CONSTRAINT invitations_creation_idempotency_key_digest_check CHECK (((creation_idempotency_key_digest IS NULL) OR (octet_length(creation_idempotency_key_digest) = 32))),
    CONSTRAINT invitations_opaque_reference_sha256_check CHECK ((octet_length(opaque_reference_sha256) = 32)),
    CONSTRAINT invitations_open_uniqueness_sha256_check CHECK (((open_uniqueness_sha256 IS NULL) OR (octet_length(open_uniqueness_sha256) = 32))),
    CONSTRAINT invitations_permission_mode_check CHECK ((permission_mode = ANY (ARRAY['standard'::text, 'read_only'::text]))),
    CONSTRAINT invitations_scope_sha256_check CHECK (((scope_sha256 IS NULL) OR (octet_length(scope_sha256) = 32))),
    CONSTRAINT invitations_state_check CHECK ((state = ANY (ARRAY['pending_approval'::text, 'active'::text, 'accepted'::text, 'declined'::text, 'rejected'::text, 'revoked'::text, 'expired'::text]))),
    CONSTRAINT invitations_target_email_sha256_check CHECK ((octet_length(target_email_sha256) = 32)),
    CONSTRAINT invitations_transition_reason_code_check CHECK (((transition_reason_code IS NULL) OR (transition_reason_code ~ '^[a-z][a-z0-9_]{0,119}$'::text)))
);

ALTER TABLE ONLY public.invitations FORCE ROW LEVEL SECURITY;


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    status text NOT NULL,
    authorization_epoch bigint DEFAULT 0 NOT NULL,
    display_name text NOT NULL,
    profile jsonb,
    activated_at timestamp(6) with time zone,
    suspended_at timestamp(6) with time zone,
    closed_at timestamp(6) with time zone,
    reactivated_at timestamp(6) with time zone,
    lifecycle_reason text,
    creator_account_id uuid,
    default_locale text,
    reporting_time_zone text,
    profile_schema_version text,
    current_access_policy_id uuid,
    current_entitlement_policy_id uuid,
    current_plan_assignment_id uuid,
    current_billing_entity_id uuid,
    CONSTRAINT organization_suspended_has_time CHECK (((status <> 'suspended'::text) OR (suspended_at IS NOT NULL))),
    CONSTRAINT organizations_authorization_epoch_check CHECK ((authorization_epoch >= 0)),
    CONSTRAINT organizations_lifecycle_reason_check CHECK (((lifecycle_reason IS NULL) OR ((char_length(lifecycle_reason) >= 1) AND (char_length(lifecycle_reason) <= 2000)))),
    CONSTRAINT organizations_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'suspended'::text, 'closed'::text])))
);

ALTER TABLE ONLY public.organizations FORCE ROW LEVEL SECURITY;


--
-- Name: plan_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_assignments (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    billing_entity_id uuid NOT NULL,
    plan_version text NOT NULL,
    approval_version text NOT NULL,
    policy_version text NOT NULL,
    content_sha256 bytea NOT NULL,
    assigned_by_service_identity_id uuid,
    effective_at timestamp(6) with time zone NOT NULL,
    ended_at timestamp(6) with time zone,
    superseded_at timestamp(6) with time zone,
    revoked_at timestamp(6) with time zone,
    revoked_reason text,
    state text NOT NULL,
    CONSTRAINT plan_assignments_content_sha256_check CHECK ((octet_length(content_sha256) = 32)),
    CONSTRAINT plan_assignments_state_check CHECK ((state = ANY (ARRAY['active'::text, 'superseded'::text, 'revoked'::text])))
);

ALTER TABLE ONLY public.plan_assignments FORCE ROW LEVEL SECURITY;


--
-- Name: pretenant_authorization_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pretenant_authorization_decisions (
    id uuid NOT NULL,
    schema_version text NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    causation_id uuid NOT NULL,
    command_id uuid NOT NULL,
    idempotency_key_digest bytea,
    content_sha256 bytea,
    bootstrap_principal_digest bytea NOT NULL,
    receipt_id uuid NOT NULL,
    subject_service_identity_id uuid NOT NULL,
    action text NOT NULL,
    resource_type text NOT NULL,
    resource_id uuid,
    decision text NOT NULL,
    reason_code text NOT NULL,
    policy_versions jsonb NOT NULL,
    policy_hash bytea,
    decided_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT pretenant_authorization_decisi_bootstrap_principal_digest_check CHECK ((octet_length(bootstrap_principal_digest) = 32)),
    CONSTRAINT pretenant_authorization_decisions_content_sha256_check CHECK (((content_sha256 IS NULL) OR (octet_length(content_sha256) = 32))),
    CONSTRAINT pretenant_authorization_decisions_decision_check CHECK ((decision = ANY (ARRAY['allow'::text, 'deny'::text]))),
    CONSTRAINT pretenant_authorization_decisions_idempotency_key_digest_check CHECK (((idempotency_key_digest IS NULL) OR (octet_length(idempotency_key_digest) = 32))),
    CONSTRAINT pretenant_authorization_decisions_policy_hash_check CHECK (((policy_hash IS NULL) OR (octet_length(policy_hash) = 32)))
);

ALTER TABLE ONLY public.pretenant_authorization_decisions FORCE ROW LEVEL SECURITY;


--
-- Name: projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.projects (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    display_name text NOT NULL,
    locale text NOT NULL,
    time_zone text NOT NULL,
    objective text,
    state text NOT NULL,
    source_set_version bigint DEFAULT 0 NOT NULL,
    activated_at timestamp(6) with time zone,
    paused_at timestamp(6) with time zone,
    archived_at timestamp(6) with time zone,
    lifecycle_reason text,
    project_profile_schema_version text,
    local_presence_applicable boolean,
    local_presence_reason text,
    local_business_profile jsonb,
    local_business_profile_content_sha256 bytea,
    profile_attesting_account_id uuid,
    profile_committed_at timestamp(6) with time zone,
    CONSTRAINT projects_local_business_profile_content_sha256_check CHECK (((local_business_profile_content_sha256 IS NULL) OR (octet_length(local_business_profile_content_sha256) = 32))),
    CONSTRAINT projects_local_presence_reason_check CHECK (((local_presence_reason IS NULL) OR ((char_length(local_presence_reason) >= 20) AND (char_length(local_presence_reason) <= 500)))),
    CONSTRAINT projects_local_profile_shape CHECK ((((local_presence_applicable IS NULL) AND (local_presence_reason IS NULL) AND (local_business_profile IS NULL) AND (local_business_profile_content_sha256 IS NULL) AND (project_profile_schema_version IS NULL) AND (profile_attesting_account_id IS NULL) AND (profile_committed_at IS NULL)) OR ((local_presence_applicable = true) AND (project_profile_schema_version IS NOT NULL) AND (profile_attesting_account_id IS NOT NULL) AND (profile_committed_at IS NOT NULL) AND (local_presence_reason IS NULL) AND (local_business_profile IS NOT NULL) AND (local_business_profile_content_sha256 IS NOT NULL)) OR ((local_presence_applicable = false) AND (project_profile_schema_version IS NOT NULL) AND (profile_attesting_account_id IS NOT NULL) AND (profile_committed_at IS NOT NULL) AND (local_presence_reason IS NOT NULL) AND (local_business_profile IS NULL) AND (local_business_profile_content_sha256 IS NULL)))),
    CONSTRAINT projects_project_profile_schema_version_check CHECK (((project_profile_schema_version IS NULL) OR (project_profile_schema_version = 'project-profile-v1'::text))),
    CONSTRAINT projects_state_check CHECK ((state = ANY (ARRAY['draft'::text, 'active'::text, 'paused'::text, 'archived'::text])))
);

ALTER TABLE ONLY public.projects FORCE ROW LEVEL SECURITY;


--
-- Name: role_assignment_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_assignment_approvals (
    id uuid NOT NULL,
    schema_version text NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    organization_id uuid NOT NULL,
    role_assignment_id uuid NOT NULL,
    sequence_number integer NOT NULL,
    approver_account_id uuid,
    approver_platform_id uuid,
    authority text NOT NULL,
    decision text NOT NULL,
    reason text,
    decided_at timestamp(6) with time zone NOT NULL,
    policy_version text NOT NULL,
    separation_result text NOT NULL,
    correlation_id uuid NOT NULL,
    CONSTRAINT approval_has_exactly_one_approver CHECK (((approver_account_id IS NULL) <> (approver_platform_id IS NULL))),
    CONSTRAINT role_assignment_approvals_decision_check CHECK ((decision = ANY (ARRAY['approve'::text, 'reject'::text]))),
    CONSTRAINT role_assignment_approvals_separation_result_check CHECK ((separation_result = ANY (ARRAY['distinct'::text, 'same_principal'::text]))),
    CONSTRAINT role_assignment_approvals_sequence_number_check CHECK ((sequence_number >= 1))
);

ALTER TABLE ONLY public.role_assignment_approvals FORCE ROW LEVEL SECURITY;


--
-- Name: role_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_assignments (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    account_id uuid NOT NULL,
    canonical_role text NOT NULL,
    permission_mode text NOT NULL,
    persona text,
    status text NOT NULL,
    effective_at timestamp(6) with time zone,
    expires_at timestamp(6) with time zone,
    scope_sha256 bytea,
    protected_permission_allowlist jsonb DEFAULT '[]'::jsonb NOT NULL,
    requester_account_id uuid,
    requested_at timestamp(6) with time zone,
    approval_due_at timestamp(6) with time zone,
    terminated_at timestamp(6) with time zone,
    reason text,
    transition_reason_code text,
    decision_authorization_epoch bigint,
    idempotency_key_digest bytea,
    fulfilled_invitation_id uuid,
    bootstrap_admin_exception boolean DEFAULT false NOT NULL,
    CONSTRAINT role_assignment_active_is_effective CHECK (((status <> 'active'::text) OR (effective_at IS NOT NULL))),
    CONSTRAINT role_assignment_approval_due_is_24_hours CHECK (((approval_due_at IS NULL) OR (requested_at IS NULL) OR (approval_due_at = (requested_at + '24:00:00'::interval)))),
    CONSTRAINT role_assignment_bootstrap_exception_is_admin CHECK (((bootstrap_admin_exception = false) OR (canonical_role = 'OrganizationAdmin'::text))),
    CONSTRAINT role_assignment_pending_has_no_allowlist CHECK (((status <> 'pending'::text) OR (jsonb_array_length(protected_permission_allowlist) = 0))),
    CONSTRAINT role_assignment_pending_is_not_effective CHECK (((status <> 'pending'::text) OR (effective_at IS NULL))),
    CONSTRAINT role_assignment_protected_expiry_within_30_days CHECK (((jsonb_array_length(protected_permission_allowlist) = 0) OR (effective_at IS NULL) OR (expires_at IS NULL) OR (expires_at <= (effective_at + '30 days'::interval)))),
    CONSTRAINT role_assignments_idempotency_key_digest_check CHECK (((idempotency_key_digest IS NULL) OR (octet_length(idempotency_key_digest) = 32))),
    CONSTRAINT role_assignments_permission_mode_check CHECK ((permission_mode = ANY (ARRAY['standard'::text, 'read_only'::text]))),
    CONSTRAINT role_assignments_protected_permission_allowlist_check CHECK ((jsonb_typeof(protected_permission_allowlist) = 'array'::text)),
    CONSTRAINT role_assignments_reason_check CHECK (((reason IS NULL) OR ((char_length(reason) >= 1) AND (char_length(reason) <= 2000)))),
    CONSTRAINT role_assignments_scope_sha256_check CHECK (((scope_sha256 IS NULL) OR (octet_length(scope_sha256) = 32))),
    CONSTRAINT role_assignments_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'rejected'::text, 'revoked'::text, 'expired'::text]))),
    CONSTRAINT role_assignments_transition_reason_code_check CHECK (((transition_reason_code IS NULL) OR (transition_reason_code ~ '^[a-z][a-z0-9_]{0,119}$'::text)))
);

ALTER TABLE ONLY public.role_assignments FORCE ROW LEVEL SECURITY;


--
-- Name: role_expiry_block_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_expiry_block_decisions (
    id uuid NOT NULL,
    schema_version text NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    organization_id uuid NOT NULL,
    role_assignment_id uuid NOT NULL,
    assignment_expires_at timestamp(6) with time zone NOT NULL,
    authorization_epoch bigint NOT NULL,
    block_reason text NOT NULL,
    predicate_result jsonb NOT NULL,
    decided_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    retention_class text NOT NULL,
    CONSTRAINT role_expiry_block_decisions_block_reason_check CHECK ((block_reason = 'expiry_blocked_last_admin'::text)),
    CONSTRAINT role_expiry_block_decisions_retention_class_check CHECK ((retention_class = 'security_audit'::text))
);

ALTER TABLE ONLY public.role_expiry_block_decisions FORCE ROW LEVEL SECURITY;


--
-- Name: scheduled_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scheduled_actions (
    id uuid NOT NULL,
    schema_version text NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    causation_id uuid NOT NULL,
    command_id uuid,
    claim_owner uuid,
    claim_generation bigint DEFAULT 0 NOT NULL,
    claimed_at timestamp(6) with time zone,
    lease_expires_at timestamp(6) with time zone,
    last_heartbeat_at timestamp(6) with time zone,
    claim_phase text,
    organization_id uuid,
    project_id uuid,
    executing_service_identity_id uuid NOT NULL,
    action_kind text NOT NULL,
    action_schema_version text NOT NULL,
    target_type text NOT NULL,
    target_id uuid NOT NULL,
    product_generation bigint DEFAULT 0 NOT NULL,
    schedule_generation bigint DEFAULT 1 NOT NULL,
    due_at timestamp(6) with time zone NOT NULL,
    not_before_at timestamp(6) with time zone,
    identity_preimage bytea NOT NULL,
    identity_sha256 bytea NOT NULL,
    collision_ordinal integer DEFAULT 0 NOT NULL,
    payload_refs jsonb DEFAULT '{}'::jsonb NOT NULL,
    status text NOT NULL,
    dispatched_at timestamp(6) with time zone,
    completed_at timestamp(6) with time zone,
    canceled_at timestamp(6) with time zone,
    quarantined_at timestamp(6) with time zone,
    reason text,
    dispatch_attempt_count bigint DEFAULT 0 NOT NULL,
    next_dispatch_at timestamp(6) with time zone,
    CONSTRAINT scheduled_action_canceled_has_time CHECK (((status = 'canceled'::text) = (canceled_at IS NOT NULL))),
    CONSTRAINT scheduled_action_claim_fields_match_status CHECK (((status = ANY (ARRAY['claimed'::text, 'dispatched'::text])) = ((claim_owner IS NOT NULL) AND (claimed_at IS NOT NULL) AND (lease_expires_at IS NOT NULL) AND (claim_phase IS NOT NULL) AND (claim_generation > 0)))),
    CONSTRAINT scheduled_action_completed_has_time CHECK (((status = 'completed'::text) = (completed_at IS NOT NULL))),
    CONSTRAINT scheduled_action_dispatch_time_required CHECK (((status <> ALL (ARRAY['dispatched'::text, 'completed'::text])) OR (dispatched_at IS NOT NULL))),
    CONSTRAINT scheduled_action_heartbeat_requires_claim CHECK (((last_heartbeat_at IS NULL) OR (claim_owner IS NOT NULL))),
    CONSTRAINT scheduled_action_quarantined_has_time_and_reason CHECK (((status = 'quarantined'::text) = ((quarantined_at IS NOT NULL) AND (reason IS NOT NULL)))),
    CONSTRAINT scheduled_actions_action_kind_check CHECK ((action_kind = ANY (ARRAY['bootstrap_grant_expire'::text, 'session_expire'::text, 'invitation_expire'::text, 'role_assignment_expire'::text, 'source_scope_request_expire'::text, 'verification_observation_slot'::text, 'verification_request_expire'::text, 'verification_material_destroy'::text, 'crawl_dispatch'::text, 'crawl_fetch_due'::text, 'crawl_terminal_deadline'::text, 'ingestion_attempt_due'::text, 'parsing_attempt_due'::text, 'indexing_attempt_due'::text, 'check_attempt_due'::text, 'evaluation_stage_advance'::text, 'evaluation_deadline'::text, 'score_recalculation_due'::text, 'adjudication_due'::text, 'ai_generation_deadline'::text, 'ai_validation_deadline'::text, 'ai_publication_expire'::text, 'reassessment_slot'::text, 'notification_delivery_attempt_due'::text, 'notification_reconciliation_due'::text, 'notification_escalation_due'::text, 'credential_initialization_retry'::text, 'credential_expire'::text, 'entitlement_lease_expire'::text, 'export_generate'::text, 'export_expire'::text, 'export_policy_reevaluate'::text, 'closure_request_expire'::text, 'organization_closure_execute'::text, 'support_session_expire'::text, 'incident_restoration_observe'::text, 'investigation_input_collect'::text, 'provider_event_consume'::text, 'projection_repair_due'::text, 'transport_lease_sweep_due'::text, 'running_work_sweep_due'::text, 'entitlement_invariant_sweep_due'::text, 'staged_object_invariant_sweep_due'::text, 'export_invariant_sweep_due'::text, 'mailgun_uncertainty_sweep_due'::text, 'deletion_tombstone_invariant_sweep_due'::text, 'evidence_retention_warning'::text, 'lifecycle_deletion_start'::text, 'lifecycle_deletion_attempt_due'::text, 'lifecycle_deletion_deadline'::text, 'backup_tombstone_verify'::text, 'restore_drill_due'::text, 'partition_maintenance_due'::text]))),
    CONSTRAINT scheduled_actions_claim_generation_check CHECK ((claim_generation >= 0)),
    CONSTRAINT scheduled_actions_claim_phase_check CHECK ((claim_phase = ANY (ARRAY['scheduler'::text, 'worker'::text]))),
    CONSTRAINT scheduled_actions_collision_ordinal_check CHECK ((collision_ordinal >= 0)),
    CONSTRAINT scheduled_actions_dispatch_attempt_count_check CHECK ((dispatch_attempt_count >= 0)),
    CONSTRAINT scheduled_actions_identity_preimage_check CHECK ((octet_length(identity_preimage) > 0)),
    CONSTRAINT scheduled_actions_identity_sha256_check CHECK ((octet_length(identity_sha256) = 32)),
    CONSTRAINT scheduled_actions_product_generation_check CHECK ((product_generation >= 0)),
    CONSTRAINT scheduled_actions_reason_check CHECK (((reason IS NULL) OR (reason ~ '^[a-z][a-z0-9_]{0,119}$'::text))),
    CONSTRAINT scheduled_actions_schedule_generation_check CHECK ((schedule_generation >= 1)),
    CONSTRAINT scheduled_actions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'claimed'::text, 'dispatched'::text, 'canceled'::text, 'completed'::text, 'quarantined'::text])))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: service_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_identities (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    organization_id uuid,
    project_id uuid,
    subject text NOT NULL,
    display_name text NOT NULL,
    status text NOT NULL,
    key_id text NOT NULL,
    permission_scope jsonb NOT NULL,
    activated_at timestamp(6) with time zone,
    revoked_at timestamp(6) with time zone,
    CONSTRAINT service_identities_status_check CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'revoked'::text]))),
    CONSTRAINT service_identity_status_times CHECK (((status = 'active'::text) = ((activated_at IS NOT NULL) AND (revoked_at IS NULL))))
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    account_id uuid NOT NULL,
    identity_receipt_digest bytea NOT NULL,
    authorization_context_version bigint NOT NULL,
    creation_reason text NOT NULL,
    issued_at timestamp(6) with time zone NOT NULL,
    last_activity_at timestamp(6) with time zone NOT NULL,
    idle_expires_at timestamp(6) with time zone NOT NULL,
    absolute_expires_at timestamp(6) with time zone NOT NULL,
    status text NOT NULL,
    revoke_reason text,
    expiry_reason text,
    terminated_at timestamp(6) with time zone,
    CONSTRAINT session_absolute_is_twelve_hours CHECK ((absolute_expires_at = (issued_at + '12:00:00'::interval))),
    CONSTRAINT session_idle_is_thirty_minutes CHECK ((idle_expires_at = (last_activity_at + '00:30:00'::interval))),
    CONSTRAINT sessions_identity_receipt_digest_check CHECK ((octet_length(identity_receipt_digest) = 32)),
    CONSTRAINT sessions_status_check CHECK ((status = ANY (ARRAY['active'::text, 'revoked'::text, 'expired'::text])))
);


--
-- Name: source_scope_change_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.source_scope_change_requests (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    schema_version text NOT NULL,
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    source_id uuid NOT NULL,
    requester_account_id uuid NOT NULL,
    expected_active_policy_version text NOT NULL,
    current_content_sha256 bytea NOT NULL,
    proposed_canonical_host text NOT NULL,
    proposed_allowed_schemes text[] NOT NULL,
    proposed_allowed_ports integer[] NOT NULL,
    proposed_include_prefixes text[] NOT NULL,
    proposed_exclude_prefixes text[] DEFAULT '{}'::text[] NOT NULL,
    proposed_query_handling text NOT NULL,
    proposed_content_sha256 bytea NOT NULL,
    request_reason text NOT NULL,
    requested_at_utc timestamp(6) with time zone NOT NULL,
    due_at_utc timestamp(6) with time zone NOT NULL,
    state text DEFAULT 'pending'::text NOT NULL,
    decision_actor_id uuid,
    decided_at_utc timestamp(6) with time zone,
    decision_reason text,
    activated_policy_version text,
    terminal_at_utc timestamp(6) with time zone,
    idempotency_key_digest bytea NOT NULL,
    CONSTRAINT source_scope_change_requests_current_content_sha256_check CHECK ((octet_length(current_content_sha256) = 32)),
    CONSTRAINT source_scope_change_requests_idempotency_key_digest_check CHECK ((octet_length(idempotency_key_digest) = 32)),
    CONSTRAINT source_scope_change_requests_proposed_allowed_ports_check CHECK ((cardinality(proposed_allowed_ports) >= 1)),
    CONSTRAINT source_scope_change_requests_proposed_allowed_schemes_check CHECK ((cardinality(proposed_allowed_schemes) >= 1)),
    CONSTRAINT source_scope_change_requests_proposed_content_sha256_check CHECK ((octet_length(proposed_content_sha256) = 32)),
    CONSTRAINT source_scope_change_requests_proposed_include_prefixes_check CHECK ((cardinality(proposed_include_prefixes) >= 1)),
    CONSTRAINT source_scope_change_requests_request_reason_check CHECK (((char_length(request_reason) >= 20) AND (char_length(request_reason) <= 2000))),
    CONSTRAINT source_scope_change_requests_schema_version_check CHECK ((schema_version = 'source-scope-change-request-v1'::text)),
    CONSTRAINT source_scope_change_requests_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'canceled'::text, 'expired'::text])))
);

ALTER TABLE ONLY public.source_scope_change_requests FORCE ROW LEVEL SECURITY;


--
-- Name: source_scope_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.source_scope_policies (
    id uuid NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    schema_version text NOT NULL,
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    source_id uuid,
    policy_version text NOT NULL,
    scope text NOT NULL,
    canonical_host text NOT NULL,
    allowed_schemes text[] NOT NULL,
    allowed_ports integer[] NOT NULL,
    include_prefixes text[] NOT NULL,
    exclude_prefixes text[] DEFAULT '{}'::text[] NOT NULL,
    query_handling text NOT NULL,
    content_sha256 bytea NOT NULL,
    CONSTRAINT source_scope_policies_allowed_ports_check CHECK ((cardinality(allowed_ports) >= 1)),
    CONSTRAINT source_scope_policies_allowed_schemes_check CHECK ((cardinality(allowed_schemes) >= 1)),
    CONSTRAINT source_scope_policies_content_sha256_check CHECK ((octet_length(content_sha256) = 32)),
    CONSTRAINT source_scope_policies_include_prefixes_check CHECK ((cardinality(include_prefixes) >= 1)),
    CONSTRAINT source_scope_policies_schema_version_check CHECK ((schema_version = 'source-scope-policy-v1'::text)),
    CONSTRAINT source_scope_policies_scope_check CHECK ((scope = ANY (ARRAY['organization'::text, 'project'::text, 'source'::text]))),
    CONSTRAINT source_scope_policies_scope_source_agreement CHECK ((((scope = 'source'::text) AND (source_id IS NOT NULL)) OR ((scope <> 'source'::text) AND (source_id IS NULL))))
);

ALTER TABLE ONLY public.source_scope_policies FORCE ROW LEVEL SECURITY;


--
-- Name: sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sources (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    submitted_root_uri text NOT NULL,
    canonical_root_uri text NOT NULL,
    canonical_host text NOT NULL,
    registration_schema_version text NOT NULL,
    host_normalization_version text NOT NULL,
    registration_origin text NOT NULL,
    registering_account_id uuid NOT NULL,
    registration_command_id uuid NOT NULL,
    registration_idempotency_key_digest bytea NOT NULL,
    registration_authorization_decision_id uuid NOT NULL,
    registered_at timestamp(6) with time zone NOT NULL,
    state text NOT NULL,
    current_scope_policy_id uuid,
    verified_at timestamp(6) with time zone,
    activated_at timestamp(6) with time zone,
    disabled_at timestamp(6) with time zone,
    removed_at timestamp(6) with time zone,
    lifecycle_reason text,
    CONSTRAINT sources_host_normalization_version_check CHECK ((host_normalization_version = 'ascii-host-v1'::text)),
    CONSTRAINT sources_lifecycle_reason_check CHECK (((lifecycle_reason IS NULL) OR ((char_length(lifecycle_reason) >= 1) AND (char_length(lifecycle_reason) <= 2000)))),
    CONSTRAINT sources_registration_idempotency_key_digest_check CHECK ((octet_length(registration_idempotency_key_digest) = 32)),
    CONSTRAINT sources_registration_origin_check CHECK ((registration_origin = 'human_command'::text)),
    CONSTRAINT sources_registration_schema_version_check CHECK ((registration_schema_version = 'source-registration-v1'::text)),
    CONSTRAINT sources_state_check CHECK ((state = ANY (ARRAY['proposed'::text, 'verified'::text, 'active'::text, 'disabled'::text, 'removed'::text])))
);

ALTER TABLE ONLY public.sources FORCE ROW LEVEL SECURITY;


--
-- Name: verification_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.verification_attempts (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    schema_version text NOT NULL,
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    verification_request_id uuid NOT NULL,
    source_id uuid NOT NULL,
    attempt_number integer NOT NULL,
    origin text NOT NULL,
    automated_slot_offset_minutes integer,
    reserved_at_utc timestamp(6) with time zone NOT NULL,
    started_at_utc timestamp(6) with time zone,
    completed_at_utc timestamp(6) with time zone,
    deadline_at_utc timestamp(6) with time zone,
    network_outcome text,
    http_status integer,
    dns_response_code text,
    received_byte_count integer,
    observed_value_sha256 bytea,
    match_decision text,
    reason_code text,
    state text NOT NULL,
    CONSTRAINT verification_attempts_attempt_number_check CHECK ((attempt_number > 0)),
    CONSTRAINT verification_attempts_match_decision_check CHECK (((match_decision IS NULL) OR (match_decision = ANY (ARRAY['matched'::text, 'not_matched'::text, 'indeterminate'::text])))),
    CONSTRAINT verification_attempts_network_outcome_check CHECK (((network_outcome IS NULL) OR (network_outcome = ANY (ARRAY['response'::text, 'timeout'::text, 'resolver_failure'::text, 'connection_failure'::text, 'tls_failure'::text])))),
    CONSTRAINT verification_attempts_observed_value_sha256_check CHECK (((observed_value_sha256 IS NULL) OR (octet_length(observed_value_sha256) = 32))),
    CONSTRAINT verification_attempts_origin_check CHECK ((origin = ANY (ARRAY['automated'::text, 'on_demand'::text]))),
    CONSTRAINT verification_attempts_reason_code_check CHECK (((reason_code IS NULL) OR (reason_code = ANY (ARRAY['matched'::text, 'dns_nxdomain'::text, 'dns_value_mismatch'::text, 'dns_timeout'::text, 'dns_temporary_failure'::text, 'http_status_mismatch'::text, 'http_content_mismatch'::text, 'http_body_too_large'::text, 'http_redirect_rejected'::text, 'http_timeout'::text, 'http_rate_limited'::text, 'http_server_error'::text, 'tls_validation_failed'::text, 'connection_failure'::text])))),
    CONSTRAINT verification_attempts_received_byte_count_check CHECK (((received_byte_count IS NULL) OR (received_byte_count >= 0))),
    CONSTRAINT verification_attempts_reserved_has_no_outcome CHECK (((state <> 'reserved'::text) OR ((started_at_utc IS NULL) AND (completed_at_utc IS NULL) AND (deadline_at_utc IS NULL) AND (network_outcome IS NULL) AND (http_status IS NULL) AND (dns_response_code IS NULL) AND (received_byte_count IS NULL) AND (observed_value_sha256 IS NULL) AND (match_decision IS NULL) AND (reason_code IS NULL)))),
    CONSTRAINT verification_attempts_schema_version_check CHECK ((schema_version = 'verification-attempt-v1'::text)),
    CONSTRAINT verification_attempts_slot_offset_matches_origin CHECK ((((origin = 'automated'::text) AND (automated_slot_offset_minutes IS NOT NULL)) OR ((origin = 'on_demand'::text) AND (automated_slot_offset_minutes IS NULL)))),
    CONSTRAINT verification_attempts_state_check CHECK ((state = ANY (ARRAY['reserved'::text, 'running'::text, 'completed'::text, 'quarantined'::text])))
);

ALTER TABLE ONLY public.verification_attempts FORCE ROW LEVEL SECURITY;


--
-- Name: verification_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.verification_requests (
    id uuid NOT NULL,
    state_version bigint DEFAULT 0 NOT NULL,
    lock_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    correlation_id uuid NOT NULL,
    schema_version text NOT NULL,
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    source_id uuid NOT NULL,
    request_initiator_account_id uuid NOT NULL,
    method text NOT NULL,
    canonical_host text NOT NULL,
    challenge_token_sha256 bytea NOT NULL,
    challenge_ciphertext_reference uuid,
    challenge_key_id text,
    initial_challenge_delivered_at_utc timestamp(6) with time zone NOT NULL,
    issued_at_utc timestamp(6) with time zone NOT NULL,
    expires_at_utc timestamp(6) with time zone NOT NULL,
    idempotency_key_digest bytea NOT NULL,
    request_status text NOT NULL,
    attempt_count integer DEFAULT 0 NOT NULL,
    on_demand_observation_count integer DEFAULT 0 NOT NULL,
    on_demand_in_progress_attempt_id uuid,
    last_on_demand_completed_at_utc timestamp(6) with time zone,
    last_observed_at_utc timestamp(6) with time zone,
    decision_reason_code text,
    CONSTRAINT verification_requests_attempt_count_check CHECK ((attempt_count >= 0)),
    CONSTRAINT verification_requests_challenge_token_sha256_check CHECK ((octet_length(challenge_token_sha256) = 32)),
    CONSTRAINT verification_requests_expires_at_utc_is_24h CHECK ((expires_at_utc = (issued_at_utc + '24:00:00'::interval))),
    CONSTRAINT verification_requests_idempotency_key_digest_check CHECK ((octet_length(idempotency_key_digest) = 32)),
    CONSTRAINT verification_requests_method_check CHECK ((method = ANY (ARRAY['dns_txt'::text, 'http_file'::text]))),
    CONSTRAINT verification_requests_on_demand_observation_count_check CHECK (((on_demand_observation_count >= 0) AND (on_demand_observation_count <= 10))),
    CONSTRAINT verification_requests_pending_has_challenge CHECK (((request_status <> 'pending'::text) OR ((challenge_ciphertext_reference IS NOT NULL) AND (challenge_key_id IS NOT NULL)))),
    CONSTRAINT verification_requests_pending_reason_null CHECK (((request_status <> 'pending'::text) OR (decision_reason_code IS NULL))),
    CONSTRAINT verification_requests_request_status_check CHECK ((request_status = ANY (ARRAY['pending'::text, 'verified'::text, 'expired'::text, 'canceled'::text, 'failed'::text]))),
    CONSTRAINT verification_requests_schema_version_check CHECK ((schema_version = 'verification-request-v1'::text))
);

ALTER TABLE ONLY public.verification_requests FORCE ROW LEVEL SECURITY;


--
-- Name: work_dispatch_bindings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_dispatch_bindings (
    id uuid NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    organization_id uuid,
    source_action_id uuid NOT NULL,
    source_claim_generation bigint NOT NULL,
    action_kind text NOT NULL,
    target_type text NOT NULL,
    target_id uuid NOT NULL,
    target_generation bigint,
    CONSTRAINT work_dispatch_bindings_source_claim_generation_check CHECK ((source_claim_generation > 0)),
    CONSTRAINT work_dispatch_bindings_target_generation_check CHECK (((target_generation IS NULL) OR (target_generation > 0))),
    CONSTRAINT work_dispatch_bindings_target_type_check CHECK ((target_type = 'scheduled_action'::text))
);


--
-- Name: access_policies access_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_policies
    ADD CONSTRAINT access_policies_pkey PRIMARY KEY (id);


--
-- Name: accounts accounts_identity_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_identity_unique UNIQUE (organization_id, identity_issuer_key, identity_subject);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: role_assignment_approvals approval_records_are_ordered; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_assignment_approvals
    ADD CONSTRAINT approval_records_are_ordered UNIQUE (role_assignment_id, sequence_number);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_record_registry audit_record_registry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_record_registry
    ADD CONSTRAINT audit_record_registry_pkey PRIMARY KEY (id);


--
-- Name: authorization_decisions authorization_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.authorization_decisions
    ADD CONSTRAINT authorization_decisions_pkey PRIMARY KEY (id);


--
-- Name: billing_entities billing_entities_org_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_entities
    ADD CONSTRAINT billing_entities_org_id_unique UNIQUE (organization_id, id);


--
-- Name: billing_entities billing_entities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_entities
    ADD CONSTRAINT billing_entities_pkey PRIMARY KEY (id);


--
-- Name: bootstrap_grants bootstrap_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bootstrap_grants
    ADD CONSTRAINT bootstrap_grants_pkey PRIMARY KEY (id);


--
-- Name: command_executions command_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_executions
    ADD CONSTRAINT command_executions_pkey PRIMARY KEY (id);


--
-- Name: command_results command_results_command_execution_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_results
    ADD CONSTRAINT command_results_command_execution_id_key UNIQUE (command_execution_id);


--
-- Name: command_results command_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_results
    ADD CONSTRAINT command_results_pkey PRIMARY KEY (id);


--
-- Name: crawl_policies crawl_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crawl_policies
    ADD CONSTRAINT crawl_policies_pkey PRIMARY KEY (id);


--
-- Name: crawl_sources crawl_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crawl_sources
    ADD CONSTRAINT crawl_sources_pkey PRIMARY KEY (id);


--
-- Name: crawls crawls_org_project_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crawls
    ADD CONSTRAINT crawls_org_project_id_unique UNIQUE (organization_id, project_id, id);


--
-- Name: crawls crawls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crawls
    ADD CONSTRAINT crawls_pkey PRIMARY KEY (id);


--
-- Name: entitlement_commit_intents entitlement_commit_intents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_commit_intents
    ADD CONSTRAINT entitlement_commit_intents_pkey PRIMARY KEY (id);


--
-- Name: entitlement_counter_windows entitlement_counter_windows_org_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_counter_windows
    ADD CONSTRAINT entitlement_counter_windows_org_id_unique UNIQUE (organization_id, id);


--
-- Name: entitlement_counter_windows entitlement_counter_windows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_counter_windows
    ADD CONSTRAINT entitlement_counter_windows_pkey PRIMARY KEY (id);


--
-- Name: entitlement_decisions entitlement_decisions_org_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_decisions
    ADD CONSTRAINT entitlement_decisions_org_id_unique UNIQUE (organization_id, id);


--
-- Name: entitlement_decisions entitlement_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_decisions
    ADD CONSTRAINT entitlement_decisions_pkey PRIMARY KEY (id);


--
-- Name: entitlement_lease_heartbeats entitlement_lease_heartbeats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_lease_heartbeats
    ADD CONSTRAINT entitlement_lease_heartbeats_pkey PRIMARY KEY (id);


--
-- Name: entitlement_policies entitlement_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_policies
    ADD CONSTRAINT entitlement_policies_pkey PRIMARY KEY (id);


--
-- Name: entitlement_reservations entitlement_reservations_decision_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_reservations
    ADD CONSTRAINT entitlement_reservations_decision_unique UNIQUE (decision_id);


--
-- Name: entitlement_reservations entitlement_reservations_org_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_reservations
    ADD CONSTRAINT entitlement_reservations_org_id_unique UNIQUE (organization_id, id);


--
-- Name: entitlement_reservations entitlement_reservations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_reservations
    ADD CONSTRAINT entitlement_reservations_pkey PRIMARY KEY (id);


--
-- Name: evaluations evaluations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluations
    ADD CONSTRAINT evaluations_pkey PRIMARY KEY (id);


--
-- Name: event_registry event_registry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_registry
    ADD CONSTRAINT event_registry_pkey PRIMARY KEY (id);


--
-- Name: evidence evidence_org_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence
    ADD CONSTRAINT evidence_org_id_unique UNIQUE (organization_id, id);


--
-- Name: evidence evidence_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence
    ADD CONSTRAINT evidence_pkey PRIMARY KEY (id);


--
-- Name: evidence evidence_producer_attempt_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence
    ADD CONSTRAINT evidence_producer_attempt_unique UNIQUE (organization_id, producer_id, attempt_id);


--
-- Name: f1_context_keys f1_context_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.f1_context_keys
    ADD CONSTRAINT f1_context_keys_pkey PRIMARY KEY (key_name);


--
-- Name: f1_encrypted_records f1_encrypted_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.f1_encrypted_records
    ADD CONSTRAINT f1_encrypted_records_pkey PRIMARY KEY (id);


--
-- Name: f1_encryption_key_versions f1_encryption_key_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.f1_encryption_key_versions
    ADD CONSTRAINT f1_encryption_key_versions_pkey PRIMARY KEY (provider, version);


--
-- Name: idempotency_records idempotency_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_records
    ADD CONSTRAINT idempotency_records_pkey PRIMARY KEY (id);


--
-- Name: identity_receipt_consumptions identity_receipt_consumptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_receipt_consumptions
    ADD CONSTRAINT identity_receipt_consumptions_pkey PRIMARY KEY (id);


--
-- Name: identity_receipt_consumptions identity_receipt_consumptions_receipt_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_receipt_consumptions
    ADD CONSTRAINT identity_receipt_consumptions_receipt_id_key UNIQUE (receipt_id);


--
-- Name: identity_receipt_nonces identity_receipt_nonces_nonce_sha256_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_receipt_nonces
    ADD CONSTRAINT identity_receipt_nonces_nonce_sha256_key UNIQUE (nonce_sha256);


--
-- Name: identity_receipt_nonces identity_receipt_nonces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_receipt_nonces
    ADD CONSTRAINT identity_receipt_nonces_pkey PRIMARY KEY (id);


--
-- Name: identity_receipt_nonces identity_receipt_nonces_receipt_digest_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_receipt_nonces
    ADD CONSTRAINT identity_receipt_nonces_receipt_digest_key UNIQUE (receipt_digest);


--
-- Name: invitation_reference_registry invitation_reference_registry_invitation_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitation_reference_registry
    ADD CONSTRAINT invitation_reference_registry_invitation_id_key UNIQUE (invitation_id);


--
-- Name: invitation_reference_registry invitation_reference_registry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitation_reference_registry
    ADD CONSTRAINT invitation_reference_registry_pkey PRIMARY KEY (opaque_reference_sha256);


--
-- Name: invitations invitations_opaque_reference_sha256_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_opaque_reference_sha256_key UNIQUE (opaque_reference_sha256);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


--
-- Name: role_expiry_block_decisions one_decision_per_assignment_epoch; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_expiry_block_decisions
    ADD CONSTRAINT one_decision_per_assignment_epoch UNIQUE (role_assignment_id, authorization_epoch);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: plan_assignments plan_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_assignments
    ADD CONSTRAINT plan_assignments_pkey PRIMARY KEY (id);


--
-- Name: pretenant_authorization_decisions pretenant_authorization_decisions_command_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pretenant_authorization_decisions
    ADD CONSTRAINT pretenant_authorization_decisions_command_id_key UNIQUE (command_id);


--
-- Name: pretenant_authorization_decisions pretenant_authorization_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pretenant_authorization_decisions
    ADD CONSTRAINT pretenant_authorization_decisions_pkey PRIMARY KEY (id);


--
-- Name: projects projects_org_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_org_id_unique UNIQUE (organization_id, id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: role_assignment_approvals role_assignment_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_assignment_approvals
    ADD CONSTRAINT role_assignment_approvals_pkey PRIMARY KEY (id);


--
-- Name: role_assignments role_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT role_assignments_pkey PRIMARY KEY (id);


--
-- Name: role_expiry_block_decisions role_expiry_block_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_expiry_block_decisions
    ADD CONSTRAINT role_expiry_block_decisions_pkey PRIMARY KEY (id);


--
-- Name: scheduled_actions scheduled_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_actions
    ADD CONSTRAINT scheduled_actions_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: service_identities service_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_identities
    ADD CONSTRAINT service_identities_pkey PRIMARY KEY (id);


--
-- Name: service_identities service_identities_subject_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_identities
    ADD CONSTRAINT service_identities_subject_key UNIQUE (subject);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: source_scope_change_requests source_scope_change_requests_org_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_scope_change_requests
    ADD CONSTRAINT source_scope_change_requests_org_id_unique UNIQUE (organization_id, id);


--
-- Name: source_scope_change_requests source_scope_change_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_scope_change_requests
    ADD CONSTRAINT source_scope_change_requests_pkey PRIMARY KEY (id);


--
-- Name: source_scope_policies source_scope_policies_org_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_scope_policies
    ADD CONSTRAINT source_scope_policies_org_id_unique UNIQUE (organization_id, id);


--
-- Name: source_scope_policies source_scope_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_scope_policies
    ADD CONSTRAINT source_scope_policies_pkey PRIMARY KEY (id);


--
-- Name: source_scope_policies source_scope_policies_source_version_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_scope_policies
    ADD CONSTRAINT source_scope_policies_source_version_unique UNIQUE (organization_id, project_id, source_id, policy_version);


--
-- Name: sources sources_org_project_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT sources_org_project_id_unique UNIQUE (organization_id, project_id, id);


--
-- Name: sources sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT sources_pkey PRIMARY KEY (id);


--
-- Name: verification_attempts verification_attempts_org_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_attempts
    ADD CONSTRAINT verification_attempts_org_id_unique UNIQUE (organization_id, id);


--
-- Name: verification_attempts verification_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_attempts
    ADD CONSTRAINT verification_attempts_pkey PRIMARY KEY (id);


--
-- Name: verification_attempts verification_attempts_request_attempt_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_attempts
    ADD CONSTRAINT verification_attempts_request_attempt_unique UNIQUE (verification_request_id, attempt_number);


--
-- Name: verification_requests verification_requests_org_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_requests
    ADD CONSTRAINT verification_requests_org_id_unique UNIQUE (organization_id, id);


--
-- Name: verification_requests verification_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_requests
    ADD CONSTRAINT verification_requests_pkey PRIMARY KEY (id);


--
-- Name: work_dispatch_bindings work_dispatch_bindings_identity; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_dispatch_bindings
    ADD CONSTRAINT work_dispatch_bindings_identity UNIQUE (source_action_id, source_claim_generation);


--
-- Name: work_dispatch_bindings work_dispatch_bindings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_dispatch_bindings
    ADD CONSTRAINT work_dispatch_bindings_pkey PRIMARY KEY (id);


--
-- Name: crawl_policies_active_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX crawl_policies_active_unique ON public.crawl_policies USING btree (organization_id, scope, COALESCE(project_id, '00000000-0000-0000-0000-000000000000'::uuid)) WHERE (state = 'active'::text);


--
-- Name: crawl_policies_org_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX crawl_policies_org_scope ON public.crawl_policies USING btree (organization_id, scope, project_id);


--
-- Name: crawl_policies_version_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX crawl_policies_version_unique ON public.crawl_policies USING btree (organization_id, scope, COALESCE(project_id, '00000000-0000-0000-0000-000000000000'::uuid), policy_version);


--
-- Name: crawl_sources_crawl_order_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX crawl_sources_crawl_order_unique ON public.crawl_sources USING btree (crawl_id, source_order);


--
-- Name: crawl_sources_crawl_source_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX crawl_sources_crawl_source_unique ON public.crawl_sources USING btree (crawl_id, source_id);


--
-- Name: crawls_project_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX crawls_project_state ON public.crawls USING btree (organization_id, project_id, state);


--
-- Name: entitlement_commit_intents_reservation_output_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX entitlement_commit_intents_reservation_output_unique ON public.entitlement_commit_intents USING btree (reservation_id, durable_output_type, durable_output_id);


--
-- Name: entitlement_counter_windows_slot_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX entitlement_counter_windows_slot_unique ON public.entitlement_counter_windows USING btree (organization_id, counter_group, window_start, window_end);


--
-- Name: entitlement_decisions_org_operation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX entitlement_decisions_org_operation ON public.entitlement_decisions USING btree (organization_id, operation, decided_at);


--
-- Name: entitlement_lease_heartbeats_generation_time_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX entitlement_lease_heartbeats_generation_time_unique ON public.entitlement_lease_heartbeats USING btree (entitlement_reservation_id, heartbeat_generation, renewed_at);


--
-- Name: entitlement_lease_heartbeats_generation_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX entitlement_lease_heartbeats_generation_unique ON public.entitlement_lease_heartbeats USING btree (entitlement_reservation_id, heartbeat_generation);


--
-- Name: entitlement_reservations_window_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX entitlement_reservations_window_state ON public.entitlement_reservations USING btree (organization_id, counter_window_id, state);


--
-- Name: evaluations_initial_per_crawl_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX evaluations_initial_per_crawl_unique ON public.evaluations USING btree (organization_id, project_id, crawl_id) WHERE (kind = 'initial'::text);


--
-- Name: evaluations_orchestration_slot_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX evaluations_orchestration_slot_unique ON public.evaluations USING btree (organization_id, project_id) WHERE orchestration_slot_active;


--
-- Name: evaluations_project_kind_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX evaluations_project_kind_state ON public.evaluations USING btree (organization_id, project_id, kind, state);


--
-- Name: evidence_content_hash_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX evidence_content_hash_lookup ON public.evidence USING btree (organization_id, content_sha256);


--
-- Name: f1_encrypted_records_by_wrapping_version; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX f1_encrypted_records_by_wrapping_version ON public.f1_encrypted_records USING btree (key_provider, wrapping_key_version) WHERE (state = 'active'::text);


--
-- Name: f1_one_active_encryption_key_per_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX f1_one_active_encryption_key_per_provider ON public.f1_encryption_key_versions USING btree (provider) WHERE (state = 'active'::text);


--
-- Name: idempotency_scope_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idempotency_scope_key ON public.idempotency_records USING btree (scope_kind, command_type, target_type, key_digest, COALESCE(organization_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(bootstrap_principal_digest, '\x'::bytea), COALESCE(target_id, '00000000-0000-0000-0000-000000000000'::uuid));


--
-- Name: one_active_access_policy_per_org; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_active_access_policy_per_org ON public.access_policies USING btree (organization_id, policy_type) WHERE (status = 'active'::text);


--
-- Name: one_active_assignment_per_tuple; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_active_assignment_per_tuple ON public.role_assignments USING btree (organization_id, account_id, canonical_role, permission_mode, COALESCE(persona, ''::text), COALESCE(scope_sha256, '\x'::bytea)) WHERE (status = 'active'::text);


--
-- Name: one_active_entitlement_policy_per_org; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_active_entitlement_policy_per_org ON public.entitlement_policies USING btree (organization_id, policy_type) WHERE (status = 'active'::text);


--
-- Name: one_active_plan_assignment_per_org; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_active_plan_assignment_per_org ON public.plan_assignments USING btree (organization_id) WHERE (state = 'active'::text);


--
-- Name: one_approval_per_approver; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_approval_per_approver ON public.role_assignment_approvals USING btree (role_assignment_id, COALESCE(approver_account_id, approver_platform_id));


--
-- Name: one_bootstrap_admin_per_organization; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_bootstrap_admin_per_organization ON public.role_assignments USING btree (organization_id) WHERE bootstrap_admin_exception;


--
-- Name: one_consumed_grant_per_principal; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_consumed_grant_per_principal ON public.bootstrap_grants USING btree (bootstrap_principal_digest) WHERE (state = 'consumed'::text);


--
-- Name: one_consumed_per_receipt; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_consumed_per_receipt ON public.identity_receipt_consumptions USING btree (receipt_id) WHERE (outcome = 'consumed'::text);


--
-- Name: one_consumption_per_command; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_consumption_per_command ON public.identity_receipt_consumptions USING btree (command_execution_id);


--
-- Name: one_issued_grant_per_principal; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_issued_grant_per_principal ON public.bootstrap_grants USING btree (bootstrap_principal_digest) WHERE (state = 'issued'::text);


--
-- Name: one_nonclosed_billing_entity_per_org; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_nonclosed_billing_entity_per_org ON public.billing_entities USING btree (organization_id) WHERE (state <> 'closed'::text);


--
-- Name: one_open_invitation_per_preimage; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_open_invitation_per_preimage ON public.invitations USING btree (organization_id, open_uniqueness_sha256) WHERE (state = ANY (ARRAY['pending_approval'::text, 'active'::text]));


--
-- Name: scheduled_actions_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX scheduled_actions_due ON public.scheduled_actions USING btree (due_at, id) WHERE (status = 'pending'::text);


--
-- Name: scheduled_actions_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX scheduled_actions_identity ON public.scheduled_actions USING btree (action_kind, identity_sha256, collision_ordinal);


--
-- Name: scheduled_actions_leases; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX scheduled_actions_leases ON public.scheduled_actions USING btree (lease_expires_at) WHERE (status = ANY (ARRAY['claimed'::text, 'dispatched'::text]));


--
-- Name: source_scope_change_requests_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX source_scope_change_requests_due ON public.source_scope_change_requests USING btree (due_at_utc) WHERE (state = 'pending'::text);


--
-- Name: source_scope_change_requests_source_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX source_scope_change_requests_source_state ON public.source_scope_change_requests USING btree (organization_id, source_id, state);


--
-- Name: sources_nonremoved_host_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sources_nonremoved_host_unique ON public.sources USING btree (organization_id, project_id, canonical_host) WHERE (state <> 'removed'::text);


--
-- Name: verification_attempts_one_automated_per_slot; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX verification_attempts_one_automated_per_slot ON public.verification_attempts USING btree (verification_request_id, automated_slot_offset_minutes) WHERE (origin = 'automated'::text);


--
-- Name: verification_requests_one_pending_per_source; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX verification_requests_one_pending_per_source ON public.verification_requests USING btree (organization_id, project_id, source_id) WHERE (request_status = 'pending'::text);


--
-- Name: work_dispatch_bindings_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX work_dispatch_bindings_source ON public.work_dispatch_bindings USING btree (source_action_id, source_claim_generation);


--
-- Name: billing_entities billing_entities_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER billing_entities_guard BEFORE INSERT OR UPDATE ON public.billing_entities FOR EACH ROW EXECUTE FUNCTION public.f1_billing_entities_guard();


--
-- Name: crawl_policies crawl_policies_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER crawl_policies_guard BEFORE DELETE OR UPDATE ON public.crawl_policies FOR EACH ROW EXECUTE FUNCTION public.f1_crawl_policies_guard();


--
-- Name: crawl_sources crawl_sources_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER crawl_sources_guard BEFORE DELETE OR UPDATE ON public.crawl_sources FOR EACH ROW EXECUTE FUNCTION public.f1_crawl_sources_guard();


--
-- Name: crawls crawls_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER crawls_guard BEFORE DELETE OR UPDATE ON public.crawls FOR EACH ROW EXECUTE FUNCTION public.f1_crawls_guard();


--
-- Name: entitlement_commit_intents entitlement_commit_intents_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER entitlement_commit_intents_guard BEFORE DELETE OR UPDATE ON public.entitlement_commit_intents FOR EACH ROW EXECUTE FUNCTION public.f1_entitlement_commit_intents_guard();


--
-- Name: entitlement_counter_windows entitlement_counter_windows_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER entitlement_counter_windows_guard BEFORE DELETE OR UPDATE ON public.entitlement_counter_windows FOR EACH ROW EXECUTE FUNCTION public.f1_entitlement_counter_windows_guard();


--
-- Name: entitlement_decisions entitlement_decisions_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER entitlement_decisions_guard BEFORE DELETE OR UPDATE ON public.entitlement_decisions FOR EACH ROW EXECUTE FUNCTION public.f1_entitlement_decisions_guard();


--
-- Name: entitlement_lease_heartbeats entitlement_lease_heartbeats_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER entitlement_lease_heartbeats_guard BEFORE DELETE OR UPDATE ON public.entitlement_lease_heartbeats FOR EACH ROW EXECUTE FUNCTION public.f1_entitlement_lease_heartbeats_guard();


--
-- Name: entitlement_reservations entitlement_reservations_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER entitlement_reservations_guard BEFORE DELETE OR UPDATE ON public.entitlement_reservations FOR EACH ROW EXECUTE FUNCTION public.f1_entitlement_reservations_guard();


--
-- Name: evaluations evaluations_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER evaluations_guard BEFORE DELETE OR UPDATE ON public.evaluations FOR EACH ROW EXECUTE FUNCTION public.f1_evaluations_guard();


--
-- Name: evidence evidence_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER evidence_append_only BEFORE DELETE OR UPDATE ON public.evidence FOR EACH ROW EXECUTE FUNCTION public.f1_evidence_append_only();


--
-- Name: organizations organizations_lifecycle_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER organizations_lifecycle_guard BEFORE UPDATE ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.f1_organizations_lifecycle_guard();


--
-- Name: projects projects_lifecycle_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER projects_lifecycle_guard BEFORE UPDATE ON public.projects FOR EACH ROW EXECUTE FUNCTION public.f1_projects_lifecycle_guard();


--
-- Name: role_assignments role_assignments_lifecycle_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER role_assignments_lifecycle_guard BEFORE UPDATE ON public.role_assignments FOR EACH ROW EXECUTE FUNCTION public.f1_role_assignments_lifecycle_guard();


--
-- Name: scheduled_actions scheduled_actions_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER scheduled_actions_guard BEFORE UPDATE ON public.scheduled_actions FOR EACH ROW EXECUTE FUNCTION public.f1_scheduled_actions_guard();


--
-- Name: source_scope_change_requests source_scope_change_requests_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER source_scope_change_requests_guard BEFORE DELETE OR UPDATE ON public.source_scope_change_requests FOR EACH ROW EXECUTE FUNCTION public.f1_source_scope_change_requests_guard();


--
-- Name: source_scope_policies source_scope_policies_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER source_scope_policies_immutable BEFORE DELETE OR UPDATE ON public.source_scope_policies FOR EACH ROW EXECUTE FUNCTION public.f1_source_scope_policies_immutable();


--
-- Name: sources sources_lifecycle_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sources_lifecycle_guard BEFORE UPDATE ON public.sources FOR EACH ROW EXECUTE FUNCTION public.f1_sources_lifecycle_guard();


--
-- Name: verification_attempts verification_attempts_lifecycle_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER verification_attempts_lifecycle_guard BEFORE UPDATE ON public.verification_attempts FOR EACH ROW EXECUTE FUNCTION public.f1_verification_attempts_lifecycle_guard();


--
-- Name: verification_requests verification_requests_lifecycle_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER verification_requests_lifecycle_guard BEFORE UPDATE ON public.verification_requests FOR EACH ROW EXECUTE FUNCTION public.f1_verification_requests_lifecycle_guard();


--
-- Name: work_dispatch_bindings work_dispatch_bindings_no_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER work_dispatch_bindings_no_update BEFORE DELETE OR UPDATE ON public.work_dispatch_bindings FOR EACH ROW EXECUTE FUNCTION public.f1_work_dispatch_bindings_immutable();


--
-- Name: audit_record_registry audit_records_service_identity_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_record_registry
    ADD CONSTRAINT audit_records_service_identity_fkey FOREIGN KEY (service_identity_id) REFERENCES public.service_identities(id);


--
-- Name: bootstrap_grants bootstrap_grants_issuer_service_identity_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bootstrap_grants
    ADD CONSTRAINT bootstrap_grants_issuer_service_identity_fkey FOREIGN KEY (issuer_service_identity_id) REFERENCES public.service_identities(id);


--
-- Name: command_executions command_executions_service_identity_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_executions
    ADD CONSTRAINT command_executions_service_identity_fkey FOREIGN KEY (service_identity_id) REFERENCES public.service_identities(id);


--
-- Name: command_results command_results_service_identity_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_results
    ADD CONSTRAINT command_results_service_identity_fkey FOREIGN KEY (service_identity_id) REFERENCES public.service_identities(id);


--
-- Name: crawl_policies crawl_policies_project_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crawl_policies
    ADD CONSTRAINT crawl_policies_project_fk FOREIGN KEY (organization_id, project_id) REFERENCES public.projects(organization_id, id);


--
-- Name: crawl_sources crawl_sources_crawl_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crawl_sources
    ADD CONSTRAINT crawl_sources_crawl_fk FOREIGN KEY (organization_id, project_id, crawl_id) REFERENCES public.crawls(organization_id, project_id, id);


--
-- Name: crawl_sources crawl_sources_source_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crawl_sources
    ADD CONSTRAINT crawl_sources_source_fk FOREIGN KEY (organization_id, project_id, source_id) REFERENCES public.sources(organization_id, project_id, id);


--
-- Name: crawls crawls_project_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crawls
    ADD CONSTRAINT crawls_project_fk FOREIGN KEY (organization_id, project_id) REFERENCES public.projects(organization_id, id);


--
-- Name: entitlement_commit_intents entitlement_commit_intents_org_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_commit_intents
    ADD CONSTRAINT entitlement_commit_intents_org_fk FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: entitlement_commit_intents entitlement_commit_intents_reservation_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_commit_intents
    ADD CONSTRAINT entitlement_commit_intents_reservation_fk FOREIGN KEY (organization_id, reservation_id) REFERENCES public.entitlement_reservations(organization_id, id);


--
-- Name: entitlement_counter_windows entitlement_counter_windows_org_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_counter_windows
    ADD CONSTRAINT entitlement_counter_windows_org_fk FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: entitlement_decisions entitlement_decisions_org_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_decisions
    ADD CONSTRAINT entitlement_decisions_org_fk FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: entitlement_decisions entitlement_decisions_window_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_decisions
    ADD CONSTRAINT entitlement_decisions_window_fk FOREIGN KEY (organization_id, counter_window_id) REFERENCES public.entitlement_counter_windows(organization_id, id);


--
-- Name: entitlement_lease_heartbeats entitlement_lease_heartbeats_reservation_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_lease_heartbeats
    ADD CONSTRAINT entitlement_lease_heartbeats_reservation_fk FOREIGN KEY (organization_id, entitlement_reservation_id) REFERENCES public.entitlement_reservations(organization_id, id);


--
-- Name: entitlement_reservations entitlement_reservations_decision_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_reservations
    ADD CONSTRAINT entitlement_reservations_decision_fk FOREIGN KEY (organization_id, decision_id) REFERENCES public.entitlement_decisions(organization_id, id);


--
-- Name: entitlement_reservations entitlement_reservations_org_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_reservations
    ADD CONSTRAINT entitlement_reservations_org_fk FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: entitlement_reservations entitlement_reservations_window_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_reservations
    ADD CONSTRAINT entitlement_reservations_window_fk FOREIGN KEY (organization_id, counter_window_id) REFERENCES public.entitlement_counter_windows(organization_id, id);


--
-- Name: evaluations evaluations_project_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluations
    ADD CONSTRAINT evaluations_project_fk FOREIGN KEY (organization_id, project_id) REFERENCES public.projects(organization_id, id);


--
-- Name: evidence evidence_project_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence
    ADD CONSTRAINT evidence_project_fk FOREIGN KEY (organization_id, project_id) REFERENCES public.projects(organization_id, id);


--
-- Name: evidence evidence_source_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence
    ADD CONSTRAINT evidence_source_fk FOREIGN KEY (organization_id, project_id, source_id) REFERENCES public.sources(organization_id, project_id, id);


--
-- Name: identity_receipt_consumptions identity_receipt_consumptions_receipt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_receipt_consumptions
    ADD CONSTRAINT identity_receipt_consumptions_receipt_id_fkey FOREIGN KEY (receipt_id) REFERENCES public.identity_receipt_nonces(id);


--
-- Name: plan_assignments plan_assignment_billing_same_org; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_assignments
    ADD CONSTRAINT plan_assignment_billing_same_org FOREIGN KEY (organization_id, billing_entity_id) REFERENCES public.billing_entities(organization_id, id);


--
-- Name: pretenant_authorization_decisions pretenant_decisions_subject_service_identity_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pretenant_authorization_decisions
    ADD CONSTRAINT pretenant_decisions_subject_service_identity_fkey FOREIGN KEY (subject_service_identity_id) REFERENCES public.service_identities(id);


--
-- Name: scheduled_actions scheduled_actions_executing_service_identity_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_actions
    ADD CONSTRAINT scheduled_actions_executing_service_identity_fkey FOREIGN KEY (executing_service_identity_id) REFERENCES public.service_identities(id);


--
-- Name: source_scope_change_requests source_scope_change_requests_source_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_scope_change_requests
    ADD CONSTRAINT source_scope_change_requests_source_fk FOREIGN KEY (organization_id, project_id, source_id) REFERENCES public.sources(organization_id, project_id, id);


--
-- Name: source_scope_policies source_scope_policies_source_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_scope_policies
    ADD CONSTRAINT source_scope_policies_source_fk FOREIGN KEY (organization_id, project_id, source_id) REFERENCES public.sources(organization_id, project_id, id);


--
-- Name: sources sources_project_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT sources_project_fk FOREIGN KEY (organization_id, project_id) REFERENCES public.projects(organization_id, id);


--
-- Name: verification_attempts verification_attempts_request_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_attempts
    ADD CONSTRAINT verification_attempts_request_fk FOREIGN KEY (organization_id, verification_request_id) REFERENCES public.verification_requests(organization_id, id);


--
-- Name: verification_attempts verification_attempts_source_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_attempts
    ADD CONSTRAINT verification_attempts_source_fk FOREIGN KEY (organization_id, project_id, source_id) REFERENCES public.sources(organization_id, project_id, id);


--
-- Name: verification_requests verification_requests_source_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_requests
    ADD CONSTRAINT verification_requests_source_fk FOREIGN KEY (organization_id, project_id, source_id) REFERENCES public.sources(organization_id, project_id, id);


--
-- Name: access_policies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.access_policies ENABLE ROW LEVEL SECURITY;

--
-- Name: access_policies access_policies_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY access_policies_context ON public.access_policies USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: accounts accounts_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY accounts_context ON public.accounts USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: audit_record_registry; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_record_registry ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_record_registry audit_record_registry_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_record_registry_context ON public.audit_record_registry USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: authorization_decisions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.authorization_decisions ENABLE ROW LEVEL SECURITY;

--
-- Name: authorization_decisions authorization_decisions_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authorization_decisions_context ON public.authorization_decisions USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: billing_entities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.billing_entities ENABLE ROW LEVEL SECURITY;

--
-- Name: billing_entities billing_entities_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY billing_entities_context ON public.billing_entities USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: bootstrap_grants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bootstrap_grants ENABLE ROW LEVEL SECURITY;

--
-- Name: bootstrap_grants bootstrap_grants_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY bootstrap_grants_context ON public.bootstrap_grants USING ((bootstrap_principal_digest = public.f1_current_bootstrap_principal())) WITH CHECK ((bootstrap_principal_digest = public.f1_current_bootstrap_principal()));


--
-- Name: command_executions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.command_executions ENABLE ROW LEVEL SECURITY;

--
-- Name: command_executions command_executions_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY command_executions_context ON public.command_executions USING (((bootstrap_principal_digest = public.f1_current_bootstrap_principal()) OR (organization_id = public.f1_current_context_org()))) WITH CHECK (((bootstrap_principal_digest = public.f1_current_bootstrap_principal()) OR (organization_id = public.f1_current_context_org())));


--
-- Name: command_results; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.command_results ENABLE ROW LEVEL SECURITY;

--
-- Name: command_results command_results_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY command_results_context ON public.command_results USING ((command_execution_id IN ( SELECT command_executions.id
   FROM public.command_executions))) WITH CHECK ((command_execution_id IN ( SELECT command_executions.id
   FROM public.command_executions)));


--
-- Name: crawl_policies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.crawl_policies ENABLE ROW LEVEL SECURITY;

--
-- Name: crawl_policies crawl_policies_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crawl_policies_context ON public.crawl_policies USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: crawl_sources; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.crawl_sources ENABLE ROW LEVEL SECURITY;

--
-- Name: crawl_sources crawl_sources_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crawl_sources_context ON public.crawl_sources USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: crawls; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.crawls ENABLE ROW LEVEL SECURITY;

--
-- Name: crawls crawls_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crawls_context ON public.crawls USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: entitlement_commit_intents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.entitlement_commit_intents ENABLE ROW LEVEL SECURITY;

--
-- Name: entitlement_commit_intents entitlement_commit_intents_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY entitlement_commit_intents_context ON public.entitlement_commit_intents USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: entitlement_counter_windows; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.entitlement_counter_windows ENABLE ROW LEVEL SECURITY;

--
-- Name: entitlement_counter_windows entitlement_counter_windows_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY entitlement_counter_windows_context ON public.entitlement_counter_windows USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: entitlement_decisions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.entitlement_decisions ENABLE ROW LEVEL SECURITY;

--
-- Name: entitlement_decisions entitlement_decisions_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY entitlement_decisions_context ON public.entitlement_decisions USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: entitlement_lease_heartbeats; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.entitlement_lease_heartbeats ENABLE ROW LEVEL SECURITY;

--
-- Name: entitlement_lease_heartbeats entitlement_lease_heartbeats_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY entitlement_lease_heartbeats_context ON public.entitlement_lease_heartbeats USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: entitlement_policies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.entitlement_policies ENABLE ROW LEVEL SECURITY;

--
-- Name: entitlement_policies entitlement_policies_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY entitlement_policies_context ON public.entitlement_policies USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: entitlement_reservations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.entitlement_reservations ENABLE ROW LEVEL SECURITY;

--
-- Name: entitlement_reservations entitlement_reservations_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY entitlement_reservations_context ON public.entitlement_reservations USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: evaluations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.evaluations ENABLE ROW LEVEL SECURITY;

--
-- Name: evaluations evaluations_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY evaluations_context ON public.evaluations USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: event_registry; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.event_registry ENABLE ROW LEVEL SECURITY;

--
-- Name: event_registry event_registry_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_registry_context ON public.event_registry USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: evidence; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.evidence ENABLE ROW LEVEL SECURITY;

--
-- Name: evidence evidence_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY evidence_context ON public.evidence USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: idempotency_records; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.idempotency_records ENABLE ROW LEVEL SECURITY;

--
-- Name: idempotency_records idempotency_records_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY idempotency_records_context ON public.idempotency_records USING (((bootstrap_principal_digest = public.f1_current_bootstrap_principal()) OR (organization_id = public.f1_current_context_org()))) WITH CHECK (((bootstrap_principal_digest = public.f1_current_bootstrap_principal()) OR (organization_id = public.f1_current_context_org())));


--
-- Name: identity_receipt_consumptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.identity_receipt_consumptions ENABLE ROW LEVEL SECURITY;

--
-- Name: identity_receipt_nonces; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.identity_receipt_nonces ENABLE ROW LEVEL SECURITY;

--
-- Name: invitation_reference_registry; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invitation_reference_registry ENABLE ROW LEVEL SECURITY;

--
-- Name: invitation_reference_registry invitation_reference_registry_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invitation_reference_registry_context ON public.invitation_reference_registry USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: invitations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: invitations invitations_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invitations_context ON public.invitations USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: organizations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

--
-- Name: organizations organizations_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY organizations_context ON public.organizations USING ((id = public.f1_current_context_org())) WITH CHECK ((id = public.f1_current_context_org()));


--
-- Name: plan_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.plan_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: plan_assignments plan_assignments_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY plan_assignments_context ON public.plan_assignments USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: pretenant_authorization_decisions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pretenant_authorization_decisions ENABLE ROW LEVEL SECURITY;

--
-- Name: pretenant_authorization_decisions pretenant_authorization_decisions_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pretenant_authorization_decisions_context ON public.pretenant_authorization_decisions USING ((bootstrap_principal_digest = public.f1_current_bootstrap_principal())) WITH CHECK ((bootstrap_principal_digest = public.f1_current_bootstrap_principal()));


--
-- Name: projects; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;

--
-- Name: projects projects_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY projects_context ON public.projects USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: identity_receipt_nonces receipt_by_principal; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY receipt_by_principal ON public.identity_receipt_nonces USING ((bootstrap_principal_digest = public.f1_current_bootstrap_principal()));


--
-- Name: role_assignment_approvals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.role_assignment_approvals ENABLE ROW LEVEL SECURITY;

--
-- Name: role_assignment_approvals role_assignment_approvals_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY role_assignment_approvals_context ON public.role_assignment_approvals USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: role_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.role_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: role_assignments role_assignments_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY role_assignments_context ON public.role_assignments USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: role_expiry_block_decisions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.role_expiry_block_decisions ENABLE ROW LEVEL SECURITY;

--
-- Name: role_expiry_block_decisions role_expiry_block_decisions_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY role_expiry_block_decisions_context ON public.role_expiry_block_decisions USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: scheduled_actions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.scheduled_actions ENABLE ROW LEVEL SECURITY;

--
-- Name: scheduled_actions scheduled_actions_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY scheduled_actions_context ON public.scheduled_actions USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: service_identities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.service_identities ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions sessions_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sessions_context ON public.sessions USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: source_scope_change_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.source_scope_change_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: source_scope_change_requests source_scope_change_requests_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY source_scope_change_requests_context ON public.source_scope_change_requests USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: source_scope_policies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.source_scope_policies ENABLE ROW LEVEL SECURITY;

--
-- Name: source_scope_policies source_scope_policies_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY source_scope_policies_context ON public.source_scope_policies USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: sources; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sources ENABLE ROW LEVEL SECURITY;

--
-- Name: sources sources_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sources_context ON public.sources USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: verification_attempts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.verification_attempts ENABLE ROW LEVEL SECURITY;

--
-- Name: verification_attempts verification_attempts_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY verification_attempts_context ON public.verification_attempts USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: verification_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.verification_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: verification_requests verification_requests_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY verification_requests_context ON public.verification_requests USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: work_dispatch_bindings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_dispatch_bindings ENABLE ROW LEVEL SECURITY;

--
-- Name: work_dispatch_bindings work_dispatch_bindings_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY work_dispatch_bindings_context ON public.work_dispatch_bindings USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260727120120'),
('20260727120110'),
('20260727120100'),
('20260727120090'),
('20260727120080'),
('20260727120070'),
('20260727120060'),
('20260727120051'),
('20260727120050'),
('20260727120040'),
('20260726120033'),
('20260726120032'),
('20260726120031'),
('20260726120030'),
('20260726120029'),
('20260725120028'),
('20260725120027'),
('20260725120026'),
('20260725120025'),
('20260725120024'),
('20260725120023'),
('20260725120022'),
('20260723120021'),
('20260723120020'),
('20260723120019'),
('20260722120018'),
('20260722120017'),
('20260722120016'),
('20260722120015'),
('20260722120014'),
('20260722120013'),
('20260722120012'),
('20260722120011'),
('20260722120010'),
('20260722120009'),
('20260722120008'),
('20260722120007'),
('20260722120006'),
('20260721120005'),
('20260721120004'),
('20260719120003'),
('20260719120002'),
('20260719120001');

