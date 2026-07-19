# frozen_string_literal: true

module Platform
  # Platform::UnitOfWork is the single transaction boundary; a handler must not be
  # invoked inside an already-open transaction.
  class NestedTransactionError < StandardError; end
end
