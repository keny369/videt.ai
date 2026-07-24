# frozen_string_literal: true

module F1
  # The single authoritative source of runtime database privileges
  # (schemas/POSTGRESQL_SCHEMA.md § Tenant Isolation And Database Roles).
  #
  # Rails dumps db/structure.sql with pg_dump -x -O, so it contains NO grants or
  # ownership; a database materialized from structure.sql exists structurally but
  # cannot run under f1_runtime, and — because structure.sql recreates functions
  # with the default PUBLIC EXECUTE — would also expose owner-only functions. This
  # module is the one place runtime privileges are defined. It is applied after
  # every schema load and migration (lib/tasks/f1_db.rake), so both the
  # migrate path and the structure-load path converge on the same grant state.
  #
  # Properties: idempotent (GRANT/REVOKE re-run safely); guarded by
  # to_regclass/to_regprocedure so it is safe on a partially built or empty
  # database; and privilege-only, so FORCE ROW LEVEL SECURITY is preserved.
  #
  # Values mirror the ratified role model exactly (verified against a
  # migration-built database). Update this module — and only this module — when a
  # table, function, or privilege changes.
  module RuntimeGrants
    module_function

    RUNTIME_ROLE = "f1_runtime"

    # table => the exact DML the runtime uses. The receipt store, the proof-key
    # table and the pretenant/tenant secrets are absent: they are reached only
    # through SECURITY DEFINER functions and carry no runtime grant.
    TABLE_PRIVILEGES = {
      # The self-service genesis inserts the Organization; suspend/reactivate/close
      # update it.
      "organizations"                     => "SELECT, INSERT, UPDATE",
      "accounts"                          => "SELECT, INSERT, UPDATE",
      "role_assignments"                  => "SELECT, INSERT, UPDATE",
      # ":314 ordered immutable approval records" — insert/read only.
      "role_assignment_approvals"         => "SELECT, INSERT",
      # Immutable decision record (:343): insert/read only.
      "role_expiry_block_decisions"       => "SELECT, INSERT",
      # The genesis Access Policy is written once at bootstrap and read thereafter;
      # its supersession is a later slice, so INSERT joins the sign-in SELECT.
      "access_policies"                   => "SELECT, INSERT",
      # The S-02 genesis roots. BillingEntity and the draft Project are written and
      # later transitioned (activation, closure), so they carry UPDATE; the policy
      # and Plan Assignment artifacts are activated in place at genesis and
      # superseded (not mutated) later, so they are insert/read here.
      "billing_entities"                  => "SELECT, INSERT, UPDATE",
      "plan_assignments"                  => "SELECT, INSERT, UPDATE",
      "entitlement_policies"              => "SELECT, INSERT, UPDATE",
      "projects"                          => "SELECT, INSERT, UPDATE",
      # S-04 registers a proposed Source and later slices transition it in place
      # (verify/activate/disable) and set its scope policy, so it carries UPDATE;
      # removal is a state transition to 'removed', never a row DELETE, so no
      # DELETE is granted.
      "sources"                           => "SELECT, INSERT, UPDATE",
      # F-03 Evidence is append-only: SELECT/INSERT, never UPDATE or DELETE. A trigger
      # refuses UPDATE/DELETE from every role; the missing grant is defence in depth.
      "evidence"                          => "SELECT, INSERT",
      "sessions"                          => "SELECT, INSERT, UPDATE",
      "invitations"                       => "SELECT, INSERT, UPDATE",
      "invitation_reference_registry"     => "SELECT, INSERT, UPDATE",
      "bootstrap_grants"                  => "SELECT, INSERT, UPDATE",
      "idempotency_records"               => "SELECT, INSERT, UPDATE",
      "command_executions"                => "SELECT, INSERT",
      "command_results"                   => "SELECT, INSERT",
      "pretenant_authorization_decisions" => "SELECT, INSERT",
      "audit_record_registry"             => "SELECT, INSERT",
      "event_registry"                    => "SELECT, INSERT",
      # Immutable authorization-decision record (T-IMM): insert/read only.
      "authorization_decisions"           => "SELECT, INSERT",
      # The durable timer authority. The runtime creates an action inside the
      # proved Organization context of the scheduling command and reads its own
      # Organization's rows; it holds NO UPDATE or DELETE, so every claim,
      # dispatch, settle, release and cancel must go through the restricted
      # SECURITY DEFINER transport functions below.
      "scheduled_actions"                 => "SELECT, INSERT"
    }.freeze

    # Every table has PUBLIC revoked as defence in depth (structure-load leaves
    # tables owner-only by default, but the migrate path and older PG defaults do
    # not guarantee it, and the receipt/secret tables must never be PUBLIC).
    REVOKE_PUBLIC_TABLES = (TABLE_PRIVILEGES.keys + %w[
      identity_receipt_nonces identity_receipt_consumptions f1_context_keys
      f1_encryption_key_versions f1_encrypted_records
    ]).freeze

    # Rails owns these outside our migrations; the runtime reads migration state.
    METADATA_TABLES = %w[schema_migrations ar_internal_metadata].freeze

    # F1 functions the runtime may execute (f1_context_proof is owner-only and
    # absent). pgcrypto functions are granted to PUBLIC by the extension and are
    # not managed here.
    RUNTIME_FUNCTIONS = [
      "f1_bootstrap_principal_uuid(bytea)",
      "f1_current_bootstrap_principal()",
      "f1_current_context_org()",
      "f1_enter_bootstrap_context(bytea, uuid)",
      "f1_enter_context(bytea, uuid, uuid)",
      "f1_consume_receipt_nonce(uuid, timestamptz, uuid, bytea, uuid, timestamptz, text, text)",
      "f1_resolve_invitation_reference(bytea)",
      "f1_resolve_invitation_org(bytea)",
      "f1_authenticate_session(uuid)",
      "f1_enter_org_context(uuid, uuid)",
      # The self-service genesis context: resolves the second self-service receipt
      # and enters a combined principal+real-Organization context so the Bootstrap
      # Grant and the tenant roots are both reachable in one transaction.
      "f1_enter_self_service_context(bytea, uuid, uuid)",
      # The execution-boundary Service Identity status predicate. Existence is
      # guaranteed by the ledger foreign keys; this is the separate question of
      # whether the identity is still permitted to act. Fixed boolean projection,
      # so it cannot enumerate the platform-control register.
      "f1_service_identity_active(uuid)",
      # F-02 key-ring READ boundary. The runtime may resolve the active version and
      # describe a version (state + non-secret fingerprint) to wrap/unwrap DEKs, but the
      # ring MATERIAL is out of band and the ring METADATA table carries no runtime grant.
      # The register/lifecycle mutations are owner-only and deliberately absent here.
      "f1_encryption_active_version(text)",
      "f1_encryption_describe_version(text, text)",
      # F-02 encrypted-record storage boundary. The runtime stores, fetches and destroys
      # envelopes by reference through these functions; it cannot touch the owner-only
      # table. Destroy is record-level (one reference) — not bulk key-version erasure.
      "f1_encrypted_record_put(text, text, text, text, text, text, text, text, bytea, bytea)",
      "f1_encrypted_record_get(uuid)",
      "f1_encrypted_record_destroy(uuid)",
      # F-02 rotation: rewrap re-wraps a record's DEK under the active version (guarded on
      # the expected version). The key-version retire/register/destroy mutations are
      # owner-only and absent here.
      "f1_encrypted_record_rewrap(uuid, text, text, bytea)"
    ].freeze

    # Platform-control authority, deliberately NOT in f1_runtime.
    #
    # schemas/POSTGRESQL_SCHEMA.md:175 requires the scheduler's dispatch function
    # to be "revoked from `PUBLIC`, granted only to `f1_platform_worker`"; :166
    # scopes scheduler leadership and dead-letter administration to
    # `f1_platform_worker` registered functions; :136 limits `f1_web` to
    # "registered browser/API tables and functions only"; and :143 requires every
    # reviewed restricted function to be "granted only to its named runtime role".
    #
    # These six are the only reachable mutations of `scheduled_actions` and they
    # read across every Organization as the owner, so an ordinary request-serving
    # connection must not be able to claim, dispatch, settle, release, sweep or
    # cancel scheduled work. The runtime keeps SELECT/INSERT on the table alone,
    # which is what the activation transaction needs and nothing more.
    PLATFORM_WORKER_ROLE = "f1_platform_worker"

    PLATFORM_WORKER_FUNCTIONS = [
      "f1_claim_due_scheduled_actions(uuid, integer, integer)",
      "f1_dispatch_scheduled_action(uuid, uuid, bigint, uuid, integer)",
      "f1_settle_scheduled_action(uuid, uuid, bigint, text, text)",
      "f1_release_scheduled_action_claim(uuid, uuid, bigint, text)",
      "f1_release_expired_scheduled_action_leases(integer)",
      "f1_cancel_scheduled_action(uuid, text)"
    ].freeze

    # Functions that must NOT be PUBLIC-executable. structure.sql load recreates
    # every function with the default PUBLIC EXECUTE, so these are re-revoked. The
    # remaining runtime functions deliberately retain their default PUBLIC EXECUTE
    # (they only read proof-validated context and are harmless), matching the
    # ratified model.
    REVOKE_PUBLIC_FUNCTIONS = [
      "f1_context_proof(text, text)",
      "f1_consume_receipt_nonce(uuid, timestamptz, uuid, bytea, uuid, timestamptz, text, text)",
      "f1_enter_bootstrap_context(bytea, uuid)",
      "f1_enter_context(bytea, uuid, uuid)",
      "f1_resolve_invitation_reference(bytea)",
      "f1_resolve_invitation_org(bytea)",
      "f1_authenticate_session(uuid)",
      "f1_enter_org_context(uuid, uuid)",
      "f1_enter_self_service_context(bytea, uuid, uuid)",
      "f1_service_identity_active(uuid)",
      # F-02: the read boundary is SECURITY DEFINER (re-revoke PUBLIC on structure-load);
      # the register mutation is owner-only — PUBLIC revoked and never granted anywhere.
      "f1_encryption_active_version(text)",
      "f1_encryption_describe_version(text, text)",
      "f1_encryption_register_active_version(text, text, bytea, text)",
      "f1_encrypted_record_put(text, text, text, text, text, text, text, text, bytea, bytea)",
      "f1_encrypted_record_get(uuid)",
      "f1_encrypted_record_destroy(uuid)",
      "f1_encrypted_record_rewrap(uuid, text, text, bytea)",
      # F-02 owner-only key-version mutations: PUBLIC revoked, never granted to a runtime role.
      # destroy_version is bulk cryptographic erasure and MUST stay unreachable from the runtime.
      "f1_encryption_retire_version(text, text)",
      "f1_encryption_destroy_version(text, text)"
    ].freeze + PLATFORM_WORKER_FUNCTIONS

    # The ordered, idempotent, guarded statements. Run as the schema owner.
    def statements
      stmts = []
      REVOKE_PUBLIC_TABLES.each { |t| stmts << table_guard(t, "REVOKE ALL ON public.#{t} FROM PUBLIC") }
      TABLE_PRIVILEGES.each { |t, priv| stmts << table_guard(t, "GRANT #{priv} ON public.#{t} TO #{RUNTIME_ROLE}") }
      METADATA_TABLES.each { |t| stmts << table_guard(t, "GRANT SELECT ON public.#{t} TO #{RUNTIME_ROLE}") }
      REVOKE_PUBLIC_FUNCTIONS.each { |fn| stmts << function_guard(fn, "REVOKE ALL ON FUNCTION public.#{fn} FROM PUBLIC") }
      RUNTIME_FUNCTIONS.each { |fn| stmts << function_guard(fn, "GRANT EXECUTE ON FUNCTION public.#{fn} TO #{RUNTIME_ROLE}") }
      # Explicitly withdraw the transport from the runtime group before granting
      # it to the platform worker, so a database provisioned by an earlier build
      # converges on the restricted posture rather than keeping a stale grant.
      PLATFORM_WORKER_FUNCTIONS.each do |fn|
        stmts << function_guard(fn, "REVOKE ALL ON FUNCTION public.#{fn} FROM #{RUNTIME_ROLE}")
        stmts << function_guard(fn, "GRANT EXECUTE ON FUNCTION public.#{fn} TO #{PLATFORM_WORKER_ROLE}")
      end
      stmts
    end

    # Apply every runtime grant idempotently on the given connection.
    def apply_all(connection)
      statements.each { |sql| connection.execute(sql) }
      statements.size
    end

    def table_guard(table, sql)
      "DO $$ BEGIN IF to_regclass('public.#{table}') IS NOT NULL THEN EXECUTE #{quote(sql)}; END IF; END $$;"
    end

    def function_guard(signature, sql)
      "DO $$ BEGIN IF to_regprocedure('public.#{signature}') IS NOT NULL THEN EXECUTE #{quote(sql)}; END IF; END $$;"
    end

    def quote(sql) = "'#{sql.gsub("'", "''")}'"
  end
end
