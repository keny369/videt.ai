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
-- Name: f1_resolve_invitation_reference(bytea, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f1_resolve_invitation_reference(p_reference_digest bytea, p_now timestamp with time zone) RETURNS TABLE(organization_id uuid, invitation_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT r.organization_id, r.invitation_id
  FROM invitation_reference_registry r
  WHERE r.opaque_reference_sha256 = p_reference_digest
    AND r.invitation_state = 'active'
    AND (r.expires_at IS NULL OR p_now < r.expires_at);
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
    CONSTRAINT invitation_active_expiry_is_seven_days CHECK (((activated_at IS NULL) OR (expires_at = (activated_at + '7 days'::interval)))),
    CONSTRAINT invitation_bound_identity_pairwise CHECK (((target_identity_issuer_key IS NULL) = (target_identity_subject IS NULL))),
    CONSTRAINT invitations_opaque_reference_sha256_check CHECK ((octet_length(opaque_reference_sha256) = 32)),
    CONSTRAINT invitations_permission_mode_check CHECK ((permission_mode = ANY (ARRAY['standard'::text, 'read_only'::text]))),
    CONSTRAINT invitations_scope_sha256_check CHECK (((scope_sha256 IS NULL) OR (octet_length(scope_sha256) = 32))),
    CONSTRAINT invitations_state_check CHECK ((state = ANY (ARRAY['pending_approval'::text, 'active'::text, 'accepted'::text, 'declined'::text, 'rejected'::text, 'revoked'::text, 'expired'::text]))),
    CONSTRAINT invitations_target_email_sha256_check CHECK ((octet_length(target_email_sha256) = 32))
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
    lifecycle_reason text,
    CONSTRAINT organizations_authorization_epoch_check CHECK ((authorization_epoch >= 0)),
    CONSTRAINT organizations_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'suspended'::text, 'closed'::text])))
);

ALTER TABLE ONLY public.organizations FORCE ROW LEVEL SECURITY;


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
    CONSTRAINT role_assignments_permission_mode_check CHECK ((permission_mode = ANY (ARRAY['standard'::text, 'read_only'::text]))),
    CONSTRAINT role_assignments_scope_sha256_check CHECK (((scope_sha256 IS NULL) OR (octet_length(scope_sha256) = 32))),
    CONSTRAINT role_assignments_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'rejected'::text, 'revoked'::text, 'expired'::text])))
);

ALTER TABLE ONLY public.role_assignments FORCE ROW LEVEL SECURITY;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
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

ALTER TABLE ONLY public.sessions FORCE ROW LEVEL SECURITY;


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
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


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
-- Name: role_assignments role_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT role_assignments_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


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
-- Name: identity_receipt_consumptions identity_receipt_consumptions_receipt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_receipt_consumptions
    ADD CONSTRAINT identity_receipt_consumptions_receipt_id_fkey FOREIGN KEY (receipt_id) REFERENCES public.identity_receipt_nonces(id);


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
-- Name: pretenant_authorization_decisions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pretenant_authorization_decisions ENABLE ROW LEVEL SECURITY;

--
-- Name: pretenant_authorization_decisions pretenant_authorization_decisions_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pretenant_authorization_decisions_context ON public.pretenant_authorization_decisions USING ((bootstrap_principal_digest = public.f1_current_bootstrap_principal())) WITH CHECK ((bootstrap_principal_digest = public.f1_current_bootstrap_principal()));


--
-- Name: identity_receipt_nonces receipt_by_principal; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY receipt_by_principal ON public.identity_receipt_nonces USING ((bootstrap_principal_digest = public.f1_current_bootstrap_principal()));


--
-- Name: role_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.role_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: role_assignments role_assignments_context; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY role_assignments_context ON public.role_assignments USING ((organization_id = public.f1_current_context_org())) WITH CHECK ((organization_id = public.f1_current_context_org()));


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
('20260721120005'),
('20260721120004'),
('20260719120003'),
('20260719120002'),
('20260719120001');

