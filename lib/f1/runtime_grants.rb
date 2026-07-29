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
      # S-05 IssueVerificationChallenge inserts one pending Verification Request and
      # later S-05 limbs transition it in place (observation completion -> verified,
      # the expiry job -> expired, cancellation, and the cryptographic-deletion limb
      # that nulls the challenge material), so it carries UPDATE; there is no row
      # DELETE (deletion is cryptographic erasure of the F-02 envelope, an UPDATE).
      # Additive new-table grant (backwards-compatible extension, Foundation
      # Consumption Rule): no existing table's privileges change and FORCE RLS is
      # preserved. The challenge plaintext is never in this table; only the F-02
      # ciphertext reference, key reference and digest are.
      "verification_requests"             => "SELECT, INSERT, UPDATE",
      # S-05-004 ReserveVerificationAttempt inserts one `reserved` attempt and later
      # S-05 limbs transition it in place (reserved -> running -> completed, or
      # quarantined), so it carries SELECT/INSERT/UPDATE; there is no row DELETE (an
      # attempt is never physically removed — quarantine and terminal are state
      # transitions). Additive new-table grant (backwards-compatible extension,
      # Foundation Consumption Rule / ADR-029): no existing table's privileges change
      # and FORCE RLS is preserved. The row carries only the restricted observation
      # digest and enum/status fields — never the plaintext token or raw content.
      "verification_attempts"             => "SELECT, INSERT, UPDATE",
      # F-03 Evidence is append-only: SELECT/INSERT, never UPDATE or DELETE. A trigger
      # refuses UPDATE/DELETE from every role; the missing grant is defence in depth.
      "evidence"                          => "SELECT, INSERT",
      # S-05-006 materializes the immutable source-scope-interim-v1 policy in the matched
      # success commit and reads it thereafter: SELECT/INSERT, never UPDATE or DELETE (a
      # T-IMM version table — a correction is a new version; an immutability trigger
      # refuses UPDATE/DELETE and the missing grant is defence in depth). Additive
      # new-table grant (backwards-compatible extension, ADR-029); no existing grant
      # changes and FORCE RLS is preserved.
      "source_scope_policies"             => "SELECT, INSERT",
      "crawl_policies"                    => "SELECT, INSERT, UPDATE",
      "crawls"                            => "SELECT, INSERT, UPDATE",
      "crawl_sources"                     => "SELECT, INSERT",
      "evaluations"                       => "SELECT, INSERT, UPDATE",
      # S-07-003 StartCrawl: the immutable orchestration context for an accepted root start (T-IMM;
      # a trigger refuses UPDATE/DELETE, the missing grant is defence in depth). Additive new-table
      # grant (ADR-029); no existing grant changes and FORCE RLS is preserved.
      "evaluation_orchestration_contexts" => "SELECT, INSERT",
      # S-07-004 crawl frontier. Entries are T-MUT (admitted, claimed, discarded in place, never
      # deleted — a discard is a state, not a row removal); occurrences are T-IMM. Both are
      # implementation-owned technical execution records (MTX-030 persistence_model), never product
      # entities. Additive new-table grants (ADR-029); no existing grant changes and FORCE RLS is
      # preserved.
      "crawl_frontier_entries"            => "SELECT, INSERT, UPDATE",
      "crawl_frontier_occurrences"        => "SELECT, INSERT",
      # S-07-005 per-host gate. T-MUT: the rate/concurrency counters change on every claim and
      # release and the robots record transitions to its write-once terminal decision, so
      # SELECT/INSERT/UPDATE — never DELETE (a gate is never removed within a run). Additive
      # new-table grant (ADR-029); no existing grant changes and FORCE RLS is preserved.
      "crawl_host_gates"                  => "SELECT, INSERT, UPDATE",
      # S-07-007 run-wide budget accounting and the attempt record. `crawl_budget_counters` is
      # T-MUT — :442's reserve/commit/release protocol UPDATEs the row on every attempt — and
      # `fetch_attempts` is insert-then-terminalise, so both need UPDATE and neither ever needs
      # DELETE: an attempt that was made is a fact, and a run's byte total is never un-spent.
      # Additive new-table grants (ADR-029); no existing grant changes and FORCE RLS is preserved.
      "crawl_budget_counters"             => "SELECT, INSERT, UPDATE",
      "fetch_attempts"                    => "SELECT, INSERT, UPDATE",
      # S-07-008 limit decisions. T-IMM: an observation is written once and never revised, so
      # SELECT/INSERT only — the missing UPDATE is defence in depth behind the trigger, not a
      # substitute for it. Additive new-table grant (ADR-029); FORCE RLS preserved.
      "crawl_limit_decisions"             => "SELECT, INSERT",
      # S-07-008 sitemap-document charge ledger. `UNIQUE (crawl_id, canonical_url_sha256)` is
      # :437's "distinct canonical sitemap URLs" made durable across scheduler re-entry. T-IMM for
      # the same reason as the decisions: releasing a charge would let one URL be charged twice.
      "crawl_sitemap_document_charges"    => "SELECT, INSERT",
      # F-05 entitlement reservation subsystem (entitlement-interim-v1; DECISIONS ADR-069).
      # Additive new-table grants (Foundation Consumption Rule / ADR-029): no existing grant
      # changes and FORCE RLS is preserved. The counter windows accumulate (UPDATE the counter
      # columns), reservations move through their lifecycle (UPDATE) and commit intents transition
      # pending -> committed/released (UPDATE); the immutable Decision and lease-heartbeat records
      # are SELECT/INSERT only (T-IMM triggers refuse UPDATE/DELETE, the missing grant is defence
      # in depth); no row DELETE anywhere.
      "entitlement_counter_windows"       => "SELECT, INSERT, UPDATE",
      "entitlement_decisions"             => "SELECT, INSERT",
      "entitlement_reservations"          => "SELECT, INSERT, UPDATE",
      "entitlement_lease_heartbeats"      => "SELECT, INSERT",
      "entitlement_commit_intents"        => "SELECT, INSERT, UPDATE",
      "source_scope_change_requests"      => "SELECT, INSERT, UPDATE",
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
      work_dispatch_bindings
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
      # F-04: dispatch now resolves the Work Dispatch Binding by work_id (uuid) at the
      # envelope's claim generation (bigint), transferring to the worker owner (uuid).
      "f1_dispatch_scheduled_action(uuid, bigint, uuid, integer)",
      # F-04: the infrastructure dispatch-retry / redis_dispatch_exhausted transition.
      "f1_fail_scheduled_action_dispatch(uuid, uuid, bigint)",
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
