# Volume II Search, Crawl And Retrieval Architecture

## Status And Authority

- Status: Volume II Implementation Architecture Pass 001
- Behavioural baseline: frozen Volume I at `v1.5-volume-i-frozen` (commit `c6b3853`, ADR-020). Historical `v1.3-volume-i-corrected` is retained as predecessor history and is not the baseline.
- Engineering-practice baseline: accepted Engineering Manual at `v1.7-engineering-manual-accepted` (commit `b049a41`, ADR-022), normative for engineering practice only.
- Behaviour owner: [Volume I workflows](../volume-i/WORKFLOW_SPECIFICATIONS.md)
- Persistence owner: [PostgreSQL schema](../../schemas/POSTGRESQL_SCHEMA.md)
- Job owner: [Background processing](BACKGROUND_PROCESSING.md)

This document fixes the physical crawler, parser, index and retrieval implementation. It does not change Source scope, crawl limits, coverage, Evidence, Evaluation readiness, Check behavior or customer-visible search capability.

## Component Boundary

| Component | Rails package | Input | Durable output | Prohibited responsibility |
| --- | --- | --- | --- | --- |
| Crawl coordinator | `Intake` | admitted Crawl and frozen policies | ordered frontier, fetch attempts and terminal Crawl decision | parsing, Check execution, provider measurement |
| Destination connector | `Intake` infrastructure | one claimed fetch attempt | normalized transport result and staged bytes | redirects or retries not directed by coordinator |
| Ingestion validator | `Intake` | staged successful fetch | Document, source-document Evidence and IngestionJob result | interpreting HTML |
| Parser | `Intake` infrastructure | validated immutable Document bytes | `parsed-observation-v1` Parsed Artifact | network access or remote context resolution |
| Evaluation-input builder | `Evaluation` with `Intake` DTOs | sealed parse manifest | immutable Evaluation Input Snapshot and derived Evidence | using retrieval index output |
| Index writer | `Retrieval` | validated Parsed Artifact | search document plus immutable Index Receipt | mutating Evidence or Evaluation input |
| Internal retriever | `Retrieval` | authorized typed retrieval request | bounded result DTO with lineage | public/customer arbitrary search |

The crawl aggregate remains the canonical write entry for Document execution lineage. Indexing is a non-gating projection. A parser success may enqueue indexing, but Evaluation readiness never waits for an IndexingJob.

## Pinned Parsing And URL Stack

- URL syntax, percent handling and HTTP-date parsing use Ruby 3.4.10 standard-library `URI`, `IPAddr` and `Time`; a single `Intake::Domain::CanonicalUrlV1` implementation applies the stricter Volume I rules. No controller, adapter or parser has a second canonicalizer.
- HTML/XHTML/XML parsing uses Nokogiri `1.19.4` from its precompiled `x86_64-linux-gnu` package. The parser artifact records the Nokogiri version, bundled libxml2/libxslt or libgumbo version, platform checksum and parser-policy hash.
- HTTP uses Ruby `Net::HTTP` behind `Intake::Application::Ports::DestinationHttp`. `max_retries=0`; decompression is explicit; redirects, retries, DNS and deadlines are coordinator decisions rather than library defaults.
- DNS uses the platform resolver through `Resolv::DNS` behind `DestinationResolver`. It returns the complete answer set; the connector never accepts an OS-resolver-selected address that was absent from the validated set.
- Unicode normalization uses Ruby `String#unicode_normalize(:nfc)`. BCP-47 validation and every normalized payload rule live in versioned pure validators, not database collation.

Changing any item that can alter canonical URL, document, parser or index output requires a new policy/schema version, side-by-side output comparison and a new artifact or index generation. A dependency patch that provably cannot change semantic output still requires the ordinary dependency security gate.

## Crawl Admission And Snapshot

`TriggerCrawl` only persists an admitted queued Crawl. `StartCrawl` locks the Project, Source-set version, Crawl and entitlement counter in the global lock order, then atomically:

1. reauthorizes current Organization/Project/Source state;
2. resolves and stores full immutable Policy Snapshot references;
3. reserves the root high-cost entitlement;
4. changes the Crawl to running;
5. creates the one initial Evaluation when this is a root run;
6. creates ordered root frontier entries; and
7. emits the outbox events.

No network connection occurs in that transaction. The post-commit outbox creates the first `crawl_dispatch` ScheduledAction. Reassessment child execution reuses the reassessment Evaluation and reservation exactly as Volume I requires.

## Frontier And Deterministic Selection

PostgreSQL is the authority for frontier state. Redis and Sidekiq carry only wake-up identities. The physical records are:

- `crawl_frontier_entries`: one complete retained uniqueness preimage and hash per distinct candidate, origin, depth, discovery locator, policy decision and terminal disposition;
- `crawl_frontier_occurrences`: every duplicate discovery and its referrer/position for audit, without becoming another candidate;
- `crawl_host_gates`: next permitted start, active connection count, robots state and generation under a row lock;
- `crawl_budget_counters`: reserved/committed pages, queue entries, accounted bytes, sitemap documents, redirects and limit-event bits;
- `fetch_attempts`: immutable attempt identity/input plus mutable write-once checkpoint/result columns;
- `crawl_terminal_outcomes`: one serialized terminal-decision record.

Candidate order is materialized into `dequeue_key bytea` using the exact Volume I tuple. The byte encoding is length-prefixed unsigned big-endian depth/origin rank, then NFC UTF-8 fields, link position and UUID bytes. It is tested against a reference tuple comparator. Workers may fetch concurrently, but one coordinator commits discoveries and budget effects in increasing dequeue key. A completion with a later key waits in `fetched_pending_commit`; it cannot change selection.

All uniqueness allocations retain both SHA-256 and full canonical preimage. Hash equality without byte-equal preimage allocates a collision ordinal, never merges candidates, emits restricted collision telemetry and follows the Volume I integrity result.

## Destination And HTTP Safety

For each initial request, retry and redirect the connector executes this indivisible sequence:

1. canonicalize and recheck Source Scope and robots policy;
2. resolve all A/AAAA answers;
3. normalize IPv4-mapped IPv6, sort unique address bytes and reject the whole answer when any address is non-global under `destination-safety-v1`;
4. pin the first sorted allowed address;
5. connect to that address while sending only the canonical hostname as Host and TLS SNI;
6. validate the peer address equals the pin and validate the system trust chain plus hostname;
7. start the Volume I connection-plus-response deadline; and
8. stream through separate transfer-decoded and content-decoded bounded counters.

HTTP proxy environment variables are cleared for crawler processes. Redirect following, authentication challenge handling, cookies, client certificates, HTTP downgrade, alternate ports and automatic decompression are disabled unless the frozen policy explicitly admits the behavior. The connector sends no tenant credential. Response headers are reduced to an allowlisted normalized result; `Set-Cookie`, authentication fields and unrestricted server diagnostics are discarded.

The run and per-host gates use PostgreSQL `clock_timestamp()` and row locks. A worker cannot start merely because Redis granted a token. It claims a host slot only when the rolling-start and concurrency predicates pass, commits `submission_started`, then connects. Process loss after claim is repaired by the lease sweeper; the same attempt identity is completed or timed out, never replaced by an unaccounted request.

## Robots And Sitemap Processing

One robots record exists per `(crawl_id, canonical_host)` and stores request attempts, normalized rules, selected agent group, optional crawl delay, sitemap candidates, source digest and terminal reason. Content dispatch is blocked until that record is terminal. The parser implements the exact `F1DiscoverabilityBot` longest-rule algorithm from Volume I and is covered by a golden corpus.

Sitemap processing enforces the Volume I :450 guarantee — no DTD, general or parameter entity, XInclude, external schema, or network/file resolution reaches a parser — through three layered defences, because the SAX parser context exposes no options bitmask and therefore cannot itself express `NONET`.

First, an ENCODING GATE. :450 accepts UTF-8 XML only, and that is enforced as a security control rather than a formality: libxml2 auto-detects UTF-16 and UTF-32 from the leading bytes with no byte-order mark, and NUL-interleaved ASCII is itself valid UTF-8, so a raw-byte scan for a prohibited construct sees nothing while the parser decodes and processes it. A foreign byte-order mark, a declared non-UTF-8 encoding, an invalid UTF-8 sequence, and any NUL byte (illegal in XML at every position) are refused; a UTF-8 mark is stripped.

Second, a PRE-PARSE BYTE SCAN rejects `DOCTYPE`, `ENTITY` and the XInclude namespace before the parser is handed anything — before, not by configuring the parser to ignore it. It is authoritative only because the encoding gate guarantees it reads the bytes libxml2 will read.

Third, a PROLOG INSPECTION using libxml2's own lexer, through `Nokogiri::XML::Reader` in `NONET` mode with DTD loading, DTD attribute defaulting, entity substitution and XInclude disabled. The reader is pulled only as far as the root element, so it costs a prolog rather than a document, and it reports a document-type node for any `DOCTYPE`, including a spelling the byte scan does not anticipate. This is the independent mechanism: it is driven by the same parser that would perform the resolving, so it cannot disagree with it about what the document declares.

The streaming SAX pass then runs with error recovery and entity substitution off and aborts on any entity reference, and enforces all byte, character, element, nesting, document-count and index-depth counters while streaming. Media type is an allowlist that FAILS CLOSED: an absent `Content-Type` is not one of the three ratified names, and the header is attacker-controlled. A sitemap item only creates a frontier candidate after canonicalization, same-host scope, destination and queue admission checks.

The sitemap-document ceiling is a PER-RUN bound over distinct canonical sitemap URLs ATTEMPTED, reserved atomically from the Crawl's own limit counters before each attempt, so neither multiple hosts nor an index naming unreachable children can exceed it. :454's retention is a selection over the whole candidate set including index children, so which candidates are retained is decided by the ratified order rather than by the order a remote document named them. Every skipped or failed candidate is recorded with its reason, and the limit subset is recorded separately because only those force `limit_reached`.

Discovery for one host is claimed: the `pending -> in_progress` transition is version-guarded and mints a claim token, only the token holder may write the write-once terminal outcome, and an attempt whose worker was lost may be taken over after a stale window, the takeover rotating the token.

Robots and sitemap bytes are temporary-processing objects. Only their digests, normalized decision records and allowed observations survive the staging lifetime; they are not silently promoted to Evidence.

## Body Staging And Ingestion

The connector streams to a private S3 staging object using a random nonsemantic key. It computes SHA-256 and the two Volume I accounting counters while reading. Staging metadata includes Organization, Project, Crawl, attempt, exact content encoding, media type, byte counts, policy versions and expiry. The database row is created before upload and changes from `staged` to `sealed` only after an S3 HEAD proves size, checksum metadata and server-side encryption context.

The Ingestion transaction locks the attempt and Document uniqueness guard, validates the sealed object and digest, and creates or replays the Document, source-document Evidence envelope, IngestionJob result and outbox event atomically. No database row contains body bytes. Failed, superseded or expired staging objects are destroyed by the scheduled lifecycle action within their Volume I limit; the object sweeper reconciles missing or orphaned objects.

## Parsing Pipeline

Each ParsingJob runs in a forked Heroku worker process with no outbound network permission in the application adapter. The process receives a local read stream and fixed parser policy, not an S3 credential or Rails model. It returns canonical JSON plus metrics over a pipe. The parent enforces 30 elapsed seconds and the memory ceiling; timeout or abnormal exit maps through the fixed reason precedence.

Processing order is fixed:

1. verify Evidence/object identity, digest, media type and current quarantine state;
2. decode only the HTTP-declared supported charset, with the frozen deterministic fallback/replacement rule from the parser policy;
3. parse HTML with HTML5 mode or XHTML with XML `NONET` mode as declared by media type;
4. traverse once in document order to build title nodes, link edges and Organization JSON-LD nodes;
5. canonicalize node strings/URLs and stable locators;
6. validate exact `parsed-observation-v1` JSON Schema with unknown members forbidden;
7. canonical-JSON serialize and hash; and
8. upload the immutable Parsed Artifact before the success transaction.

Remote JSON-LD contexts, scripts, styles, embedded resources, XInclude, schemas and external entities are never executed or fetched. Parser subprocess stderr is restricted diagnostic data and never enters a customer payload.

## Evaluation Input Boundary

The parse-manifest head row serializes membership. It records every expected job identity before parsing begins. The builder may seal only when every member is succeeded/dead-letter and the external-intake close predicate is terminal. It performs one repeatable-read transaction that:

- locks the manifest head and Evaluation;
- validates ordered membership and all content hashes;
- derives the three platform Evidence schemas from Parsed Artifacts;
- records each missing/derivation reason rather than omitting it;
- creates the immutable Evaluation Input Snapshot and applicability inputs; and
- commits the exact ready or blocked Evaluation transition plus outbox.

Index receipts are neither queried nor accepted by this transaction.

## PostgreSQL Retrieval Index

Baseline retrieval remains inside PostgreSQL; there is no Elasticsearch, OpenSearch, pgvector or external search service. `retrieval_documents` contains only authorized projection text and metadata derived from a Parsed Artifact:

- exact Organization, Project, Source, Document, Parsed Artifact and Index Receipt identities;
- canonical URL, title text, Organization-node names and normalized visible-text excerpt admitted by the index schema;
- `search_vector tsvector` generated by an immutable SQL expression using PostgreSQL `simple` configuration;
- field weights: title `A`, Organization names `B`, canonical host/path `C`, excerpt `D`;
- classification, schema/policy/parser generations, content hash, indexed/retired times; and
- no Evidence payload byte, secret, raw HTML or cross-tenant token.

The unique live key is `(organization_id, project_id, document_id, index_schema_version, parsed_artifact_sha256)`. Reindexing creates a new generation then atomically advances `retrieval_projection_heads`; it never overwrites a receipt. Retired/quarantined documents are excluded by current head and RLS.

An internal typed query is normalized to NFC, trimmed, whitespace-collapsed and parsed only as `websearch_to_tsquery('simple', value)` after a 256-codepoint limit. No raw `tsquery` syntax or SQL fragment is accepted. Ranking is:

```text
round(ts_rank_cd(search_vector, query, 32)::numeric, 8) DESC,
canonical_url COLLATE "C" ASC,
document_id ASC
```

The rounded rank is persisted in the cursor with URL and UUID. A request returns at most 50 rows and at most 20,000 authorized UTF-8 output bytes; it times out at 750 ms database statement time. Empty queries and stopword-only queries return an empty deterministic result. Retrieval never broadens the caller's Evidence permission and always returns lineage IDs/digests sufficient for later validation.

## Indexing Transaction And Recovery

The IndexingJob claims one attempt, builds the candidate row outside a transaction, then commits under the projection-head lock:

1. revalidate Parsed Artifact identity/digest/classification and Document state;
2. insert or locate the exact retrieval document;
3. insert immutable Index Receipt with field-set hash and generation;
4. advance the projection head only if this input is still eligible;
5. move the same-version Document from parsed to indexed when applicable; and
6. terminalize job and emit events.

Failure leaves the old head unchanged. Retry uses the same job/attempt schedule; authorized dead-letter replay increments its replay generation. A projection-rebuild command is internal release/operations work over existing eligible artifacts and cannot change product history.

## Observability And Budgets

Structured telemetry includes crawl/frontier/attempt/job IDs, bounded host digest, policy/generation, dequeue key hash, selected address classification result, stage/deadline, bytes/reservations, retry reason, parser/index versions, coverage and terminal reason. Raw IP answers, full URLs with queries, page text and bodies are restricted and never metric labels.

Required service indicators are frontier oldest age, runnable/blocked counts, host-gate delay, fetch duration/outcome, accepted/accounted byte rates, parser/index queue and execution latency, staging-object age, manifest terminal lag, retrieval latency/rows/bytes and RLS denial. Alert thresholds and recovery ownership are in [Deployment and observability](DEPLOYMENT_OBSERVABILITY.md).

## Verification Gates

Implementation cannot pass this architecture unless tests prove:

1. the reference comparator and materialized dequeue key select identical candidates under concurrency;
2. DNS rebinding, mixed answers, redirects and peer mismatch fail closed on every attempt;
3. every exact soft/hard/equality/sentinel boundary matches Volume I;
4. process death at every host-slot, object, ingestion, parser and index checkpoint repeats no product side effect;
5. unsafe XML/JSON-LD fixtures cause no network/file access;
6. parser output is byte-stable across supported runtime hosts;
7. Evaluation input never reads retrieval tables or waits for indexing;
8. RLS and composite FKs prevent cross-Organization and cross-Project index access;
9. rank/order/cursor output is stable for tied rows; and
10. no customer arbitrary search endpoint or dormant measurement-provider call exists.
