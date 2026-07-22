# frozen_string_literal: true

# Forces a real transaction abort at a precise production statement, without a
# test-only hook in the production code.
#
# A trigger is installed on the table the next statement writes; the statement
# raises; PostgreSQL aborts the whole transaction. That proves atomicity where a
# mock could only prove that a mock was called: every write the command made
# before that point — the command execution, the authorization decision, the
# approval record, the allowlist, the epoch advance — has to disappear because
# the database removed it, not because the application remembered to.
module FailureInjector
  module_function

  ERROR = "f1_injected_failure"

  # Abort the transaction at the first `event` on `table`. `timing: "AFTER"`
  # lets the row change happen first, which is how "rolled back after the write
  # began" is distinguished from "rolled back before it".
  def abort_on(table, event, timing: "BEFORE")
    name = "f1_test_abort_#{table}"
    conn = DbInspector.connection
    conn.exec(<<~SQL)
      CREATE OR REPLACE FUNCTION #{name}() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION '#{ERROR}' USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER #{name} #{timing} #{event} ON #{table}
        FOR EACH ROW EXECUTE FUNCTION #{name}();
    SQL
    yield
  ensure
    conn.exec("DROP TRIGGER IF EXISTS #{name} ON #{table}; DROP FUNCTION IF EXISTS #{name}();")
  end

  # Run `operation`, expecting the injected abort to reach the caller.
  def expect_abort(&operation)
    operation.call
    raise "expected the injected failure to abort the transaction, but it completed"
  rescue PG::RaiseException, ActiveRecord::StatementInvalid => e
    raise unless e.message.include?(ERROR)

    e
  end
end
