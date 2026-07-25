# frozen_string_literal: true

module AutonomousBuild
  # Append-only execution records (mandate §3.2, §4.5). Each run keeps its input task, source commit,
  # generated brief, agent outputs, verification results, review findings, repair attempts, policy
  # decisions and final status under automation/runs/<run-id>/. History is never silently overwritten:
  # events are appended to an events log, and named artifacts refuse to overwrite an existing file.
  # Everything written is REDACTED — no secret, key or restricted payload lands in a run record.
  class RunRecord
    EVENTS_FILE = "events.jsonl"
    META_FILE = "meta.json"

    attr_reader :dir

    def initialize(dir, extra_secrets: nil)
      @dir = dir
      @extra_secrets = extra_secrets
    end

    def start(metadata)
      FileUtils.mkdir_p(@dir)
      write_artifact(META_FILE, JSON.pretty_generate(redact(metadata)))
      self
    end

    # Append one redacted, timestamped event to the append-only log.
    def append_event(type, data = {}, now: Time.now.utc)
      line = JSON.generate(redact({ "ts" => now.iso8601, "type" => type.to_s, "data" => data }))
      File.open(File.join(@dir, EVENTS_FILE), "a") { |f| f.puts(line) }
      self
    end

    # Write a named artifact once. Refuses to overwrite existing history (append a new attempt-scoped
    # name instead, e.g. implementer_attempt_2.json).
    def write_artifact(name, content)
      path = File.join(@dir, sanitized(name))
      raise Error, "run-record artifact already exists (append-only): #{name}" if File.exist?(path) && name != META_FILE

      redacted = content.is_a?(String) ? Redaction.redact(content, extra_secrets: secrets) : JSON.pretty_generate(redact(content))
      File.write(path, redacted)
      path
    end

    def events
      path = File.join(@dir, EVENTS_FILE)
      return [] unless File.exist?(path)

      File.readlines(path).map { |l| JSON.parse(l) }
    end

    private

    def secrets = @extra_secrets || Redaction.environment_secrets
    def redact(obj) = Redaction.redact_deep(obj, extra_secrets: secrets)

    def sanitized(name)
      raise UnsafePath, "unsafe artifact name #{name.inspect}" unless name.to_s.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/)

      name.to_s
    end
  end
end
