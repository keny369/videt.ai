# frozen_string_literal: true

module Platform
  # Shared Outbound Transport (F-01, FOUNDATION-001) — FROZEN public contract.
  #
  # This module IS the entire public surface of the platform's single guarded egress.
  # Every platform-originated HTTP(S) request and every verification DNS lookup — S-05
  # Ownership Verification, S-07 Crawl Execution, and any future HTTP-based capability
  # (AI providers, robots/sitemap retrieval, health checks, integrations) — goes through
  # `fetch` / `fetch_dns_txt`. There is no other outbound path.
  #
  # The guarded classes behind these two methods (GuardedResolver, GuardedHttpClient,
  # TlsConnector, SystemResolver, HttpResponseReader, RequestPolicy, Ceilings,
  # AddressPolicy) are INTERNAL. A consumer must never construct or call them directly:
  # doing so would be a second way to reach the network and could bypass the SSRF
  # classification, address pinning, peer-equality, redirect revalidation or byte cap.
  # `spec/architecture/outbound_single_surface_spec.rb` fails CI on both halves — a raw
  # socket/DNS/TLS/HTTP primitive, OR a reference to an internal transport class, outside
  # this adapter.
  #
  # The adapter owns SAFETY; the caller owns MEANING. `fetch` returns a typed Outcome and
  # `fetch_dns_txt` a Txt/Refusal; the caller reads their fields (all duck-typed, so a
  # consumer never has to name an internal class) and applies its own predicate.
  module Outbound
    module_function

    # Perform a guarded HTTPS GET and return an Outcome. Every budget is clamped to the
    # platform hard ceilings on the way in — a caller may ask for tighter, never wider.
    #
    #   Platform::Outbound.fetch("https://host/.well-known/f1-verification.txt",
    #                            timeout_s: 10, byte_cap: 4096, max_redirects: 0)
    #     => Outcome(kind: :response|:timeout|:connection_failure|:tls_failure|
    #                      :resolver_failure|:rejected, ...)
    #
    # `timeout_s` IS A PER-ATTEMPT CEILING AND `total_timeout_s` IS THE WALL-CLOCK BOUNDARY
    # (FU-43, ADR-141). DNS, connection setup, TLS negotiation, response headers, body reads
    # and every redirect hop spend ONE budget; no hop re-arms anything, and the effective
    # timeout for each operation is the lesser of the two. `total_timeout_s` DEFAULTS TO
    # `timeout_s`, so a caller that supplies only a per-attempt number gets that number as
    # its total — the tightest reading — and there is no form of this call that is unbounded.
    def fetch(url, timeout_s:, byte_cap:, total_timeout_s: nil, max_redirects: 0, allowed_ports: nil,
              user_agent: nil, redirect_guard: nil)
      policy = RequestPolicy.build(
        timeout_s:, byte_cap:, total_timeout_s:, max_redirects:, allowed_ports:,
        user_agent: user_agent || Ceilings::DEFAULT_USER_AGENT, redirect_guard:
      )
      GuardedHttpClient.new.get(url, policy:)
    end

    # Resolve TXT records for a canonical host through the same guarded DNS surface
    # (S-05 dns_txt). Returns Txt(records) on success, or Refusal(reason, retryable) with
    # reason :absent / :resolver_timeout / :resolver_temporary_failure for the caller to
    # map to its own dns_* reasons. There is no address pinning on a record lookup: the
    # SSRF surface is the configured recursive resolver, not the customer host.
    def fetch_dns_txt(host, timeout_s:)
      GuardedResolver.new.resolve_txt(host, timeout_s:)
    end
  end
end
