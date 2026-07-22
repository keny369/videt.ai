# frozen_string_literal: true

require_relative "../f1/runtime_grants"

# Reproducible database provisioning from the canonical checked-in assets.
#
# db/structure.sql carries no grants, ownership, or seed data (pg_dump -x -O), so
# loading it alone yields a database that exists structurally but cannot run under
# f1_runtime and has no proof key. These tasks close that gap from ONE grant
# source (F1::RuntimeGrants) applied after every schema materialization, plus an
# idempotent proof-key seed, plus a verification that connects as f1_web — not the
# owner — so a broken build fails loudly.
namespace :f1 do
  namespace :db do
    desc "Apply runtime (f1_runtime) grants from the single source (F1::RuntimeGrants)"
    task grants: :environment do
      count = F1::RuntimeGrants.apply_all(ActiveRecord::Base.connection)
      puts "[f1:db:grants] applied #{count} guarded grant statements"
    end

    desc "Ensure the proof-key row exists (idempotent). Production supplies the key out of band."
    task ensure_context_key: :environment do
      applied = F1DbProvision.ensure_context_key(ActiveRecord::Base.connection)
      puts "[f1:db:ensure_context_key] #{applied ? 'inserted a random proof key' : 'proof key already present'}"
    end

    desc "Ensure the reserved platform Service Identity rows exist (idempotent)"
    task ensure_service_identities: :environment do
      conn = ActiveRecord::Base.connection
      applied = F1DbProvision.ensure_service_identities(conn)
      F1DbProvision.assert_executor_identity!(conn)
      puts "[f1:db:ensure_service_identities] #{applied} reserved service identity row(s) inserted; executor active"
    end

    desc "Verify the runtime role (f1_web) can actually use the database, with RLS intact"
    task verify_runtime: :environment do
      F1DbProvision.verify_runtime!(ActiveRecord::Base.connection_db_config.configuration_hash)
    end

    desc "Finalize an already-loaded schema: grants + proof key + verify (see bin/f1-provision-db for the full route)"
    task provision: :environment do
      Rake::Task["f1:db:grants"].invoke
      Rake::Task["f1:db:ensure_context_key"].invoke
      Rake::Task["f1:db:ensure_service_identities"].invoke
      Rake::Task["f1:db:verify_runtime"].invoke
    end
  end
end

# Shared provisioning helpers (kept out of app/ autoload; used only by these tasks).
module F1DbProvision
  module_function

  # Insert a random 32-byte proof key iff absent. Never overwrites an existing
  # key. Guarded so it is safe before the table exists.
  def ensure_context_key(connection)
    return false if connection.select_value("SELECT to_regclass('public.f1_context_keys')::text").nil?

    connection.select_value(<<~SQL).to_i.positive?
      WITH ins AS (
        INSERT INTO public.f1_context_keys (key_name, key_bytes)
        SELECT 'context_proof', gen_random_bytes(32)
        WHERE NOT EXISTS (SELECT 1 FROM public.f1_context_keys WHERE key_name = 'context_proof')
        RETURNING 1
      )
      SELECT count(*) FROM ins
    SQL
  end

  # Insert the reserved platform Service Identity rows iff absent, never
  # overwriting an existing row (an operator may have suspended or revoked one,
  # and re-activating it behind their back would defeat the control). Guarded so
  # it is safe before the table exists.
  #
  # This is a provisioning step rather than a migration seed for the same reason
  # the proof key is: db/structure.sql carries no data, and `db:migrate` against
  # an empty database materializes the schema from structure.sql instead of
  # replaying migrations, so a migration-time INSERT never runs on that route.
  def ensure_service_identities(connection)
    return 0 if connection.select_value("SELECT to_regclass('public.service_identities')::text").nil?

    Platform::ServiceIdentity::RESERVED.sum do |id, subject, display_name, key_id, scope|
      connection.select_value(<<~SQL).to_i
        WITH ins AS (
          INSERT INTO public.service_identities
            (id, created_at, updated_at, subject, display_name, status, key_id, permission_scope, activated_at)
          VALUES ('#{id}', now(), now(), '#{subject}', '#{display_name}', 'active', '#{key_id}',
                  '#{scope}'::jsonb, now())
          ON CONFLICT (id) DO NOTHING
          RETURNING 1
        )
        SELECT count(*) FROM ins
      SQL
    end
  end

  # Fail provisioning loudly if the ScheduledAction executor is missing or not
  # active: without it the timer table's foreign key rejects every new action and
  # the claim function refuses every existing one, so the service is inert.
  def assert_executor_identity!(connection)
    return if connection.select_value("SELECT to_regclass('public.service_identities')::text").nil?

    ids = Platform::ServiceIdentity::RESERVED.map { |id, *| "'#{id}'" }.join(",")
    active = connection.select_value(<<~SQL)
      SELECT count(*) FROM public.service_identities WHERE id IN (#{ids}) AND status = 'active'
    SQL
    return if active.to_i == Platform::ServiceIdentity::RESERVED.size

    abort "[f1:db:ensure_service_identities] FAILED: a reserved Service Identity is absent or not active"
  end

  # Connect as the runtime login role and prove the database is usable: metadata
  # readable, a forced-RLS table selectable (returns 0 rows with no context, which
  # also proves RLS is intact), the expected DML granted, and a runtime function
  # executable. Aborts loudly on any failure.
  def verify_runtime!(config)
    require "pg"
    conn = PG.connect(host: config[:host], port: config[:port], dbname: config[:database], user: "f1_web")
    all = checks(conn)
    failures = all.reject { |_label, check| (check.call rescue false) } # rubocop:disable Style/RescueModifier
    conn.close
    if failures.any?
      abort "[f1:db:verify_runtime] FAILED as f1_web: #{failures.map(&:first).join('; ')}"
    end
    puts "[f1:db:verify_runtime] OK as f1_web — #{all.size} checks passed (RLS intact)"
  end

  TRANSPORT_FUNCTIONS = <<~SQL
    SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN (
      'f1_claim_due_scheduled_actions','f1_dispatch_scheduled_action','f1_settle_scheduled_action',
      'f1_release_scheduled_action_claim','f1_release_expired_scheduled_action_leases',
      'f1_cancel_scheduled_action')
  SQL

  # 't' only when EVERY transport function is executable by the role.
  def transport_privilege(conn, role)
    conn.exec_params(<<~SQL, [role]).getvalue(0, 0)
      SELECT coalesce(bool_and(has_function_privilege($1, oid, 'EXECUTE')), false)
      FROM (#{TRANSPORT_FUNCTIONS}) f
    SQL
  end

  # 't' only when NO transport function declares a timestamptz argument.
  def transport_takes_no_time(conn)
    conn.exec(<<~SQL).getvalue(0, 0)
      SELECT coalesce(bool_and(NOT ('timestamptz'::regtype = ANY (p.proargtypes::oid[]))), false)
      FROM pg_proc p WHERE p.oid IN (SELECT oid FROM (#{TRANSPORT_FUNCTIONS}) f)
    SQL
  end

  def checks(conn)
    {
      "schema_migrations readable" => -> { conn.exec("SELECT count(*) FROM schema_migrations").getvalue(0, 0).to_i >= 0 },
      "sessions selectable, 0 rows without context (RLS intact)" => -> { conn.exec("SELECT count(*) FROM sessions").getvalue(0, 0) == "0" },
      "accounts SELECT granted" => -> { conn.exec("SELECT has_table_privilege('f1_web','public.accounts','SELECT')").getvalue(0, 0) == "t" },
      "sessions INSERT granted" => -> { conn.exec("SELECT has_table_privilege('f1_web','public.sessions','INSERT')").getvalue(0, 0) == "t" },
      "idempotency_records INSERT granted" => -> { conn.exec("SELECT has_table_privilege('f1_web','public.idempotency_records','INSERT')").getvalue(0, 0) == "t" },
      "f1_current_context_org executable" => -> { conn.exec("SELECT has_function_privilege('f1_web','public.f1_current_context_org()','EXECUTE')").getvalue(0, 0) == "t" },
      "f1_context_proof NOT executable by runtime" => -> { conn.exec("SELECT has_function_privilege('f1_web','public.f1_context_proof(text,text)','EXECUTE')").getvalue(0, 0) == "f" },
      # The service execution path: the timer table is readable but never
      # directly mutable by the runtime; every transition goes through the
      # restricted claim function.
      "scheduled_actions selectable, 0 rows without context (RLS intact)" => -> { conn.exec("SELECT count(*) FROM scheduled_actions").getvalue(0, 0) == "0" },
      "scheduled_actions INSERT granted" => -> { conn.exec("SELECT has_table_privilege('f1_web','public.scheduled_actions','INSERT')").getvalue(0, 0) == "t" },
      "scheduled_actions UPDATE NOT granted" => -> { conn.exec("SELECT has_table_privilege('f1_web','public.scheduled_actions','UPDATE')").getvalue(0, 0) == "f" },
      # The ScheduledAction transport is platform-control authority
      # (POSTGRESQL_SCHEMA.md :166, :175): the request-serving role must not be
      # able to claim, dispatch, settle, release, sweep or cancel scheduled work,
      # and no transport function may accept a caller-supplied instant.
      "ScheduledAction transport NOT executable by f1_web" => -> { transport_privilege(conn, "f1_web") == "f" },
      "ScheduledAction transport NOT executable by PUBLIC" => -> { transport_privilege(conn, "public") == "f" },
      "ScheduledAction transport executable by f1_platform_worker" => -> { transport_privilege(conn, "f1_platform_worker") == "t" },
      "no ScheduledAction transport function accepts a caller-supplied time" => -> { transport_takes_no_time(conn) == "t" },
      # Global service identities are platform control (POSTGRESQL_SCHEMA.md
      # :166): the runtime holds no grant on the register at all.
      "service_identities NOT readable by the runtime" => -> { conn.exec("SELECT has_table_privilege('f1_web','public.service_identities','SELECT')").getvalue(0, 0) == "f" }
    }
  end
end

# One grant source, applied after every schema materialization so the migrate
# path and the structure-load path converge on the same runtime-usable state.
["db:schema:load", "db:test:prepare", "db:migrate"].each do |task_name|
  next unless Rake::Task.task_defined?(task_name)

  Rake::Task[task_name].enhance do
    conn = ActiveRecord::Base.connection
    F1::RuntimeGrants.apply_all(conn)
    F1DbProvision.ensure_context_key(conn)
    F1DbProvision.ensure_service_identities(conn)
  end
end
