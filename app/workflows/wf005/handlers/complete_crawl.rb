# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"

module Workflows
  module Wf005
    module Handlers
      # WF-005 THE TERMINAL CHECKPOINT (S-07-009) — the service execution behind the ratified
      # `crawl_terminal_deadline` ScheduledAction (BACKGROUND_PROCESSING.md :139/:199/:377;
      # WORKFLOW_SPECIFICATIONS.md :450, :452, :453, :458; contracts/S-07.json MTX-030).
      #
      # ":458 — Terminal selection occurs ONCE at a serialized checkpoint." The serialization is a `FOR
      # UPDATE` lock on the Crawl row, taken before anything is read, so a second delivery blocks, then
      # sees the first one's decision and finds the Crawl terminal. Everything the selection needs is
      # then counted in ONE statement under that lock: eight separate reads would let the run change
      # between them and produce a selection no single state of the database ever justified.
      #
      # ONE JOB, TWO OF :377's OPERATIONS. ":377 — `StartCrawl`, `CompleteCrawl`, `FailCrawl`, or
      # `CancelCrawl`, SELECTED SOLELY FROM PERSISTED CRAWL/DEADLINE STATE." This selects between
      # `CompleteCrawl` and `FailCrawl` from `Wf005::TerminalSelection`, which is a pure function over
      # the counted facts; the audit record and the event both say which it made. `CancelCrawl` is not
      # selected here — :458 settles cancellation by ORDER OF COMMIT ("a cancellation committed strictly
      # before that checkpoint yields `Crawl.Canceled`"), so a cancelled Crawl is already terminal when
      # this arrives and this writes nothing.
      #
      # FOUR THINGS HAPPEN IN THE ONE TRANSACTION, and the order is the specification's:
      #
      #   1. FU-9's TRANSFERRED OBLIGATION, first, because the coverage count reads its result.
      #      `DiscoverSitemaps` writes :450's terminal sitemap outcome only once the run has expired,
      #      and `CrawlDriver#advance` halts on the same wall clock BEFORE it calls discovery with the
      #      same `now` — so a gate under sustained contention stayed `pending` for ever and :450's
      #      `sitemap_unavailable` was unreachable on any production path. Here it is reachable and
      #      TRUE: at this instant no candidate can ever be attempted, which is exactly the "after
      #      retries/validation" premise :450 conditions the outcome on.
      #   2. THE COUNT, in one statement (`CrawlStartStore#terminal_facts`).
      #   3. THE SELECTION AND THE TRANSITION — :458's state, its single completion reason and, for a
      #      completed run, its coverage status.
      #   4. THE RESERVATION, committed or released EXACTLY ONCE (MTX-030 transaction_boundary; :551).
      #      `entitlement-interim-v1` names the durable commit point
      #      `crawl_completed_with_valid_document`, so a completed run commits and a failed one
      #      releases — and `Service#commit` itself releases instead if the lease has expired, which
      #      FU-31 is what keeps from being the only outcome.
      #
      # THE ONE INTERIM BOUNDARY, STATED RATHER THAN HIDDEN. :453's "zero valid Documents" is counted
      # over `crawl_terminal_outcomes.outcome = 'document_created'`, because nothing creates a
      # `documents` row yet — S-07-010 owns them, and the accepted `crawl_terminal_outcomes` migration
      # already ratified `document_created` with `document_id` NULL as the record of a fetch that did
      # everything :436 asks of an accepted page. S-07-010 must confirm it against the artifact; until
      # that artifact exists there is nothing truer to read, and inventing a stricter test would make
      # every run fail for a reason that is about this build rather than about the customer's site.
      class CompleteCrawl
        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "crawl"
        ACTION = "crawl.terminal_checkpoint"
        POLICY_VERSION = "permission-baseline-v1"
        WORKFLOW_ID = "WF-005"

        # `entitlement-interim-v1`'s durable commit point for `crawl.start`, and the durable output it
        # binds to. The Crawl IS the output: MTX-030 names the commit point
        # "crawl_completed_with_valid_document", and the artifact that carries it is this run.
        DURABLE_OUTPUT_TYPE = "crawl"
        COMMIT_REASON = "durable_commit_point_reached"
        RELEASE_REASON = "crawl_terminal_without_durable_output"

        class LostRace < StandardError; end

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") unless command.target_type == TARGET_TYPE

          key_digest = Digest::SHA256.digest(command.action_identity_sha256)

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            store = IdentityAccess::Infrastructure::CrawlStartStore.new(pg)
            org = command.organization_id
            store.enter_org_context(org:, correlation_id: ctx.correlation_id)
            # An action naming an Organization that does not exist is a transport-integrity deviation,
            # not a domain outcome: fail closed BEFORE any ledger row is written.
            next in_memory_failure(command, ctx, "scheduled_action_target_mismatch") if store.organization(org).nil?

            process(store:, entitlement: Platform::Entitlement::Service.new(pg), pg:, command:, ctx:,
                    org:, now:, key_digest:)
          end
        end

        private

        def process(store:, entitlement:, pg:, command:, ctx:, org:, now:, key_digest:)
          request_sha256 = request_hash(command, ctx)
          d = { store:, entitlement:, pg:, command:, ctx:, org:, now:, key_digest:, request_sha256: }

          # THE SERIALIZATION, IN TWO PARTS AND IN THIS ORDER (DECISIONS ADR-105).
          #
          # 1. THE FRONTIER ADVISORY LOCK, which fences an in-flight RETIREMENT. `CrawlDriver#retire`
          #    holds `crawl-frontier:<crawl>` for its whole transaction — the frontier terminalize AND
          #    the `crawl_terminal_outcomes` INSERT — so taking it here means no pass can be part-way
          #    through retiring an entry while this counts. Without it the checkpoint counted a snapshot
          #    the pass invalidated a moment later, and a run that fetched a valid Document was recorded
          #    `failed` with its reservation RELEASED while `crawl_terminal_outcomes` said
          #    `document_created / covered`. Reproduced at natural timing, 10/10, and IRREVERSIBLE:
          #    `f1_crawls_guard` refuses every UPDATE of a terminal row, so nothing can correct it.
          #
          # 2. THE CRAWL ROW LOCK, which is :458's "once" — a concurrent checkpoint or cancellation
          #    blocks here and then finds the Crawl terminal rather than deriving a second opinion.
          #
          # THE ORDER IS THE SUBSYSTEM'S, NOT A CHOICE MADE HERE. `Admission#claim` takes the frontier
          # advisory lock and then writes `crawl_budget_counters`, whose FK to `crawls` takes `FOR KEY
          # SHARE` on that row; `retire` does the same through the outcome row's FK. Frontier THEN crawls
          # is therefore already established, and the checkpoint conforms to it. Taking them the other
          # way round — the obvious fix, and the one the review's own concurrency lens proposed for the
          # driver — would invert the order against `Admission` and is how a deadlock is built.
          IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg).lock_frontier(command.crawl_id)
          crawl = store.lock_crawl(org, command.crawl_id)
          return mismatch(d) if crawl.nil?

          # Idempotency BEFORE the domain preconditions, as every other WF-005 handler orders it: a
          # duplicate delivery returns its stored result faithfully, whether that was the terminal
          # decision or a recorded refusal.
          existing = store.find_idempotency(org:, command_type: command.command_type,
                                            target_type: TARGET_TYPE, target_id: command.crawl_id, key_digest:)
          if existing
            return rebuild(store, existing, command) if existing["request_hex"] == hex(request_sha256)

            return deny(**d, crawl:, outward: "idempotency_conflict", internal: "idempotency_conflict",
                        replayable: false)
          end
          if now < command.due_at
            return deny(**d, crawl:, outward: "scheduled_action_not_due", internal: "scheduled_action_not_due",
                        replayable: false)
          end

          # THE CANONICAL HARMLESS TERMINAL EXECUTION. A Crawl already `completed`, `failed` or
          # `canceled` has had its one selection — :458's "once" — and this delivery has nothing to
          # decide. A `queued` Crawl never started, so it has no run to terminalize either; its own
          # `crawl_dispatch` owns that outcome.
          unless crawl["state"] == "running"
            reason = %w[completed failed canceled].include?(crawl["state"]) ? "crawl_already_terminal" : "crawl_not_running"
            return deny(**d, crawl:, outward: reason, internal: reason)
          end

          checkpoint(d, crawl)
        end

        # ---- the checkpoint --------------------------------------------------------

        def checkpoint(d, crawl)
          store = d[:store]
          ctx = d[:ctx]
          org = d[:org]
          now = d[:now]
          command = d[:command]
          pid = crawl["project_id"]
          ids = %i[execution audit event result idem commit_intent].to_h { |k| [k, ctx.generate_id] }
          new_version = crawl["state_version"].to_i + 1

          write_execution(store, command, ctx, org, ids[:execution], d[:request_sha256], d[:key_digest], now)

          gates = IdentityAccess::Infrastructure::CrawlHostGateStore.new(d[:pg])
          sitemaps = resolve_pending_sitemaps(store, gates, org, crawl, now)
          # BEFORE THE COUNT, because the count reads its result.
          wall_clock = observe_wall_clock(d, crawl)
          facts = count_facts(store, org, crawl, pid)
          selection = TerminalSelection.derive(facts)

          raise LostRace if store.terminalize(crawl["id"], crawl["state_version"].to_i, now,
                                              state: selection.state,
                                              completion_reason: selection.completion_reason,
                                              coverage_status: selection.coverage_status).to_i.zero?

          metering = settle_reservation(d, crawl, selection, ids)

          payload = {
            "crawl_id" => crawl["id"], "organization_id" => org, "project_id" => pid,
            "state" => selection.state, "completion_reason" => selection.completion_reason,
            "coverage_status" => selection.coverage_status,
            "terminal_at_utc" => now.iso8601(6),
            # THE COUNTS THE SELECTION WAS MADE FROM, not a restatement of the selection. MTX-030's
            # audit requirement is "the complete failed subset with counts and reasons; the derived
            # coverage and completion", so a reader can re-derive the decision rather than trust it.
            "documents" => facts.documents, "source_roots" => facts.roots_total,
            "source_roots_succeeded" => facts.roots_succeeded,
            "source_root_failures" => facts.root_failures,
            "content_fetch_failures" => facts.fetch_failures,
            "uncovered_candidates" => facts.uncovered, "unevaluated_candidates" => facts.unevaluated,
            "unresolved_discovery" => facts.unresolved_discovery, "hard_limit_decisions" => facts.hard_limits,
            # FU-9's obligation, reported so its exercise is visible rather than silent.
            "sitemap_outcomes_derived" => sitemaps,
            "entitlement_reservation_id" => crawl["entitlement_reservation_id"],
            "entitlement_outcome" => metering
          }
          write_audit(store, ids[:audit], org, ctx, command, crawl["id"], to_state: selection.state,
                      outcome: "success", reason_code: selection.completion_reason, payload:, now:)
          write_event(store, ids[:event], ids[:audit], org, ctx, command, now, new_version, pid,
                      d[:request_sha256], d[:key_digest], event_type(selection), "state_transition",
                      TARGET_TYPE, crawl["id"],
                      { "from_state" => "running", "to_state" => selection.state,
                        "crawl_id" => crawl["id"], "completion_reason" => selection.completion_reason,
                        "coverage_status" => selection.coverage_status })
          write_result(store, ids, command, ctx, org, now, payload, target_id: crawl["id"])
          write_idempotency(store, ids[:idem], org, command, d[:key_digest], d[:request_sha256],
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue LostRace
          raise Platform::InvariantViolation, "crawl terminal checkpoint lost its serialized transition"
        end

        # :453's two events. `CrawlCompleted` and `CrawlFailed` are both `crawl_terminal` profile rows in
        # API_CONTRACTS.md :807-808; which one fires is the selection, never a separate judgement.
        def event_type(selection)
          selection.state == TerminalSelection::FAILED ? "CrawlFailed" : "CrawlCompleted"
        end

        # FU-9's TRANSFERRED OBLIGATION (ADR-096). Returns how many gates this checkpoint decided.
        #
        # :450's outcome table, applied to a gate the run left `pending`: "when robots declares no
        # sitemap AND the default sitemap returns 404 or 410, record `sitemap_absent`" — but a gate
        # still `pending` never completed a traversal, so it cannot have observed the default's 404, and
        # the `absent` limb's second condition is unmet by construction. Every such gate is therefore
        # `unavailable`, which is also what :450's own sentence says: "if a declared sitemap exists, or
        # the default returns a non-404/410 response, AND NO SITEMAP CANDIDATE SUCCEEDS after
        # retries/validation, record `sitemap_unavailable`". At the terminal checkpoint no candidate can
        # ever succeed, so the premise is satisfied for the run as a whole rather than guessed at.
        #
        # A GATE WHOSE ROBOTS RECORD IS FAIL-CLOSED IS SKIPPED. :448 denies all content fetching for
        # that host, so discovery never had a sitemap to fail at; recording `sitemap_unavailable` there
        # would count one host's robots failure twice in the coverage measure.
        #
        # THROUGH THE ACCEPTED CLAIM/TERMINALIZE SURFACE, not around it.
        # `f1_crawl_host_gates_sitemap_guard` admits `pending -> in_progress -> unavailable` and nothing
        # wider, so the checkpoint claims the gate exactly as a discovery pass does and then writes the
        # outcome under its own token. That is not a detour around the guard, it is the reason the guard
        # is right: a worker that still holds the claim BLOCKS this, so the checkpoint can never write
        # over a decision another delivery is in the middle of making. `retained` and `discarded` are
        # empty because this claim performs no traversal — it records that none is possible any more.
        def resolve_pending_sitemaps(store, gates, org, crawl, now)
          store.pending_sitemap_gates(org, crawl["id"]).count do |gate|
            next false if gate["robots_state"] == "unavailable"

            token = SecureRandom.uuid_v7
            next false unless gates.begin_sitemaps(gate["id"], gate["state_version"].to_i, now,
                                                   [], [], token).to_i.positive?

            gates.terminalize_sitemaps(gate["id"], token, now, state: "unavailable",
                                       reason: DiscoverSitemaps::UNAVAILABLE,
                                       documents: 0, max_depth: 0).to_i.positive?
          end
        end

        # :442's WALL CLOCK, OBSERVED WHERE IT ACTUALLY ENDS THE RUN (DECISIONS ADR-107).
        #
        # `Admission` records this crossing when a PASS arrives past the deadline. But the case this
        # action exists for is the one where no pass ever does — FU-22's pinned run, and any run whose
        # chain simply stopped — so the run that was ended BY its own sixty minutes recorded nothing
        # about them. :458 requires that "any in-scope candidate not evaluated because of … wall-clock
        # bound makes coverage partial AND RECORDS ITS EXACT LIMIT REASON", and the reason has to exist
        # somewhere to be recorded.
        #
        # THE DECISION TABLE IS THE IDEMPOTENCE. `crawl_limit_decisions` is unique on
        # `(crawl_id, limit_dimension, threshold_kind)`, so a pass that already observed the crossing
        # makes this a no-op returning `replayed`, and `CrawlLimitReached` still fires exactly once per
        # dimension and run. Nothing here counts or decides — the count below reads the decision table
        # like any other, so the selection is derived from one source whether a pass or this recorded it.
        #
        # Both thresholds, independently, for the reason `Admission#wall_clock` already records: a run
        # that crossed the hard bound genuinely crossed the soft one on the way past it, and gating the
        # soft limb behind the hard one loses it permanently for a run whose only crossing was the hard.
        def observe_wall_clock(d, crawl)
          deadline = crawl["deadline_at"]
          return false if deadline.nil? || d[:now] < Time.parse(deadline.to_s).utc

          limits = EffectiveLimits.resolve(d[:store].active_crawl_policies(d[:org], crawl["project_id"]))
          observer = LimitDecisions.new(ids: d[:ctx].ids, correlation_id: d[:ctx].correlation_id)
                                   .for(d[:pg], organization_id: d[:org], project_id: crawl["project_id"],
                                        crawl_id: crawl["id"], limits:)
          elapsed = elapsed_minutes(crawl, d[:now])
          soft = limits.configured(Admission::WALL_CLOCK_DIMENSION, LimitDimensions::SOFT)
          observer.soft(Admission::WALL_CLOCK_DIMENSION, elapsed, now: d[:now]) if elapsed >= soft
          # ":442 — record dimension, configured value, observed value, AFFECTED SOURCE AND URL COUNTS."
          # The wall clock abandons whatever the run still had, so the affected counts are the run's own
          # unevaluated candidates and the Sources they belong to, read from the frontier rather than
          # assumed.
          observer.hard(Admission::WALL_CLOCK_DIMENSION, elapsed, now: d[:now],
                        affected: affected_by_wall_clock(d, crawl))
          true
        end

        def elapsed_minutes(crawl, now)
          started = crawl["started_at"]
          return 0 if started.nil?

          ((now.utc - Time.parse(started.to_s).utc) / 60).floor
        end

        def affected_by_wall_clock(d, crawl)
          row = d[:store].unevaluated_reach(d[:org], crawl["id"])
          LimitDecisions::Affected.new(sources: row["sources"].to_i, urls: row["urls"].to_i)
        end

        def count_facts(store, org, crawl, project_id)
          row = store.terminal_facts(org, crawl["id"], project_id)
          TerminalSelection::Facts.new(
            documents: row["documents"].to_i, roots_total: row["roots_total"].to_i,
            roots_succeeded: row["roots_succeeded"].to_i, fetch_failures: row["fetch_failures"].to_i,
            unresolved_discovery: row["unresolved"].to_i, hard_limits: row["hard_limits"].to_i,
            uncovered: row["uncovered"].to_i, unevaluated: row["unevaluated"].to_i
          )
        end

        # MTX-030 — "committing or releasing the root reservation EXACTLY ONCE" at the Crawl's durable
        # point. `entitlement-interim-v1` names that point `crawl_completed_with_valid_document`, and
        # :453 makes `completed` mean at least one valid Document by construction (a run with none is
        # `failed`), so the state IS the test. A run that never started one — a Crawl whose reservation
        # column is NULL — has nothing to settle and says so rather than guessing.
        def settle_reservation(d, crawl, selection, ids)
          reservation_id = crawl["entitlement_reservation_id"]
          return "none" if reservation_id.nil?

          if selection.state == TerminalSelection::FAILED
            return d[:entitlement].release(organization_id: d[:org], reservation_id:,
                                           reason: RELEASE_REASON, now: d[:now]).to_s
          end

          d[:entitlement].commit(organization_id: d[:org], reservation_id:,
                                 durable_output: { type: DURABLE_OUTPUT_TYPE, id: crawl["id"], sha256: nil },
                                 now: d[:now], ids: { commit_intent: ids[:commit_intent] },
                                 reason: COMMIT_REASON).to_s
        end

        # ---- audited no-state outcome ----------------------------------------------

        def mismatch(d)
          deny(**d, crawl: nil, outward: "scheduled_action_target_mismatch",
               internal: "scheduled_action_target_mismatch", replayable: false)
        end

        # `**_rest` absorbs the context keys the callers splat in that an audited no-state outcome has
        # no use for, so no parameter is declared and left dead.
        def deny(store:, command:, ctx:, org:, now:, key_digest:, request_sha256:, crawl:,
                 outward:, internal:, replayable: true, **_rest)
          ids = %i[execution audit result idem].to_h { |k| [k, ctx.generate_id] }
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command, command.crawl_id, to_state: nil, outcome: "failure",
                      reason_code: internal,
                      payload: { "crawl_id" => command.crawl_id, "organization_id" => org,
                                 "project_id" => crawl && crawl["project_id"], "internal_reason" => internal,
                                 "outward_reason" => outward, "scheduled_action_id" => command.action_id }, now:)
          failure = Platform::ErrorCatalog.failure(outward, support_reference: ctx.correlation_id)
          write_result(store, ids, command, ctx, org, now, {}, failure:)
          if replayable
            write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256, ids[:execution],
                              ids[:result], now)
          end
          Platform::CommandResult.failure(result_id: ids[:result], command_type: command.command_type,
                                          failure:, audit_record_id: ids[:audit], correlation_id: ctx.correlation_id)
        end

        def rebuild(store, existing, command)
          stored = store.load_command_result(existing["command_result_id"])
          if stored["outcome"] == "success"
            Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type,
                                            payload: JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym),
                                            audit_record_id: stored["audit_record_id"],
                                            correlation_id: stored["correlation_id"], replayed: true)
          else
            failure = Platform::Failure.new(
              error_class: stored["error_class"], error_code: stored["error_code"],
              reason_code: stored["reason_code"], severity: stored["severity"],
              retryable: stored["retryable"] == "t" || stored["retryable"] == true,
              recovery_action: stored["recovery_action"], support_reference: stored["support_reference"]
            )
            Platform::CommandResult.failure(result_id: stored["id"], command_type: command.command_type,
                                            failure:, audit_record_id: stored["audit_record_id"],
                                            correlation_id: stored["correlation_id"], replayed: true)
          end
        end

        # ---- writers ---------------------------------------------------------------

        def write_execution(store, command, ctx, org, id, request_sha256, key_digest, now)
          store.insert_command_execution(
            id:, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, idempotency_key_digest: key_digest,
            command_type: command.command_type, command_schema_version: command.schema_version,
            service_identity_id: ctx.service_identity_id, organization_id: org, target_type: TARGET_TYPE,
            target_id: command.crawl_id, action: ACTION,
            requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
            policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            canonical_payload: JSON.generate({ "scheduled_action_id" => command.action_id }), request_sha256:
          )
        end

        def write_audit(store, id, org, ctx, command, entity_id, to_state:, outcome:, reason_code:, payload:, now:)
          store.insert_audit(
            id:, occurred_at: iso(now), partition_month: month(now), organization_id: org,
            service_identity_id: ctx.service_identity_id, correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id, entity_type: TARGET_TYPE,
            entity_id:, to_state:, outcome:, reason_code:, payload: JSON.generate(payload),
            content_sha256: Platform::CanonicalJson.digest(payload)
          )
        end

        def write_event(store, event_id, audit_id, org, ctx, command, now, aggregate_version, project_id,
                        request_sha256, key_digest, type, profile, aggregate_type, aggregate_id, extra)
          envelope = {
            "account_id" => nil, "actor_id" => nil, "affected_entity_id" => aggregate_id,
            "affected_entity_type" => aggregate_type, "aggregate_version" => aggregate_version,
            "audit_record_id" => audit_id, "causation_id" => ctx.correlation_id,
            "command_id" => command.command_id, "correlation_id" => ctx.correlation_id,
            "event_id" => event_id, "event_profile" => profile, "event_type" => type,
            "idempotency_identity_hash" => hex(key_digest), "input_hash" => hex(request_sha256),
            "occurred_at_utc" => now.iso8601(6), "organization_id" => org, "outcome" => "success",
            "project_id" => project_id, "reason_code" => nil, "schema_version" => "1.0",
            "scheduled_action_id" => command.action_id, "service_identity_id" => ctx.service_identity_id,
            "state_version" => aggregate_version, "workflow_id" => WORKFLOW_ID
          }.merge(extra)
          bytes = Platform::CanonicalJson.encode(envelope)
          store.insert_event(
            id: event_id, created_at: iso(now), event_type: type, event_profile: profile,
            occurred_at: iso(now), organization_id: org, aggregate_type:, aggregate_id:,
            aggregate_version:, partition_month: month(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id, audit_record_id: audit_id,
            event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
          )
        end

        def write_result(store, ids, command, ctx, org, now, payload, failure: nil, target_id: nil)
          store.insert_command_result(
            id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id,
            command_execution_id: ids[:execution], outcome: failure ? "failure" : "success",
            organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
            authorization_check_at: iso(now),
            target_refs: JSON.generate(failure ? {} : { TARGET_TYPE => target_id }),
            governing_policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            failure:, authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
          )
        end

        def write_idempotency(store, id, org, command, key_digest, request_sha256, execution_id, result_id, now)
          store.insert_idempotency(
            id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
            target_type: TARGET_TYPE, target_id: command.crawl_id, key_digest:, request_sha256:,
            command_execution_id: execution_id, command_result_id: result_id,
            retain_until: iso(now + (30 * 24 * 3600))
          )
        end

        def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
        end

        def request_hash(command, ctx)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "service_identity_id" => ctx.service_identity_id,
            "organization_id" => command.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.crawl_id, "project_id" => nil,
            "policy_versions" => [POLICY_VERSION],
            "command_payload" => { "scheduled_action_identity_sha256" => hex(command.action_identity_sha256),
                                   "due_at" => command.due_at.getutc.iso8601(6) }
          })
        end

        def hex(bytes) = bytes.unpack1("H*")
        def iso(time) = time.getutc.floor(6).iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1)
        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
      end
    end
  end
end
