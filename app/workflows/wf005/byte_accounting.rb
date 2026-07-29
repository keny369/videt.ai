# frozen_string_literal: true

module Workflows
  module Wf005
    # WORKFLOW_SPECIFICATIONS.md :442's byte-accounting protocol, as a value type plus the pure
    # arithmetic. The persistence is `CrawlBudgetStore`; what lives here is the part that must be
    # right regardless of storage.
    #
    # THE FORMULA (:436). "For attempt `i`,
    #   accounted_response_bytes_i = max(received_entity_body_bytes_i_after_transfer_coding,
    #                                    expanded_body_bytes_i_after_content_decoding)"
    # — the MAXIMUM of the two paths, not the received count and not the decoded count. A response
    # that arrives as 2 KiB of gzip and expands to 40 MiB costs the run 40 MiB, and a response that
    # arrives as 8 MiB of plain text costs 8 MiB even though decoding produced nothing new. Taking
    # either path alone lets one of the two shapes through unaccounted.
    #
    # THE SENTINEL (:436). "To distinguish an EXACT-MAXIMUM body from an OVER-LIMIT body, the reader
    # may inspect AT MOST ONE nonretained sentinel byte on EACH accounting path after the maximum;
    # sentinel bytes are recorded separately as `limit_probe_bytes`, are NEVER PARSED OR RETAINED,
    # and do not enter either accounted counter. EOF at the maximum is ALLOWED; observing a sentinel
    # byte FAILS THAT URL as over-limit."
    #
    # That is a genuine three-way distinction and the reason `truncated` alone is not enough: a body
    # of exactly the maximum and a body of maximum+1 both stop the reader at the same place. F-01
    # reads `byte_cap + 1` bytes precisely so the caller can tell them apart — reaching cap+1 IS the
    # sentinel observation, and it means over-limit; stopping at or below the cap means the body
    # ended within the bound.
    module ByteAccounting
      module_function

      # :425-438 — response body per URL soft 8 / hard 10 MiB; accounted response-body bytes per run
      # soft 1,000 / hard 1,250 MiB.
      MIB = 1024 * 1024
      PER_URL_CEILING = CrawlPolicy::GLOBAL_CEILING.fetch("per_url_body_mib").fetch("hard") * MIB
      PER_URL_TARGET = CrawlPolicy::GLOBAL_CEILING.fetch("per_url_body_mib").fetch("soft") * MIB
      RUN_CEILING = CrawlPolicy::GLOBAL_CEILING.fetch("run_response_mib").fetch("hard") * MIB
      RUN_TARGET = CrawlPolicy::GLOBAL_CEILING.fetch("run_response_mib").fetch("soft") * MIB

      OVER_LIMIT = "response_body_limit_exceeded"

      # What one attempt actually consumed. `probe_bytes` is the sentinel count — at most one per
      # accounting path — and is deliberately NOT part of `accounted`.
      Measurement = Data.define(:accounted, :received, :expanded, :probe_bytes, :over_limit) do
        def over_limit? = over_limit
      end

      # Measure one response against a per-URL ceiling.
      #
      # `expanded` is the content-decoded length when the transport decoded the body, and nil when
      # it did not — in which case the two accounting paths coincide and the received count IS the
      # accounted count. Passing `received` for both would be equivalent; nil says "there was one
      # path", which is the honest description.
      def measure(received:, expanded: nil, ceiling: PER_URL_CEILING)
        received = received.to_i
        # ":442 — at most one nonretained sentinel byte on EACH accounting path". When the transport
        # did not content-decode the body there is ONE path, not two that happen to agree, so the
        # probe count must be one. Deriving `expanded` from `received` and then counting both would
        # report two probes for a single observation and inflate the telemetry counter.
        paths = expanded.nil? ? [received] : [received, expanded.to_i]

        # A path that reached ceiling + 1 has had its one sentinel byte observed: the body is
        # over-limit, and that byte is telemetry rather than capacity.
        probes = paths.count { |n| n > ceiling }
        accounted = paths.map { |n| n > ceiling ? ceiling : n }.max

        Measurement.new(accounted:, received:, expanded: expanded.nil? ? received : expanded.to_i,
                        probe_bytes: probes, over_limit: probes.positive?)
      end

      # What to reserve before reading a body. :442 — "the scheduler RESERVES UP TO the per-URL
      # maximum from the REMAINING run-wide budget". Up to, so a run with 3 MiB left reserves 3 MiB
      # and the attempt is bounded by that rather than by the per-URL ceiling; and a run with none
      # left reserves nothing, which is the caller's signal that the dimension is exhausted.
      def reservation(remaining:, per_url: PER_URL_CEILING)
        [[remaining.to_i, per_url].min, 0].max
      end

      # The effective per-URL and per-run bounds for one Crawl: the most restrictive of the frozen
      # global ceiling and every active Organization/Project crawl policy (:390 — "effective crawl
      # and capacity limits are the most restrictive of global safety, approved entitlement,
      # Organization, and Project limits").
      Bounds = Data.define(:per_url, :per_url_target, :per_run, :per_run_target)

      def bounds_from(policy_bounds)
        per_url = policy_bounds.fetch("per_url_body_mib")
        per_run = policy_bounds.fetch("run_response_mib")
        Bounds.new(per_url: per_url.fetch("hard").to_i * MIB,
                   per_url_target: per_url.fetch("soft").to_i * MIB,
                   per_run: per_run.fetch("hard").to_i * MIB,
                   per_run_target: per_run.fetch("soft").to_i * MIB)
      end

      GLOBAL_BOUNDS = bounds_from(CrawlPolicy::GLOBAL_CEILING)
    end
  end
end
