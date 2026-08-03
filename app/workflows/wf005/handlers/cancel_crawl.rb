# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf005
    module Handlers
      # WF-005 CancelCrawl (S-07-009; WORKFLOW_SPECIFICATIONS.md :736, :738, :458, :551;
      # API_CONTRACTS.md :279; contracts/S-07.json MTX-030).
      #
      # Authenticates the actor, refuses a cross-tenant or missing Project, authorizes `crawl.cancel`
      # (:738 — "cancellation requires `crawl.cancel`", a permission separate from `crawl.trigger` even
      # though :147 gives them the same cells), and then, under the CRAWL ROW LOCK, moves a `queued` or
      # `running` Crawl to `canceled` with :456's `canceled` completion reason, releases its entitlement
      # reservation, and emits `CrawlCanceled`.
      #
      # :458 HAS THREE SENTENCES ABOUT THE BOUNDARY AND THIS HANDLER CARRIES ALL THREE (ADR-107). The
      # third — "at exactly the 60-minute boundary the wall-clock terminal handler wins over a
      # simultaneous cancellation" — is the `deadline_at` limb in `process`; the first two are below.
      #
      # :458'S BOUNDARY IS COMMIT ORDER, AND THE ROW LOCK IS WHAT MAKES IT A FACT. "A cancellation
      # committed STRICTLY BEFORE that checkpoint yields `Crawl.Canceled`; a cancellation at or after
      # the checkpoint is rejected as `crawl_already_terminal`." Both sides take `SELECT ... FOR UPDATE`
      # on the same row, so one of them commits first and the other sees it: this handler finds a
      # terminal Crawl and refuses with exactly the token :458 names, and the checkpoint finds a
      # cancelled one and derives nothing. Neither side implements the other's rule — `f1_crawls_guard`
      # refuses every edge out of a terminal state, so the losing party could not write even if it tried.
      #
      # THE RESERVATION IS RELEASED, NEVER COMMITTED. ":551 — Cancellation or any terminal failure
      # before the listed commit point RELEASES exactly once even when intermediate Documents or other
      # partial artifacts exist; those artifacts remain governed by their workflow but are NOT a usage
      # commitment." A cancelled run is never `crawl_completed_with_valid_document`, whatever it managed
      # to fetch first, so the customer is not charged for it.
      #
      # NO COVERAGE STATUS. `crawls_terminal_shape` requires it only of `completed` (ADR-097), and a
      # cancelled run's coverage is not a number anyone should read: the run was stopped, not measured.
      #
      # CANCELLATION IS PASS-BOUNDARY EFFECTIVE, AND THAT IS DISCLOSED RATHER THAN IMPLIED (FU-32).
      # A cancellation prevents every LATER pass and the terminal checkpoint, because both re-read the
      # Crawl and refuse a terminal one. It does NOT interrupt a pass that has already been authorized:
      # `CrawlDriver#advance` checks the run once at the top and then performs its fetch, so after this
      # command commits, one already-running pass may still make outbound requests and write attempt and
      # terminal-outcome rows. Those rows are inert — the checkpoint will never read them, because it
      # finds the Crawl terminal — but the outbound requests are observable customer behaviour. Making
      # cancellation effective INSIDE a pass is a product and architectural decision recorded as FU-32,
      # deliberately not taken opportunistically here: it changes locking, database traffic and outbound
      # guarantees, and it belongs with FU-28's bounded execution units, which give it natural
      # boundaries without holding a lock or polling through one large pass.
      class CancelCrawl
        include Wf005::CrawlLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "crawl"
        ACTION = "crawl.cancel"
        CAPABILITY = "crawl.cancel"
        WORKFLOW_ID = "WF-005"
        COMPLETION_REASON = "canceled"
        RELEASE_REASON = "crawl_canceled"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
            store = IdentityAccess::Infrastructure::CrawlStore.new(pg)

            actor = auth.authenticate(session_id: command.session_id, now:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, actor.to_s) if actor.is_a?(Symbol)

            request_sha256 = request_hash(command, actor)
            # `requested_at` is the instant this cancellation ARRIVED at, kept separately from `now`
            # because :458's third sentence is a statement about arrival and `now` becomes the
            # post-wait decision instant below. The tie limb in `process` is its only reader.
            d = { command:, ctx:, store:, auth_store:, actor:, org: actor.organization_id, now:,
                  requested_at: now, request_sha256:, pg:,
                  crawls: IdentityAccess::Infrastructure::CrawlStartStore.new(pg) }
            process(d, auth)
          end
        end

        private

        def process(d, auth)
          command = d[:command]
          actor = d[:actor]

          project = d[:store].project(d[:org], command.project_id)
          return denied(d, "tenant_mismatch") if project.nil? || command.organization_id != actor.organization_id

          decision = auth.authorize(actor:, capability: CAPABILITY, now: d[:now])
          d = d.merge(decision:)
          unless decision.allowed?
            return deny(**denial_args(d), resource_id: command.crawl_id,
                        outward: "crawl_cancel_unauthorized", internal: "crawl_cancel_unauthorized")
          end

          # THE SERIALIZATION AGAINST THE TERMINAL CHECKPOINT *AND* AGAINST AN IN-FLIGHT PASS, taken
          # before anything is read that decides. Whichever transaction arrives first wins :458's
          # ordering, and the other reads the winner's committed state rather than its own stale view.
          #
          # THE FRONTIER LOCK IS FIRST AND IS NOT OPTIONAL (round 3, R3-6). `CrawlDriver#retire` decides
          # whether to write its outcome row by re-reading `crawls.state`, and ADR-113 justified that
          # PLAIN SELECT by saying it happens "under the frontier advisory lock it already takes, which
          # is the same lock `Handlers::CompleteCrawl` takes first (ADR-105) — so exactly one of the two
          # transactions holds it". That argument covered the CHECKPOINT and nothing else: this handler
          # took only the `crawls` row lock, and the outcome row's FK takes `FOR KEY SHARE`, which is
          # compatible with this transaction's `FOR NO KEY UPDATE`. So nothing blocked, and a pass could
          # commit `document_created / covered` onto a Crawl this transaction had already cancelled and
          # whose entitlement it had already released — R2-B1's corrupt shape with `canceled` in place of
          # `failed`, reproduced 3/3 and 10/10 by two lenses independently, and IRREVERSIBLE because
          # `f1_crawls_guard` refuses every UPDATE of a terminal row.
          #
          # Frontier THEN crawls, matching `Admission#claim`, `retire` and `CompleteCrawl`. Taking them
          # the other way round is what ADR-105 rejected for the driver.
          IdentityAccess::Infrastructure::CrawlFrontierStore.new(d[:pg]).lock_frontier(command.crawl_id)
          crawl = d[:crawls].lock_crawl(d[:org], command.crawl_id)
          return denied(d, "tenant_mismatch") if crawl.nil? || crawl["project_id"] != command.project_id

          # THE WAIT IS OVER, SO EVERYTHING TIME-SENSITIVE IS RE-READ FROM HERE DOWN (owner ruling 1;
          # `Wf005::PostWaitDecision` states the rule). Both locks above can block for as long as the
          # transaction ahead of them holds them, and every test below this line — :458's boundary
          # tie, the audit and event instants, the reservation release — was being decided on the
          # instant this command entered with.
          post_wait = PostWaitDecision.new(d[:pg], entered_with: d[:now])
          d = d.merge(now: post_wait.now)

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = d[:store].find_idempotency(org: d[:org], command_type: command.command_type,
                                                target_type: TARGET_TYPE, target_id: command.crawl_id,
                                                key_digest:)
          return replay(d, existing) if existing && existing["request_hex"] == hex(d[:request_sha256])
          return denied(d, "idempotency_conflict") if existing

          # :458's own token, for the run that had its one terminal selection first.
          return denied(d, "crawl_already_terminal") if post_wait.terminal?(crawl)
          # :458's THIRD SENTENCE, AT THE INSTANT IT IS ABOUT AND NOT A MOMENT LONGER (round 3, R3-2).
          # "At exactly the 60-minute boundary the WALL-CLOCK TERMINAL HANDLER WINS over a SIMULTANEOUS
          # cancellation."
          #
          # ADR-107 implemented this as `now >= deadline`, which barred EVERY post-deadline
          # cancellation. That is a different rule from the one :458 states, and it contradicted the
          # two sentences before it: "a cancellation committed STRICTLY BEFORE that checkpoint yields
          # `Crawl.Canceled`; a cancellation AT OR AFTER THE CHECKPOINT is rejected". The boundary
          # sentence 1 draws is THE CHECKPOINT'S COMMIT, not the deadline instant — and the checkpoint
          # committing is exactly what the state test above already detects. So a cancellation at
          # minute sixty-one, arriving while the Crawl is still `running` because the checkpoint has
          # not been delivered yet, is governed by sentence 1 and WINS.
          #
          # THE OLD FORM ALSO TOLD THE CALLER SOMETHING FALSE. It answered `crawl_already_terminal`
          # about a Crawl whose authoritative state was `running` with `terminal_at` NULL. A refusal
          # code is a statement about the record, and that one contradicted it.
          #
          # `==`, not `>=`: "at exactly the boundary" is a tie between two eligible parties at ONE
          # instant, which is the only thing commit order cannot settle on its own. :551 uses the same
          # construction twice for the same kind of tie ("At exactly the prestart expiry, execution-start
          # loses to expiry"; "At exactly 15 minutes ... the lease-expiry handler wins"), and settles
          # everything else by whether the durable commit point "committed STRICTLY BEFORE that instant".
          #
          # THE METERING ESCAPE ADR-107 GUARDED AGAINST IS RATIFIED BEHAVIOUR, which is why removing
          # the guard is not a hole. :551: "CANCELLATION OR ANY TERMINAL FAILURE BEFORE THE LISTED
          # COMMIT POINT RELEASES even when intermediate Documents or other partial artifacts exist;
          # those artifacts remain governed by their workflow but are NOT A USAGE COMMITMENT." A
          # cancellation that beats the checkpoint releasing rather than committing is the contract, not
          # an exploit of it, and a handler may not invent a broader bar to prevent what :551 permits.
          # COMPARED AGAINST THE UNTRUNCATED INSTANT (round 4, R4-1). This read
          # `Time.parse(deadline.to_s).utc`, and `Time#to_s` FORMATS TO WHOLE SECONDS — the raw
          # connection decodes `timestamptz` to a Ruby `Time` carrying microseconds, so the round trip
          # silently dropped them. `deadline_at` of `12:01:30.123456Z` became `12:01:30.000000Z`, which
          # broke :458 in BOTH directions at once:
          #
          #   * sentence 3 NEVER FIRED at the real boundary — `now` would have to equal the truncated
          #     instant, which is 123ms before the deadline the run actually has;
          #   * sentence 2 was VIOLATED for the whole remainder of that second — a cancellation
          #     committed STRICTLY BEFORE the checkpoint was refused `crawl_already_terminal`, the
          #     exact objection this limb was narrowed from `>=` to answer.
          #
          # Invisible to the suite because every fixture instant is a whole second and the proofs read
          # `deadline_at` back through a raw `PG.connect` with no type map, which is a DIFFERENT
          # DECODING PATH from production. PROOF 128 uses a sub-second deadline for that reason.
          #
          # THE TIE IS TESTED AGAINST ARRIVAL, AND IT IS THE ONE TEST HERE THAT IS (round 6, R6-5's
          # sibling question). Every other time-sensitive test in this handler moved to the post-wait
          # instant, because every other one asks "may this effect still happen", which is a question
          # about NOW. Sentence 3 asks something different: it names the instant the cancellation IS
          # ABOUT, and declares that a request made AT the boundary loses to the handler whose whole
          # subject is that boundary. Measuring it against the post-wait instant would not make it
          # stricter or looser, it would DELETE it: the post-wait instant is the arrival instant plus
          # however long the locks took, so it can never equal a stored microsecond, and `==` would be
          # dead code. That is round 1's B1 — ":458's third sentence is unimplemented" — reintroduced
          # by an unrelated repair, which is the exact failure mode this tranche exists to stop.
          #
          # NOTHING STALE SURVIVES IT. A `true` refuses and writes only a denial record stamped with
          # the post-wait instant; a `false` falls through to the authority recheck and the
          # post-wait-stamped transition below. The pre-wait value decides no durable effect.
          deadline = Platform::PgInstant.utc(crawl["deadline_at"])
          return denied(d, "crawl_already_terminal") if deadline && d[:requested_at] == deadline
          # MTX-030's request schema carries the expected state version; a cancellation holding a
          # version the run has moved past is refused rather than applied to a Crawl its sender was not
          # looking at.
          return denied(d, "stale_state_version") if command.expected_state_version != crawl["state_version"].to_i

          # THE HUMAN AUTHORITY, RE-READ IMMEDIATELY BEFORE THE IRREVERSIBLE ACT (round 6, R6-5; :335,
          # SEC-REQ-004/005). `authorize` ran before `lock_frontier`, and what follows this line
          # cancels the Crawl, releases its entitlement reservation and emits `CrawlCanceled` — none
          # of which `f1_crawls_guard` will let anything undo.
          #
          # THE PLATFORM DEFERRAL DOES NOT REACH THIS HANDLER, and the owner ruled on exactly that.
          # DECISIONS.md records the missing epoch recheck as a consistent platform pattern shared
          # with `DecideSourceScopeChange` and the `source.register` family. Every one of those
          # authorizes and acts with no wait in between, so the window is a few statements wide. This
          # one can block on `crawl-frontier:<crawl>` for as long as an in-flight pass or checkpoint
          # holds it, and a revocation, suspension or policy change committed inside that window
          # would otherwise be spent by an allowed decision that no longer exists.
          unless post_wait.authority_current?(auth_store: d[:auth_store], actor:)
            return denied(d, "crawl_cancel_unauthorized")
          end

          commit(d, crawl, key_digest)
        end

        def commit(d, crawl, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          actor = d[:actor]
          ids = %i[execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          from_state = crawl["state"]
          new_version = crawl["state_version"].to_i + 1

          # Guarded on the state AND the version, so a race that got past the read above still writes
          # nothing. Zero rows here would mean the lock did not hold, which is corruption rather than a
          # domain outcome.
          moved = d[:crawls].cancel(crawl["id"], crawl["state_version"].to_i, now)
          raise Platform::InvariantViolation, "crawl cancellation lost its serialized transition" if moved.to_i.zero?

          metering = release_reservation(d, crawl)

          payload = {
            "crawl_id" => crawl["id"], "organization_id" => org, "project_id" => command.project_id,
            "from_state" => from_state, "state" => "canceled", "completion_reason" => COMPLETION_REASON,
            "coverage_status" => nil, "terminal_at_utc" => now.iso8601(6),
            "entitlement_reservation_id" => crawl["entitlement_reservation_id"],
            "entitlement_outcome" => metering
          }
          write_execution(store, command, ctx, org, ids[:execution], crawl["id"], actor, d[:request_sha256],
                          key_digest, now, ACTION)
          write_authorization_decision(d[:auth_store], ids[:decision], ctx, command, actor, d[:decision], now,
                                       crawl["id"], ACTION)
          write_audit(store, ids[:audit], org, ctx, command, crawl["id"], actor,
                      to_state: "canceled", outcome: "success", reason_code: COMPLETION_REASON, payload:, now:)
          write_event(store, ids, org, ctx, command, actor, now, new_version, crawl["id"], d[:request_sha256],
                      key_digest, "CrawlCanceled", "state_transition",
                      # :808 gives `CrawlCanceled` the reason source `transition`, so :938 requires the
                      # `state_transition` base member `transition_reason_code` and root `reason_code`
                      # equal to it. :956 makes the `crawl_terminal` extra schema THREE members —
                      # `coverage_status`, `completion_reason` AND `accepted_document_count: uint53`,
                      # "values are null/zero before terminal derivation" (ADR-110).
                      #
                      # `coverage_status` IS EMITTED, AS NULL (round 3, R3-3). ADR-110 added the third
                      # member to this envelope and left the FIRST one out, so `CrawlCanceled` declared
                      # the `crawl_terminal` profile and carried two of its three members — while this
                      # handler's own command-result payload eight lines above set `coverage_status`
                      # explicitly. Two surfaces describing one terminal act disagreed about its shape.
                      #
                      # NULL IS THE VALUE, NOT AN OMISSION, and the two are different facts to a
                      # consumer: :956 admits `nullable enum{full,partial}` and says the values are null
                      # "before terminal derivation", `crawls_terminal_shape` requires a coverage status
                      # only of `completed` (ADR-097), and a cancelled run's coverage is not a number
                      # anyone should read because the run was STOPPED, not measured. An absent required
                      # member is what :938's consumer rule REJECTS; a null one is what it defines.
                      { "project_id" => command.project_id, "crawl_id" => crawl["id"],
                        "from_state" => from_state, "to_state" => "canceled",
                        "completion_reason" => COMPLETION_REASON,
                        "coverage_status" => nil,
                        "accepted_document_count" => 0,
                        "reason_code" => COMPLETION_REASON,
                        "transition_reason_code" => COMPLETION_REASON })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, crawl["id"])
          write_idempotency(store, ids[:idem], org, command, crawl["id"], key_digest, d[:request_sha256],
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # :551 — cancellation RELEASES exactly once, never commits, "even when intermediate Documents or
        # other partial artifacts exist". A `queued` Crawl has no reservation at all (POSTGRESQL_SCHEMA
        # :338 — "NULL until start"), and says so rather than guessing.
        def release_reservation(d, crawl)
          reservation_id = crawl["entitlement_reservation_id"]
          return "none" if reservation_id.nil?

          Platform::Entitlement::Service.new(d[:pg])
                                        .release(organization_id: d[:org], reservation_id:,
                                                 reason: RELEASE_REASON, now: d[:now]).to_s
        end

        # ---- replay + denial + helpers ---------------------------------------------

        def replay(d, existing)
          stored = d[:store].load_command_result(existing["command_result_id"])
          Platform::CommandResult.success(result_id: stored["id"], command_type: d[:command].command_type,
                                          payload: JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym),
                                          audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        def denied(d, reason)
          decision = d[:decision] || pre_authorization_decision(d[:actor])
          deny(**denial_args(d.merge(decision:)), resource_id: d[:command].crawl_id,
               outward: reason, internal: reason)
        end

        def denial_args(d)
          { command: d[:command], ctx: d[:ctx], store: d[:store], auth_store: d[:auth_store], actor: d[:actor],
            decision: d[:decision], org: d[:org], now: d[:now], request_sha256: d[:request_sha256] }
        end

        def pre_authorization_decision(actor)
          IdentityAccess::Authorization::Decision.new(
            allowed: false, reason: "not_evaluated", organization_epoch: actor.authorization_epoch,
            policy_snapshot_id: nil, role_assignment_versions: [], granting_assignments: []
          )
        end

        def request_hash(command, actor)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "actor_id" => actor.account_id,
            "organization_id" => actor.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.crawl_id, "project_id" => command.project_id,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => { "crawl_id" => command.crawl_id,
                                   "expected_state_version" => command.expected_state_version }
          })
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR

      end
    end
  end
end
