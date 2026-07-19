# frozen_string_literal: true

module Platform
  # Raised only for an unmapped implementation defect (APPLICATION_LAYER.md §
  # Command Type And Handler Contract). A handler returns a CommandResult for
  # every accepted success or contract failure and raises this for nothing else.
  class InvariantViolation < StandardError; end
end
