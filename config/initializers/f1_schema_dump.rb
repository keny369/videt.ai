# frozen_string_literal: true

# PROVISIONING MUST NOT REWRITE THE CANONICAL SCHEMA ARTIFACT (ADR-129).
#
# `db:migrate` invokes `db:_dump`, so provisioning a scratch database rewrites `db/structure.sql` in
# the working tree. That is how a probe table created in a throwaway test database ended up in the
# repository's canonical schema file. Developers still get the dump by default when they add a
# migration; the bootstrap route sets this flag because its job is to BUILD a database, not to
# redefine what the canonical schema is.
Rails.application.configure do
  config.active_record.dump_schema_after_migration = false if ENV["F1_SUPPRESS_SCHEMA_DUMP"] == "1"
end
