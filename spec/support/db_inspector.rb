# frozen_string_literal: true

require "pg"

# Reads committed rows for assertions using a BYPASSRLS superuser connection.
# The runtime role and even the schema owner are subject to FORCE RLS, so tests
# verify cross-principal state (counts, the OD-013 event organization_id) from
# outside any established context.
module DbInspector
  module_function

  def connection
    @connection ||= begin
      cfg = ActiveRecord::Base.connection_db_config.configuration_hash
      # The local cluster superuser bypasses RLS.
      PG.connect(host: cfg[:host], port: cfg[:port], dbname: cfg[:database], user: superuser)
    end
  end

  def superuser
    @superuser ||= ActiveRecord::Base.connection.select_value(
      "SELECT rolname FROM pg_roles WHERE rolsuper AND rolcanlogin ORDER BY rolname LIMIT 1"
    )
  end

  def count(table) = connection.exec("SELECT count(*) FROM #{table}").getvalue(0, 0).to_i

  def one(sql, params = []) = connection.exec_params(sql, params).to_a.first

  def all(sql, params = []) = connection.exec_params(sql, params).to_a

  def bootstrap_principal_uuid(principal_digest)
    connection.exec_params("SELECT f1_bootstrap_principal_uuid($1)", [{ value: principal_digest, format: 1 }])
              .getvalue(0, 0)
  end
end
