# frozen_string_literal: true

require "rails_helper"

# Organization lifecycle concurrency and the invariants that must hold whatever
# order commands arrive in.
#
# Every lifecycle command takes the same per-Organization advisory lock and
# compare-and-swaps on BOTH the state version and the authorization epoch, so a
# loser observes zero rows changed rather than overwriting a winner. Nothing here
# sleeps; the races are real transactions on separate connections.
RSpec.describe "WF-013 organization lifecycle concurrency", type: :acceptance,
               acceptance_ids: ["AC-CAP-013", "AC-WF-013"],
               test_types: %w[TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "admin-#{SecureRandom.hex(8)}" } }
  let(:invitee_email) { "invitee-#{SecureRandom.hex(4)}@example.com" }

  # An active Organization whose admin identity can also mint reactivation proofs.
  let(:world) do
    org = TenantSeeder.create_organization
    account = TenantSeeder.create_account(organization_id: org, issuer_key: identity[:issuer_key],
                                          subject: identity[:subject])
    TenantSeeder.create_role_assignment(organization_id: org, account_id: account,
                                        bootstrap_admin_exception: true)
    TenantSeeder.create_access_policy(organization_id: org)
    { organization_id: org, account_id: account }
  end

  def session_for(w) = TenantSeeder.create_session(organization_id: w[:organization_id],
                                                   account_id: w[:account_id], issued_at: fixed_now - 900)

  def ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(fixed_now),
                                               ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)

  def suspend(session_id, key: "s-#{SecureRandom.hex(3)}", version: 0, epoch: 7)
    cmd = Workflows::Wf013::Commands::SuspendOrganization.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      expected_state_version: version, expected_authorization_epoch: epoch,
      reason: "concurrency coverage", requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::SuspendOrganization.new.call(command: cmd, request_context: ctx)
  end

  def reactivate(org, digest, key: "r-#{SecureRandom.hex(3)}", version: 1, epoch: 8)
    cmd = Workflows::Wf013::Commands::ReactivateOrganization.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", organization_id: org,
      receipt_digest: digest, expected_state_version: version, expected_authorization_epoch: epoch,
      requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::ReactivateOrganization.new.call(command: cmd, request_context: ctx)
  end

  def reactivation_receipt
    ReceiptMinter.mint_reactivation_receipt(validated_at: fixed_now, issuer_key: identity[:issuer_key],
                                            subject: identity[:subject])
  end

  def create_invitation(session_id, key: "inv")
    cmd = Workflows::Wf013::Commands::CreateInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      target_email: invitee_email, target_identity_issuer_key: nil, target_identity_subject: nil,
      canonical_role: "MarketingOperator", permission_mode: "standard", persona: nil,
      scope_sha256: Digest::SHA256.digest("scope:organization"),
      intended_assignment_expires_at: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::CreateInvitation.new.call(command: cmd, request_context: ctx)
  end

  def organization(org) = DbInspector.one("SELECT * FROM organizations WHERE id = $1::uuid", [org])
  def lifecycle_events
    DbInspector.all(<<~SQL).map { |e| e["event_type"] }
      SELECT event_type FROM event_registry
      WHERE event_type IN ('OrganizationSuspended','OrganizationReactivated')
    SQL
  end

  # BOUNDED, BECAUSE A GATE THAT HANGS IS WORSE THAN A GATE THAT FAILS (round 9's gate-reliability
  # finding). `Thread#value` waits forever, so a pair of racing commands that deadlock, or that block
  # on a lock nobody releases, wedged the FULL SUITE indefinitely rather than failing it — observed
  # once under concurrent load, with the main thread in `thread_join` and a worker blocked in
  # `PQgetResult` while every connection sat idle. Five other runs completed normally, so it is
  # intermittent and suite-context-dependent, which is exactly the shape a bound exists for.
  #
  # THE RACE IS PRESERVED, NOT SERIALISED. Both threads still start together and still contend for the
  # same locks; the only change is that waiting has an end, and reaching that end reports WHAT WAS
  # STILL RUNNING rather than a bare timeout. `RaceHarness::TIMEOUT_SECONDS` is the repository's
  # existing bound for exactly this, so there is one number rather than a second one invented here.
  def race(first, second)
    threads = [Thread.new { ActiveRecord::Base.connection_pool.with_connection { first.call } },
               Thread.new { ActiveRecord::Base.connection_pool.with_connection { second.call } }]
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + RaceHarness::TIMEOUT_SECONDS
    threads.each do |thread|
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      next if remaining.positive? && thread.join(remaining)

      states = threads.map { |t| "#{t.name || 'thread'}=#{t.status.inspect}" }.join(", ")
      backtraces = threads.filter_map { |t| t.backtrace&.first(4)&.join("\n      ") }
      threads.each(&:kill)
      raise "a racing command did not finish within #{RaceHarness::TIMEOUT_SECONDS}s. " \
            "Thread states: #{states}.\n  Backtraces:\n      #{backtraces.join("\n      --\n      ")}"
    end
    threads.map(&:value)
  end

  describe "exactly one lifecycle transition wins" do
    it "suspend x suspend: one transition, one event, one epoch advance" do
      w = world
      a = session_for(w)
      b = session_for(w)

      results = race(-> { suspend(a, key: "s1") }, -> { suspend(b, key: "s2") })

      expect(results.count(&:success?)).to eq(1)
      expect(organization(w[:organization_id])["status"]).to eq("suspended")
      expect(organization(w[:organization_id])["authorization_epoch"].to_i).to eq(8)
      expect(lifecycle_events).to eq(["OrganizationSuspended"])
      # The loser is refused by the shared boundary or by the guarded update, never
      # by overwriting the winner.
      expect(results.find(&:failure?).reason_code)
        .to be_in(%w[session_invalid organization_inactive organization_state_invalid])
    end

    it "reactivate x reactivate: one transition and no second epoch advance" do
      w = world
      expect(suspend(session_for(w))).to be_success
      first = reactivation_receipt
      second = reactivation_receipt

      results = race(-> { reactivate(w[:organization_id], first[:receipt_digest], key: "r1") },
                     -> { reactivate(w[:organization_id], second[:receipt_digest], key: "r2") })

      expect(results.count(&:success?)).to eq(1)
      expect(organization(w[:organization_id])["status"]).to eq("active")
      expect(organization(w[:organization_id])["authorization_epoch"].to_i).to eq(9)
      expect(lifecycle_events).to eq(%w[OrganizationSuspended OrganizationReactivated])
      expect(results.find(&:failure?).reason_code)
        .to be_in(%w[organization_state_invalid stale_state_version stale_authorization_epoch])
    end

    it "suspend x reactivate: the Organization ends in exactly one state with one event each at most" do
      w = world
      expect(suspend(session_for(w))).to be_success
      proof = reactivation_receipt
      # Reactivate, racing a further suspension attempt from a session created
      # after the first suspension.
      late = session_for(w)

      race(-> { reactivate(w[:organization_id], proof[:receipt_digest]) },
           -> { suspend(late, key: "late", version: 1, epoch: 8) })

      row = organization(w[:organization_id])
      expect(row["status"]).to be_in(%w[active suspended])
      expect(lifecycle_events.count("OrganizationSuspended")).to eq(1)
      expect(lifecycle_events.count("OrganizationReactivated")).to be <= 1
      expect(row["authorization_epoch"].to_i).to be_in([8, 9])
    end
  end

  describe "suspension races an ordinary authorized command" do
    it "suspend x CreateInvitation: the Invitation is created or refused, never half-authorized" do
      w = world
      admin_session = session_for(w)
      other_session = session_for(w)

      results = race(-> { suspend(admin_session) }, -> { create_invitation(other_session) })
      suspended, created = results

      expect(suspended).to be_success
      expect(organization(w[:organization_id])["status"]).to eq("suspended")
      if created.success?
        # It won the race: it committed under the pre-suspension epoch, and its
        # Invitation and timer are both present and consistent.
        expect(DbInspector.count("invitations")).to eq(1)
        expect(DbInspector.count("scheduled_actions")).to eq(1)
      else
        # THE THIRD REFUSAL WAS REACHABLE AND UNNAMED (measured 2026-08-11, ADR-150).
        #
        # This list held two codes and the suspension race produced a third in a whole-suite run:
        # `stale_authorization_epoch`, which `create_invitation.rb:156` returns when the epoch
        # advances between authentication and the write — which is EXACTLY what the suspension in
        # this race does. Under the interleaving where the advance commits inside that window, the
        # command refuses for that reason, the property this example defends STILL HOLDS (no
        # Invitation, no timer, nothing half-authorized), and the example failed anyway on an
        # enumeration rather than on the invariant.
        #
        # IT IS NOT A WIDENING TO MAKE A RUN GREEN, and the file's own siblings are the evidence:
        # `:126` and `:143` each name THREE outcomes for the same shape of race, and `:143` names
        # this very code. One assertion out of three had been written from a shorter reading of the
        # handler. The two row counts below are untouched, so a genuinely half-authorized outcome
        # still fails here whatever reason code it carries.
        expect(created.reason_code).to be_in(%w[session_invalid organization_inactive
                                                stale_authorization_epoch])
        expect(DbInspector.count("invitations")).to eq(0)
        expect(DbInspector.count("scheduled_actions")).to eq(0)
      end
    end

    it "never leaves an Invitation without its timer, whichever way the race falls" do
      w = world
      # THE SESSIONS ARE SEEDED BEFORE THE THREADS START, as every other race in this file does.
      #
      # This example was the only `race` call that constructed its sessions INSIDE the racing lambdas,
      # and `TenantSeeder.create_session` writes. Two threads therefore began by contending in the
      # HARNESS rather than in the commands under test, and roughly one full-suite run in three ended
      # with a thread parked in `create_session` until the 15-second bound expired. The sibling
      # example above races the identical pair — `suspend` against `create_invitation` — with its
      # sessions hoisted, and has never hung.
      #
      # THE RACE UNDER TEST IS NOT WEAKENED; it is isolated. Both threads still start together and
      # still contend for the same lifecycle locks. What changed is that they now start AT the
      # commands, so what contends is the thing this example is about.
      suspending, inviting = session_for(w), session_for(w)
      results = race(-> { suspend(suspending) }, -> { create_invitation(inviting) })
      expect(results.first).to be_success

      orphans = DbInspector.all(<<~SQL)
        SELECT i.id FROM invitations i
        WHERE i.activated_at IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM scheduled_actions a
                          WHERE a.target_id = i.id AND a.due_at = i.expires_at)
      SQL
      expect(orphans).to be_empty
    end
  end

  describe "no split-brain state or epoch" do
    it "never commits a status change without its epoch advance, under any interleaving" do
      w = world
      3.times { |i| suspend(session_for(w), key: "x#{i}") }
      reactivate(w[:organization_id], reactivation_receipt[:receipt_digest])

      row = organization(w[:organization_id])
      # Every committed transition advanced both, so the epoch is exactly the
      # number of committed transitions above the seeded baseline.
      transitions = lifecycle_events.size
      expect(row["authorization_epoch"].to_i).to eq(7 + transitions)
      expect(row["state_version"].to_i).to eq(transitions)
    end

    it "keeps the epoch monotonic across the whole lifecycle" do
      w = world
      epochs = []
      epochs << organization(w[:organization_id])["authorization_epoch"].to_i
      suspend(session_for(w))
      epochs << organization(w[:organization_id])["authorization_epoch"].to_i
      reactivate(w[:organization_id], reactivation_receipt[:receipt_digest])
      epochs << organization(w[:organization_id])["authorization_epoch"].to_i
      suspend(session_for(w), version: 2, epoch: 9)
      epochs << organization(w[:organization_id])["authorization_epoch"].to_i

      expect(epochs).to eq(epochs.sort)
      expect(epochs.uniq.size).to eq(epochs.size)
    end
  end

  describe "idempotency keys do not bridge authorization epochs" do
    it "refuses to reuse one key across materially different epochs, rather than replaying the old result" do
      w = world
      first = suspend(session_for(w), key: "shared")
      expect(first.payload[:authorization_epoch]).to eq(8)

      reactivate(w[:organization_id], reactivation_receipt[:receipt_digest])
      second = suspend(session_for(w), key: "shared", version: 2, epoch: 9)

      # The request digest binds the expected state version AND expected epoch, so
      # the same key against a different epoch is an altered command, not a replay:
      # `idempotency_conflict` rather than a stale success being handed back.
      expect(second).to be_failure
      expect(second.reason_code).to eq("idempotency_conflict")
      expect(organization(w[:organization_id])["status"]).to eq("active")
      expect(lifecycle_events).to eq(%w[OrganizationSuspended OrganizationReactivated])
    end

    it "lets a fresh key suspend again after reactivation, under the new epoch" do
      w = world
      suspend(session_for(w), key: "first")
      reactivate(w[:organization_id], reactivation_receipt[:receipt_digest])
      again = suspend(session_for(w), key: "second", version: 2, epoch: 9)

      expect(again).to be_success
      expect(again.payload[:authorization_epoch]).to eq(10)
      expect(lifecycle_events).to eq(%w[OrganizationSuspended OrganizationReactivated OrganizationSuspended])
    end
  end
end
