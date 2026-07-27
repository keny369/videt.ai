# frozen_string_literal: true

module Workflows
  module Wf004
    # The pure Source Scope Change classifier (WF-004 Source Scope Change Contract,
    # WORKFLOW_SPECIFICATIONS.md :410-421; APPLICATION_LAYER.md § WF-004 :769-813;
    # owner decision HD-S06-002-SCOPE-CLASSIFIER = Option B, DECISIONS ADR-054).
    #
    # Given the current active Source Scope Policy, a proposed policy, and the verified
    # boundary (all as `SourceScopePredicate::Policy` value objects), it classifies a
    # proposed scope change as `:contraction`, `:expansion`, or `:boundary_violation` so
    # the caller (WF-004 ProposeSourceScopeChange / DecideSourceScopeChange, later
    # sub-tranches) can route dual control: a contraction may activate atomically without
    # dual control; an expansion needs an OrganizationAdmin; a boundary violation is
    # rejected through the authoritative failure path and is never a classification.
    #
    # Option B semantics:
    #   1. Base classification is a SEMANTIC SUBSET test with PRULE-021 (S-06-001) as the
    #      admission ORACLE: a proposal is a CONTRACTION only when its admitted URL set is
    #      a subset of the current active policy's admitted set. Any non-strict-subset or
    #      mixed change is an EXPANSION. Fail-closed: inability to prove subset => expansion.
    #   2. Query handling exception: any query-handling change that can INCREASE the set of
    #      distinct crawlable canonical URLs (canonical-target multiplicity) is an EXPANSION,
    #      even though query parameters do not affect PRULE-021 admission. `allowlist ->
    #      retain_all`, or widening the retained-key set, is an expansion; a change that
    #      preserves or reduces multiplicity may remain contraction-eligible.
    #   3. Boundary: host/scheme/port beyond the verified boundary is a `:boundary_violation`,
    #      not a classification.
    #
    # It is PURE: no persistence, no outbound call, no event, no mutation of its inputs;
    # the same inputs always yield the same Result.
    module ScopeChangeClassification
      module_function

      Predicate = SourceScopePredicate

      # A fresh path segment used to probe "strictly inside a prefix's cone but matching no
      # deeper prefix". ASCII/unreserved so it is a valid path and never a real customer
      # prefix segment; collision would only matter if a policy literally used it as a path
      # component, which the caller's normalization and this token's shape make absurd.
      WITNESS_SEGMENT = "f1-scope-classifier-witness"

      Result = Data.define(:classification, :reason) do
        def contraction? = classification == :contraction
        def expansion? = classification == :expansion
        def boundary_violation? = classification == :boundary_violation
      end

      # Classify the proposed change. `boundary` is the verified boundary policy
      # (source-scope-interim-v1 shape: the verified host, HTTPS, its default port,
      # include "/", no exclude, retain_all).
      def classify(current:, proposed:, boundary:)
        # The boundary check is intentionally OUTSIDE the fail-closed rescue below: a
        # boundary violation must hard-reject and must never degrade to an approvable
        # expansion (independent review, ADR-057). For the documented Policy value-object
        # inputs it cannot raise; if a malformed non-Policy input made it raise, the error
        # propagates and the caller rejects, which is more restrictive than an expansion.
        violation = boundary_violation(proposed, boundary)
        return Result.new(classification: :boundary_violation, reason: violation) if violation

        classify_broadening(current, proposed)
      end

      # The broadening classification, guarded fail-closed (ADR-054): an unexpected error
      # in the admitted-set or query probes means non-broadening could not be proven, so the
      # result is an EXPANSION — never a contraction (the sole auto-activating classification).
      def classify_broadening(current, proposed)
        return expansion("broadens_admitted_set") if admitted_set_broadens?(proposed, current)
        return expansion("broadens_query_multiplicity") if query_multiplicity_broadens?(proposed, current)

        Result.new(classification: :contraction, reason: nil)
      rescue StandardError
        expansion("unprovable_fail_closed")
      end

      def expansion(reason) = Result.new(classification: :expansion, reason:)

      # ---- boundary (host / scheme / port must stay within the verified boundary) ----

      def boundary_violation(proposed, boundary)
        return "cross_host_expansion" unless proposed.canonical_host.to_s.downcase == boundary.canonical_host.to_s.downcase
        return "unsupported_source_scheme" unless subset?(downcase(proposed.allowed_schemes), downcase(boundary.allowed_schemes))
        return "port_out_of_boundary" unless subset?(ints(proposed.allowed_ports), ints(boundary.allowed_ports))

        nil
      end

      # ---- admitted-set broadening (PRULE-021 as the oracle) ----

      # True iff some URL is admitted by `proposed` but denied by `current` — i.e. the
      # proposed admitted set is NOT a subset of the current one. Witnesses are derived
      # from every include/exclude prefix of both policies (the admission decision only
      # changes at prefix boundaries), so a finite probe set is complete for the
      # `/`-boundary prefix semantics. Host/scheme/port are equal within the boundary, so
      # the probe varies only the path.
      def admitted_set_broadens?(proposed, current)
        host = proposed.canonical_host
        witness_paths(current, proposed).any? do |path|
          url = "https://#{host}#{path}"
          Predicate.evaluate(url:, policies: [proposed]).allowed? &&
            !Predicate.evaluate(url:, policies: [current]).allowed?
        end
      end

      def witness_paths(current, proposed)
        prefixes = (Array(current.include_prefixes) + Array(current.exclude_prefixes) +
                    Array(proposed.include_prefixes) + Array(proposed.exclude_prefixes) + ["/"]).uniq
        paths = prefixes.flat_map { |prefix| [prefix, "#{prefix.chomp('/')}/#{WITNESS_SEGMENT}"] }
        (paths + ["/#{WITNESS_SEGMENT}-none"]).uniq
      end

      # ---- query-handling multiplicity broadening ----

      # True iff the proposed query handling can produce MORE distinct canonical URLs than
      # the current one. `retain_all` is the maximal multiplicity (every query variation is
      # distinct); an allowlist retains only its keys. So multiplicity broadens iff the
      # proposed retained-key set is not a subset of the current one (retain_all = the
      # universal set).
      def query_multiplicity_broadens?(proposed, current)
        cur = current.query_handling
        prop = proposed.query_handling
        return false if cur == Predicate::RETAIN_ALL   # current already maximal; nothing broadens it
        return true if prop == Predicate::RETAIN_ALL    # proposed maximal, current not => broadens

        # both explicit allowlists: broadens iff proposed retains a key current does not
        !subset?(Array(prop), Array(cur))
      end

      # ---- helpers ----

      def subset?(a, b) = (a - b).empty?
      def downcase(values) = Array(values).map { |v| v.to_s.downcase }
      def ints(values) = Array(values).map(&:to_i)
    end
  end
end
