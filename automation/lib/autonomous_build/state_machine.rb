# frozen_string_literal: true

module AutonomousBuild
  # The explicit controller run state machine (mandate §2). Every run ends in exactly one TERMINAL
  # state — there is no ambiguous "still working" state after the process exits. Transitions are
  # closed: an illegal transition raises rather than being silently coerced.
  module StateMachine
    module_function

    # The run is in progress.
    WORKING = %w[idle planning implementing verifying committing reviewing repairing reporting].freeze

    # The run has exited. Terminal states have no outgoing transitions.
    TERMINAL = %w[
      completed ready_for_review human_decision_required blocked_external_dependency
      verification_failed retry_limit_reached policy_violation controller_error
    ].freeze

    STATES = (WORKING + TERMINAL).freeze

    # Commit happens AFTER verification passes and BEFORE independent review (§9): the reviewer
    # inspects the committed diff; repairs re-enter verification and produce new commits.
    TRANSITIONS = {
      "idle" => %w[planning controller_error],
      "planning" => %w[implementing human_decision_required blocked_external_dependency policy_violation controller_error],
      "implementing" => %w[verifying human_decision_required blocked_external_dependency policy_violation retry_limit_reached controller_error],
      "verifying" => %w[committing repairing verification_failed retry_limit_reached policy_violation controller_error],
      "committing" => %w[reviewing controller_error],
      "reviewing" => %w[reporting repairing human_decision_required blocked_external_dependency policy_violation controller_error],
      "repairing" => %w[verifying retry_limit_reached human_decision_required blocked_external_dependency policy_violation controller_error],
      "reporting" => %w[ready_for_review completed controller_error]
    }.freeze

    def terminal?(state) = TERMINAL.include?(state)
    def working?(state) = WORKING.include?(state)
    def state?(state) = STATES.include?(state)

    def allowed?(from, to)
      raise InvalidState, "unknown state #{from.inspect}" unless state?(from)
      raise InvalidState, "unknown state #{to.inspect}" unless state?(to)

      TRANSITIONS.fetch(from, []).include?(to)
    end

    # Return `to` if the transition is allowed, else raise. A terminal state never transitions.
    def transition!(from, to)
      raise InvalidTransition, "#{from} is terminal; cannot transition to #{to}" if terminal?(from)
      raise InvalidTransition, "illegal transition #{from} -> #{to}" unless allowed?(from, to)

      to
    end
  end
end
