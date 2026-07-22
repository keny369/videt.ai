# frozen_string_literal: true

require "securerandom"

# Drives the ScheduledAction subsystem the way production does, so the specs
# exercise the real privilege path rather than a test-only shortcut.
#
# `create` runs the production Store inside a unit of work that has entered the
# proved Organization context — exactly what an activation transaction does — on
# the ordinary runtime connection (f1_web), under row level security and with no
# UPDATE grant. `row`/`rows` read committed state back through the BYPASSRLS
# superuser connection so cross-Organization and cross-principal assertions are
# possible from outside any context.
module ScheduledActionHarness
  module_function

  DEFAULT_KIND = "invitation_expire"

  # Create one action through the runtime path. Returns the Store result
  # ({ id:, replayed:, collision_ordinal: }).
  def create(organization_id:, target_id:, action_kind: DEFAULT_KIND, action_schema_version: "1.0",
             target_type: "invitation", due_at: Time.utc(2026, 7, 25, 10, 0, 0),
             now: Time.utc(2026, 7, 18, 10, 0, 0), **overrides)
    in_context(organization_id) do |store, correlation_id|
      store.create(
        id: SecureRandom.uuid_v7, action_kind:, action_schema_version:, organization_id:,
        target_type:, target_id:, due_at:, now:, correlation_id:, causation_id: correlation_id,
        executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor, **overrides
      )
    end
  end

  # Yield a Store bound to a runtime connection already inside `organization_id`.
  def in_context(organization_id)
    Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      correlation_id = SecureRandom.uuid_v7
      pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [organization_id, correlation_id])
      yield Platform::ScheduledActions::Store.new(pg), correlation_id
    end
  end

  # A Store on the real platform-worker transport connection: the only principal
  # permitted to claim, dispatch, settle, release, sweep or cancel scheduled work.
  def transport_store
    Platform::ScheduledActions::TransportConnection.with do |pg|
      yield Platform::ScheduledActions::Store.new(pg)
    end
  end

  # Deterministic time control without a caller-supplied clock and without
  # sleeping. PostgreSQL transaction time is the authority, so a test makes an
  # action due, or a lease elapsed, by writing the row's own instants. `due_at` is
  # immutable, so due-ness is chosen at creation; `lease_expires_at` is mutable
  # within the same status, which is exactly what a lease is.
  def elapse_lease!(id)
    owner_exec(<<~SQL, [id])
      UPDATE scheduled_actions
      SET lease_expires_at = transaction_timestamp() - interval '1 second'
      WHERE id = $1::uuid
    SQL
  end

  # An instant PostgreSQL already considers past / still future.
  def past(seconds = 3600) = db_instant("- interval '#{seconds} seconds'")
  def future(seconds = 3600) = db_instant("+ interval '#{seconds} seconds'")

  def db_instant(offset = "")
    Time.parse(DbInspector.connection.exec("SELECT transaction_timestamp() #{offset}").getvalue(0, 0)).getutc
  end

  def row(id) = DbInspector.one("SELECT * FROM scheduled_actions WHERE id = $1::uuid", [id])
  def rows = DbInspector.all("SELECT * FROM scheduled_actions ORDER BY due_at, id")
  def count = DbInspector.count("scheduled_actions")

  # Owner-side statement, for asserting that the database boundary — not the
  # application — rejects an illegal mutation.
  def owner_exec(sql, params = [])
    DbInspector.connection.exec_params(sql, params)
  end

  # A short-lived connection as a named login role, for proving what a principal
  # genuinely cannot do rather than what the application declines to attempt.
  def as_role(role)
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    conn = PG.connect(host: cfg[:host], port: cfg[:port], dbname: cfg[:database], user: role)
    begin
      yield conn
    ensure
      conn.close
    end
  end
end
