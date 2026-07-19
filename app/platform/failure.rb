# frozen_string_literal: true

module Platform
  # The failure fields of the Logical Result And Error Contract. Immutable.
  Failure = Data.define(
    :error_class, :error_code, :reason_code, :severity,
    :retryable, :recovery_action, :support_reference
  )
end
