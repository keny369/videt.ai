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

    desc "Verify the runtime role (f1_web) can actually use the database, with RLS intact"
    task verify_runtime: :environment do
      F1DbProvision.verify_runtime!(ActiveRecord::Base.connection_db_config.configuration_hash)
    end

    desc "Finalize an already-loaded schema: grants + proof key + verify (see bin/f1-provision-db for the full route)"
    task provision: :environment do
      Rake::Task["f1:db:grants"].invoke
      Rake::Task["f1:db:ensure_context_key"].invoke
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

  def checks(conn)
    {
      "schema_migrations readable" => -> { conn.exec("SELECT count(*) FROM schema_migrations").getvalue(0, 0).to_i >= 0 },
      "sessions selectable, 0 rows without context (RLS intact)" => -> { conn.exec("SELECT count(*) FROM sessions").getvalue(0, 0) == "0" },
      "accounts SELECT granted" => -> { conn.exec("SELECT has_table_privilege('f1_web','public.accounts','SELECT')").getvalue(0, 0) == "t" },
      "sessions INSERT granted" => -> { conn.exec("SELECT has_table_privilege('f1_web','public.sessions','INSERT')").getvalue(0, 0) == "t" },
      "idempotency_records INSERT granted" => -> { conn.exec("SELECT has_table_privilege('f1_web','public.idempotency_records','INSERT')").getvalue(0, 0) == "t" },
      "f1_current_context_org executable" => -> { conn.exec("SELECT has_function_privilege('f1_web','public.f1_current_context_org()','EXECUTE')").getvalue(0, 0) == "t" },
      "f1_context_proof NOT executable by runtime" => -> { conn.exec("SELECT has_function_privilege('f1_web','public.f1_context_proof(text,text)','EXECUTE')").getvalue(0, 0) == "f" }
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
  end
end
