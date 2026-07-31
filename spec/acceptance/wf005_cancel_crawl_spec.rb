# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# WF-005 CancelCrawl (S-07-009; WORKFLOW_SPECIFICATIONS.md :736, :738, :458, :551;
# API_CONTRACTS.md :279), over the production-real chain.
#
# :458's boundary is the point of this command and of these examples: "a cancellation committed
# STRICTLY BEFORE that checkpoint yields `Crawl.Canceled`; a cancellation at or after the checkpoint is
# rejected as `crawl_already_terminal`." Both sides take the Crawl row lock, so one commits first and
# the other reads it; neither implements the other's rule, and `f1_crawls_guard` refuses every edge out
# of a terminal state so the loser could not write even if it tried.
RSpec.describe "WF-005 cancel crawl", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-E2E TYP-DATA TYP-SEC TYP-INT] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def crawl_row(cid) = DbInspector.one("SELECT * FROM crawls WHERE id = $1::uuid", [cid])

  def events(cid)
    DbInspector.all(<<~SQL, [cid])
      SELECT * FROM event_registry WHERE aggregate_id = $1::uuid
        AND event_type IN ('CrawlCompleted','CrawlFailed','CrawlCanceled') ORDER BY created_at
    SQL
  end

  def reservation(cid)
    DbInspector.one(<<~SQL, [cid])
      SELECT r.* FROM entitlement_reservations r
      JOIN crawls c ON c.entitlement_reservation_id = r.id WHERE c.id = $1::uuid
    SQL
  end

  def envelope(event) = JSON.parse([event["event_bytes"].sub(/\A\\x/, "")].pack("H*"))

  # The command alone, so an example can choose the instant it is issued at. `expected_state_version` is
  # read at build time, which is what a real caller does.
  def cancel_command(ctx, key:, session: nil)
    Workflows::Wf005::Commands::CancelCrawl.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: session || ctx[:g][:session_id], organization_id: ctx[:g][:organization_id],
      project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id],
      expected_state_version: crawl_row(ctx[:crawl_id])["state_version"].to_i, requested_at_utc: act_now
    )
  end

  # A session an actor genuinely holds AT the instant under test. The bootstrap session is issued at
  # `fixed_now - 300` and is `session_invalid` an hour later, which is correct behaviour and not the
  # property these examples are about — a cancellation at the sixty-minute boundary is issued by someone
  # who signed in near it. A MarketingOperator, because :147 allows the role `crawl.cancel` (PROOF 85)
  # and `one_bootstrap_admin_per_organization` admits only the one bootstrap admin the chain created.
  def session_at(ctx, at)
    TenantSeeder.seed_authorized_admin(organization_id: ctx[:g][:organization_id],
                                       canonical_role: "MarketingOperator",
                                       with_policy: false, issued_at: at - 60)[:session_id]
  end

  # An actor context whose clock is the instant under test. `CancelCrawl` reads `now` from the context,
  # so this is how a cancellation issued at the boundary is expressed without falsifying a column.
  def executor_ctx_for_actor(at)
    Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(at), ids: Platform::Ids.system,
                                       correlation_id: SecureRandom.uuid_v7)
  end

  def cancel(ctx, session: nil, version: nil, key: "cc-#{SecureRandom.hex(6)}", crawl_id: nil)
    cid = crawl_id || ctx[:crawl_id]
    Workflows::Wf005::Handlers::CancelCrawl.new.call(
      command: Workflows::Wf005::Commands::CancelCrawl.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: session || ctx[:g][:session_id], organization_id: ctx[:g][:organization_id],
        project_id: ctx[:g][:project_id], crawl_id: cid,
        expected_state_version: version || crawl_row(cid)["state_version"].to_i,
        requested_at_utc: act_now
      ),
      request_context: act_ctx
    )
  end

  # A QUEUED Crawl in the SAME Organization but a SECOND Project, created through the real WF-002
  # command. One bootstrap per example is a harness rule (`identity` is memoized per example, so a
  # second bootstrap would reuse the first one's subject), which is why the cross-Project case is built
  # inside one tenant rather than across two.
  def second_project(g)
    Workflows::Wf002::Handlers::CreateProject.new.call(
      command: Workflows::Wf002::Commands::CreateProject.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "cp-#{SecureRandom.hex(6)}",
        schema_version: "1.0", session_id: g[:session_id], organization_id: g[:organization_id],
        profile: {
          "project_profile_schema_version" => "project-profile-v1", "display_name" => "Second Project",
          "default_locale" => "en-AU", "reporting_time_zone" => "UTC",
          "objective" => "discoverability_assessment", "local_presence_applicable" => false,
          "local_presence_reason" => "This program operates entirely online across the country.",
          "local_business_profile" => nil
        }, requested_at_utc: act_now
      ), request_context: act_ctx
    ).payload[:project_id]
  end

  # A QUEUED Crawl: queued and never dispatched, so `entitlement_reservation_id` is NULL.
  def queued_crawl
    g = bootstrap
    ids = ["https://shop.acme.example"].map { |u| register_source(g, u).tap { |sid| verify(g, sid) } }
    ids.each { |sid| activate_source(g, sid) }
    raise "activation failed" unless activate_project(g).success?

    { g:, crawl_id: queue_in(g, g[:project_id]) }
  end

  def queue_in(g, project_id)
    Workflows::Wf005::Handlers::QueueCrawl.new.call(
      command: Workflows::Wf005::Commands::QueueCrawl.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "qc-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id:,
        requested_at_utc: act_now
      ), request_context: act_ctx
    ).payload[:crawl_id]
  end

  describe ":736's two cancel edges" do
    it "PROOF 80 — a RUNNING Crawl cancels, records `canceled`, and releases its reservation" do
      ctx = running_crawl
      before = crawl_row(ctx[:crawl_id])
      expect(before["state"]).to eq("running")
      expect(reservation(ctx[:crawl_id])["state"]).to eq("executing")

      result = cancel(ctx)

      expect(result.success?).to be(true)
      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["state"]).to eq("canceled")
      # :456's closed CompletionReason enum; `crawls_terminal_shape` requires a reason of every
      # terminal state and coverage only of `completed`.
      expect(crawl["completion_reason"]).to eq("canceled")
      expect(crawl["coverage_status"]).to be_nil
      expect(crawl["terminal_at"]).not_to be_nil
      # :551 — "cancellation ... RELEASES exactly once even when intermediate Documents or other
      # partial artifacts exist; those artifacts ... are NOT a usage commitment."
      expect(result.payload[:entitlement_outcome]).to eq("released")
      expect(reservation(ctx[:crawl_id])["state"]).to eq("released")
      expect(reservation(ctx[:crawl_id])["terminal_reason"]).to eq("crawl_canceled")
      event = events(ctx[:crawl_id]).sole
      expect(event["event_type"]).to eq("CrawlCanceled")
      body = envelope(event)
      expect(body["from_state"]).to eq("running")
      expect(body["to_state"]).to eq("canceled")
      # :808 gives `CrawlCanceled` the reason source `transition`, so :938 requires the base member and
      # a root reason equal to it; :956 makes `accepted_document_count` the third `crawl_terminal`
      # member, zero for a run that accepted none (ADR-110).
      expect(body["reason_code"]).to eq("canceled")
      expect(body["transition_reason_code"]).to eq("canceled")
      expect(body["accepted_document_count"]).to eq(0)
    end

    it "PROOF 81 — a QUEUED Crawl cancels too, and has no reservation to release" do
      # :736 gives `Crawl.Queued -> Crawl.Canceled` as well, and POSTGRESQL_SCHEMA :338 makes the
      # entitlement columns "NULL until start" — so a queued cancellation settles nothing and says so
      # rather than guessing at a reservation that was never taken.
      ctx = queued_crawl

      result = cancel(ctx)

      expect(result.success?).to be(true)
      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["state"]).to eq("canceled")
      expect(crawl["completion_reason"]).to eq("canceled")
      expect(result.payload[:entitlement_outcome]).to eq("none")
      expect(result.payload[:from_state]).to eq("queued")
    end
  end

  describe ":458's boundary, and :738's permission" do
    it "PROOF 82 — a cancellation AT OR AFTER the terminal checkpoint is `crawl_already_terminal`" do
      # The exact token :458 names. The Crawl has had its one terminal selection, and
      # `f1_crawls_guard` refuses every edge out of it — so this refusal is the command agreeing with
      # the state machine rather than being the only thing standing between them.
      ctx = running_crawl
      DbInspector.connection.exec_params(<<~SQL, [ctx[:crawl_id]])
        UPDATE crawls SET state='completed', terminal_at=now(), completion_reason='completed',
               coverage_status='full', state_version = state_version + 1 WHERE id = $1::uuid
      SQL

      result = cancel(ctx)

      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("crawl_already_terminal")
      expect(crawl_row(ctx[:crawl_id])["completion_reason"]).to eq("completed")
      expect(events(ctx[:crawl_id])).to be_empty
    end

    it "PROOF 93 — at and after the 60-minute boundary the WALL CLOCK wins, not the cancellation" do
      # :458's THIRD sentence, which the first implementation stopped short of: "At exactly the 60-minute
      # boundary the wall-clock terminal handler wins over a simultaneous cancellation." The two
      # sentences before it are settled by commit order; this one is an ASYMMETRY at an instant, and
      # without it whether a cancellation at minute sixty-one won was decided by whether the transport
      # had yet delivered `crawl_terminal_deadline`.
      ctx = running_crawl
      deadline = Time.parse(crawl_row(ctx[:crawl_id])["deadline_at"]).getutc

      # AT the boundary — the exact case the sentence names, so `>=` and not `>`.
      at_boundary = Workflows::Wf005::Handlers::CancelCrawl.new.call(
        command: cancel_command(ctx, key: "cc-#{SecureRandom.hex(6)}", session: session_at(ctx, deadline)),
        request_context: executor_ctx_for_actor(deadline)
      )
      expect(at_boundary.success?).to be(false)
      expect(at_boundary.failure.reason_code).to eq("crawl_already_terminal")

      # And past it. The run is still `running` — the wall-clock handler has not arrived yet — and that
      # is precisely the window this closes.
      past = Workflows::Wf005::Handlers::CancelCrawl.new.call(
        command: cancel_command(ctx, key: "cc-#{SecureRandom.hex(6)}", session: session_at(ctx, deadline + 60)),
        request_context: executor_ctx_for_actor(deadline + 60)
      )
      expect(past.failure.reason_code).to eq("crawl_already_terminal")

      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["state"]).to eq("running")
      expect(events(ctx[:crawl_id])).to be_empty
      # THE METERING ESCAPE THIS CLOSES. :551 releases a reservation for a cancellation before the
      # durable commit point and the checkpoint COMMITS one for a completed run, so a `crawl.cancel`
      # holder who could cancel after the clock could choose the release limb over the commit — for
      # every run, from an ordinary MarketingOperator's authority.
      expect(reservation(ctx[:crawl_id])["state"]).to eq("executing")
    end

    it "PROOF 116 — a cancellation AT the boundary emits no limit decision and no limit event" do
      # The last of FU-35's distinctions. A cancellation refused at the boundary is a refusal, not a
      # limit hit: :442's `wall_clock_run_duration` decision belongs to the run's own terminal handler
      # and only when the clock actually prevented an evaluation. A denial that wrote one would fire
      # `CrawlLimitReached` for a dimension nothing had reached, from a path that decides nothing.
      ctx = running_crawl
      deadline = Time.parse(crawl_row(ctx[:crawl_id])["deadline_at"]).getutc

      result = Workflows::Wf005::Handlers::CancelCrawl.new.call(
        command: cancel_command(ctx, key: "cc-#{SecureRandom.hex(6)}", session: session_at(ctx, deadline)),
        request_context: executor_ctx_for_actor(deadline)
      )

      expect(result.failure.reason_code).to eq("crawl_already_terminal")
      expect(DbInspector.all("SELECT * FROM crawl_limit_decisions WHERE crawl_id=$1::uuid", [ctx[:crawl_id]]))
        .to be_empty
      expect(DbInspector.all(<<~SQL, [ctx[:crawl_id]])).to be_empty
        SELECT event_type FROM event_registry WHERE aggregate_id = $1::uuid
          AND event_type IN ('CrawlLimitReached','CrawlSoftLimitApproaching')
      SQL
      expect(crawl_row(ctx[:crawl_id])["state"]).to eq("running")
    end

    it "PROOF 94 — a cancellation one second BEFORE the boundary still wins, so the limb is a boundary" do
      # The other side of the same instant. Without this, `>=` and `> now + anything` are
      # indistinguishable and the limb could silently become "cancellation is unavailable near the end".
      ctx = running_crawl
      deadline = Time.parse(crawl_row(ctx[:crawl_id])["deadline_at"]).getutc

      result = Workflows::Wf005::Handlers::CancelCrawl.new.call(
        command: cancel_command(ctx, key: "cc-#{SecureRandom.hex(6)}", session: session_at(ctx, deadline - 1)),
        request_context: executor_ctx_for_actor(deadline - 1)
      )

      expect(result.success?).to be(true)
      expect(crawl_row(ctx[:crawl_id])["state"]).to eq("canceled")
      expect(reservation(ctx[:crawl_id])["state"]).to eq("released")
    end

    it "PROOF 83 — a stale expected state version changes nothing" do
      # MTX-030's request schema for this command is "Crawl ID, EXPECTED STATE VERSION", and it is the
      # other half of the same boundary: a cancellation holding a version the run has moved past is
      # refused rather than applied to a Crawl its sender was not looking at.
      ctx = running_crawl

      result = cancel(ctx, version: crawl_row(ctx[:crawl_id])["state_version"].to_i - 1)

      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("stale_state_version")
      expect(crawl_row(ctx[:crawl_id])["state"]).to eq("running")
    end

    it "PROOF 84 — cancellation requires `crawl.cancel`, and a TechnicalImplementer has none" do
      # :738 — "cancellation requires `crawl.cancel`"; :147 allows it for OrganizationAdmin and
      # MarketingOperator and denies every other role. It is a SEPARATE permission from
      # `crawl.trigger`, which is why the denial has its own reason code.
      ctx = running_crawl
      session = TenantSeeder.seed_authorized_admin(organization_id: ctx[:g][:organization_id],
                                                   canonical_role: "TechnicalImplementer",
                                                   with_policy: false, issued_at: fixed_now - 300)[:session_id]

      result = cancel(ctx, session:)

      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("crawl_cancel_unauthorized")
      expect(crawl_row(ctx[:crawl_id])["state"]).to eq("running")
      expect(events(ctx[:crawl_id])).to be_empty
    end

    it "PROOF 85 — a MarketingOperator may cancel, because :147 allows both roles" do
      ctx = running_crawl
      session = TenantSeeder.seed_authorized_admin(organization_id: ctx[:g][:organization_id],
                                                   canonical_role: "MarketingOperator",
                                                   with_policy: false, issued_at: fixed_now - 300)[:session_id]

      expect(cancel(ctx, session:).success?).to be(true)
      expect(crawl_row(ctx[:crawl_id])["state"]).to eq("canceled")
    end
  end

  describe "idempotency and tenancy" do
    it "PROOF 86 — an exact replay returns the stored result and cancels nothing twice" do
      ctx = running_crawl
      key = "cc-#{SecureRandom.hex(6)}"
      version = crawl_row(ctx[:crawl_id])["state_version"].to_i
      first = cancel(ctx, key:, version:)

      replay = cancel(ctx, key:, version:)

      expect(replay.replayed).to be(true)
      expect(replay.payload[:crawl_id]).to eq(first.payload[:crawl_id])
      expect(events(ctx[:crawl_id]).size).to eq(1)
      expect(reservation(ctx[:crawl_id])["state"]).to eq("released")
    end

    it "PROOF 87 — a Crawl in another Project of the same Organization is a tenant mismatch" do
      # POSTGRESQL_SCHEMA :128's rule, applied at the command: the Crawl must belong to the NAMED
      # Project, not merely to the actor's Organization. FU-7 records this defect class appearing
      # silently in three consecutive tranches, so it is checked by predicate rather than assumed.
      # The command names a REAL Project of the actor's own Organization and a REAL Crawl of the same
      # Organization — they simply are not each other's. Nothing about the Organization is wrong, which
      # is exactly what makes the Organization-scoped RLS an insufficient answer on its own.
      ctx = running_crawl
      other_project = second_project(ctx[:g])

      result = Workflows::Wf005::Handlers::CancelCrawl.new.call(
        command: Workflows::Wf005::Commands::CancelCrawl.new(
          command_id: SecureRandom.uuid_v7, idempotency_key: "cc-#{SecureRandom.hex(6)}",
          schema_version: "1.0", session_id: ctx[:g][:session_id],
          organization_id: ctx[:g][:organization_id], project_id: other_project,
          crawl_id: ctx[:crawl_id], expected_state_version: crawl_row(ctx[:crawl_id])["state_version"].to_i,
          requested_at_utc: act_now
        ), request_context: act_ctx
      )

      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("tenant_mismatch")
      expect(crawl_row(ctx[:crawl_id])["state"]).to eq("running")
    end
  end
end
