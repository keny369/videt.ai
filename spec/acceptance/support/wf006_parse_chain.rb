# frozen_string_literal: true

require_relative "wf005_crawl_chain"

# Drives the REAL WF-005 -> WF-006 chain end to end: a running Crawl, its fetches, its
# ingestion, its terminal checkpoint, the Evaluation input gate, and every ParsingJob the
# gate opens — each through its registered production handler behind a real ScheduledAction.
#
# WHY A SHARED HARNESS. The two defects this file's specs pin were both found by RUNNING the
# product, not by the suite, and both live at a SEAM: one between the Crawl's terminal-outcome
# vocabulary and the parser's, the other between an empty manifest and the scheduler. A seam
# defect is only reachable from a spec that crosses the seam, so the harness drives the whole
# chain rather than calling either side in isolation.
module Wf006ParseChain
  include Wf005CrawlChain

  ALLOW_EVERYTHING = "User-agent: *\nAllow: /\n"

  # ---- outbound ----------------------------------------------------------------------

  def page_response(status: 200, body: "<html><title>t</title></html>", type: "text/html",
                    host: "shop.acme.example", path: "/")
    Platform::Outbound::Outcome.response(
      status:, headers: type.nil? ? {} : { "content-type" => type }, body:, byte_count: body.bytesize,
      truncated: false, canonical_host: host, port: 443, pinned_address: "198.51.100.7",
      final_url: "https://#{host}#{path}", redirect_count: 0, latency_ms: 5
    )
  end

  # Answers as the host it was asked for, so a run with more than one Source does not fail
  # :436's final-URL scope check on a stub that reports one canonical host for everything.
  def outbound_pages(map)
    Object.new.tap do |o|
      o.define_singleton_method(:fetch) do |url, **_kwargs|
        uri = URI.parse(url.to_s)
        spec = map["#{uri.host}#{uri.path}"] || map[uri.path]
        raise "unexpected outbound fetch: #{url}" if spec.nil?

        spec = spec.length > 1 ? spec.shift : spec.first if spec.is_a?(Array)
        body = spec.fetch(:body, "<html><title>t</title></html>")
        Platform::Outbound::Outcome.response(
          status: spec.fetch(:status, 200), headers: { "content-type" => spec.fetch(:type, "text/html") },
          body:, byte_count: body.bytesize, truncated: false, canonical_host: uri.host, port: 443,
          pinned_address: "198.51.100.7", final_url: "https://#{uri.host}#{uri.path}",
          redirect_count: 0, latency_ms: 5
        )
      end
    end
  end

  # ---- row readers -------------------------------------------------------------------

  def sa_row(id) = DbInspector.one("SELECT * FROM scheduled_actions WHERE id = $1::uuid", [id])

  # Ordered by (due_at, created_at, id). The id tiebreak is load-bearing rather than
  # cosmetic: several actions in one run are scheduled at the SAME instant from the same
  # fixed clock, so due_at and created_at tie, and a harness that stops there picks an
  # arbitrary row and fails intermittently. The identifiers are UUIDv7, so id orders by
  # creation.
  def actions_of(kind, target_id)
    DbInspector.all(<<~SQL, [kind, target_id])
      SELECT * FROM scheduled_actions
      WHERE action_kind = $1 AND target_id = $2::uuid ORDER BY due_at, created_at, id
    SQL
  end

  def crawl_row(cid) = DbInspector.one("SELECT * FROM crawls WHERE id = $1::uuid", [cid])
  def evaluation_row(id) = DbInspector.one("SELECT * FROM evaluations WHERE id = $1::uuid", [id])

  def evaluation_for(cid)
    DbInspector.one("SELECT * FROM evaluations WHERE crawl_id = $1::uuid AND kind = 'initial'", [cid])
  end

  def parsing_jobs(cid)
    DbInspector.all("SELECT * FROM parsing_jobs WHERE crawl_id = $1::uuid ORDER BY created_at, id", [cid])
  end

  def parsed_artifacts(cid)
    DbInspector.all(<<~SQL, [cid])
      SELECT a.* FROM parsed_artifacts a
      JOIN parsing_jobs j ON j.id = a.parsing_job_id WHERE j.crawl_id = $1::uuid ORDER BY a.created_at
    SQL
  end

  def input_snapshot(evaluation_id)
    DbInspector.one("SELECT * FROM evaluation_input_snapshots WHERE evaluation_id = $1::uuid", [evaluation_id])
  end

  def terminal_outcomes(cid)
    DbInspector.all("SELECT * FROM crawl_terminal_outcomes WHERE crawl_id = $1::uuid ORDER BY commit_order", [cid])
  end

  # ---- the chain ---------------------------------------------------------------------

  # A run whose robots and sitemap records are terminal and whose rate window is clear.
  #
  # `sitemap:` seeds additional in-scope URLs into the frontier. IN-CRAWL LINK DISCOVERY IS NOW
  # BUILT (S-07-007), so a run seeded only from the Source root DOES follow the links its pages
  # name, and seeding is no longer what makes CHK-TI-001 reachable. It is still useful, and for a
  # different reason: a sitemap-seeded URL is admitted at depth 1 with `origin_rank` `sitemap`,
  # so a spec that wants a target present in the frontier BEFORE its referring page is parsed
  # asks for it here rather than depending on traversal order to produce it.
  def crawlable(hosts: ["shop.acme.example"], at: start_now, sitemap: nil)
    prepare_run(running_crawl(hosts:, at:).merge(sitemap:), at:, sitemap:)
  end

  # A SECOND run of an existing Project, queued and started exactly as the first was — no new
  # Organization, no new Source. This is the helper the OD-018 release is actually about: it
  # only works if the first Evaluation reached a terminal state, because `QueueCrawl` refuses
  # while one is pending or running.
  def recrawl(ctx, at: start_now + 3600)
    g = ctx[:g]
    queued = Workflows::Wf005::Handlers::QueueCrawl.new.call(
      command: Workflows::Wf005::Commands::QueueCrawl.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "qc-#{SecureRandom.hex(6)}",
        schema_version: "1.0", session_id: g[:session_id], organization_id: g[:organization_id],
        project_id: g[:project_id], requested_at_utc: at
      ), request_context: act_ctx
    )
    raise "second crawl refused: #{queued.failure&.reason_code}" unless queued.success?

    crawl_id = queued.payload[:crawl_id]
    action = sa_row(DbInspector.one(<<~SQL, [crawl_id])["id"])
      SELECT id FROM scheduled_actions WHERE action_kind='crawl_dispatch' AND target_id=$1::uuid
    SQL
    Workflows::Wf005::Handlers::StartCrawl.new.call(
      command: Workflows::Wf005::Commands::StartCrawl.new(
        command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
        organization_id: action["organization_id"], target_type: action["target_type"],
        crawl_id: action["target_id"], due_at: Time.parse(action["due_at"]).getutc,
        action_id: action["id"], action_identity_sha256: sha_bytes(action["identity_sha256"]),
        requested_at_utc: at
      ), request_context: executor_ctx(at)
    )
    ctx.merge(crawl_id:).tap { |second| prepare_run(second, at:, sitemap: ctx[:sitemap]) }
  end

  # Robots, sitemaps and the rate window for a run that already exists.
  def prepare_run(ctx, at: start_now, sitemap: nil)
    ensure_gate(ctx)
    robots = ALLOW_EVERYTHING + (sitemap ? "Sitemap: https://#{ctx[:host]}/sitemap.xml\n" : "")
    resolve_robots(ctx, outbound_returning(response(status: 200, body: robots)))
    if sitemap
      resolve_sitemaps(ctx, outbound_returning(response(status: 200, body: urlset(*sitemap),
                                                        headers: { "content-type" => "application/xml" })))
    else
      resolve_sitemaps(ctx, outbound_returning(response(status: 404, body: "")))
    end
    clear_rate_window_for_crawl(ctx[:crawl_id])
    ctx
  end

  def urlset(*locs)
    entries = locs.map { |l| "<url><loc>#{l}</loc></url>" }.join
    %(<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{entries}</urlset>)
  end

  def link_next_fetch(ctx, at: start_now)
    link = Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
                                                        .enter_org_context(org: ctx[:g][:organization_id],
                                                                          correlation_id: SecureRandom.uuid_v7)
      Workflows::Wf005::CrawlFetchDueSchedule.link_next(
        pg:, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
        crawl_id: ctx[:crawl_id], now: at, correlation_id: SecureRandom.uuid_v7
      )
    end
    link[:action_id] && sa_row(link[:action_id])
  end

  def record_fetch(ctx, action, outbound, at:)
    command = Workflows::Wf005::Commands::RecordFetchAttempt.new(
      command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
      organization_id: action["organization_id"], target_type: action["target_type"],
      frontier_entry_id: action["target_id"], due_at: Time.parse(action["due_at"]).getutc,
      action_id: action["id"], action_identity_sha256: sha_bytes(action["identity_sha256"]),
      requested_at_utc: at
    )
    Workflows::Wf005::Handlers::RecordFetchAttempt.new.call(
      command:, request_context: executor_ctx(at), outbound:, pacer: pacer_for(ctx)
    )
  end

  # Every pass at ITS OWN due instant, which is what the transport does; a retry is due at
  # `completed_at + 30s` and a pass executed early is refused `scheduled_action_not_due`.
  def drain_fetches(ctx, outbound, limit: 12, at: start_now)
    action = link_next_fetch(ctx, at:)
    return [] if action.nil?

    [].tap do |results|
      limit.times do
        results << record_fetch(ctx, action, outbound, at: Time.parse(action["due_at"]).getutc)
        nxt = results.last.success? && results.last.payload[:next_action_id]
        break unless nxt

        clear_rate_window_for_crawl(ctx[:crawl_id])
        action = sa_row(nxt)
      end
    end
  end

  # Every queued IngestionJob, through the real handler behind its real action.
  def drain_ingestion(ctx)
    DbInspector.all(<<~SQL, [ctx[:crawl_id]]).map do |action|
      SELECT a.* FROM scheduled_actions a
      JOIN ingestion_jobs j ON j.id = a.target_id
      WHERE a.action_kind = 'ingestion_attempt_due' AND j.crawl_id = $1::uuid
      ORDER BY a.due_at, a.created_at
    SQL
      at = Time.parse(action["due_at"]).getutc
      command = Workflows::Wf005::Commands::RunIngestionJob.new(
        command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
        organization_id: action["organization_id"], target_type: action["target_type"],
        ingestion_job_id: action["target_id"], due_at: at, action_id: action["id"],
        action_identity_sha256: sha_bytes(action["identity_sha256"]), requested_at_utc: at
      )
      Workflows::Wf005::Handlers::RunIngestionJob.new.call(command:, request_context: executor_ctx(at))
    end
  end

  # The terminal checkpoint, through the REAL registered handler and a REAL action. Defaults
  # to the earliest, which is the path an ordinary run takes: a pass that drains the frontier
  # schedules a checkpoint for itself and the deadline one behind it finds the Crawl terminal.
  def complete_crawl(ctx, at: nil)
    row = actions_of("crawl_terminal_deadline", ctx[:crawl_id]).first
    raise "no terminal checkpoint action exists" if row.nil?

    instant = at || Time.parse(row["due_at"]).getutc
    command = Workflows::Wf005::Commands::CompleteCrawl.new(
      command_id: SecureRandom.uuid_v7, schema_version: row["action_schema_version"],
      organization_id: row["organization_id"], target_type: row["target_type"],
      crawl_id: row["target_id"], due_at: Time.parse(row["due_at"]).getutc, action_id: row["id"],
      action_identity_sha256: sha_bytes(row["identity_sha256"]), requested_at_utc: instant
    )
    Workflows::Wf005::Handlers::CompleteCrawl.new.call(command:, request_context: executor_ctx(instant))
  end

  # One visit to the Evaluation input gate: the OLDEST action this harness has not already
  # driven. The gate is re-entered across a run — once from the terminal checkpoint to open
  # parsing, once from the last ParsingJob to seal the snapshot — and driving the same action
  # twice only replays its stored idempotency record, which silently skips the second visit.
  def advance_evaluation(ctx, at: nil)
    driven = (@driven_stage_actions ||= [])
    row = actions_of("evaluation_stage_advance", ctx[:crawl_id]).find { |a| !driven.include?(a["id"]) }
    raise "no undriven evaluation stage action exists" if row.nil?

    driven << row["id"]
    instant = at || Time.parse(row["due_at"]).getutc
    command = Workflows::Wf006::Commands::SealEvaluationInputs.new(
      command_id: SecureRandom.uuid_v7, schema_version: row["action_schema_version"],
      organization_id: row["organization_id"], target_type: row["target_type"],
      crawl_id: row["target_id"], due_at: Time.parse(row["due_at"]).getutc, action_id: row["id"],
      action_identity_sha256: sha_bytes(row["identity_sha256"]), requested_at_utc: instant
    )
    Workflows::Wf006::Handlers::SealEvaluationInputs.new.call(command:, request_context: executor_ctx(instant))
  end

  # Every open ParsingJob attempt, through the real handler behind its real action.
  def drain_parsing(ctx)
    DbInspector.all(<<~SQL, [ctx[:crawl_id]]).map do |action|
      SELECT a.* FROM scheduled_actions a
      JOIN parsing_jobs j ON j.id = a.target_id
      WHERE a.action_kind = 'parsing_attempt_due' AND j.crawl_id = $1::uuid AND a.status = 'pending'
      ORDER BY a.due_at, a.created_at
    SQL
      at = Time.parse(action["due_at"]).getutc
      command = Workflows::Wf006::Commands::ExecuteParsingJob.new(
        command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
        organization_id: action["organization_id"], target_type: action["target_type"],
        parsing_job_id: action["target_id"], due_at: at, action_id: action["id"],
        action_identity_sha256: sha_bytes(action["identity_sha256"]), requested_at_utc: at
      )
      Workflows::Wf006::Handlers::ExecuteParsingJob.new.call(command:, request_context: executor_ctx(at))
    end
  end

  # ---- WF-007 -------------------------------------------------------------------------
  #
  # The stage chain continues on the SAME ratified action kind, with the Evaluation as the
  # target instead of the Crawl, so these drive the same registered router the transport
  # drives — not the WF-007 handler directly.

  def evaluation_stage_actions(evaluation_id) = actions_of("evaluation_stage_advance", evaluation_id)

  def advance_wf007(ctx, evaluation_id: nil, at: nil)
    eid = evaluation_id || evaluation_for(ctx[:crawl_id])["id"]
    driven = (@driven_stage_actions ||= [])
    row = evaluation_stage_actions(eid).find { |a| !driven.include?(a["id"]) }
    raise "no undriven WF-007 stage action exists" if row.nil?

    driven << row["id"]
    instant = at || Time.parse(row["due_at"]).getutc
    command = Workflows::Wf007::Commands::AdvanceEvaluationStage.new(
      command_id: SecureRandom.uuid_v7, schema_version: row["action_schema_version"],
      organization_id: row["organization_id"], target_type: row["target_type"],
      evaluation_id: row["target_id"], stage_ordinal: row["product_generation"].to_i,
      due_at: Time.parse(row["due_at"]).getutc, action_id: row["id"],
      action_identity_sha256: sha_bytes(row["identity_sha256"]), requested_at_utc: instant
    )
    Workflows::Wf007::Handlers::AdvanceEvaluationStage.new.call(command:, request_context: executor_ctx(instant))
  end

  # Every scheduled Check attempt, through the real handler behind its real action.
  def drain_check_attempts(ctx)
    evaluation_id = evaluation_for(ctx[:crawl_id])["id"]
    driven = (@driven_check_actions ||= [])
    DbInspector.all(<<~SQL, [evaluation_id]).reject { |a| driven.include?(a["id"]) }.map do |action|
      SELECT a.* FROM scheduled_actions a
      JOIN check_result_slots s ON s.id = a.target_id
      WHERE a.action_kind = 'check_attempt_due' AND s.evaluation_id = $1::uuid
      ORDER BY s.ordering, a.created_at, a.id
    SQL
      driven << action["id"]
      at = Time.parse(action["due_at"]).getutc
      command = Workflows::Wf007::Commands::ExecuteCheckAttempt.new(
        command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
        organization_id: action["organization_id"], target_type: action["target_type"],
        slot_id: action["target_id"], attempt_number: action["product_generation"].to_i,
        due_at: at, action_id: action["id"],
        action_identity_sha256: sha_bytes(action["identity_sha256"]), requested_at_utc: at
      )
      Workflows::Wf007::Handlers::ExecuteCheckAttempt.new.call(command:, request_context: executor_ctx(at))
    end
  end

  def check_results(evaluation_id)
    DbInspector.all(<<~SQL, [evaluation_id])
      SELECT * FROM check_results WHERE evaluation_id = $1::uuid
      ORDER BY check_definition_id, canonical_subject_key
    SQL
  end

  def applicability_entries(evaluation_id)
    DbInspector.all(<<~SQL, [evaluation_id])
      SELECT e.* FROM check_applicability_entries e
      JOIN check_applicability_snapshots s ON s.id = e.snapshot_id
      WHERE s.evaluation_id = $1::uuid ORDER BY e.ordering
    SQL
  end

  def issues_of(evaluation_id)
    DbInspector.all("SELECT * FROM issues WHERE evaluation_id = $1::uuid ORDER BY issue_type, canonical_subject_key",
                    [evaluation_id])
  end

  def issue_set_of(evaluation_id)
    DbInspector.one("SELECT * FROM issue_sets WHERE evaluation_id = $1::uuid", [evaluation_id])
  end

  def derived_evidence(evaluation_id)
    DbInspector.all(<<~SQL, [evaluation_id])
      SELECT * FROM evidence WHERE evaluation_id = $1::uuid AND producer_id = 'wf006.evidence_derivation'
      ORDER BY schema_version, id
    SQL
  end

  # Crawl -> ingest -> terminalize -> open parsing -> parse -> re-enter the gate, which is
  # the exact order the transport runs them in. Returns the context.
  def run_to_parsed(ctx, outbound)
    drain_fetches(ctx, outbound)
    drain_ingestion(ctx)
    complete_crawl(ctx)
    advance_evaluation(ctx)
    drain_parsing(ctx)
    advance_evaluation(ctx)
    ctx
  end

  # ...and on through WF-007: seal the applicability, execute every Check, seal the Issue Set
  # and complete the Evaluation.
  def run_to_evaluated(ctx, outbound)
    run_to_parsed(ctx, outbound)
    advance_wf007(ctx)
    drain_check_attempts(ctx)
    advance_wf007(ctx)
    ctx
  end

  def sha_bytes(hex) = [hex.to_s.sub(/\A\\x/, "")].pack("H*")
end
