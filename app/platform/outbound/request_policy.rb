# frozen_string_literal: true

module Platform
  module Outbound
    # A caller's parameterisation of one guarded request (FOUNDATION-001 properties
    # 4/5/6). The caller owns the numbers; the platform bounds them. Every field is
    # clamped to a Ceilings hard bound on construction, so a constructed policy can
    # only ever be within the ratified envelope — a caller may ask for something
    # tighter, never wider.
    #
    #  - timeout_s     : the connect-plus-response ceiling for ONE connection attempt,
    #                    bounded by the 15s hard ceiling. S-05 verification passes 10s.
    #                    IT IS A SUBORDINATE CEILING, NOT A BUDGET (FU-43): it used to be
    #                    re-armed per redirect hop, so it was the only bound and a chain
    #                    of hops multiplied it. The effective timeout for every operation
    #                    is now `min(timeout_s, remaining total budget)`.
    #  - total_timeout_s : THE WALL-CLOCK BOUNDARY FOR THE WHOLE OPERATION (FU-43).
    #                    DNS, connection setup, TLS negotiation, response headers, body
    #                    reads AND every redirect hop consume this one budget. When it is
    #                    exhausted the client stops deterministically with `:timeout`.
    #
    #                    IT DEFAULTS TO `timeout_s`, AND THAT IS THE POINT. The owner's
    #                    requirement is that "callers cannot accidentally bypass the total
    #                    deadline by supplying only a per-attempt timeout". A caller that
    #                    passes only `timeout_s: 10` therefore gets a TOTAL of 10 seconds
    #                    across every hop — the tightest possible reading — and a caller
    #                    that wants a redirect chain to have more must ask for it by name.
    #                    Omission cannot widen anything; there is no unbounded form.
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
    RequestPolicy = Data.define(:timeout_s, :total_timeout_s, :byte_cap, :max_redirects, :allowed_ports,
                                :user_agent, :redirect_guard) do
      def self.build(timeout_s:, byte_cap:, total_timeout_s: nil, max_redirects: 0, allowed_ports: nil,
                     user_agent: Ceilings::DEFAULT_USER_AGENT, redirect_guard: nil)
        ports = Array(allowed_ports || Ceilings::ALLOWED_PORTS).map(&:to_i) & Ceilings::ALLOWED_PORTS
        per_attempt = Ceilings.clamp_positive(timeout_s, Ceilings::CONNECT_RESPONSE_TIMEOUT_MAX_S)
        new(
          timeout_s: per_attempt,
          # The total defaults to the per-attempt number, so omitting it is the TIGHTEST form
          # rather than an unbounded one, and is then clamped to the platform's own hard bound.
          total_timeout_s: Ceilings.clamp_positive(total_timeout_s || per_attempt,
                                                   Ceilings::TOTAL_REQUEST_TIMEOUT_MAX_S),
          byte_cap: Ceilings.clamp_bytes(byte_cap),
          max_redirects: Ceilings.clamp_redirects(max_redirects),
          allowed_ports: ports.uniq.freeze,
          user_agent: user_agent.to_s,
          redirect_guard:
        )
      end

      # THE EFFECTIVE TIMEOUT FOR ONE OPERATION: the lesser of the per-attempt ceiling and what is
      # left of the total budget (FU-43). Every network operation the client performs — the resolver
      # call, the connect, the read — asks this rather than reading `timeout_s` directly, so there
      # is one place the rule lives and no operation can be given a budget the total does not have.
      def effective_timeout_s(remaining_s) = [timeout_s, remaining_s].min

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
