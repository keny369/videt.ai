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

    # THE SHAPE OF A FAILED ATTEMPT (FU-40).
    #
    # WHAT WAS OPEN. `failed_attempts` was REQUIRED, VALIDATED AS AN ARRAY and given a dedicated
    # `append_failed_attempt` writer, and it accepted ANY hash — so its only caller was its own unit
    # spec, which appended `{"attempt" => 1, "reason" => "verification_failed"}`, a shape nothing else
    # in the repository knows how to read. A field with no shape has no writer, because there is
    # nothing for a writer to write. Meanwhile fourteen five-lens rounds returned NOT ACCEPTED against
    # S-07-009 and every one of them lived in prose, so a reader that trusted only this field
    # concluded the tranche had never failed.
    #
    # THE MEMBERS ARE THE MINIMUM A READER NEEDS TO RE-DERIVE THE FAILURE, and each is answerable from
    # the review record rather than from recollection: which attempt it was, which tranche it judged,
    # the range it judged (pinned, never `..HEAD`), what it returned, by what mechanism, how many
    # blocking findings it confirmed, and where the findings themselves are written down. Nothing
    # here is a summary or a judgement — `spec/architecture/repository_truth_spec.rb` derives all
    # seven from the review record and fails when they disagree.
    FAILED_ATTEMPT_KEYS = %w[attempt tranche candidate_range outcome mechanism
                             blocking_findings record].freeze

    # A CLOSED ENUMERATION, because "what went wrong" is the one member a writer is tempted to
    # freetext. `not_accepted` is an ADR-080 review returning FAIL; `verification_failed` is the
    # objective gate refusing before any review ran. The controller reaches only the first today; the
    # second exists because `StateMachine` already has that terminal state and a row for it must not
    # have to invent a word.
    FAILED_ATTEMPT_OUTCOMES = %w[not_accepted verification_failed].freeze

    RANGE = /\A[0-9a-f]{7,40}\.\.[0-9a-f]{7,40}\z/

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

      @data["failed_attempts"].each_with_index { |record, i| validate_failed_attempt!(record, i) }

      self
    end

    # Validated here rather than only in the writer, so a row that reached the file by any route —
    # a hand edit, a backfill, an older controller — is refused on the next load instead of being
    # trusted because of how it arrived.
    def validate_failed_attempt!(record, index)
      raise SchemaError, "failed_attempts[#{index}] must be an object" unless record.is_a?(Hash)

      keys = record.keys.sort
      unless keys == FAILED_ATTEMPT_KEYS.sort
        raise SchemaError, "failed_attempts[#{index}] members are #{keys.join(', ')}; " \
                           "the shape is #{FAILED_ATTEMPT_KEYS.join(', ')}"
      end
      unless record["attempt"].is_a?(Integer) && record["attempt"].positive?
        raise SchemaError, "failed_attempts[#{index}].attempt must be a positive integer"
      end
      unless FAILED_ATTEMPT_OUTCOMES.include?(record["outcome"])
        raise SchemaError, "failed_attempts[#{index}].outcome #{record['outcome'].inspect} is not one of " \
                           "#{FAILED_ATTEMPT_OUTCOMES.join(', ')}"
      end
      unless record["candidate_range"].to_s.match?(RANGE)
        raise SchemaError, "failed_attempts[#{index}].candidate_range #{record['candidate_range'].inspect} " \
                           "is not a pinned base..head range"
      end
      unless record["blocking_findings"].is_a?(Integer) && !record["blocking_findings"].negative?
        raise SchemaError, "failed_attempts[#{index}].blocking_findings must be a non-negative integer"
      end
      %w[tranche mechanism record].each do |member|
        raise SchemaError, "failed_attempts[#{index}].#{member} must be a non-empty string" if record[member].to_s.empty?
      end
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
