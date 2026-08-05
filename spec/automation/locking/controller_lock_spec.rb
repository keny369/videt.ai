# frozen_string_literal: true

require_relative "../automation_helper"
require "autonomous_build/controller_lock"

# THE MANDATORY GATE `controller_locking` NOW HAS A TARGET (FU-45).
#
# It has always named `spec/automation/locking`, and that path HAS NEVER EXISTED — not at any commit
# in this repository. The gate has therefore never executed, for any acceptance, while being declared
# mandatory. Its subject matter was partly covered elsewhere by accident of naming; this is the
# correctly owned target the declaration was always pointing at.
#
# WHAT IT PROVES, from the mandate: a single-instance advisory lock so two autonomous runs cannot
# operate on the same build state at once, failing FAST rather than queueing, and releasing when the
# holder dies.
RSpec.describe AutonomousBuild::ControllerLock do
  around do |example|
    Dir.mktmpdir("f1-lock") { |dir| @dir = dir; example.run }
  end

  def lock_path = File.join(@dir, "nested", "controller.lock")

  it "grants the lock to one holder and records who holds it" do
    lock = described_class.new(lock_path)
    lock.acquire

    expect(lock).to be_held
    expect(File.read(lock_path)).to match(/\A#{Process.pid} \d{4}-\d{2}-\d{2}T/)
  ensure
    lock&.release
  end

  it "REFUSES a second holder rather than queueing behind the first" do
    # The distinction is the point: a lock that blocked would silently SERIALISE two controller runs
    # that each believe they own the build state. Duplicate execution must be locked out, not delayed.
    first = described_class.new(lock_path).acquire
    second = described_class.new(lock_path)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { second.acquire }.to raise_error(AutonomousBuild::LockError, /duplicate execution is locked out/)
    # BOUNDED: fail-fast means fail-fast. A blocking implementation would sit here.
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2.0
    expect(second).not_to be_held
  ensure
    first&.release
  end

  it "releases on `release`, so the next run can proceed" do
    described_class.new(lock_path).acquire.release

    expect { described_class.new(lock_path).acquire.release }.not_to raise_error
  end

  it "releases when the holding PROCESS DIES, which is the crash case the mandate names" do
    # A REAL PROCESS, REALLY KILLED. `flock` is released by the kernel when the owning process exits,
    # and that is the property the controller depends on after a crash — asserting it against a
    # stubbed holder would prove nothing about the kernel.
    path = lock_path
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      AutonomousBuild::ControllerLock.new(path).acquire
      writer.puts("held")
      writer.flush
      sleep 30
    end
    writer.close
    expect(reader.gets(chomp: true)).to eq("held"), "the child never took the lock"

    # While it lives, we are locked out.
    expect { described_class.new(path).acquire }.to raise_error(AutonomousBuild::LockError)

    Process.kill("KILL", pid)
    Process.wait(pid)

    # BOUNDED WAIT, with a diagnostic rather than a bare timeout.
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5.0
    acquired = nil
    until acquired
      begin
        acquired = described_class.new(path).acquire
      rescue AutonomousBuild::LockError
        raise "the lock survived the death of its holder (#{File.read(path).strip})" if
          Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.05
      end
    end
    expect(acquired).to be_held
    acquired.release
  ensure
    reader&.close
  end

  it "with_lock releases even when the block raises" do
    lock = described_class.new(lock_path)
    expect { lock.with_lock { raise "boom" } }.to raise_error("boom")

    expect(lock).not_to be_held
    expect { described_class.new(lock_path).acquire.release }.not_to raise_error
  end
end
