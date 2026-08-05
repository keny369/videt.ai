# frozen_string_literal: true

module AutonomousBuild
  # THE S-07-009 MUTATION SET, IN THE REPOSITORY (D5 family 5).
  #
  # The ledger is REGENERATED from this file by `f1:mutations:regenerate`, never edited by hand. Each
  # entry names an exact substitution and the proof that must reject it, so the repository can replay
  # the whole set and recompute every verdict from first principles.
  #
  # WHAT IS AND IS NOT HERE. These are file substitutions, which the harness can apply and restore
  # deterministically. D4's mutations act on a PostgreSQL trigger definition rather than on a file and
  # are driven by `spec/persistence/crawl_terminal_fact_closure_spec.rb` plus the separate trigger
  # battery recorded in the completion report; they are listed here as `mechanism: "trigger"` so the
  # set is complete as a record even though the harness replays only the file ones.
  module S07009MutationSet
    RUN_DEADLINE = "app/platform/run_deadline.rb"
    ADMISSION = "app/workflows/wf005/admission.rb"
    DRIVER = "app/workflows/wf005/crawl_driver.rb"
    BOUNDED = "app/workflows/wf005/run_bounded_outbound.rb"
    CANCEL = "app/workflows/wf005/handlers/cancel_crawl.rb"
    STORE = "app/contexts/identity_access/infrastructure/crawl_start_store.rb"
    PROBE = "spec/support/execution_probe.rb"
    SENTINEL = "spec/support/authority_sentinel.rb"
    CENSUS = "spec/support/governed_write_sentinel.rb"
    CRAWL_STORE = "app/contexts/identity_access/infrastructure/crawl_store.rb"
    POLICY_STORE = "app/contexts/identity_access/infrastructure/crawl_policy_store.rb"
    QUEUE_HANDLER = "app/workflows/wf005/handlers/queue_crawl.rb"
    POLICY_HANDLER = "app/workflows/wf005/handlers/activate_crawl_policy.rb"
    # D7
    DOOR = "spec/support/protected_effect_door.rb"
    ATTESTATION = "app/workflows/wf005/authority_attestation.rb"
    WRITE_AUTHORITY = "app/contexts/identity_access/authorization/write_authority.rb"

    DEADLINE_PROOF = "spec/platform/run_deadline_spec.rb"
    GATES_PROOF = "spec/acceptance/wf005_deadline_gates_spec.rb"
    AUTHORITY_PROOF = "spec/acceptance/wf005_cancel_authority_write_spec.rb"
    CANCEL_PROOF = "spec/acceptance/wf005_cancel_crawl_spec.rb"
    PROBE_PROOF = "spec/architecture/execution_probe_spec.rb"
    SENTINEL_PROOF = "spec/architecture/authority_sentinel_spec.rb"
    CLOSED_FACT_PROOF = "spec/acceptance/wf005_closed_fact_set_spec.rb"
    QUEUE_PROOF = "spec/acceptance/wf005_queue_crawl_spec.rb"
    POLICY_PROOF = "spec/acceptance/wf005_activate_crawl_policy_spec.rb"
    DOOR_PROOF = "spec/architecture/protected_effect_door_spec.rb"
    LOCK_PROOF = "spec/acceptance/wf005_authority_lock_concurrency_spec.rb"
    CAPABILITY_PROOF = "spec/acceptance/wf005_capability_write_authority_spec.rb"
    # ROUND 15
    BATTERY_PROOF = "spec/acceptance/wf005_grant_battery_spec.rb"
    LIFETIME_PROOF = "spec/acceptance/wf005_grant_lifetime_spec.rb"
    ORDER_PROOF = "spec/acceptance/wf005_authority_lock_order_spec.rb"
    CLASSIFY_PROOF = "spec/automation/unit/mutation_harness_classification_spec.rb"
    REVOKE_HANDLER = "app/workflows/wf013/handlers/revoke_role_assignment.rb"
    EXPIRE_HANDLER = "app/workflows/wf013/handlers/expire_role_assignment.rb"
    HARNESS = "automation/lib/autonomous_build/mutation_harness.rb"

    ENTRIES = [
      # ---- D1/D2: the dead question, and the ones nothing pinned -------------------------------
      { id: "d2-beyond-constant", blocker: "D2/R10-3", file: RUN_DEADLINE, proof: DEADLINE_PROOF,
        description: "`beyond?` always false — round 10 shipped it unproved and this survived the suite",
        from: "    def beyond?(instant) = PgInstant.utc(instant) > @instant",
        to: "    def beyond?(_instant) = false", expectation: "kill" },
      { id: "d2-not-after-unclamped", blocker: "D2/R10-3", file: RUN_DEADLINE, proof: DEADLINE_PROOF,
        description: "`not_after` stops clamping to the deadline",
        from: "      candidate > @instant ? @instant : candidate", to: "      candidate",
        expectation: "kill" },
      { id: "d2-at-weakened", blocker: "D2/R10-3", file: RUN_DEADLINE, proof: DEADLINE_PROOF,
        description: "`at?` weakened from equality to inequality, deleting :458's third sentence",
        from: "    def at?(instant) = PgInstant.utc(instant) == @instant",
        to: "    def at?(instant) = PgInstant.utc(instant) <= @instant", expectation: "kill" },
      { id: "d2-none-incomplete", blocker: "D2/R10-4", file: RUN_DEADLINE, proof: DEADLINE_PROOF,
        description: "NONE loses a question its declared callers ask, restoring the NoMethodError",
        from: "      def none.beyond?(_instant) = false\n", to: "", expectation: "kill" },
      { id: "d1-dead-method-returns", blocker: "D1", file: RUN_DEADLINE, proof: DEADLINE_PROOF,
        description: "the dead `iso8601` returns with no production caller",
        from: "    def instant_for_transport = @instant",
        to: "    def iso8601(precision = 6) = @instant.iso8601(precision)\n\n    def instant_for_transport = @instant",
        expectation: "kill" },

      # ---- D3: authority as a conjunct of the cancellation write --------------------------------
      { id: "d3-conjunct-removed", blocker: "D3/R10-10", file: STORE, proof: AUTHORITY_PROOF,
        description: "the epoch conjunct removed from the write, accepting another actor's authority",
        from: "              AND EXISTS (SELECT 1 FROM epoch_authority)\n", to: "", expectation: "kill" },
      { id: "d3-epoch-inequality", blocker: "D3/R10-10", file: STORE, proof: AUTHORITY_PROOF,
        description: "equality weakened to >=, accepting a stale epoch",
        from: "WHERE id = $5::uuid AND authorization_epoch = $4::bigint",
        to: "WHERE id = $5::uuid AND authorization_epoch >= $4::bigint", expectation: "kill" },
      { id: "d3-authority-always-true", blocker: "D3/R10-10", file: STORE, proof: AUTHORITY_PROOF,
        description: "the authority CTE made unconditionally true",
        # EVERY PARAMETER STAYS BOUND (round-16 architecture finding A16-1). `SELECT 1` alone orphans
        # $4 and $5, so PostgreSQL refuses the statement with `IndeterminateDatatype` and the kill
        # says only that the statement no longer type-checks — including the POSITIVE control, which
        # then cannot tell a refusing write from a broken one. This form is unconditionally true and
        # well-typed, so the proof fails on the epoch conjunct's absence.
        from: "            SELECT 1 FROM organizations\n            WHERE id = $5::uuid AND authorization_epoch = $4::bigint",
        to: "            SELECT 1 WHERE $5::uuid IS NOT NULL AND $4::bigint IS NOT NULL",
        expectation: "kill" },
      { id: "d3-wrong-organization", blocker: "D3/R10-10", file: STORE, proof: AUTHORITY_PROOF,
        description: "the epoch compared against the wrong organization, rejecting valid ownership",
        from: "WHERE id = $5::uuid AND authorization_epoch = $4::bigint",
        to: "WHERE id = $1::uuid AND authorization_epoch = $4::bigint", expectation: "kill" },
      { id: "d3-authorized-independent", blocker: "D3/R10-10", file: STORE, proof: AUTHORITY_PROOF,
        description: "`authorized` reported independently of the write's own predicate",
        from: "          SELECT (SELECT count(*) FROM epoch_authority) AS epoch_authorized,",
        to: "          SELECT 1 AS epoch_authorized,", expectation: "kill" },
      { id: "d3-denial-swallowed", blocker: "D3/R10-10", file: CANCEL, proof: AUTHORITY_PROOF,
        description: "the handler treats an unauthorized write as success",
        from: "          return denied(d, \"crawl_cancel_unauthorized\") unless outcome[:authorized]\n",
        to: "", expectation: "kill" },
      { id: "d3-branches-reversed", blocker: "D3/R10-10", file: CANCEL, proof: AUTHORITY_PROOF,
        description: "the denial and the corruption raise reversed, reporting revocation as corruption",
        from: "          return denied(d, \"crawl_cancel_unauthorized\") unless outcome[:authorized]\n          raise Platform::InvariantViolation, \"crawl cancellation lost its serialized transition\" if outcome[:moved].zero?",
        to: "          raise Platform::InvariantViolation, \"crawl cancellation lost its serialized transition\" if outcome[:moved].zero?\n          return denied(d, \"crawl_cancel_unauthorized\") unless outcome[:authorized]",
        expectation: "kill" },
      { id: "d3-write-carries-another-capability", blocker: "D3/R10-10, FU-48", file: CANCEL,
        proof: CANCEL_PROOF,
        description: "the write carries a capability the attestation was not minted for, so the " \
                     "attestation and the statement no longer describe the same authority",
        from: "            actor: d[:actor], decision: d[:decision], capability: CAPABILITY\n          )\n          Wf005::AuthorityAttestation.require!(attestation, connection: d[:pg], authority:)",
        to: "            actor: d[:actor], decision: d[:decision], capability: \"crawl.recover\"\n          )\n          Wf005::AuthorityAttestation.require!(attestation, connection: d[:pg], authority:)",
        expectation: "kill" },
      # THE BOUND PROOF NAMES WHAT ACTUALLY REJECTS IT. The first regeneration bound this to the
      # cancel spec alone and it SURVIVED — the lock's absence is not observable from a single
      # command, only from two racing it. A ledger row whose proof cannot reject its mutation is a
      # false row, and the fix is the correct proof rather than a weaker expectation.
      { id: "d3-lock-removed", blocker: "D3/R10-10", file: CANCEL,
        proof: "#{CANCEL_PROOF} spec/acceptance/wf005_start_cancel_concurrency_spec.rb " \
               "spec/acceptance/wf005_admission_terminal_concurrency_spec.rb",
        description: "lock_frontier removed, so there is no wait for authority to change during",
        from: "          IdentityAccess::Infrastructure::CrawlFrontierStore.new(d[:pg]).lock_frontier(command.crawl_id)\n",
        to: "", expectation: "kill" },

      # ---- D5 family 1: caller-bound invocation ------------------------------------------------
      { id: "f1-admission-inverted", blocker: "R10-17", file: ADMISSION, proof: GATES_PROOF,
        description: "R10-17's exact inversion of admission's gate through instant_for_transport",
        from: "        Platform::RunDeadline.of(crawl).expired?(at: now)",
        to: "        d = Platform::RunDeadline.of(crawl)\n        d.equal?(Platform::RunDeadline::NONE) ? false : d.instant_for_transport <= Platform::PgInstant.utc(now)",
        expectation: "kill" },
      { id: "f1-driver-reimplemented", blocker: "R9-7", file: DRIVER, proof: GATES_PROOF,
        description: "the pass's gate reimplemented behind one endpoint method",
        from: "        !Platform::RunDeadline.of(crawl).expired?(at: now)",
        to: "        ceiling = crawl[\"deadline_at\"]\n        ceiling.nil? || Platform::PgInstant.utc(now) <= Platform::PgInstant.utc(ceiling)",
        expectation: "kill" },
      { id: "f1-bounded-respelled", blocker: ":442", file: BOUNDED, proof: GATES_PROOF,
        description: "the request-start bound respelled so the owner is never consulted",
        from: "        return unless @deadline.expired?(at: @clock.call)",
        to: "        return unless @deadline.instant_for_transport && Platform::PgInstant.utc(@deadline.instant_for_transport) <= Platform::PgInstant.utc(@clock.call)",
        expectation: "kill" },
      { id: "f1-gate-delegates", blocker: "R10-17", file: ADMISSION, proof: GATES_PROOF,
        description: "the gate delegates to a helper, so the caller itself never consults the owner",
        from: "      def wall_clock_expired?(crawl, now)\n        Platform::RunDeadline.of(crawl).expired?(at: now)\n      end",
        to: "      def wall_clock_expired?(crawl, now) = deadline_reached?(crawl, now)\n\n      def deadline_reached?(crawl, now)\n        Platform::RunDeadline.of(crawl).expired?(at: now)\n      end",
        expectation: "kill" },
      { id: "f1-caller-binding-dropped", blocker: "R10-17", file: PROBE, proof: PROBE_PROOF,
        description: "caller binding dropped from the matcher, restoring 'the owner ran somewhere'",
        from: "    @site.nil? || observation.evaluated_from?(target, @site, thread: @thread || Thread.current)",
        to: "    true", expectation: "kill" },
      { id: "f1-thread-identity-dropped", blocker: "R10-17", file: PROBE, proof: PROBE_PROOF,
        description: "thread identity dropped, so another thread's invocation satisfies the proof",
        from: "      invocations(target).any? { |i| site_matches?(i[:site], site) && i[:thread] == thread.object_id }",
        to: "      invocations(target).any? { |i| site_matches?(i[:site], site) }", expectation: "kill" },

      # ---- D5 family 3: RowInstantGuard's claim, re-based ---------------------------------------
      { id: "f3-rebuilt-via-local", blocker: "R10-16", file: ADMISSION, proof: GATES_PROOF,
        description: "the comparison rebuilt from the raw row via a local variable",
        from: "        Platform::RunDeadline.of(crawl).expired?(at: now)",
        to: "        raw = crawl[\"deadline_at\"]\n        raw.nil? ? false : Platform::PgInstant.utc(raw) <= Platform::PgInstant.utc(now)",
        expectation: "kill" },
      { id: "f3-rebuilt-via-container", blocker: "R10-16", file: ADMISSION, proof: GATES_PROOF,
        description: "rebuilt via multiple assignment and a container",
        from: "        Platform::RunDeadline.of(crawl).expired?(at: now)",
        to: "        pair = [crawl[\"deadline_at\"], now]\n        a, b = pair\n        a.nil? ? false : Platform::PgInstant.utc(a) <= Platform::PgInstant.utc(b)",
        expectation: "kill" },
      { id: "f3-rebuilt-via-block-pass", blocker: "R10-16", file: ADMISSION, proof: GATES_PROOF,
        description: "rebuilt via a block-pass form the guard's enumeration could not cover",
        from: "        Platform::RunDeadline.of(crawl).expired?(at: now)",
        to: "        [crawl[\"deadline_at\"]].compact.map(&Platform::PgInstant.method(:utc)).any? { |d| d <= Platform::PgInstant.utc(now) }",
        expectation: "kill" },

      # ---- D5 family 2: the narrow owned door ---------------------------------------------------
      { id: "f2-census-door-removed", blocker: "R10-7", file: CENSUS, proof: CLOSED_FACT_PROOF,
        description: "the census hook removed, so the instrument observes nothing",
        from: "      PG::Connection.prepend(Instrumentation)\n", to: "", expectation: "kill" },
      { id: "f2-refusals-unobserved", blocker: "R10-7", file: CENSUS, proof: CLOSED_FACT_PROOF,
        description: "the hook stops observing refusals, so a trigger-refused write is invisible",
        from: "    rescue PG::Error => e\n      GovernedWriteSentinel.observe(sql, e)\n      raise",
        to: "    rescue PG::Error\n      raise", expectation: "kill" },

      # ---- D5 family 4: runtime discovery and thread-local accounting ---------------------------
      # RE-POINTED IN ROUND 15. Discovery is no longer a directory glob to narrow — it is a namespace
      # walk (A15-2) — so the mutation is the narrowing that walk admits: stop recursing, which is
      # exactly the escape the glob had.
      { id: "f4-discovery-narrowed", blocker: "R10-9, A15-2", file: SENTINEL, proof: SENTINEL_PROOF,
        description: "discovery stops recursing into nested namespaces, so a handler one module " \
                     "deeper is silently outside the rule",
        from: "        elsif value.is_a?(Module) then handlers_under(value)\n",
        to: "        elsif value.is_a?(Module) then []\n",
        expectation: "kill" },
      { id: "f4-accounting-global", blocker: "R10-11", file: SENTINEL, proof: SENTINEL_PROOF,
        description: "accounting returned to process-global state, so threads corrupt each other",
        from: "    def frame = (Thread.current[:authority_sentinel_frame] ||= { depth: 0 })",
        to: "    def frame = (@global_frame ||= { depth: 0 })", expectation: "kill" },
      { id: "f4-empty-census-accepted", blocker: "R10-9", file: SENTINEL, proof: SENTINEL_PROOF,
        description: "the empty-census guard neutered, so a blind run reports success",
        from: "      if commands.zero?", to: "      if false", expectation: "kill" },
      { id: "f4-frame-not-restored", blocker: "R10-11", file: SENTINEL, proof: SENTINEL_PROOF,
        description: "the frame is not restored on exit, so nesting corrupts the outer command",
        from: "      f.replace(outer)", to: "      f", expectation: "kill" },

      # ---- D5 family 6: the probe --------------------------------------------------------------
      { id: "f6-source-location-discriminator", blocker: "R10-21", file: PROBE, proof: PROBE_PROOF,
        description: "the round-11 discriminator restored: source_location, which accepts attr_reader",
        from: "      return :ruby if RubyVM::InstructionSequence.of(method)\n      return :accessor if method.source_location # attr_* and friends: a location, but no body to trace",
        to: "      return :ruby if method.source_location", expectation: "kill" },
      { id: "f6-refusal-removed", blocker: "R10-21", file: PROBE, proof: PROBE_PROOF,
        description: "the refusal removed entirely, restoring R10-21",
        from: "      refuse_unobservable!\n", to: "", expectation: "kill" },
      { id: "f6-kind-forced-ruby", blocker: "R10-21", file: PROBE, proof: PROBE_PROOF,
        description: "`kind` forced to :ruby, so every unobservable target is accepted",
        from: "      return :ruby if RubyVM::InstructionSequence.of(method)", to: "      return :ruby if true",
        expectation: "kill" },
      # ---- D6: write-level authority for QueueCrawl and ActivateCrawlPolicy ---------------------
      { id: "d6-q-predicate-removed", blocker: "D6", file: CRAWL_STORE, proof: QUEUE_PROOF,
        description: "the authority predicate removed from the queue write",
        from: "            WHERE EXISTS (SELECT 1 FROM epoch_authority)\n              AND EXISTS (SELECT 1 FROM capability_authority)\n",
        to: "            WHERE true\n", expectation: "kill" },
      { id: "d6-q-predicate-inverted", blocker: "D6", file: CRAWL_STORE, proof: QUEUE_PROOF,
        description: "the authority predicate inverted, admitting exactly the revoked actor",
        from: "WHERE id = $4::uuid AND authorization_epoch = $14::bigint",
        to: "WHERE id = $4::uuid AND authorization_epoch <> $14::bigint", expectation: "kill" },
      { id: "d6-q-wrong-epoch-column", blocker: "D6", file: CRAWL_STORE, proof: QUEUE_PROOF,
        description: "the epoch compared against an unrelated column",
        from: "WHERE id = $4::uuid AND authorization_epoch = $14::bigint",
        to: "WHERE id = $4::uuid AND state_version = $14::bigint", expectation: "kill" },
      { id: "d6-q-wrong-row", blocker: "D6", file: CRAWL_STORE, proof: QUEUE_PROOF,
        description: "the predicate applied to the wrong row (project id in place of organization id)",
        from: "WHERE id = $4::uuid AND authorization_epoch = $14::bigint",
        to: "WHERE id = $5::uuid AND authorization_epoch = $14::bigint", expectation: "kill" },
      { id: "d6-q-stale-captured-epoch", blocker: "D6", file: QUEUE_HANDLER, proof: QUEUE_PROOF,
        description: "a stale captured epoch passed to the write",
        from: "            authority:,",
        to: "            authority: IdentityAccess::Authorization::WriteAuthority.new(**authority.to_h.merge(epoch: 0)),",
        expectation: "kill" },
      { id: "d6-q-handler-accepts-unauthorized", blocker: "D6", file: QUEUE_HANDLER, proof: QUEUE_PROOF,
        description: "the handler stops translating an unauthorised write into its domain denial",
        from: "          return denied(d, \"crawl_trigger_unauthorized\") unless queued[:authorized]\n",
        to: "", expectation: "kill" },
      { id: "d6-q-ruby-recheck-deleted", blocker: "D6", file: QUEUE_HANDLER, proof: QUEUE_PROOF,
        description: "the handler's Ruby post-wait recheck deleted entirely; the write must still own safety",
        from: "          if attestation.nil?\n            return deny(**denial_args(d), resource_id: command.project_id,\n                        outward: \"crawl_trigger_unauthorized\", internal: \"crawl_trigger_unauthorized\")\n          end\n",
        to: "", expectation: "kill" },
      { id: "d6-a-predicate-removed", blocker: "D6", file: POLICY_STORE, proof: POLICY_PROOF,
        description: "the authority predicate removed from the activation statement",
        # $13 STAYS REFERENCED (A16-1): dropping it outright orphaned the parameter and the statement
        # died of `IndeterminateDatatype` before the write was attempted.
        from: "            WHERE id = $4::uuid AND authorization_epoch = $13::bigint",
        to: "            WHERE id = $4::uuid AND ($13::bigint IS NULL OR $13::bigint IS NOT NULL)",
        expectation: "kill" },
      { id: "d6-a-insert-unconditional", blocker: "D6", file: POLICY_STORE, proof: POLICY_PROOF,
        description: "the insert made unconditional, permitting a partial transition",
        from: "            WHERE EXISTS (SELECT 1 FROM authority)\n              AND ($8::uuid IS NULL OR EXISTS (SELECT 1 FROM superseded))",
        to: "            WHERE true", expectation: "kill" },
      { id: "d6-a-supersede-unconditional", blocker: "D6", file: POLICY_STORE, proof: POLICY_PROOF,
        description: "the supersede made unconditional, so half the transition can commit on revoked authority",
        from: "              AND EXISTS (SELECT 1 FROM authority)\n            RETURNING 1",
        to: "            RETURNING 1", expectation: "kill" },
      { id: "d6-a-conjunction-to-disjunction", blocker: "D6", file: POLICY_STORE, proof: POLICY_PROOF,
        description: "the insert's conjunction weakened to a disjunction",
        from: "            WHERE EXISTS (SELECT 1 FROM authority)\n              AND ($8::uuid IS NULL OR EXISTS (SELECT 1 FROM superseded))",
        to: "            WHERE EXISTS (SELECT 1 FROM authority)\n              OR ($8::uuid IS NULL OR EXISTS (SELECT 1 FROM superseded))",
        expectation: "kill" },
      { id: "d6-a-state-predicate-omitted", blocker: "D6", file: POLICY_STORE, proof: POLICY_PROOF,
        description: "the expected-version predicate omitted from the supersede",
        from: "AND id = $8::uuid AND state = 'active'\n              AND state_version = $12::int",
        to: "AND id = $8::uuid AND state = 'active'", expectation: "kill" },
      { id: "d6-a-wrong-organization", blocker: "D6", file: POLICY_STORE, proof: POLICY_PROOF,
        description: "the predicate applied to the wrong row",
        from: "            WHERE id = $4::uuid AND authorization_epoch = $13::bigint",
        to: "            WHERE id = $5::uuid AND authorization_epoch = $13::bigint", expectation: "kill" },
      { id: "d6-a-ledger-before-guard", blocker: "D6", file: POLICY_HANDLER, proof: POLICY_PROOF,
        description: "the durable ledger writes hoisted above the guarded write, so a refused " \
                     "activation commits a command_execution naming a policy never created",
        from: "          write_execution(store, command, ctx, org, ids[:execution], ids[:policy], actor, request_sha256,\n                          key_digest, now, ACTION)\n          write_authorization_decision(d[:auth_store], ids[:decision], ctx, command, actor, d[:decision], now,\n                                       ids[:policy], ACTION)\n",
        to: "", expectation: "kill" },
      { id: "f4-human-door-removed", blocker: "R10-9", file: SENTINEL, proof: SENTINEL_PROOF,
        description: "AuthoritySentinel's human-authorization door removed, so its antecedent is " \
                     "never satisfied and judge returns at its first guard for every command",
        from: "      IdentityAccess::Authorization::CommandAuthorizer.prepend(AuthenticationObserver)\n",
        to: "", expectation: "kill" },
      { id: "d6-a-outcomes-collapsed", blocker: "D6", file: POLICY_HANDLER, proof: POLICY_PROOF,
        description: "the domain denial and the lost-serialization raise collapsed into one",
        from: "          return denied(d, \"crawl_policy_unauthorized\") unless applied[:authorized]\n          raise LostRace if current && applied[:superseded].zero?",
        to: "          raise LostRace if current && applied[:superseded].zero?", expectation: "kill" },

      # ---- D7: the antecedent, the door, the lock strength, and FU-48 --------------------------
      #
      # WHAT EACH FAMILY FALSIFIES. The antecedent is the tranche's central completeness mechanism, so
      # every component it now rests on gets a mutation that removes or weakens it INDEPENDENTLY:
      # the door that observes a protected side effect, the catalogue classification on each side,
      # the lock strength that makes the authority read lock-based, both authority limbs at all three
      # writes, the attestation binding, the handler's own pre-lock refusal, and idempotent replay.

      # -- the door: how a protected side effect is observed --
      { id: "d7-door-regex-restored", blocker: "D7", file: DOOR, proof: DOOR_PROOF,
        description: "the planner replaced by the HEAD verb regex, which counts SELECT ... FOR UPDATE " \
                     "as a write and is exactly how a replay came to satisfy the antecedent",
        from: "      json = mutex.synchronize do\n        connection.exec(\"EXPLAIN (GENERIC_PLAN, FORMAT JSON) \#{text}\").getvalue(0, 0)\n      end\n      modify_table_nodes(JSON.parse(json))",
        to: "      return [] unless text.match?(/\\\\b(?:INSERT\\\\s+INTO|UPDATE|DELETE\\\\s+FROM)\\\\b/i)\n\n      [Effect.new(operation: \"Update\", relation: text[/\\\\b(?:INTO|UPDATE|FROM)\\\\s+\\\"?(\\\\w+)/i, 1])]",
        expectation: "kill" },
      { id: "d7-door-anchored", blocker: "D7", file: DOOR, proof: DOOR_PROOF,
        description: "the door anchored to the start of the statement, the FIRST historical form, " \
                     "which is blind to every CTE-shaped write and so to all three protected writes",
        from: "      computed = plan(text)",
        to: "      return (plans[text] = []) unless text.strip.match?(/\\\\A(?:INSERT|UPDATE|DELETE)\\\\b/i)\n\n      computed = plan(text)",
        expectation: "kill" },
      { id: "d7-door-hook-removed", blocker: "D7", file: SENTINEL, proof: DOOR_PROOF,
        description: "the statement door removed, so no protected side effect is ever observed",
        from: "      PG::Connection.prepend(StatementObserver)\n", to: "", expectation: "kill" },
      { id: "d7-door-unknown-read-as-empty", blocker: "D7", file: DOOR, proof: DOOR_PROOF,
        description: "a statement the planner could not answer for is reported as modifying nothing, " \
                     "so a blind spot reads as a read instead of failing the run",
        from: "      reconnect_if_dead(e)\n      nil", to: "      reconnect_if_dead(e)\n      []",
        expectation: "kill" },

      # -- the classification, on both sides --
      { id: "d7-classification-all-governed", blocker: "D7", file: DOOR, proof: DOOR_PROOF,
        description: "every relation classified as a product fact, so the command-evidence ledgers " \
                     "are misclassified and the antecedent is the over-broad one D7 removed",
        from: "    def governed?(relation) = governed_relations.include?(relation)",
        to: "    def governed?(relation) = !relation.nil?", expectation: "kill" },
      { id: "d7-classification-none-governed", blocker: "D7", file: DOOR, proof: DOOR_PROOF,
        description: "no relation classified as a product fact, so a genuine governed write is never " \
                     "observed and the invariant is switched off while reporting success",
        from: "    def governed?(relation) = governed_relations.include?(relation)",
        to: "    def governed?(_relation) = false", expectation: "kill" },
      { id: "d7-classification-not-derived", blocker: "D7", file: DOOR, proof: DOOR_PROOF,
        description: "the governed set stops being read from the catalogue and becomes a list, so a "\
                     "guarded relation a later tranche adds never joins it",
        from: "            SELECT DISTINCT c.relname\n            FROM pg_trigger t\n"\
              "            JOIN pg_class c ON c.oid = t.tgrelid\n"\
              "            JOIN pg_namespace n ON n.oid = c.relnamespace\n"\
              "            WHERE NOT t.tgisinternal AND n.nspname = 'public'\n",
        to: "            SELECT unnest(ARRAY['crawls', 'crawl_policies']) AS relname\n",
        expectation: "kill" },
      { id: "d7-census-not-recorded", blocker: "D7", file: SENTINEL, proof: DOOR_PROOF,
        description: "the per-command relation census stops being recorded, so the classification's " \
                     "own gate has nothing to read back and passes on an empty population",
        from: "      f[:relations].uniq.each do |(relation, operation)|",
        to: "      [].each do |(relation, operation)|", expectation: "kill" },

      # -- the antecedent itself --
      { id: "d7-antecedent-any-write", blocker: "D7", file: SENTINEL, proof: DOOR_PROOF,
        description: "the antecedent widened back from a protected side effect to any statement, " \
                     "which is the rule that fired on an idempotent replay",
        from: "      governed = effects.count { |e| ProtectedEffectDoor.governed?(e.relation) }",
        to: "      governed = effects.length", expectation: "kill" },
      { id: "d7-antecedent-dropped", blocker: "D7", file: SENTINEL, proof: DOOR_PROOF,
        description: "the antecedent's governed-write clause deleted, so every successful " \
                     "human-authorized command satisfies it, replays included",
        from: "      return unless f[:governed].positive?\n", to: "", expectation: "kill" },

      # -- the lock strength, at all three writes --
      { id: "d7-cancel-lock-key-share", blocker: "D7", file: STORE, proof: LOCK_PROOF,
        description: "the cancellation's authority read downgraded to FOR KEY SHARE, which does NOT " \
                     "conflict with a non-key epoch advance — the round-two repair, measured",
        from: "            FOR SHARE\n", to: "            FOR KEY SHARE\n", expectation: "kill" },
      { id: "d7-cancel-lock-removed", blocker: "D7", file: STORE, proof: LOCK_PROOF,
        description: "the cancellation's authority read stops locking, so the predicate comes from " \
                     "the statement's opening snapshot",
        from: "            WHERE id = $5::uuid AND authorization_epoch = $4::bigint\n            FOR SHARE\n",
        to: "            WHERE id = $5::uuid AND authorization_epoch = $4::bigint\n", expectation: "kill" },
      { id: "d7-queue-lock-key-share", blocker: "D7", file: CRAWL_STORE, proof: LOCK_PROOF,
        description: "the queue insert's authority read downgraded to FOR KEY SHARE",
        from: "            FOR SHARE\n", to: "            FOR KEY SHARE\n", expectation: "kill" },
      { id: "d7-policy-lock-key-share", blocker: "D7", file: POLICY_STORE, proof: LOCK_PROOF,
        description: "the policy activation's authority read downgraded to FOR KEY SHARE",
        from: "            FOR SHARE\n", to: "            FOR KEY SHARE\n", expectation: "kill" },
      { id: "d7-capability-lock-removed", blocker: "D7, FU-48", file: STORE, proof: CAPABILITY_PROOF,
        description: "the capability read stops locking, so a grant revoked while the statement is " \
                     "blocked mid-flight is not seen by it",
        from: "            FOR SHARE OF ra\n", to: "", expectation: "kill" },

      # -- FU-48: the capability axis at each write --
      { id: "d7-cancel-capability-conjunct-removed", blocker: "FU-48", file: STORE,
        proof: CAPABILITY_PROOF,
        description: "the capability conjunct removed from the cancellation, restoring the state in " \
                     "which one Ruby branch was the only thing refusing an actor who held nothing",
        from: "              AND EXISTS (SELECT 1 FROM capability_authority)\n", to: "",
        expectation: "kill" },
      { id: "d7-cancel-capability-always-true", blocker: "FU-48", file: STORE, proof: CAPABILITY_PROOF,
        description: "the capability CTE made unconditionally true, so the grant is never read at all",
        from: "            SELECT 1 FROM role_assignments ra\n            JOIN unnest($6::uuid[], $7::bigint[], $8::text[]) AS g(id, state_version, scope_hex)\n              ON g.id = ra.id AND g.state_version = ra.state_version\n             AND g.scope_hex = coalesce(encode(ra.scope_sha256, 'hex'), '')\n            WHERE ra.organization_id = $5::uuid AND ra.account_id = $9::uuid\n              AND ra.status = 'active'\n              AND ra.effective_at IS NOT NULL AND ra.effective_at <= $3::timestamptz\n              AND (ra.expires_at IS NULL OR $3::timestamptz < ra.expires_at)\n              -- THE SCOPE RULE, AS A PREDICATE RATHER THAN AS A RUBY OPERAND (FU-48).\n              AND ($10::text IS NULL OR ra.canonical_role = $10::text)\n            FOR SHARE OF ra\n",
        # EVERY PARAMETER STAYS BOUND (A15-4): `SELECT 1` alone orphans $6-$10 and the statement dies
        # of `IndeterminateDatatype` before the write is ever attempted, so the kill said nothing
        # about whether the grant is read. This form is unconditionally true AND well-typed.
        to: "            SELECT 1 WHERE $6::uuid[] IS NOT NULL AND $7::bigint[] IS NOT NULL\n              AND $8::text[] IS NOT NULL AND $5::uuid IS NOT NULL AND $9::uuid IS NOT NULL\n              AND ($10::text IS NULL OR $10::text IS NOT NULL) AND $3::timestamptz IS NOT NULL\n",
        expectation: "kill" },
      { id: "d7-cancel-grant-version-unbound", blocker: "FU-48", file: STORE, proof: CAPABILITY_PROOF,
        description: "the grant's state version stops being bound, so a decision taken against a " \
                     "different version of the Assignment still authorizes the write",
        from: "              ON g.id = ra.id AND g.state_version = ra.state_version\n",
        to: "              ON g.id = ra.id\n", expectation: "kill" },
      { id: "d7-cancel-grant-scope-unbound", blocker: "FU-48, FU-2", file: STORE,
        proof: CAPABILITY_PROOF,
        description: "the grant's scope digest stops being bound, so the scope axis has no " \
                     "representation at the write at all",
        from: "             AND g.scope_hex = coalesce(encode(ra.scope_sha256, 'hex'), '')\n", to: "",
        expectation: "kill" },
      { id: "d7-cancel-grant-status-unbound", blocker: "FU-48", file: STORE, proof: CAPABILITY_PROOF,
        description: "a revoked Assignment still confers, so a revocation landing before the write " \
                     "is not seen by it",
        from: "              AND ra.status = 'active'\n", to: "", expectation: "kill" },
      { id: "d7-queue-capability-conjunct-removed", blocker: "FU-48", file: CRAWL_STORE,
        proof: CAPABILITY_PROOF,
        description: "the capability conjunct removed from the queue insert",
        from: "              AND EXISTS (SELECT 1 FROM capability_authority)\n", to: "",
        expectation: "kill" },
      { id: "d7-policy-capability-conjunct-removed", blocker: "FU-48", file: POLICY_STORE,
        proof: CAPABILITY_PROOF,
        description: "the capability conjunct removed from the policy activation's shared predicate",
        from: "            SELECT 1 WHERE EXISTS (SELECT 1 FROM epoch_authority)\n                       AND EXISTS (SELECT 1 FROM capability_authority)",
        to: "            SELECT 1 WHERE EXISTS (SELECT 1 FROM epoch_authority)", expectation: "kill" },

      # -- FU-48: the attestation binding --
      { id: "d7-attestation-mints-for-denial", blocker: "FU-48", file: ATTESTATION,
        proof: CAPABILITY_PROOF,
        description: "an attestation is minted for a decision that did not allow",
        from: "        return nil unless decision.allowed?\n", to: "", expectation: "kill" },
      { id: "d7-attestation-mints-without-grant", blocker: "FU-48", file: ATTESTATION,
        proof: CAPABILITY_PROOF,
        description: "an attestation is minted naming no grant, so it carries an empty array to a " \
                     "write whose predicate then cannot be satisfied — and the handler learns it at " \
                     "the write rather than at its own branch",
        from: "        return nil unless authority.grants?\n", to: "", expectation: "kill" },
      { id: "d7-attestation-authority-unbound", blocker: "FU-48", file: ATTESTATION,
        proof: CAPABILITY_PROOF,
        description: "the attestation stops being bound to the authority the write carries",
        from: "        unless @authority.same_principal?(authority)\n          raise Missing, \"authority attestation names a different actor, epoch, capability or grant set\"\n        end\n",
        to: "", expectation: "kill" },
      { id: "d7-write-authority-ignores-capability", blocker: "FU-48", file: WRITE_AUTHORITY,
        proof: CAPABILITY_PROOF,
        description: "the binding stops comparing the capability, so an attestation minted for one " \
                     "capability satisfies another's write",
        from: "          other.capability == capability && other.grant_ids == grant_ids &&",
        to: "          other.grant_ids == grant_ids &&", expectation: "kill" },

      # -- the handler's own refusal, per command path --
      { id: "d7-q-authorize-check-deleted", blocker: "D7, FU-48", file: QUEUE_HANDLER,
        proof: CAPABILITY_PROOF,
        description: "QueueCrawl's capability check deleted; the write still refuses, so only the " \
                     "pre-lock property distinguishes the two",
        from: "          unless decision.allowed?\n            return deny(**denial_args(d), resource_id: command.project_id,\n                        outward: \"crawl_trigger_unauthorized\", internal: \"crawl_trigger_unauthorized\")\n          end\n",
        to: "", expectation: "kill" },
      { id: "d7-c-authorize-check-deleted", blocker: "D7, FU-48", file: CANCEL,
        proof: CAPABILITY_PROOF,
        description: "CancelCrawl's capability check deleted",
        from: "          unless decision.allowed?\n            return deny(**denial_args(d), resource_id: command.crawl_id,\n                        outward: \"crawl_cancel_unauthorized\", internal: \"crawl_cancel_unauthorized\")\n          end\n",
        to: "", expectation: "kill" },
      { id: "d7-a-authorize-check-deleted", blocker: "D7, FU-48", file: POLICY_HANDLER,
        proof: CAPABILITY_PROOF,
        description: "ActivateCrawlPolicy's capability check deleted",
        from: "          unless decision.allowed? && authorized_for_scope?(command.scope, decision)\n            return deny(**denial_args(d), resource_id: scope_resource(command),\n                        outward: \"crawl_policy_unauthorized\", internal: \"crawl_policy_unauthorized\")\n          end\n",
        to: "", expectation: "kill" },

      # -- FU-48: the SCOPE rule as a predicate of the write --
      { id: "d7-a-scope-role-unbound", blocker: "FU-48", file: POLICY_STORE, proof: CAPABILITY_PROOF,
        description: "the scope rule stops being a predicate of the activation, so a MarketingOperator " \
                     "grant authorizes an ORGANIZATION-scope policy — the round-two security finding",
        # THE PARAMETER STAYS REFERENCED (round-15 architecture observation A15-4). Deleting the line
        # outright orphaned `$18`, so PostgreSQL refused the statement with `IndeterminateDatatype`
        # and the mutation died on a TYPING error rather than on the semantics it names — a kill that
        # proves the statement still parses, not that the scope rule is enforced. The vacuous form
        # below keeps every parameter bound and is refused by PROOF 258 for the right reason.
        from: "              AND ($18::text IS NULL OR ra.canonical_role = $18::text)\n",
        to: "              AND ($18::text IS NULL OR $18::text IS NOT NULL)\n",
        expectation: "kill" },
      # BOUND TO THE PROOF THAT ACTUALLY REACHES THE HANDLER'S COMMIT. The first binding named the
      # capability proof, which drives this store DIRECTLY and supplies its own `required_role`, so no
      # example reached `ActivateCrawlPolicy#commit` and the mutation SURVIVED. A ledger row whose
      # proof cannot reject its mutation is a false row, and the fix is the correct proof.
      { id: "d7-a-scope-role-not-carried", blocker: "FU-48", file: POLICY_HANDLER,
        proof: POLICY_PROOF,
        description: "the handler stops carrying the scope's required role into the write, so the " \
                     "predicate is present and permanently vacuous and the attestation it minted " \
                     "names an authority the write no longer carries",
        from: "            required_role: SCOPE_ROLE[d[:command].scope]\n", to: "            required_role: nil\n",
        expectation: "kill" },
      { id: "d7-a-scope-map-widened", blocker: "FU-48", file: POLICY_HANDLER, proof: CAPABILITY_PROOF,
        description: "the one transcription of :732/:738 widened, so both the Ruby guard and the " \
                     "write agree on the wrong rule",
        from: "        SCOPE_ROLE = { \"organization\" => \"OrganizationAdmin\", \"project\" => \"MarketingOperator\" }.freeze",
        to: "        SCOPE_ROLE = { \"organization\" => \"MarketingOperator\", \"project\" => \"MarketingOperator\" }.freeze",
        expectation: "kill" },

      # -- idempotent replay --
      { id: "d7-replay-not-idempotent", blocker: "D7", file: CANCEL, proof: DOOR_PROOF,
        description: "the replay branch deleted, so a duplicate command re-performs the transition " \
                     "and a correct replay stops being outside the antecedent",
        from: "          return replay(d, existing) if existing && existing[\"request_hex\"] == hex(d[:request_sha256])\n",
        to: "", expectation: "kill" },

      { id: "f6-lookup-class-traced", blocker: "R10-21", file: PROBE, proof: PROBE_PROOF,
        description: "traced_class reports the lookup class, not the defining class",
        from: "    def traced_class = singleton ? klass.singleton_class : reflect.owner",
        to: "    def traced_class = singleton ? klass.singleton_class : klass", expectation: "kill" },

      # ---- ROUND 15: one mutation for every repair this round made ------------------------------
      #
      # NOT ONE PER CONJUNCT PER WRITE. The battery proves all seven properties at all three writes by
      # construction, so enumerating twenty-one mutations would restate that structure rather than
      # test it. Recorded here is one representative per FAMILY the round repaired, plus one for each
      # production fix, so every new proof is shown to be capable of failing.
      { id: "r15-queue-grant-status-unbound", blocker: "A15-1", file: CRAWL_STORE, proof: BATTERY_PROOF,
        description: "the QUEUE write stops requiring the granting Assignment to be active — one of " \
                     "the ten conjuncts the architecture lens deleted with the whole suite green",
        from: "              AND ra.status = 'active'\n", to: "              AND ra.status IS NOT NULL\n",
        expectation: "kill" },
      { id: "r15-policy-grant-version-unbound", blocker: "A15-1", file: POLICY_STORE, proof: BATTERY_PROOF,
        description: "the POLICY write stops binding the grant's state version, so a decision taken " \
                     "against another version of the Assignment still authorizes the activation",
        from: "              ON g.id = ra.id AND g.state_version = ra.state_version\n",
        to: "              ON g.id = ra.id\n", expectation: "kill" },
      { id: "r15-queue-grant-expiry-unbound", blocker: "A15-1", file: CRAWL_STORE, proof: BATTERY_PROOF,
        description: "the QUEUE write stops checking that the grant has not expired",
        from: "              AND (ra.expires_at IS NULL OR $2::timestamptz < ra.expires_at)\n", to: "",
        expectation: "kill" },
      { id: "r15-queue-capability-lock-removed", blocker: "A15-1", file: CRAWL_STORE, proof: LOCK_PROOF,
        description: "the QUEUE write reads its grants without `FOR SHARE`, so a revocation can land " \
                     "while the statement is blocked mid-flight",
        from: "            FOR SHARE OF ra\n", to: "\n", expectation: "kill" },
      { id: "r15-policy-capability-lock-removed", blocker: "A15-1", file: POLICY_STORE, proof: LOCK_PROOF,
        description: "the POLICY write reads its grants without `FOR SHARE`",
        from: "            FOR SHARE OF ra\n", to: "\n", expectation: "kill" },
      { id: "r15-queue-pre-wait-instant", blocker: "R15-SEC-1", file: QUEUE_HANDLER, proof: LIFETIME_PROOF,
        description: "QueueCrawl goes back to writing with the instant it entered with, so a grant " \
                     "that expired during the lock wait still queues a Crawl",
        from: "          d = d.merge(now: post_wait.now)\n", to: "", expectation: "kill" },
      { id: "r15-policy-pre-wait-instant", blocker: "R15-SEC-1", file: POLICY_HANDLER, proof: LIFETIME_PROOF,
        description: "ActivateCrawlPolicy goes back to writing with its pre-wait instant",
        from: "          d = d.merge(now: post_wait.now)\n", to: "", expectation: "kill" },
      { id: "r15-revoke-order-reversed", blocker: "R15-CONC-1", file: REVOKE_HANDLER, proof: ORDER_PROOF,
        description: "RevokeRoleAssignment writes the grant before advancing the epoch, restoring the " \
                     "lock-order cycle that deadlocks against every protected WF-005 write",
        from: "          raise LostRace if store.advance_authorization_epoch(org, epoch, now).to_i.zero?\n" \
              "          raise LostRace if store.revoke(command.role_assignment_id, row[\"state_version\"].to_i, now,\n" \
              "                                         reason, epoch + 1).to_i.zero?\n",
        to: "          raise LostRace if store.revoke(command.role_assignment_id, row[\"state_version\"].to_i, now,\n" \
            "                                         reason, epoch + 1).to_i.zero?\n" \
            "          raise LostRace if store.advance_authorization_epoch(org, epoch, now).to_i.zero?\n",
        expectation: "kill" },
      { id: "r16-expire-order-reversed", blocker: "R16-CONC-1", file: EXPIRE_HANDLER, proof: ORDER_PROOF,
        description: "ExpireRoleAssignment writes the grant before advancing the epoch, restoring the " \
                     "lock-order cycle on the timed-expiry path — the handler round 16 found unbound",
        from: "          raise LostRace if store.advance_authorization_epoch(org, epoch, now).to_i.zero?\n" \
              "          raise LostRace if store.expire(command.role_assignment_id, row[\"state_version\"].to_i, now).to_i.zero?\n",
        to: "          raise LostRace if store.expire(command.role_assignment_id, row[\"state_version\"].to_i, now).to_i.zero?\n" \
            "          raise LostRace if store.advance_authorization_epoch(org, epoch, now).to_i.zero?\n",
        expectation: "kill" },
      { id: "r15-classify-suite-error-broken", blocker: "R15-CONC-2", file: HARNESS, proof: CLASSIFY_PROOF,
        description: "the one classifier goes back to calling a run that tripped a suite-wide " \
                     "invariant `broken`, which is what the two copies disagreed about",
        from: "      return \"survived\" if status.success? && !output.include?(SUITE_LEVEL_ERROR)",
        to: "      return \"survived\" if status.success?", expectation: "kill" }
    ].map { |e| e.transform_keys(&:to_s) }.freeze

    # D4's mutations act on a TRIGGER DEFINITION rather than on a file, and they are now REPLAYED,
    # SEALED AND VERIFIED like every other row.
    #
    # WHAT THIS CLOSES. They were written into the ledger verbatim by the regeneration task and never
    # passed through `replay`, `seal` or either verifier — an unbound channel beside the bound one,
    # carrying `expectation: "kill"` with no verdict and no gate. The single generic
    # `d4-column-dropped` entry was FALSE for four of the seven columns and nothing could say so.
    # Each column now has its own entry, and `MutationHarness.replay_trigger` applies the DDL, runs
    # the bound proof, restores from what the catalogue reported, and verifies the restoration.
    CLOSURE_PROOF = "spec/persistence/crawl_terminal_fact_closure_spec.rb"

    TRIGGER_MUTATIONS = [
      { id: "d4-when-or-to-and", blocker: "D4/R10-15", mechanism: "trigger",
        trigger: "crawl_host_gates_terminal_outcome_closure", table: "crawl_host_gates",
        description: "the WHEN clause OR replaced by AND, keeping every column name while making the limb unfireable",
        mutant_ddl: "CREATE TRIGGER crawl_host_gates_terminal_outcome_closure AFTER UPDATE ON public.crawl_host_gates FOR EACH ROW WHEN ((new.sitemap_state IS DISTINCT FROM old.sitemap_state) AND (new.sitemap_outcome_reason IS DISTINCT FROM old.sitemap_outcome_reason) AND (new.sitemap_terminal_at IS DISTINCT FROM old.sitemap_terminal_at) AND (new.sitemap_limit_reasons IS DISTINCT FROM old.sitemap_limit_reasons) AND (new.robots_state IS DISTINCT FROM old.robots_state) AND (new.robots_terminal_reason IS DISTINCT FROM old.robots_terminal_reason) AND (new.robots_terminal_at IS DISTINCT FROM old.robots_terminal_at)) EXECUTE FUNCTION f1_crawl_child_fact_closed()",
        proof: CLOSURE_PROOF, expectation: "kill" },
      { id: "d4-when-false", blocker: "D4/R10-15", mechanism: "trigger",
        trigger: "crawl_host_gates_terminal_outcome_closure", table: "crawl_host_gates",
        description: "the WHEN clause made unconditionally false",
        mutant_ddl: "CREATE TRIGGER crawl_host_gates_terminal_outcome_closure AFTER UPDATE ON public.crawl_host_gates FOR EACH ROW WHEN (false) EXECUTE FUNCTION f1_crawl_child_fact_closed()",
        proof: CLOSURE_PROOF, expectation: "kill" },
      { id: "d4-when-true", blocker: "D4/R10-15", mechanism: "trigger",
        trigger: "crawl_host_gates_terminal_outcome_closure", table: "crawl_host_gates",
        description: "the WHEN clause removed entirely, refusing pacing writes too",
        mutant_ddl: "CREATE TRIGGER crawl_host_gates_terminal_outcome_closure AFTER UPDATE ON public.crawl_host_gates FOR EACH ROW EXECUTE FUNCTION f1_crawl_child_fact_closed()",
        proof: CLOSURE_PROOF, expectation: "kill" },
      { id: "d4-drop-sitemap_state", blocker: "D4/R10-15", mechanism: "trigger",
        trigger: "crawl_host_gates_terminal_outcome_closure", table: "crawl_host_gates",
        description: "sitemap_state dropped from the WHEN clause; a post-terminal write to it goes unrefused",
        mutant_ddl: "CREATE TRIGGER crawl_host_gates_terminal_outcome_closure AFTER UPDATE ON public.crawl_host_gates FOR EACH ROW WHEN ((new.sitemap_outcome_reason IS DISTINCT FROM old.sitemap_outcome_reason) OR (new.sitemap_terminal_at IS DISTINCT FROM old.sitemap_terminal_at) OR (new.sitemap_limit_reasons IS DISTINCT FROM old.sitemap_limit_reasons) OR (new.robots_state IS DISTINCT FROM old.robots_state) OR (new.robots_terminal_reason IS DISTINCT FROM old.robots_terminal_reason) OR (new.robots_terminal_at IS DISTINCT FROM old.robots_terminal_at)) EXECUTE FUNCTION f1_crawl_child_fact_closed()",
        proof: CLOSURE_PROOF, expectation: "kill" },
      { id: "d4-drop-sitemap_outcome_reason", blocker: "D4/R10-15", mechanism: "trigger",
        trigger: "crawl_host_gates_terminal_outcome_closure", table: "crawl_host_gates",
        description: "sitemap_outcome_reason dropped from the WHEN clause; a post-terminal write to it goes unrefused",
        mutant_ddl: "CREATE TRIGGER crawl_host_gates_terminal_outcome_closure AFTER UPDATE ON public.crawl_host_gates FOR EACH ROW WHEN ((new.sitemap_state IS DISTINCT FROM old.sitemap_state) OR (new.sitemap_terminal_at IS DISTINCT FROM old.sitemap_terminal_at) OR (new.sitemap_limit_reasons IS DISTINCT FROM old.sitemap_limit_reasons) OR (new.robots_state IS DISTINCT FROM old.robots_state) OR (new.robots_terminal_reason IS DISTINCT FROM old.robots_terminal_reason) OR (new.robots_terminal_at IS DISTINCT FROM old.robots_terminal_at)) EXECUTE FUNCTION f1_crawl_child_fact_closed()",
        proof: CLOSURE_PROOF, expectation: "kill" },
      { id: "d4-drop-sitemap_terminal_at", blocker: "D4/R10-15", mechanism: "trigger",
        trigger: "crawl_host_gates_terminal_outcome_closure", table: "crawl_host_gates",
        description: "sitemap_terminal_at dropped from the WHEN clause; a post-terminal write to it goes unrefused",
        mutant_ddl: "CREATE TRIGGER crawl_host_gates_terminal_outcome_closure AFTER UPDATE ON public.crawl_host_gates FOR EACH ROW WHEN ((new.sitemap_state IS DISTINCT FROM old.sitemap_state) OR (new.sitemap_outcome_reason IS DISTINCT FROM old.sitemap_outcome_reason) OR (new.sitemap_limit_reasons IS DISTINCT FROM old.sitemap_limit_reasons) OR (new.robots_state IS DISTINCT FROM old.robots_state) OR (new.robots_terminal_reason IS DISTINCT FROM old.robots_terminal_reason) OR (new.robots_terminal_at IS DISTINCT FROM old.robots_terminal_at)) EXECUTE FUNCTION f1_crawl_child_fact_closed()",
        proof: CLOSURE_PROOF, expectation: "kill" },
      { id: "d4-drop-sitemap_limit_reasons", blocker: "D4/R10-15", mechanism: "trigger",
        trigger: "crawl_host_gates_terminal_outcome_closure", table: "crawl_host_gates",
        description: "sitemap_limit_reasons dropped from the WHEN clause; a post-terminal write to it goes unrefused",
        mutant_ddl: "CREATE TRIGGER crawl_host_gates_terminal_outcome_closure AFTER UPDATE ON public.crawl_host_gates FOR EACH ROW WHEN ((new.sitemap_state IS DISTINCT FROM old.sitemap_state) OR (new.sitemap_outcome_reason IS DISTINCT FROM old.sitemap_outcome_reason) OR (new.sitemap_terminal_at IS DISTINCT FROM old.sitemap_terminal_at) OR (new.robots_state IS DISTINCT FROM old.robots_state) OR (new.robots_terminal_reason IS DISTINCT FROM old.robots_terminal_reason) OR (new.robots_terminal_at IS DISTINCT FROM old.robots_terminal_at)) EXECUTE FUNCTION f1_crawl_child_fact_closed()",
        proof: CLOSURE_PROOF, expectation: "kill" },
      { id: "d4-drop-robots_state", blocker: "D4/R10-15", mechanism: "trigger",
        trigger: "crawl_host_gates_terminal_outcome_closure", table: "crawl_host_gates",
        description: "robots_state dropped from the WHEN clause; a post-terminal write to it goes unrefused",
        mutant_ddl: "CREATE TRIGGER crawl_host_gates_terminal_outcome_closure AFTER UPDATE ON public.crawl_host_gates FOR EACH ROW WHEN ((new.sitemap_state IS DISTINCT FROM old.sitemap_state) OR (new.sitemap_outcome_reason IS DISTINCT FROM old.sitemap_outcome_reason) OR (new.sitemap_terminal_at IS DISTINCT FROM old.sitemap_terminal_at) OR (new.sitemap_limit_reasons IS DISTINCT FROM old.sitemap_limit_reasons) OR (new.robots_terminal_reason IS DISTINCT FROM old.robots_terminal_reason) OR (new.robots_terminal_at IS DISTINCT FROM old.robots_terminal_at)) EXECUTE FUNCTION f1_crawl_child_fact_closed()",
        proof: CLOSURE_PROOF, expectation: "kill" },
      { id: "d4-drop-robots_terminal_reason", blocker: "D4/R10-15", mechanism: "trigger",
        trigger: "crawl_host_gates_terminal_outcome_closure", table: "crawl_host_gates",
        description: "robots_terminal_reason dropped from the WHEN clause; a post-terminal write to it goes unrefused",
        mutant_ddl: "CREATE TRIGGER crawl_host_gates_terminal_outcome_closure AFTER UPDATE ON public.crawl_host_gates FOR EACH ROW WHEN ((new.sitemap_state IS DISTINCT FROM old.sitemap_state) OR (new.sitemap_outcome_reason IS DISTINCT FROM old.sitemap_outcome_reason) OR (new.sitemap_terminal_at IS DISTINCT FROM old.sitemap_terminal_at) OR (new.sitemap_limit_reasons IS DISTINCT FROM old.sitemap_limit_reasons) OR (new.robots_state IS DISTINCT FROM old.robots_state) OR (new.robots_terminal_at IS DISTINCT FROM old.robots_terminal_at)) EXECUTE FUNCTION f1_crawl_child_fact_closed()",
        proof: CLOSURE_PROOF, expectation: "kill" },
      { id: "d4-drop-robots_terminal_at", blocker: "D4/R10-15", mechanism: "trigger",
        trigger: "crawl_host_gates_terminal_outcome_closure", table: "crawl_host_gates",
        description: "robots_terminal_at dropped from the WHEN clause; a post-terminal write to it goes unrefused",
        mutant_ddl: "CREATE TRIGGER crawl_host_gates_terminal_outcome_closure AFTER UPDATE ON public.crawl_host_gates FOR EACH ROW WHEN ((new.sitemap_state IS DISTINCT FROM old.sitemap_state) OR (new.sitemap_outcome_reason IS DISTINCT FROM old.sitemap_outcome_reason) OR (new.sitemap_terminal_at IS DISTINCT FROM old.sitemap_terminal_at) OR (new.sitemap_limit_reasons IS DISTINCT FROM old.sitemap_limit_reasons) OR (new.robots_state IS DISTINCT FROM old.robots_state) OR (new.robots_terminal_reason IS DISTINCT FROM old.robots_terminal_reason)) EXECUTE FUNCTION f1_crawl_child_fact_closed()",
        proof: CLOSURE_PROOF, expectation: "kill" },
    ].map { |e| e.transform_keys(&:to_s) }.freeze
  end
end
