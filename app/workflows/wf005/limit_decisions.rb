# frozen_string_literal: true

require "digest"
require "securerandom"

module Workflows
  module Wf005
    # The ONE place a Crawl limit becomes customer-visible (S-07-008; WORKFLOW_SPECIFICATIONS.md
    # :442; API_CONTRACTS.md `crawl_limit_decision`).
    #
    # :442 — "Soft-limit crossing emits `CrawlSoftLimitApproaching` once per dimension and run. …
    # At any other hard limit … emit `CrawlLimitReached` EXACTLY ONCE per dimension and run."
    #
    # EVERY EVENT IS DERIVED FROM THE DECISION ROW; NOTHING IS DERIVED FROM RUNTIME STATE.
    # The order is: insert the decision, and emit only if the insert is the one that created it.
    #
    #     decision inserted (UNIQUE decides) -> audit + event written on the same transaction
    #
    # rather than the shape this replaced everywhere it was tempting:
    #
    #     runtime detects a threshold -> emit -> hope nothing else emitted too
    #
    # The difference is not stylistic. `UNIQUE (crawl_id, limit_dimension, threshold_kind)` is the
    # only participant that can adjudicate "first" across processes, so making it the thing that
    # decides means a retry, a replay, a crash between the two writes, or eight workers crossing the
    # same threshold in the same millisecond all converge on one event without any of them
    # coordinating. There is no pre-filter and no counter bit consulted first: the insert IS the
    # check, so there is no second mechanism that could disagree with it. (S-07-008 (1/n) built a
    # counter-bit claim for this and 3/n superseded it; the method has been deleted rather than
    # left dormant with a rationale describing something that no longer runs.)
    #
    # The event's fields are read back OUT of the inserted row rather than taken from the caller's
    # arguments, so a CHECK that rejected a value stops the event too, and the stream can never
    # describe a decision the database does not hold.
    class LimitDecisions
      SOFT_EVENT = "CrawlSoftLimitApproaching"
      HARD_EVENT = "CrawlLimitReached"
      ENTITY_TYPE = "crawl"
      WORKFLOW_ID = "WF-005"

      # A decision advances no aggregate — the Crawl is exactly where it was — so the envelope
      # claims no version of one. `RoleExpiryBlocked` (WF-013) sets the same precedent for the
      # `decision` profile.
      AGGREGATE_VERSION = 0

      # What the observation did. `emitted` is false when this caller lost the race or replayed:
      # the decision exists, and it is not this caller's to announce.
      Outcome = Data.define(:decision_id, :emitted, :dimension, :threshold, :configured, :observed) do
        def emitted? = emitted
        def hard? = threshold == LimitDimensions::HARD
      end

      # :442's "affected Source and URL counts".
      Affected = Data.define(:sources, :urls)
      NONE = Affected.new(sources: 0, urls: 0)

      def initialize(ids: Platform::Ids.system, correlation_id: nil, service_identity_id: nil)
        @ids = ids
        @correlation_id = correlation_id || SecureRandom.uuid_v7
        @service_identity_id = service_identity_id || Platform::ServiceIdentity.scheduled_action_executor
      end

      # One observation point's view of this surface: the run, its connection and its RESOLVED
      # limits, fixed once. Every site that can hit a bound gets one of these rather than repeating
      # six keyword arguments per crossing — and, more to the point, rather than re-resolving the
      # policy per candidate, which is both a read per offer and a chance for two crossings in one
      # traversal to be judged against different numbers.
      class Observer
        def initialize(service, pg, organization_id:, project_id:, crawl_id:, limits:)
          @service = service
          @pg = pg
          @scope = { organization_id:, project_id:, crawl_id: }
          @limits = limits
        end

        def limits = @limits

        def soft(dimension, observed, now:)
          observe(dimension, LimitDimensions::SOFT, observed, now:, affected: nil)
        end

        def hard(dimension, observed, now:, affected: nil)
          observe(dimension, LimitDimensions::HARD, observed, now:, affected:)
        end

        # The soft bound for a dimension, so a call site can ask "have I reached it?" against the
        # same resolution the decision will record.
        def soft_bound(dimension) = @limits.configured(dimension, LimitDimensions::SOFT)
        def hard_bound(dimension) = @limits.configured(dimension, LimitDimensions::HARD)

        private

        def observe(dimension, threshold, observed, now:, affected:)
          @service.observe(@pg, **@scope, dimension:, threshold:, observed:, limits: @limits, now:,
                           affected:)
        end
      end

      def for(pg, organization_id:, project_id:, crawl_id:, limits:)
        Observer.new(self, pg, organization_id:, project_id:, crawl_id:, limits:)
      end

      # Record that `dimension` reached `threshold` at `observed`, and emit the event that follows
      # from it. `limits` is the `EffectiveLimits::Resolution` the caller ENFORCED — the configured
      # value recorded here is read from that same resolution, never re-resolved, so a customer is
      # never told they hit a bound that was not the one applied.
      #
      # Runs on the CALLER'S connection and inside the caller's transaction on purpose: the
      # observation, its decision and its event commit with the effect that caused them, or none of
      # them do.
      def observe(pg, organization_id:, project_id:, crawl_id:, dimension:, threshold:, observed:,
                  limits:, now:, affected: nil)
        raise ArgumentError, "unknown limit dimension #{dimension}" unless LimitDimensions.known?(dimension)
        raise ArgumentError, "unknown threshold #{threshold}" unless LimitDimensions::THRESHOLDS.include?(threshold)

        store = IdentityAccess::Infrastructure::CrawlLimitDecisionStore.new(pg)
        configured = limits.configured(dimension, threshold)
        counts = affected || default_affected(store, organization_id, crawl_id, dimension, threshold)

        result = store.record(decision_row(organization_id:, project_id:, crawl_id:, dimension:, threshold:,
                                           configured:, observed:, counts:, limits:, now:))
        row = result[:row]
        emit(store, row, now) unless result[:replayed]

        Outcome.new(decision_id: row["id"], emitted: !result[:replayed], dimension:, threshold:,
                    configured:, observed: row["observed_value"].to_i)
      end

      private

      # ":442 — at any other hard limit, STOP SCHEDULING AFFECTED WORK … record … affected Source
      # and URL counts." The unselected frontier is the right population for exactly the two bounds
      # that DO stop scheduling: the run's byte budget and its wall clock. Every other dimension
      # abandons something narrower and passes it explicitly — one URL for a per-URL bound or a
      # queue discard, the skipped sitemap candidates for a sitemap bound. Defaulting all of them to
      # the whole frontier reported ~20,000 abandoned URLs for a queue discard that cost exactly one.
      #
      # A soft crossing stops nothing, so nothing is affected by it.
      RUN_STOPPING = ["accounted_response_body_bytes_per_run", "wall_clock_run_duration"].freeze

      def default_affected(store, organization_id, crawl_id, dimension, threshold)
        return NONE unless threshold == LimitDimensions::HARD && RUN_STOPPING.include?(dimension)

        row = store.unselected_counts(organization_id, crawl_id)
        Affected.new(sources: row["sources"].to_i, urls: row["urls"].to_i)
      end

      def decision_row(organization_id:, project_id:, crawl_id:, dimension:, threshold:, configured:,
                       observed:, counts:, limits:, now:)
        input = { "crawl_id" => crawl_id, "limit_dimension" => dimension, "threshold_kind" => threshold,
                  "configured_value" => configured.to_i, "observed_value" => observed.to_i,
                  "affected_source_count" => counts.sources, "affected_url_count" => counts.urls,
                  "definition_versions" => limits.definition_versions }
        output = { "decision_type" => IdentityAccess::Infrastructure::CrawlLimitDecisionStore::DECISION_TYPE,
                   "decision_value" => LimitDimensions::DECISION_VALUES.fetch(threshold),
                   "decision_status" => IdentityAccess::Infrastructure::CrawlLimitDecisionStore::DECISION_STATUS,
                   "decision_reason_code" => LimitDimensions::REASON_CODES.fetch(threshold) }

        { id: @ids.generate, correlation_id: @correlation_id, causation_id: @correlation_id,
          command_id: nil, organization_id:, project_id:, crawl_id:,
          limit_dimension: dimension, threshold_kind: threshold,
          configured_value: configured.to_i, observed_value: observed.to_i,
          affected_source_count: counts.sources, affected_url_count: counts.urls,
          decision_value: output["decision_value"], decision_reason_code: output["decision_reason_code"],
          decided_by_service_identity_id: @service_identity_id,
          definition_versions: limits.definition_versions,
          input_sha256: Platform::CanonicalJson.digest(input),
          output_sha256: Platform::CanonicalJson.digest(output),
          decided_at: now.utc.iso8601(6) }
      end

      # The audit record and the event, both built from the STORED row.
      def emit(store, row, now)
        audit_id = @ids.generate
        event_id = @ids.generate
        payload = envelope_extras(row).merge("crawl_id" => row["crawl_id"], "decision_id" => row["id"])
        store.insert_audit(id: audit_id, occurred_at: iso(now), partition_month: month(now),
                           organization_id: row["organization_id"], service_identity_id: @service_identity_id,
                           correlation_id: @correlation_id, causation_id: @correlation_id,
                           entity_id: row["crawl_id"], outcome: "success",
                           reason_code: row["decision_reason_code"], payload: JSON.generate(payload),
                           content_sha256: Platform::CanonicalJson.digest(payload))

        bytes = Platform::CanonicalJson.encode(envelope(row, event_id, audit_id, now))
        store.insert_event(id: event_id, created_at: iso(now), event_type: event_type(row),
                           occurred_at: iso(now), organization_id: row["organization_id"],
                           project_id: row["project_id"], aggregate_id: row["crawl_id"],
                           aggregate_version: AGGREGATE_VERSION, partition_month: month(now),
                           correlation_id: @correlation_id, causation_id: @correlation_id,
                           audit_record_id: audit_id, event_bytes: bytes,
                           event_sha256: Digest::SHA256.digest(bytes))
      end

      def event_type(row) = row["threshold_kind"] == LimitDimensions::SOFT ? SOFT_EVENT : HARD_EVENT

      # The `decision` profile's base members plus `crawl_limit_decision`'s appended ones — every
      # one of them a column of the row that was just written.
      def envelope(row, event_id, audit_id, now)
        {
          "account_id" => nil, "actor_id" => nil,
          "affected_entity_id" => row["crawl_id"], "affected_entity_type" => ENTITY_TYPE,
          "aggregate_version" => AGGREGATE_VERSION, "audit_record_id" => audit_id,
          "authority_actor_id" => nil,
          "authority_service_identity_id" => row["decided_by_service_identity_id"],
          "causation_id" => @correlation_id, "command_id" => nil, "correlation_id" => @correlation_id,
          "decision_id" => row["id"], "decision_reason_code" => row["decision_reason_code"],
          "decision_status" => row["decision_status"], "decision_type" => row["decision_type"],
          "decision_value" => row["decision_value"],
          "definition_versions" => definition_versions(row),
          "event_id" => event_id, "event_profile" => "decision", "event_type" => event_type(row),
          "idempotency_identity_hash" => nil,
          "input_hash" => hashes(row)[:input], "output_hash" => hashes(row)[:output],
          "occurred_at_utc" => now.utc.iso8601(6), "organization_id" => row["organization_id"],
          "outcome" => "success", "project_id" => row["project_id"],
          # ":773 — root reason equals `decision_reason_code` for catalogue source `decision`."
          "reason_code" => row["decision_reason_code"], "schema_version" => "1.0",
          "scheduled_action_id" => nil, "service_identity_id" => row["decided_by_service_identity_id"],
          "state_version" => AGGREGATE_VERSION,
          "subject" => { "entity_type" => ENTITY_TYPE, "identity_kind" => "uuid",
                         "entity_id" => row["crawl_id"] },
          "workflow_id" => WORKFLOW_ID
        }.merge(envelope_extras(row))
      end

      def envelope_extras(row)
        { "limit_dimension" => row["limit_dimension"], "threshold_kind" => row["threshold_kind"],
          "configured_value" => row["configured_value"].to_i, "observed_value" => row["observed_value"].to_i,
          "affected_source_count" => row["affected_source_count"].to_i,
          "affected_url_count" => row["affected_url_count"].to_i }
      end

      def definition_versions(row) = JSON.parse(row.fetch("definition_versions"))

      def hashes(row)
        { input: row.fetch("input_sha256"), output: row.fetch("output_sha256") }
      end

      def iso(time) = time.utc.iso8601(6)
      def month(time) = time.utc.strftime("%Y-%m-01")
    end
  end
end
