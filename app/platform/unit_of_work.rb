# frozen_string_literal: true

module Platform
  # The single transaction boundary for a state-changing command
  # (APPLICATION_LAYER.md § Workflow Orchestration And Unit Of Work). It opens
  # exactly one transaction at the default READ COMMITTED isolation, rejects being
  # nested inside another transaction, and asserts on entry that the checked-out
  # connection carries no leftover proved context.
  module UnitOfWork
    module_function

    def run(connection: ActiveRecord::Base.connection)
      raise Platform::NestedTransactionError, "a command must own its transaction" if connection.transaction_open?

      connection.transaction do
        assert_clean_context!(connection)
        yield connection
      end
    end

    def assert_clean_context!(connection)
      proof = connection.select_value("SELECT current_setting('app.f1_proof', true)")
      return if proof.nil? || proof == ""

      raise Platform::LeakedContextError, "checked-out connection has leftover proved context"
    end
  end
end
