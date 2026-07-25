# frozen_string_literal: true

module AutonomousBuild
  # The machine-readable current build state (specification/automation/BUILD_STATE.json). Every write
  # is validated and ATOMIC (write-temp + fsync + rename) so a crash never leaves a torn state file
  # (§4.3, §12). `completed_blocks` and `failed_attempts` are append-only in intent: the controller
  # never rewrites state to conceal a failed attempt (AUTONOMY_POLICY prohibited actions).
  class BuildState
    SCHEMA_VERSION = 1

    REQUIRED_KEYS = %w[
      schema_version controller_version current_block current_tranche status attempt_number
      base_commit worktree_path branch_name implementation_commit review_commit
      last_verified_commit verification_run_id open_decisions completed_blocks failed_attempts updated_at
    ].freeze

    # Statuses this file may hold: the run state-machine states plus the two block-level statuses used
    # while a block is queued or actively being built.
    EXTRA_STATUSES = %w[planned in_progress].freeze

    ARRAY_KEYS = %w[open_decisions completed_blocks failed_attempts].freeze

    attr_reader :path, :data

    def self.load(path)
      data = JSON.parse(File.read(path))
      new(path, data).tap(&:validate!)
    end

    def initialize(path, data)
      @path = path
      @data = data
    end

    def validate!
      missing = REQUIRED_KEYS - @data.keys
      raise SchemaError, "BUILD_STATE missing keys: #{missing.join(', ')}" unless missing.empty?
      unless @data["schema_version"] == SCHEMA_VERSION
        raise SchemaError, "BUILD_STATE schema_version #{@data['schema_version'].inspect} != #{SCHEMA_VERSION}"
      end
      unless valid_status?(@data["status"])
        raise SchemaError, "BUILD_STATE status #{@data['status'].inspect} is not a valid state"
      end
      ARRAY_KEYS.each { |k| raise SchemaError, "#{k} must be an array" unless @data[k].is_a?(Array) }
      raise SchemaError, "attempt_number must be a non-negative integer" unless @data["attempt_number"].is_a?(Integer) && @data["attempt_number"] >= 0

      self
    end

    def status = @data["status"]
    def current_block = @data["current_block"]
    def completed_blocks = @data["completed_blocks"]
    def [](key) = @data[key.to_s]

    # Validated, atomic, crash-safe update. Merges `attrs`, stamps updated_at, validates BEFORE
    # writing (so an invalid update never lands on disk), then atomically replaces the file.
    def update(attrs, now: Time.now.utc)
      merged = @data.merge(stringify(attrs))
      merged["updated_at"] = now.iso8601
      BuildState.new(@path, merged).validate!
      atomic_write(@path, "#{JSON.pretty_generate(merged)}\n")
      @data = merged
      self
    end

    def complete_block(block_id, now: Time.now.utc)
      update({ "completed_blocks" => (@data["completed_blocks"] + [block_id]).uniq }, now:)
    end

    def append_failed_attempt(record, now: Time.now.utc)
      update({ "failed_attempts" => @data["failed_attempts"] + [stringify(record)] }, now:)
    end

    private

    def valid_status?(status) = StateMachine.state?(status) || EXTRA_STATUSES.include?(status)

    def stringify(hash) = hash.transform_keys(&:to_s)

    # Atomic replace: write a sibling temp file, flush+fsync, then rename over the target. rename(2)
    # is atomic on one filesystem, so a reader never sees a partial write and a crash leaves either
    # the old or the new complete file — never a torn one.
    def atomic_write(path, content)
      tmp = File.join(File.dirname(path), ".#{File.basename(path)}.#{SecureRandom.hex(8)}.tmp")
      File.open(tmp, "w") do |f|
        f.write(content)
        f.flush
        f.fsync
      end
      File.rename(tmp, path)
    ensure
      File.delete(tmp) if tmp && File.exist?(tmp)
    end
  end
end
