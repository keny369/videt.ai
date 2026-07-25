# frozen_string_literal: true

module AutonomousBuild
  # The machine-readable build graph (BUILD_PLAN.yml). Determines the next AUTHORISED block from
  # versioned repository state — never conversational memory (§3.1). A block is runnable only when
  # every dependency is complete/frozen; a block with a human gate before it is reported as gated and
  # is not run autonomously.
  class Plan
    DONE_STATUSES = %w[frozen completed done].freeze

    attr_reader :data

    def self.load(path) = new(YAML.safe_load_file(path))

    def initialize(data)
      @data = data
    end

    def foundations = @data.fetch("protected_foundations", [])
    def blocks = @data.fetch("blocks", [])

    # Ids that count as satisfied dependencies: frozen foundations plus completed blocks.
    def satisfied_ids(completed_blocks: [])
      done_foundations = foundations.select { |f| DONE_STATUSES.include?(f["status"]) }.map { |f| f["id"] }
      done_blocks = blocks.select { |b| DONE_STATUSES.include?(b["status"]) }.map { |b| b["id"] }
      (done_foundations + done_blocks + completed_blocks).uniq
    end

    # The next block to build: the first non-done block whose dependencies are all satisfied. Returns
    # nil when nothing is runnable.
    def next_block(completed_blocks: [])
      satisfied = satisfied_ids(completed_blocks:)
      blocks.reject { |b| DONE_STATUSES.include?(b["status"]) }
            .find { |b| Array(b["depends_on"]).all? { |dep| satisfied.include?(dep) } }
    end

    def human_gated_before?(block) = block && (block["human_gate_before"] == true)
  end
end
