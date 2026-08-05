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

    DEADLINE_PROOF = "spec/platform/run_deadline_spec.rb"
    GATES_PROOF = "spec/acceptance/wf005_deadline_gates_spec.rb"
    AUTHORITY_PROOF = "spec/acceptance/wf005_cancel_authority_write_spec.rb"
    CANCEL_PROOF = "spec/acceptance/wf005_cancel_crawl_spec.rb"
    PROBE_PROOF = "spec/architecture/execution_probe_spec.rb"
    SENTINEL_PROOF = "spec/architecture/authority_sentinel_spec.rb"
    CLOSED_FACT_PROOF = "spec/acceptance/wf005_closed_fact_set_spec.rb"
    QUEUE_PROOF = "spec/acceptance/wf005_queue_crawl_spec.rb"
    POLICY_PROOF = "spec/acceptance/wf005_activate_crawl_policy_spec.rb"

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
        from: "              AND EXISTS (SELECT 1 FROM authority)\n", to: "", expectation: "kill" },
      { id: "d3-epoch-inequality", blocker: "D3/R10-10", file: STORE, proof: AUTHORITY_PROOF,
        description: "equality weakened to >=, accepting a stale epoch",
        from: "WHERE id = $5::uuid AND authorization_epoch = $4::bigint",
        to: "WHERE id = $5::uuid AND authorization_epoch >= $4::bigint", expectation: "kill" },
      { id: "d3-authority-always-true", blocker: "D3/R10-10", file: STORE, proof: AUTHORITY_PROOF,
        description: "the authority CTE made unconditionally true",
        from: "            SELECT 1 FROM organizations\n            WHERE id = $5::uuid AND authorization_epoch = $4::bigint",
        to: "            SELECT 1", expectation: "kill" },
      { id: "d3-wrong-organization", blocker: "D3/R10-10", file: STORE, proof: AUTHORITY_PROOF,
        description: "the epoch compared against the wrong organization, rejecting valid ownership",
        from: "WHERE id = $5::uuid AND authorization_epoch = $4::bigint",
        to: "WHERE id = $1::uuid AND authorization_epoch = $4::bigint", expectation: "kill" },
      { id: "d3-authorized-independent", blocker: "D3/R10-10", file: STORE, proof: AUTHORITY_PROOF,
        description: "`authorized` reported independently of the write's own predicate",
        from: "          SELECT (SELECT count(*) FROM authority) AS authorized,",
        to: "          SELECT 1 AS authorized,", expectation: "kill" },
      { id: "d3-denial-swallowed", blocker: "D3/R10-10", file: CANCEL, proof: AUTHORITY_PROOF,
        description: "the handler treats an unauthorized write as success",
        from: "          return denied(d, \"crawl_cancel_unauthorized\") unless outcome[:authorized]\n",
        to: "", expectation: "kill" },
      { id: "d3-branches-reversed", blocker: "D3/R10-10", file: CANCEL, proof: AUTHORITY_PROOF,
        description: "the denial and the corruption raise reversed, reporting revocation as corruption",
        from: "          return denied(d, \"crawl_cancel_unauthorized\") unless outcome[:authorized]\n          raise Platform::InvariantViolation, \"crawl cancellation lost its serialized transition\" if outcome[:moved].zero?",
        to: "          raise Platform::InvariantViolation, \"crawl cancellation lost its serialized transition\" if outcome[:moved].zero?\n          return denied(d, \"crawl_cancel_unauthorized\") unless outcome[:authorized]",
        expectation: "kill" },
      { id: "d3-self-authorizing-epoch", blocker: "D3/R10-10", file: CANCEL, proof: CANCEL_PROOF,
        description: "the actor's epoch replaced by row state, so the write authorizes itself",
        from: "authorization_epoch: actor.authorization_epoch, organization_id: org",
        to: "authorization_epoch: crawl[\"state_version\"].to_i, organization_id: org", expectation: "kill" },
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
        from: "      invocations(target).any? { |i| i[:site].include?(site) && i[:thread] == thread.object_id }",
        to: "      invocations(target).any? { |i| i[:site].include?(site) }", expectation: "kill" },

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
      { id: "f4-discovery-narrowed", blocker: "R10-9", file: SENTINEL, proof: SENTINEL_PROOF,
        description: "discovery narrowed back to a source-text match over one spelling",
        from: "      @observed_handlers ||= Dir[Rails.root.join(HANDLER_DIR, \"*.rb\")].sort.filter_map { |f| constant_for(f) }",
        to: "      @observed_handlers ||= Dir[Rails.root.join(HANDLER_DIR, \"*.rb\")].sort.filter_map { |f| constant_for(f) if File.read(f).match?(/authenticate\\(session_id:/) }",
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
        from: "          WHERE EXISTS (\n            SELECT 1 FROM organizations\n            WHERE id = $4::uuid AND authorization_epoch = $14::bigint\n          )\n",
        to: "", expectation: "kill" },
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
        from: "            authorization_epoch: actor.authorization_epoch,",
        to: "            authorization_epoch: 0,", expectation: "kill" },
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
        from: "            WHERE id = $4::uuid AND authorization_epoch = $13::bigint",
        to: "            WHERE id = $4::uuid", expectation: "kill" },
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
      { id: "d6-a-outcomes-collapsed", blocker: "D6", file: POLICY_HANDLER, proof: POLICY_PROOF,
        description: "the domain denial and the lost-serialization raise collapsed into one",
        from: "          return denied(d, \"crawl_policy_unauthorized\") unless applied[:authorized]\n          raise LostRace if current && applied[:superseded].zero?",
        to: "          raise LostRace if current && applied[:superseded].zero?", expectation: "kill" },

      { id: "f6-lookup-class-traced", blocker: "R10-21", file: PROBE, proof: PROBE_PROOF,
        description: "traced_class reports the lookup class, not the defining class",
        from: "    def traced_class = singleton ? klass.singleton_class : reflect.owner",
        to: "    def traced_class = singleton ? klass.singleton_class : klass", expectation: "kill" }
    ].map { |e| e.transform_keys(&:to_s) }.freeze

    # D4's mutations act on a trigger definition rather than a file. Recorded so the set is complete.
    TRIGGER_MUTATIONS = [
      { "id" => "d4-when-or-to-and", "blocker" => "D4/R10-15", "mechanism" => "trigger",
        "description" => "the WHEN clause's OR replaced by AND, keeping every column name while " \
                         "making the limb unfireable — the exact mutant the old text proof could not see",
        "proof" => "spec/persistence/crawl_terminal_fact_closure_spec.rb", "expectation" => "kill" },
      { "id" => "d4-column-dropped", "blocker" => "D4/R10-15", "mechanism" => "trigger",
        "description" => "one column dropped from the WHEN clause",
        "proof" => "spec/persistence/crawl_terminal_fact_closure_spec.rb", "expectation" => "kill" },
      { "id" => "d4-when-false", "blocker" => "D4/R10-15", "mechanism" => "trigger",
        "description" => "the WHEN clause made unconditionally false",
        "proof" => "spec/persistence/crawl_terminal_fact_closure_spec.rb", "expectation" => "kill" },
      { "id" => "d4-when-true", "blocker" => "D4/R10-15", "mechanism" => "trigger",
        "description" => "the WHEN clause made unconditionally true, refusing pacing writes too",
        "proof" => "spec/persistence/crawl_terminal_fact_closure_spec.rb", "expectation" => "kill" }
    ].freeze
  end
end
