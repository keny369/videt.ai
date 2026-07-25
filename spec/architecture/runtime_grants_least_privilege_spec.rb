# frozen_string_literal: true

require "rails_helper"

# The runtime privilege manifest never confers a broad or destructive privilege on any
# tenant table. This is the global backstop behind the controller's additive-new-table-grant
# exception (DECISIONS.md ADR-027/ADR-029): even if the controller's content classifier were
# defeated, verification here catches a grant of DELETE, TRUNCATE, REFERENCES, TRIGGER or ALL.
# Deletion in this platform is a state transition or cryptographic erasure, never a row DELETE,
# so the runtime holds only SELECT/INSERT/UPDATE on tables.
RSpec.describe "Runtime grants least privilege", type: :model do
  ALLOWED = %w[SELECT INSERT UPDATE].freeze

  it "grants every table only privileges within {SELECT, INSERT, UPDATE}" do
    offenders = F1::RuntimeGrants::TABLE_PRIVILEGES.reject do |_table, privileges|
      privileges.split(",").map(&:strip).all? { |priv| ALLOWED.include?(priv) }
    end
    expect(offenders).to be_empty,
                         "tables granted a privilege beyond SELECT/INSERT/UPDATE: #{offenders.inspect}"
  end
end
