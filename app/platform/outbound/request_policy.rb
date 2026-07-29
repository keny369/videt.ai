# frozen_string_literal: true

module Platform
  module Outbound
    # A caller's parameterisation of one guarded request (FOUNDATION-001 properties
    # 4/5/6). The caller owns the numbers; the platform bounds them. Every field is
    # clamped to a Ceilings hard bound on construction, so a constructed policy can
    # only ever be within the ratified envelope — a caller may ask for something
    # tighter, never wider.
    #
    #  - timeout_s     : the connect-plus-response deadline for ONE connection attempt
    #                    (each redirect hop is a fresh attempt with its own budget),
    #                    bounded by the 15s hard ceiling. S-05 verification passes 10s.
    #  - byte_cap      : the entity-body cap; the reader stops after byte_cap + 1 bytes
    #                    so byte_cap + 1 proves oversize. S-05 http_file passes 4096.
    #  - max_redirects : redirects to follow before rejecting, bounded by 10.
    #                    S-05 passes 0 (every 3xx is http_redirect_rejected).
    #  - allowed_ports : the caller's port allowlist, intersected with the platform
    #                    allowlist (HTTPS only). Empty intersection is a configuration
    #                    error surfaced as an unsupported-port rejection at request time.
    #  - user_agent    : the request User-Agent; defaults to the crawler token.
    #  - redirect_guard: an optional caller predicate consulted for each redirect TARGET
    #                    before it is followed, receiving the resolved absolute URI and
    #                    returning truthy to allow. This is step 1 of the connector's
    #                    indivisible per-redirect sequence in SEARCH_CRAWL_RETRIEVAL.md
    #                    § Destination And HTTP Safety — "canonicalize and RECHECK SOURCE
    #                    SCOPE AND ROBOTS POLICY" — and WORKFLOW_SPECIFICATIONS.md :448,
    #                    "Redirects are rechecked against robots and Source Scope Policy
    #                    BEFORE FOLLOWING". Only the caller knows those policies, so the
    #                    platform cannot evaluate them and must not follow blindly.
    #
    #                    The platform still owns every safety property regardless of what
    #                    the guard returns: it can only ever REFUSE a hop the platform
    #                    would have allowed, never admit one the platform refused. Nil
    #                    means "no caller policy", which is the behaviour every existing
    #                    caller already had.
    RequestPolicy = Data.define(:timeout_s, :byte_cap, :max_redirects, :allowed_ports, :user_agent,
                                :redirect_guard) do
      def self.build(timeout_s:, byte_cap:, max_redirects: 0, allowed_ports: nil,
                     user_agent: Ceilings::DEFAULT_USER_AGENT, redirect_guard: nil)
        ports = Array(allowed_ports || Ceilings::ALLOWED_PORTS).map(&:to_i) & Ceilings::ALLOWED_PORTS
        new(
          timeout_s: Ceilings.clamp_positive(timeout_s, Ceilings::CONNECT_RESPONSE_TIMEOUT_MAX_S),
          byte_cap: Ceilings.clamp_bytes(byte_cap),
          max_redirects: Ceilings.clamp_redirects(max_redirects),
          allowed_ports: ports.uniq.freeze,
          user_agent: user_agent.to_s,
          redirect_guard:
        )
      end

      # Would the caller's policy admit this redirect target? A caller that supplied no
      # guard admits every hop the PLATFORM already validated.
      def redirect_allowed?(uri) = redirect_guard.nil? || !!redirect_guard.call(uri)

      def port_allowed?(port) = allowed_ports.include?(port)

      # The number of entity-body bytes the reader will accumulate: one past the cap,
      # so reaching this count proves the body exceeded the cap.
      def read_limit = byte_cap + 1
    end
  end
end
