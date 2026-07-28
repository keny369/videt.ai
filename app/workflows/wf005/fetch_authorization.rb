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
      end

      # Every reason this gate can return. All are terminal for the URL: none is retryable, because
      # each names a revoked or absent authority rather than a transient condition.
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
      ].freeze

      def initialize(store)
        @store = store
      end

      # Authorize ONE candidate URL immediately before its connection. `gate` is the locked host-gate
      # row; nil means robots has not been resolved for the host, which is itself a denial for a
      # content fetch.
      def authorize(organization_id:, crawl_id:, source_id:, canonical_url:, gate:, kind: "content")
        org = @store.organization(organization_id)
        return deny("fetch_organization_inactive") unless org && org["status"] == "active"

        crawl = @store.crawl(organization_id, crawl_id)
        return deny("fetch_crawl_not_running") unless crawl && crawl["state"] == "running"

        project = @store.project(organization_id, crawl["project_id"])
        return deny("fetch_project_not_active") unless project && project["state"] == "active"

        # The Source must STILL be active. `disabled`, `removed`, and every pre-`active` state are
        # denials: a Source the customer has switched off is never fetched on queue-time authority,
        # whatever the frontier still holds.
        source = @store.source(organization_id, source_id)
        return deny("fetch_source_not_active") unless source && source["state"] == "active"

        # The entitlement reservation that admitted this run must still be executing. A released,
        # committed or expired reservation means the run is no longer metered, and an unmetered
        # fetch is exactly what PRULE-007 exists to prevent.
        unless @store.reservation_executing?(organization_id, crawl["entitlement_reservation_id"])
          return deny("fetch_entitlement_not_executing")
        end

        scope = @store.current_scope_policy(organization_id, source_id)
        return deny("fetch_scope_policy_unavailable") if scope.nil?

        # The CURRENT restrictive scope, re-evaluated now — not the version pinned at queue time.
        decision = Wf004::SourceScopePredicate.evaluate(url: canonical_url, policies: [policy_of(scope)])
        return deny("fetch_url_out_of_scope") unless decision.allowed?

        robots_verdict(gate, canonical_url, kind) ||
          Verdict.new(allowed: true, reason_code: nil, scope_policy_id: scope["id"],
                      scope_policy_version: scope["policy_version"])
      end

      private

      # Robots governs CONTENT (and sitemap) fetches only — the robots fetch itself must be able to
      # proceed before any robots decision exists, or no host could ever be resolved.
      def robots_verdict(gate, canonical_url, kind)
        return nil if kind == "robots"
        # Content dispatch is blocked until the robots record is TERMINAL
        # (SEARCH_CRAWL_RETRIEVAL § Robots And Sitemap Processing). An unresolved host fails closed.
        return deny("fetch_robots_unavailable") if gate.nil?
        return deny("fetch_robots_unavailable") unless terminal?(gate["robots_state"])
        # :448 — a fail-closed host "denies ALL content fetching for that host for the run".
        return deny("fetch_robots_unavailable") if gate["robots_state"] == "unavailable"
        return nil unless gate["robots_state"] == "rules_applied"

        rules = parse_rules(gate["robots_rules"])
        return nil if RobotsPolicy.allowed?(rules, path_of(canonical_url))

        deny("fetch_robots_disallowed")
      end

      def terminal?(state) = %w[rules_applied no_restrictions unavailable].include?(state)

      def parse_rules(json)
        return [] if json.nil?

        payload = json.is_a?(::String) ? JSON.parse(json) : json
        Array(payload["rules"]).map { |r| { allow: r["allow"], path: r["path"] } }
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
          allowed_schemes: pg_array(row["allowed_schemes"]),
          allowed_ports: pg_array(row["allowed_ports"]).map(&:to_i),
          include_prefixes: pg_array(row["include_prefixes"]),
          exclude_prefixes: pg_array(row["exclude_prefixes"]),
          query_handling: query_handling(row["query_handling"])
        )
      end

      def query_handling(value)
        return Wf004::SourceScopePredicate::RETAIN_ALL if value.to_s == Wf004::SourceScopePredicate::RETAIN_ALL

        pg_array(value)
      end

      # PostgreSQL array literal -> Ruby Array.
      def pg_array(value)
        return value if value.is_a?(::Array)
        return [] if value.nil?

        value.to_s.delete_prefix("{").delete_suffix("}").split(",").reject(&:empty?).map { |v| v.delete('"') }
      end

      def deny(reason) = Verdict.new(allowed: false, reason_code: reason, scope_policy_id: nil,
                                     scope_policy_version: nil)
    end
  end
end
