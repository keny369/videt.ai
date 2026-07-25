# frozen_string_literal: true

module AutonomousBuild
  # Deterministic, bounded subprocess execution (mandate §3.5, §8.3, §8.4). Every command passes the
  # CommandPolicy first, runs with a hard timeout (the child is a process group and is killed on
  # expiry so no orphaned work continues), and its captured output is redacted before it can reach a
  # run record. The runner is injectable so the controller can be tested without real subprocesses.
  class CommandRunner
    Result = Data.define(:command, :exit_status, :output, :duration_seconds, :timed_out) do
      def success? = !timed_out && exit_status == 0
    end

    def initialize(default_chdir: AutonomousBuild::ROOT, extra_secrets: nil)
      @default_chdir = default_chdir
      @extra_secrets = extra_secrets
    end

    # Run `command` (a shell string). Rejects a prohibited command before spawning. Captures combined
    # stdout+stderr, kills the process group on timeout, and returns a redacted Result.
    def run(command, chdir: @default_chdir, timeout: 3600, env: {}, strict: false)
      CommandPolicy.assert_allowed!(command, strict:)
      secrets = @extra_secrets || Redaction.environment_secrets
      started = monotonic
      output = +""
      timed_out = false
      exit_status = nil

      Open3.popen2e(env, command, chdir:, pgroup: true) do |stdin, out, wait_thr|
        stdin.close
        reader = Thread.new { out.read.to_s }
        if wait_thr.join(timeout).nil?
          timed_out = true
          kill_group(wait_thr.pid)
        end
        output = reader.value
        exit_status = wait_thr.value&.exitstatus
      end

      Result.new(
        command: Redaction.redact(command, extra_secrets: secrets),
        exit_status:,
        output: Redaction.redact(output, extra_secrets: secrets),
        duration_seconds: (monotonic - started).round(3),
        timed_out:
      )
    end

    private

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def kill_group(pid)
      Process.kill("-TERM", pid)
      sleep 0.2
      Process.kill("-KILL", pid)
    rescue Errno::ESRCH, Errno::EPERM
      # already gone
    end
  end
end
