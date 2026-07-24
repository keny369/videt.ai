# FOUNDATION-001 — Shared Outbound Transport

Status: **Ratified contract (ADR-024).** Supporting architecture contract, not a canonical ADR; the decision of record is `DECISIONS.md` ADR-024. Implemented by the **F-01** tranche step before S-05.

- Ratified: 2026-07-24 (ADR-024)
- Owner context: Platform kernel (a shared foundation, consumed by Intake/verification and crawl; owned by neither)
- Consumers: **S-05** Ownership Verification (DNS TXT + HTTPS file observation) and **S-07** Crawl Execution (robots, sitemap, content, redirects). Any future platform-originated network access (AI providers, notifications, observation engines) is also a consumer.
- Supersedes: the SECURITY_PERFORMANCE.md statement that "S-07 owns the only outbound surface" (DEF-2). Ownership of the egress surface moves from S-07 to this shared foundation; S-07 becomes a consumer.

## Purpose

One, and only one, guarded surface through which **all platform-originated DNS and HTTP(S) access** leaves F1. There is never a second verification-specific or crawler-specific egress path. Making the outbound surface singular is what makes SSRF prevention, auditability and policy a property of the platform rather than of each caller.

## Mandatory properties

The adapter MUST enforce, on every attempt, before any bytes are exchanged:

1. **SSRF prevention before resolution AND before connection.** Resolve the exact canonical host; reject as a nonretryable outcome if the answer is empty or any answer is not public global-unicast. Prohibited space is **enumerated, not inferred** (IPv4 unspecified/current-network, private, CGNAT, loopback, link-local incl. `169.254.169.254`, protocol-assignment, documentation, benchmarking, multicast, reserved, broadcast; IPv6 unspecified, loopback, IPv4-mapped after conversion, discard-only, documentation, unique-local, link-local, multicast, reserved/non-global). **Mixed public+prohibited answers fail closed.**
2. **Hostname canonicalisation** to the ASCII canonical host before resolution (no raw Unicode; consistent with `ascii-host-v1`).
3. **DNS-rebinding protection.** Pin the first sorted allowed address for the attempt; send the canonical host as HTTP `Host` and TLS SNI; **verify the transport peer equals the pinned address**; do not re-resolve inside an attempt.
4. **Redirect revalidation.** A redirect performs a **new full resolution and SSRF check** and never inherits the prior host's decision. Redirect policy (follow/reject, max count) is a per-caller parameter within a hard platform ceiling.
5. **Scheme and port policy.** HTTPS only for content/verification observation; caller-declared allowed ports within a platform allowlist; default-port normalization.
6. **Response-size limits** and **timeout budgets** as caller-supplied parameters bounded by hard platform ceilings (e.g., connect+response deadline; per-response byte cap; read stops at the cap +1 to prove oversize).
7. **Content-type / body policy** where the caller declares one; raw bytes are surfaced to the caller for the caller's own digest/decision, never interpreted by the transport.
8. **TLS validation** (certificate chain + hostname) with caller-visible failure as a typed outcome, never a silent downgrade.
9. **Auditable request/response metadata** — canonical host, pinned address, scheme, status/response-code, byte count, latency, outcome enum — with **secret redaction**: header values, response bodies, DNS values, host addresses and unrestricted error text are reduced to enums/counts, never logged raw.
10. **No direct network access outside this adapter.** No `Net::HTTP`/`Resolv`/socket use anywhere else in `app/`/`lib/`; an architecture fitness check enforces the single surface.

## Abstraction

A vendor-neutral, caller-parameterised interface returning a typed outcome (`response`, `timeout`, `resolver_failure`, `connection_failure`, `tls_failure`, plus status/DNS code, byte count, raw bytes reference). Callers own their own predicate over the outcome (e.g., S-05's DNS/HTTP match rules; S-07's robots/content rules). The adapter owns *safety*; the caller owns *meaning*.

## Acceptance criteria (for the F-01 implementation)

- Every prohibited IPv4/IPv6 range is rejected before connection, proven per-range; mixed answers fail closed.
- DNS-rebinding is defeated: a host resolving to a public then a private address on re-resolution cannot reach the private address (peer-equality check).
- A redirect to a prohibited host is rejected with a fresh check; the prior decision is not inherited.
- Byte cap stops the read at cap+1 and reports oversize; `Content-Length` is not trusted.
- Timeout, TLS failure, resolver failure and connection failure each produce their exact typed outcome.
- No secret/raw content appears in any log, event, audit or metric — asserted.
- Deterministic tests use fixtures/local doubles; **no live internet calls in the suite**.
- Architecture check: no outbound socket/DNS/HTTP primitive exists outside this adapter.

## Non-goals / boundaries

- **Not** the crawl frontier, robots parsing, sitemap enumeration, or budget accounting — those stay in S-07 and consume this adapter.
- **Not** DNS record management, ownership challenge issuance, or content interpretation.
- No caller may widen the SSRF prohibition set or bypass the adapter.

## Genesis + Videt

Genesis contracts are unchanged; this ratifies the single egress surface the spec already implied. It is exactly the "outbound abstraction" the Videt future architecture (ADR-012) calls for: provider-independent, auditable, and reusable by future observation/provider engines without a second egress path.
