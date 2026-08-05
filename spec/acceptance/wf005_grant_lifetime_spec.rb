# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# THE GRANT'S LIFETIME IS JUDGED AFTER THE WAIT, NOT AT THE INSTANT THE COMMAND ENTERED
# (round-15 security finding R15-SEC-1).
#
# WHAT FU-48 CLAIMED. `write_authority.rb` states that the write re-reads the granting Assignments
# "still active, still effective, NOT YET EXPIRED, at the version and scope the decision saw", and
# that only row state another transaction can move while this one waits belongs in the statement.
# ADR-132 decision 6 says the same for each protected write.
#
# WHAT WAS TRUE INSTEAD. Two of the three protected writes handed the statement the instant the
# command ENTERED WITH. `CancelCrawl` adopts its post-wait instant (`d = d.merge(now: post_wait.now)`)
# and judged the grant correctly; `QueueCrawl` and `ActivateCrawlPolicy` each CONSTRUCT a
# `PostWaitDecision`, use it to mint the attestation, and then write with the pre-wait value. So the
# expiry conjunct was evaluated against a clock reading taken BEFORE an unbounded advisory-lock wait,
# and a Role Assignment that expired during that wait still conferred.
#
# The epoch limb cannot cover it: an expiry that has not yet been PROCESSED advances no
# authorization epoch, so there is nothing for `authority_current?` to see. The whole point of the
# expiry conjunct is the case nothing else can detect.
#
# WHY IT MATTERS. Every time-boxed Assignment — a contractor's, a temporary elevation, and by the
# `role_assignment_protected_expiry_within_30_days` CHECK every protected grant — was spendable after
# it expired for as long as the command took, which is as long as another transaction held the lock.
# The two affected commands are the ones that create billable work and change bounds.
#
# HOW THESE PROOFS ARE BUILT SO THEY CANNOT GO VACUOUS. `Platform::PgInstant.after_wait` advances the
# caller's instant by the time the transaction really spent alive, so the ONLY way to separate the
# two instants is to make a lock wait actually happen. Each proof therefore:
#
#   1. asserts the grant is UNEXPIRED at the instant the command enters with, so the decision the
#      handler makes upstream is genuinely an `allow` (otherwise the refusal proves nothing);
#   2. holds the handler's own advisory key until PostgreSQL reports more elapsed time than the
#      expiry offset, with the handler observed in `pg_locks` as an ungranted waiter;
#   3. is paired with a CONTROL that runs the identical wait with NO expiry and must SUCCEED, so a
#      refusal caused by the wait itself, by the lock, or by anything other than the expiry fails the
#      pair rather than passing as evidence.
RSpec.describe "WF-005 grant lifetime at the protected write", type: :acceptance,
                                                              acceptance_ids: ["AC-WF-005", "AC-CAP-007"],
                                                              test_types: %w[TYP-SEC TYP-INT] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  # The expiry lands one second after the command's entry instant; the lock is held for longer than
  # that, so the post-wait instant is necessarily past it and the pre-wait instant necessarily is not.
  EXPIRES_AFTER_SECONDS = 1
  HOLD_SECONDS = 3

  def grants(org)
    DbInspector.all(<<~SQL, [org])
      SELECT id, expires_at FROM role_assignments
      WHERE organization_id = $1::uuid AND status = 'active' ORDER BY id
    SQL
  end

  # `expires_at` is not in `f1_role_assignments_lifecycle_guard`'s immutable set — it is the same
  # column the production grant path writes — so this is a fixture, not a hole.
  def expire_grants_at(org, instant)
    DbInspector.connection.exec_params(<<~SQL, [org, instant.getutc.iso8601(6)])
      UPDATE role_assignments SET expires_at = $2::timestamptz
      WHERE organization_id = $1::uuid AND status = 'active'
    SQL
  end

  def queueable_org
    g = bootstrap
    sid = register_source(g, "https://lifetime.acme.example")
    verify(g, sid)
    activate_source(g, sid)
    raise "activation failed" unless activate_project(g).success?

    g
  end

  def queue(g)
    Workflows::Wf005::Handlers::QueueCrawl.new.call(
      command: Workflows::Wf005::Commands::QueueCrawl.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "gl-#{SecureRandom.hex(6)}",
        schema_version: "1.0", session_id: g[:session_id], organization_id: g[:organization_id],
        project_id: g[:project_id], requested_at_utc: act_now
      ), request_context: act_ctx
    )
  end

  def activate_policy(g)
    Workflows::Wf005::Handlers::ActivateCrawlPolicy.new.call(
      command: Workflows::Wf005::Commands::ActivateCrawlPolicy.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "gl-#{SecureRandom.hex(6)}",
        schema_version: "1.0", session_id: g[:session_id], organization_id: g[:organization_id],
        scope: "organization", project_id: nil, expected_current_policy_version: nil,
        expected_parent_policy_version: Workflows::Wf005::CrawlPolicy::GLOBAL_VERSION,
        expected_global_version: Workflows::Wf005::CrawlPolicy::GLOBAL_VERSION,
        proposed_bounds: Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING.to_h { |d, v| [d, v.dup] },
        requested_at_utc: act_now
      ), request_context: act_ctx
    )
  end

  def crawls(org) = DbInspector.all("SELECT id, state FROM crawls WHERE organization_id = $1::uuid", [org])
  def policies(org) = DbInspector.all("SELECT id, state FROM crawl_policies WHERE organization_id = $1::uuid", [org])
  def events(type) = DbInspector.all("SELECT id FROM event_registry WHERE event_type = $1", [type])

  # The grant is live when the command enters and dead when it writes. Asserted rather than assumed,
  # because a fixture that expired the grant too early would make every refusal below meaningless.
  def arm_expiry(org)
    expire_grants_at(org, act_now + EXPIRES_AFTER_SECONDS)
    grants(org).each do |g|
      expect(Platform::PgInstant.utc(g["expires_at"])).to be > act_now,
                                                          "the fixture expired the grant at or before the " \
                                                          "command's own instant, so an upstream denial — not " \
                                                          "the write — would refuse it"
    end
  end

  describe "PROOF 259 — QueueCrawl" do
    it "refuses a Crawl when the granting Assignment expires during the lock wait" do
      g = queueable_org
      arm_expiry(g[:organization_id])

      result = wait_out_lock("crawl-queue:#{g[:organization_id]}:#{g[:project_id]}", HOLD_SECONDS) { queue(g) }

      expect(result.success?).to be(false),
                                 "a Role Assignment that expired while this command waited still queued a Crawl"
      expect(result.reason_code).to eq("crawl_trigger_unauthorized")
      expect(crawls(g[:organization_id])).to be_empty
      expect(events("CrawlQueued")).to be_empty
    end

    it "PROOF 259b — the same wait with a live grant still queues, so the refusal is the expiry" do
      g = queueable_org

      result = wait_out_lock("crawl-queue:#{g[:organization_id]}:#{g[:project_id]}", HOLD_SECONDS) { queue(g) }

      expect(result.success?).to be(true), "the control refused, so PROOF 259 proves only that the wait refuses"
      expect(crawls(g[:organization_id]).length).to eq(1)
    end
  end

  describe "PROOF 260 — ActivateCrawlPolicy" do
    it "refuses an activation when the granting Assignment expires during the lock wait" do
      g = bootstrap
      arm_expiry(g[:organization_id])

      result = wait_out_lock("crawl-policy:#{g[:organization_id]}", HOLD_SECONDS) { activate_policy(g) }

      expect(result.success?).to be(false),
                                 "a Role Assignment that expired while this command waited still activated an " \
                                 "Organization-scope crawl policy"
      expect(result.reason_code).to eq("crawl_policy_unauthorized")
      expect(policies(g[:organization_id])).to be_empty
      expect(events("CrawlPolicyActivated")).to be_empty
    end

    it "PROOF 260b — the same wait with a live grant still activates, so the refusal is the expiry" do
      g = bootstrap

      result = wait_out_lock("crawl-policy:#{g[:organization_id]}", HOLD_SECONDS) { activate_policy(g) }

      expect(result.success?).to be(true), "the control refused, so PROOF 260 proves only that the wait refuses"
      expect(policies(g[:organization_id]).length).to eq(1)
    end
  end

  describe "PROOF 261 — CancelCrawl, which already judged the grant after the wait" do
    # THE REGRESSION LOCK. This handler was correct before the repair, and the repair's job is to make
    # the other two match it rather than to make all three wrong in a new way.
    it "refuses a cancellation when the granting Assignment expires during the lock wait" do
      ctx = running_crawl
      org = ctx[:g][:organization_id]
      version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                                [ctx[:crawl_id]])["state_version"].to_i
      arm_expiry(org)

      result = wait_out_frontier(ctx, HOLD_SECONDS) do
        Workflows::Wf005::Handlers::CancelCrawl.new.call(
          command: Workflows::Wf005::Commands::CancelCrawl.new(
            command_id: SecureRandom.uuid_v7, idempotency_key: "gl-#{SecureRandom.hex(6)}",
            schema_version: "1.0", session_id: ctx[:g][:session_id], organization_id: org,
            project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id],
            expected_state_version: version, requested_at_utc: act_now
          ), request_context: act_ctx
        )
      end

      expect(result.success?).to be(false)
      expect(result.reason_code).to eq("crawl_cancel_unauthorized")
      expect(DbInspector.one("SELECT state FROM crawls WHERE id = $1::uuid", [ctx[:crawl_id]])["state"])
        .to eq("running")
    end

    it "PROOF 261b — the same wait with a live grant still cancels, so the refusal is the expiry" do
      # THE CONTROL THIS PROOF WAS MISSING (round-16 contract finding R16-CTR-3). The file's own
      # header claimed every proof here is paired with one; 259 and 260 were, and 261 was not.
      ctx = running_crawl
      version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                                [ctx[:crawl_id]])["state_version"].to_i

      result = wait_out_frontier(ctx, HOLD_SECONDS) do
        Workflows::Wf005::Handlers::CancelCrawl.new.call(
          command: Workflows::Wf005::Commands::CancelCrawl.new(
            command_id: SecureRandom.uuid_v7, idempotency_key: "gl-#{SecureRandom.hex(6)}",
            schema_version: "1.0", session_id: ctx[:g][:session_id],
            organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
            crawl_id: ctx[:crawl_id], expected_state_version: version, requested_at_utc: act_now
          ), request_context: act_ctx
        )
      end

      expect(result.success?).to be(true), "the control refused, so PROOF 261 proves only that the wait refuses"
      expect(DbInspector.one("SELECT state FROM crawls WHERE id = $1::uuid", [ctx[:crawl_id]])["state"])
        .to eq("canceled")
    end
  end
end
