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

CREATE FUNCTION public.f1_claim_due_scheduled_actions(p_owner uuid, p_limit integer, p_lease_seconds integer) RETURNS TABLE(id uuid, action_kind text, action_schema_version text, organization_id uuid, project_id uuid, target_type text, target_id uuid, product_generation bigint, schedule_generation bigint, due_at timestamp with time zone, claim_generation bigint, correlation_id uuid, causation_id uuid, executing_service_identity_id uuid, payload_refs jsonb)
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
      AND s.status = 'active'
    ORDER BY a.due_at, a.id
    FOR UPDATE OF a SKIP LOCKED
    LIMIT greatest(p_limit, 0)
  )
  UPDATE scheduled_actions a
  SET status = 'claimed', claim_owner = p_owner, claim_generation = a.claim_generation + 1,
      claimed_at = v_now, lease_expires_at = v_now + make_interval(secs => greatest(p_lease_seconds, 1)),
      claim_phase = 'scheduler', last_heartbeat_at = NULL, updated_at = v_now,
      state_version = a.state_version + 1
  FROM due
  WHERE a.id = due.id
  RETURNING a.id, a.action_kind, a.action_schema_version, a.organization_id, a.project_id,
            a.target_type, a.target_id, a.product_generation, a.schedule_generation,
            a.due_at, a.claim_generation, a.correlation_id, a.causation_id,
            a.executing_service_identity_id, a.payload_refs;
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
-- Name: f1_dispatch_scheduled_action(uuid, uuid, bigint, uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_dispatch_scheduled_action(p_action_id uuid, p_expected_owner uuid, p_expected_generation bigint, p_worker_owner uuid, p_lease_seconds integer) RETURNS TABLE(id uuid, action_kind text, action_schema_version text, organization_id uuid, project_id uuid, target_type text, target_id uuid, product_generation bigint, schedule_generation bigint, due_at timestamp with time zone, claim_generation bigint, correlation_id uuid, causation_id uuid, executing_service_identity_id uuid, payload_refs jsonb, identity_sha256 bytea)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
#variable_conflict use_column
DECLARE v_now timestamptz(6) := transaction_timestamp();
BEGIN
  RETURN QUERY
  UPDATE scheduled_actions a
  SET status = 'dispatched',
      dispatched_at = coalesce(a.dispatched_at, v_now),
      claim_owner = p_worker_owner, claim_phase = 'worker',
      lease_expires_at = v_now + make_interval(secs => greatest(p_lease_seconds, 1)),
      updated_at = v_now, state_version = a.state_version + 1
  WHERE a.id = p_action_id
    AND a.status IN ('claimed','dispatched')
    AND a.claim_generation = p_expected_generation
    AND a.claim_owner IN (p_expected_owner, p_worker_owner)
  RETURNING a.id, a.action_kind, a.action_schema_version, a.organization_id, a.project_id,
            a.target_type, a.target_id, a.product_generation, a.schedule_generation,
            a.due_at, a.claim_generation, a.correlation_id, a.causation_id,
            a.executing_service_identity_id, a.payload_refs, a.identity_sha256;
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
  -- DM-REQ (011 DOMAIN_MODEL.md :118) "Project MUST belong to exactly one
  -- Organization": a Project's Organization and identity are fixed for life.
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    RAISE EXCEPTION 'project_organization_immutable' USING ERRCODE = 'raise_exception';
  END IF;

  -- WF-002 State Transitions define Project.Draft -> Project.Active only, and
  -- that transition is gated on >=1 active same-Project Source (CAP-003,
  -- PRULE-004). The Source aggregate is owned by S-04/S-05/S-06 and is not
  -- built, so activation is not implementable in this baseline; Project
  -- pause/resume/archive are withheld under OD-014. No path may change a
  -- Project's state here. The activation slice will relax this guard to
  -- permit the single draft->active edge under its ratified prerequisites.
  IF NEW.state IS DISTINCT FROM OLD.state THEN
    RAISE EXCEPTION 'project_lifecycle_transition_unavailable % -> %', OLD.state, NEW.state
      USING ERRCODE = 'raise_exception';
  END IF;

  -- ":671 The baseline Local Business Profile is immutable with the Project
  -- creation profile ... requires a new Project." The whole creation profile
  -- is frozen at creation.
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
-- Name: f1_context_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.f1_context_keys (
    key_name text NOT NULL,
    key_bytes bytea NOT NULL,
    CONSTRAINT f1_context_keys_key_bytes_check CHECK ((octet_length(key_bytes) = 32))
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
-- Name: entitlement_policies entitlement_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entitlement_policies
    ADD CONSTRAINT entitlement_policies_pkey PRIMARY KEY (id);


--
-- Name: event_registry event_registry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_registry
    ADD CONSTRAINT event_registry_pkey PRIMARY KEY (id);


--
-- Name: f1_context_keys f1_context_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.f1_context_keys
    ADD CONSTRAINT f1_context_keys_pkey PRIMARY KEY (key_name);


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
-- Name: billing_entities billing_entities_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER billing_entities_guard BEFORE INSERT OR UPDATE ON public.billing_entities FOR EACH ROW EXECUTE FUNCTION public.f1_billing_entities_guard();


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
-- Name: entitlement_policies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.entitlement_policies ENABLE ROW LEVEL SECURITY;

--
-- Name: entitlement_policies entitlement_policies_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY entitlement_policies_context ON public.entitlement_policies USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


--
-- Name: event_registry; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.event_registry ENABLE ROW LEVEL SECURITY;

--
-- Name: event_registry event_registry_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_registry_context ON public.event_registry USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


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
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
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

