# frozen_string_literal: true

require_relative "../automation_helper"
require "tmpdir"
require "json"
require "autonomous_build/build_state"
require "autonomous_build/controller_lock"

# THE MANDATORY GATE `controller_crash_recovery` NOW HAS A TARGET (FU-45).
#
# It has always named `spec/automation/crash_recovery`, and that path HAS NEVER EXISTED. Unlike
# `controller_locking`, whose subject was covered elsewhere by accident, THIS ONE HAD NO COVERAGE
# ANYWHERE: the controller's crash behaviour was declared mandatory and tested by nothing.
#
# WHAT THE CONTRACT SAYS, from `BuildState`'s own header and the mandate: "All state changes must be
# validated before writing. Use atomic file replacement or an equivalent crash-safe mechanism." The
# properties that follow are what a crash must not be able to produce — a torn state file, a state
# file containing an invalid document, stranded temporary files, or an unreclaimable lock that leaves
# the build permanently stuck.
#
# THE CRASHES ARE REAL. Each uses a child process that is SIGKILLed — not a stub that raises, and not
# a mocked filesystem. A crash-safety proof against a simulated crash proves the simulation.
RSpec.describe "controller crash recovery" do
  around do |example|
    Dir.mktmpdir("f1-crash") { |dir| @dir = dir; example.run }
  end

  def state_path = File.join(@dir, "BUILD_STATE.json")
  def lock_path = File.join(@dir, "controller.lock")

  # A minimally valid document, built from the class's OWN required-key list rather than a literal
  # copied here — a hand-written seed would drift the first time the schema gains a key.
  def seed_data
    AutonomousBuild::BuildState::REQUIRED_KEYS.to_h do |key|
      value = case key
              when "schema_version", "attempt_number" then 0
              when *AutonomousBuild::BuildState::ARRAY_KEYS then []
              when "status" then "idle"
              when "updated_at" then Time.now.utc.iso8601
              else ""
              end
      [key, value]
    end.merge("schema_version" => 1)
  end

  def seed_state
    state = AutonomousBuild::BuildState.new(state_path, seed_data)
    state.update({})
    state
  end

  # A child that writes the state repeatedly and is killed mid-flight. Whichever instant the kill
  # lands on, a reader must find a complete, parseable document.
  def crash_during_writes
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      state = AutonomousBuild::BuildState.load(state_path)
      writer.puts("ready")
      writer.flush
      loop do
        200.times { |i| state.update("attempt_number" => i) }
      end
    end
    writer.close
    reader.gets
    sleep 0.15 # let it get into the write loop; the kill must land mid-flight, not before it starts
    Process.kill("KILL", pid)
    Process.wait(pid)
    reader.close
  end

  it "leaves a COMPLETE, parseable state document however the crash lands" do
    seed_state
    crash_during_writes

    raw = File.read(state_path)
    expect(raw).not_to be_empty, "the crash left an empty state file; the build cannot resume"
    expect { JSON.parse(raw) }.not_to raise_error
    expect(JSON.parse(raw)).to include("schema_version" => 1)
  end

  it "leaves NO stranded temporary files, so a resumed run does not inherit debris" do
    seed_state
    crash_during_writes

    strays = Dir.children(@dir).reject { |f| f == File.basename(state_path) || f == File.basename(lock_path) }
    expect(strays).to be_empty, "the crash stranded #{strays.join(', ')} beside the state file"
  end

  it "leaves the state READABLE BY THE CONTROLLER, not merely valid JSON" do
    # Parseable is not the same as usable. The next run loads it through the same reader it always
    # uses, and a document that fails validation there is a build that cannot restart.
    seed_state
    crash_during_writes

    expect { AutonomousBuild::BuildState.load(state_path) }.not_to raise_error
  end

  it "surrenders the controller lock when the holder is killed, so the build is not stuck" do
    # NO DUPLICATE OWNERSHIP AND NO PERMANENT STALL. Exactly one holder at a time while the crashed
    # process lives, and exactly one successful reclaim after it dies.
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
    expect(reader.gets(chomp: true)).to eq("held")

    expect { AutonomousBuild::ControllerLock.new(path).acquire }
      .to raise_error(AutonomousBuild::LockError), "two controllers held the lock at once"

    Process.kill("KILL", pid)
    Process.wait(pid)

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5.0
    reclaimed = nil
    until reclaimed
      begin
        reclaimed = AutonomousBuild::ControllerLock.new(path).acquire
      rescue AutonomousBuild::LockError
        raise "the crashed run's lock was never released; the build is permanently stuck" if
          Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.05
      end
    end
    expect(reclaimed).to be_held
    reclaimed.release
  ensure
    reader&.close
  end

  it "refuses to persist an INVALID document, so a crash cannot be blamed for a bad write" do
    # Validation happens BEFORE the write. Without this, an invalid update would land atomically and
    # the resulting unusable state would be indistinguishable from crash damage.
    state = seed_state
    before = File.read(state_path)

    expect { state.update("schema_version" => "not-a-number") }.to raise_error(StandardError)
    expect(File.read(state_path)).to eq(before), "an invalid update reached the state file"
  end
end
