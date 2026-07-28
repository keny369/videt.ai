# frozen_string_literal: true

module Workflows
  module Wf005
    # EXECUTION-TIME AUTHORIZATION for a single outbound fetch (S-07-005 objective 3;
    # contracts/S-07.json MTX-030 `authorization_entry_point` — "An authorization or scope result
    # established at queue time is never trusted at execution time: WF-005 requires re-resolution
    # immediately before the running transition, and EVERY URL is validated against the pinned AND
    # current restrictive scope"; SEARCH_CRAWL_RETRIEVAL.md § Crawl Admission And Snapshot step 1).
    #
    # This is the last gate before bytes leave the platform, and it is deliberately the STRICTEST
    # one. S-07-003 re-authorized at the start commit and S-07-004 re-checks the Source at the
    # dequeue; both are necessary and NEITHER is sufficient, because an authorization can be revoked
    # in the interval between a claim and the connection. Owner direction is explicit: "Never trust
    # queue-time authorization for execution-time fetches. Fail closed whenever authorization or
    # robots semantics are uncertain."
    #
    # It is PURE with respect to its inputs — it reads current rows through the store and returns a
    # verdict; it writes nothing and it never repairs state. Every unknown answers DENY.
    class FetchAuthorization
      # First-match order, widest authority first, so the recorded reason names the outermost thing
      # that failed rather than an inner consequence of it.
      Verdict = Data.define(:allowed, :reason_code, :scope_policy_id, :scope_policy_version) do
        def allowed? = allowed
        def denied? = !allowed
        # True when the denial is a scheduling condition the caller should re-ask about, rather than
        # a revoked authority that is terminal for this URL.
        def retryable? = FetchAuthorization.retryable?(reason_code)
      end

      # Every reason this gate can return. All but `fetch_robots_not_resolved` are TERMINAL for the
      # URL: each names a revoked or absent authority rather than a transient condition.
      #
      # `fetch_robots_not_resolved` is deliberately separate from `fetch_robots_unavailable`, because
      # the two have opposite downstream consequences. A host whose robots fetch is merely still in
      # flight is a SCHEDULING condition — the caller waits and re-asks. A host that has failed closed
      # is an authority outcome, and :452 makes it "that Source root failed and coverage partial".
      # Collapsing them would terminally fail URLs on hosts seconds away from resolving, and would
      # attribute genuine fail-closed coverage penalties to them.
      RETRYABLE_REASONS = %w[fetch_robots_not_resolved].freeze

      REASONS = %w[
        fetch_organization_inactive
        fetch_crawl_not_running
        fetch_project_not_active
        fetch_source_not_active
        fetch_scope_policy_unavailable
        fetch_url_out_of_scope
        fetch_entitlement_not_executing
        fetch_robots_disallowed
        fetch_robots_unavailable
        fetch_robots_not_resolved
      ].freeze

      def self.retryable?(reason) = RETRYABLE_REASONS.include?(reason)

      # The `crawl.start` maximum-execution ceiling (WORKFLOW :527/:551), enforced as part of "still
      # metered" rather than trusted from the reservation's state column alone.
      MAX_EXECUTION_SECONDS =
        Platform::Entitlement::InterimPolicy.rule("crawl.start").fetch(:max_execution_seconds)

      def initialize(store)
        @store = store
      end

      # Authorize ONE candidate URL immediately before its connection. `gate` is the locked host-gate
      # row; nil means robots has not been resolved for the host, which is itself a denial for a
      # content fetch.
      def authorize(organization_id:, crawl_id:, source_id:, canonical_url:, gate:, now:, kind: "content")
        org = @store.organization(organization_id)
        return deny("fetch_organization_inactive") unless org && org["status"] == "active"

        crawl = @store.crawl(organization_id, crawl_id)
        return deny("fetch_crawl_not_running") unless crawl && crawl["state"] == "running"

        project = @store.project(organization_id, crawl["project_id"])
        return deny("fetch_project_not_active") unless project && project["state"] == "active"

        # The Source must STILL be active. `disabled`, `removed`, and every pre-`active` state are
        # denials: a Source the customer has switched off is never fetched on queue-time authority,
        # whatever the frontier still holds.
        # Keyed on the CRAWL'S Project, not the Organization alone. Without the project predicate a
        # Crawl in Project A could be authorized against a Source — and its scope policy — belonging
        # to Project B of the same Organization, which POSTGRESQL_SCHEMA :128 exists to make
        # impossible and which the composite FKs enforce everywhere else in this subsystem.
        source = @store.source(organization_id, crawl["project_id"], source_id)
        return deny("fetch_source_not_active") unless source && source["state"] == "active"

        # The entitlement reservation that admitted this run must still be executing. A released,
        # committed or expired reservation means the run is no longer metered, and an unmetered
        # fetch is exactly what PRULE-007 exists to prevent.
        unless @store.reservation_executing?(organization_id, crawl["entitlement_reservation_id"],
                                             MAX_EXECUTION_SECONDS, now)
          return deny("fetch_entitlement_not_executing")
        end

        scope = @store.current_scope_policy(organization_id, crawl["project_id"], source_id)
        return deny("fetch_scope_policy_unavailable") if scope.nil?

        # The CURRENT restrictive scope, re-evaluated now — not the version pinned at queue time.
        decision = Wf004::SourceScopePredicate.evaluate(url: canonical_url, policies: [policy_of(scope)])
        return deny("fetch_url_out_of_scope") unless decision.allowed?

        # EVERY later check uses the predicate's OWN canonical form, never the caller's string. The
        # predicate percent-decodes unreserved octets and removes dot segments, so `/%70rivate` and
        # `/a/../private` both normalize to `/private`. Judging scope on the normalized path and
        # robots on the raw one would let either spelling walk straight past a `Disallow: /private`.
        target = decision.canonical_url

        # The gate must belong to THIS Organization, THIS Crawl and THIS URL's host. It arrives as an
        # already-materialized row, so RLS is not in this path — nothing but these comparisons stops
        # another host's (or another tenant's) robots rules being applied to this URL.
        return deny("fetch_robots_not_resolved") unless gate_bound?(gate, organization_id, crawl_id, target)

        robots_verdict(gate, target, kind) ||
          Verdict.new(allowed: true, reason_code: nil, scope_policy_id: scope["id"],
                      scope_policy_version: scope["policy_version"])
      end

      private

      # Robots governs CONTENT (and sitemap) fetches only — the robots fetch itself must be able to
      # proceed before any robots decision exists, or no host could ever be resolved.
      #
      # That exemption is bounded to EXACTLY the gate's own `robots.txt`. Unbounded, `kind: "robots"`
      # would authorize any URL on a host that had already failed closed, which is the whole gate
      # undone by a caller-supplied string.
      def robots_verdict(gate, canonical_url, kind)
        return robots_request_verdict(gate, canonical_url) if kind == "robots"
        # Content dispatch is blocked until the robots record is TERMINAL
        # (SEARCH_CRAWL_RETRIEVAL § Robots And Sitemap Processing). An unresolved host fails closed.
        return deny("fetch_robots_not_resolved") if gate.nil?
        return deny("fetch_robots_not_resolved") unless terminal?(gate["robots_state"])
        # :448 — a fail-closed host "denies ALL content fetching for that host for the run".
        return deny("fetch_robots_unavailable") if gate["robots_state"] == "unavailable"
        return nil unless gate["robots_state"] == "rules_applied"

        rules = parse_rules(gate["robots_rules"])
        # `rules_applied` with unreadable or absent rules is a corrupt record, not permission.
        return deny("fetch_robots_unavailable") if rules.nil?
        return nil if RobotsPolicy.allowed?(rules, path_of(canonical_url))

        deny("fetch_robots_disallowed")
      end

      # The robots exemption applies to one URL and one only: `https://<gate host>/robots.txt`.
      def robots_request_verdict(gate, canonical_url)
        return deny("fetch_robots_not_resolved") if gate.nil?
        return nil if canonical_url == "https://#{gate['canonical_host']}#{EnsureRobots::ROBOTS_PATH}"

        deny("fetch_robots_disallowed")
      end

      # :448's guarantee is PER HOST and per run, so a gate may only ever rule on its own
      # Organization's, its own Crawl's and its own host's URLs. A nil gate is handled by the robots
      # limb (it is a scheduling condition, not a mismatch).
      def gate_bound?(gate, organization_id, crawl_id, canonical_url)
        return true if gate.nil?

        gate["organization_id"] == organization_id && gate["crawl_id"] == crawl_id &&
          gate["canonical_host"].to_s.downcase == host_of(canonical_url)
      end

      def host_of(canonical_url)
        authority = canonical_url.to_s.sub(%r{\A[a-zA-Z][a-zA-Z0-9+.\-]*://}, "").split(%r{[/?#]}, 2).first.to_s
        authority = authority.split("@", 2).last.to_s          # drop any userinfo
        authority.start_with?("[") ? authority[0..authority.index("]").to_i].downcase
                                   : authority.split(":", 2).first.to_s.downcase
      end

      def terminal?(state) = %w[rules_applied no_restrictions unavailable].include?(state)

      # A stored rule set that cannot be read is an UNKNOWN, and every unknown denies. Returning an
      # empty rule set here would allow everything, which is the one thing this class must never do.
      def parse_rules(json)
        return nil if json.nil?

        payload = json.is_a?(::String) ? JSON.parse(json) : json
        rules = payload["rules"]
        return nil unless rules.is_a?(::Array)

        rules.map { |r| { allow: r["allow"], path: r["path"] } }
      rescue JSON::ParserError
        nil
      end

      # The path-and-query robots compares against, taken from the already-canonical URL.
      def path_of(canonical_url)
        without_scheme = canonical_url.to_s.sub(%r{\A[a-zA-Z][a-zA-Z0-9+.\-]*://}, "")
        slash = without_scheme.index("/")
        slash ? without_scheme[slash..] : "/"
      end

      def policy_of(row)
        Wf004::SourceScopePredicate::Policy.new(
          canonical_host: row["canonical_host"],
          allowed_schemes: Platform::PgArray.parse(row["allowed_schemes"]),
          allowed_ports: Platform::PgArray.parse_integers(row["allowed_ports"]),
          include_prefixes: Platform::PgArray.parse(row["include_prefixes"]),
          exclude_prefixes: Platform::PgArray.parse(row["exclude_prefixes"]),
          query_handling: query_handling(row["query_handling"])
        )
      end

      def query_handling(value)
        return Wf004::SourceScopePredicate::RETAIN_ALL if value.to_s == Wf004::SourceScopePredicate::RETAIN_ALL

        Platform::PgArray.parse(value)
      end

      def deny(reason) = Verdict.new(allowed: false, reason_code: reason, scope_policy_id: nil,
                                     scope_policy_version: nil)
    end
  end
end
