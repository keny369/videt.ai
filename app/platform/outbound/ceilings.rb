# frozen_string_literal: true

module Platform
  module Outbound
    # The hard platform ceilings for the single guarded outbound surface
    # (FOUNDATION-001 mandatory properties 4/5/6). Every caller-supplied timeout,
    # byte cap, redirect budget and port is bounded by these — a caller may ask for
    # something tighter, never wider (FOUNDATION-001 :48 "No caller may widen the
    # SSRF prohibition set or bypass the adapter").
    #
    # The numbers are the ratified crawl-policy-v1 HARD bounds (SECURITY_PERFORMANCE.md
    # PRULE-008 :550-553), which are the widest any platform-originated request may be:
    # connect-plus-response 10/15s, per-URL body 8/10 MiB, redirects 5/10. S-05 verification
    # (SCORE_EVIDENCE_MODEL.md :137,:144-147) runs strictly inside them (10s, 4 KiB, 0 redirects).
    module Ceilings
      module_function

      # Connect-plus-response hard bound (15s). DNS resolution is one component of a
      # network operation, so its timeout is bounded by the same outermost ceiling.
      CONNECT_RESPONSE_TIMEOUT_MAX_S = 15.0
      DNS_TIMEOUT_MAX_S = 15.0

      # Per-URL body hard bound (10 MiB). The read stops at cap+1 to prove oversize.
      RESPONSE_BYTES_MAX = 10 * 1024 * 1024

      # Redirect hard bound (10). A caller may permit fewer (S-05 permits none).
      REDIRECTS_MAX = 10

      # HTTPS only; the platform port allowlist. Content and verification observation
      # are HTTPS (FOUNDATION-001 property 5); there is no plaintext egress.
      ALLOWED_PORTS = [443].freeze
      DEFAULT_PORT = 443

      # Clamp a caller timeout into (0, max]. A value above the ceiling is reduced to the
      # ceiling; a non-positive, missing or NaN value (a caller bug — an instant-timeout
      # would break every request) falls back to the ceiling, which is still bounded.
      # Either way the request stays within the hard budget.
      def clamp_positive(value, max)
        n = value.to_f
        return max if n.nan? || n <= 0.0

        [n, max].min
      end

      # Clamp a caller byte cap into [0, RESPONSE_BYTES_MAX]. Zero is a legitimate cap
      # (a body-free probe); a value above the ceiling is reduced to the ceiling.
      def clamp_bytes(value, max = RESPONSE_BYTES_MAX)
        n = value.to_i
        return 0 if n.negative?

        [n, max].min
      end

      # Clamp a caller redirect budget into [0, REDIRECTS_MAX].
      def clamp_redirects(value, max = REDIRECTS_MAX)
        n = value.to_i
        return 0 if n.negative?

        [n, max].min
      end
    end
  end
end
