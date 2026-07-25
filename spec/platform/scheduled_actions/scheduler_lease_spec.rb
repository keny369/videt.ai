# frozen_string_literal: true

require "rails_helper"
require "pg"

# F-04 Background Execution — the single-scheduler control (BACKGROUND_PROCESSING.md :67). The
# advisory lease is what keeps the committed operational configuration from running two effective
# schedulers while the full leader-election lease is deferred (G6). Proven with two independent
# transport connections, no sleeping.
RSpec.describe Platform::ScheduledActions::SchedulerLease, type: :model do
  def transport_connection
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    PG.connect(host: cfg[:host], port: cfg[:port], dbname: cfg[:database],
               user: ENV.fetch("F1_TRANSPORT_DATABASE_USER", "f1_platform_worker"),
               password: ENV.fetch("F1_TRANSPORT_DATABASE_PASSWORD", cfg[:password]))
  end

  it "lets exactly one scheduler hold the lease, and hands over only after release" do
    leader = transport_connection
    contender = transport_connection
    begin
      expect(described_class.acquire?(leader)).to be(true)
      # A second scheduler process cannot acquire it — it must not dispatch.
      expect(described_class.acquire?(contender)).to be(false)

      # Failover: once the leader releases (or its connection dies), a replacement can take over.
      described_class.release(leader)
      expect(described_class.acquire?(contender)).to be(true)
    ensure
      leader.close
      contender.close # closing the holder's connection releases the advisory lock
    end
  end

  it "runs the block only for the leader and refuses a second holder with :not_leader" do
    leader = transport_connection
    contender = transport_connection
    begin
      expect(described_class.acquire?(leader)).to be(true) # leader already holds it

      ran = false
      expect(described_class.as_leader(contender) { ran = true }).to eq(:not_leader)
      expect(ran).to be(false)
    ensure
      leader.close
      contender.close
    end
  end

  it "releases the lease after the leader's block so the next pass can re-acquire" do
    pg = transport_connection
    begin
      expect(described_class.as_leader(pg) { :did_work }).to eq(:did_work)
      # Released in the ensure: a fresh acquire on the same connection succeeds again.
      expect(described_class.acquire?(pg)).to be(true)
      described_class.release(pg)
    ensure
      pg.close
    end
  end

  # The enforceable G6 control: the committed scheduler front door MUST be lease-guarded, so a
  # second scheduler can never dispatch while the full leader-election lease is deferred. If the
  # guard is ever removed from the façade, these fail CI.
  it "guards the scheduler front door — run_scheduler refuses when the lease is already held" do
    holder = transport_connection
    begin
      expect(described_class.acquire?(holder)).to be(true)
      expect(Platform::BackgroundExecution.run_scheduler(running: -> { true }, pace: -> {})).to eq(:not_leader)
    ensure
      holder.close
    end
  end

  it "HOLDS the lease for the whole run, so a concurrent scheduler cannot lead mid-loop" do
    contender = transport_connection
    contender_acquired = nil
    begin
      # `running` is evaluated WHILE run_scheduler holds the lease; a separate connection must not
      # be able to acquire it, proving the lease is held across the run (not freed between passes).
      Platform::BackgroundExecution.run_scheduler(
        pace: -> {},
        running: lambda {
          contender_acquired = described_class.acquire?(contender)
          false # one check, then stop — no dispatch pass runs
        }
      )
      expect(contender_acquired).to be(false)
    ensure
      described_class.release(contender) if contender_acquired
      contender.close
    end
  end

  # A pinned transport connection must NOT be silently reconnected — losing it raises so the
  # scheduler can fail closed rather than dispatch on a connection that holds no lease.
  it "raises ConnectionLost instead of silently reconnecting a lost pinned connection" do
    Platform::ScheduledActions::TransportConnection.pinned do |pg|
      pg.close # simulate connection loss
      expect { Platform::ScheduledActions::TransportConnection.with { |c| c } }
        .to raise_error(Platform::ScheduledActions::TransportConnection::ConnectionLost)
    end
  end

  # run_scheduler must fail closed (never continue lease-less) when the lease-holding connection is
  # lost mid-run; the next start must re-acquire the lease before dispatching.
  it "fails closed with :lease_lost when the lease-holding connection is lost mid-run" do
    losing = Object.new
    def losing.recover_expired_leases
      raise Platform::ScheduledActions::TransportConnection::ConnectionLost, "lost"
    end
    def losing.dispatch_due(*) = raise("must not dispatch after the lease connection is lost")

    expect(Platform::BackgroundExecution.run_scheduler(dispatcher: losing, pace: -> {})).to eq(:lease_lost)
  end
end
