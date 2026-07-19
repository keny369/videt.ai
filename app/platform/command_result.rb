# frozen_string_literal: true

module Platform
  # One deeply frozen result per command (WORKFLOW_SPECIFICATIONS.md § Logical
  # Result And Error Contract). `replayed` distinguishes a fresh commit from a
  # returned stored result. `payload` is the authorized/redacted success body;
  # `failure` is a Platform::Failure. Exactly one is present.
  class CommandResult
    attr_reader :result_id, :command_type, :outcome, :replayed,
                :payload, :failure, :audit_record_id, :correlation_id

    def self.success(result_id:, command_type:, payload:, audit_record_id:, correlation_id:, replayed: false)
      new(result_id:, command_type:, outcome: "success", replayed:,
          payload: payload.freeze, failure: nil, audit_record_id:, correlation_id:)
    end

    def self.failure(result_id:, command_type:, failure:, audit_record_id:, correlation_id:, replayed: false)
      new(result_id:, command_type:, outcome: "failure", replayed:,
          payload: nil, failure:, audit_record_id:, correlation_id:)
    end

    def initialize(result_id:, command_type:, outcome:, replayed:, payload:, failure:, audit_record_id:, correlation_id:)
      @result_id = result_id
      @command_type = command_type
      @outcome = outcome
      @replayed = replayed
      @payload = payload
      @failure = failure
      @audit_record_id = audit_record_id
      @correlation_id = correlation_id
      freeze
    end

    def success? = outcome == "success"
    def failure? = outcome == "failure"
    def reason_code = failure&.reason_code
  end
end
