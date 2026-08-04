# frozen_string_literal: true

# A SCHEMA FINGERPRINT DEEP ENOUGH TO BE WORTH COMPARING (ADR-129).
#
# The gate this feeds must catch "comparing only table names while missing constraints or policies",
# which is exactly how `migration_safety_no_drift` could not fail: it diffed a dump of a database
# against the file that built it. This covers columns and their types and nullability and defaults,
# every constraint including CHECK expressions, indexes, triggers, ROW LEVEL SECURITY state and every
# policy, functions and their bodies, extensions, and object ownership.
namespace :f1 do
  namespace :db do
    FINGERPRINT_SQL = <<~SQL
      WITH cols AS (
        SELECT string_agg(format('%s.%s:%s:%s:%s', c.table_name, c.column_name, c.data_type,
                                 c.is_nullable, coalesce(c.column_default, '-')), E'\\n' ORDER BY c.table_name, c.column_name) AS t
        FROM information_schema.columns c WHERE c.table_schema = 'public'
      ), cons AS (
        SELECT string_agg(format('%s:%s:%s:%s', rel.relname, con.conname, con.contype,
                                 pg_get_constraintdef(con.oid)), E'\\n' ORDER BY rel.relname, con.conname) AS t
        FROM pg_constraint con JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace n ON n.oid = rel.relnamespace WHERE n.nspname = 'public'
      ), idx AS (
        SELECT string_agg(format('%s:%s', indexname, indexdef), E'\\n' ORDER BY indexname) AS t
        FROM pg_indexes WHERE schemaname = 'public'
      ), trg AS (
        SELECT string_agg(format('%s:%s:%s', c.relname, t.tgname, pg_get_triggerdef(t.oid)), E'\\n'
                          ORDER BY c.relname, t.tgname) AS t
        FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND NOT t.tgisinternal
      ), rls AS (
        SELECT string_agg(format('%s:rls=%s:force=%s', c.relname, c.relrowsecurity, c.relforcerowsecurity), E'\\n'
                          ORDER BY c.relname) AS t
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r'
      ), pol AS (
        SELECT string_agg(format('%s:%s:%s:%s:%s:%s', tablename, policyname, permissive, cmd,
                                 coalesce(qual, '-'), coalesce(with_check, '-')), E'\\n'
                          ORDER BY tablename, policyname) AS t
        FROM pg_policies WHERE schemaname = 'public'
      ), fns AS (
        SELECT string_agg(format('%s:%s:%s', p.proname, pg_get_function_identity_arguments(p.oid),
                                 md5(p.prosrc)), E'\\n' ORDER BY p.proname, p.oid) AS t
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
      ), ext AS (
        SELECT string_agg(extname, E'\\n' ORDER BY extname) AS t FROM pg_extension
      ), own AS (
        SELECT string_agg(format('%s:%s', c.relname, pg_get_userbyid(c.relowner)), E'\\n' ORDER BY c.relname) AS t
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v', 'S')
      )
      SELECT json_build_object(
        'columns', md5(coalesce((SELECT t FROM cols), '')), 'constraints', md5(coalesce((SELECT t FROM cons), '')),
        'indexes', md5(coalesce((SELECT t FROM idx), '')),  'triggers', md5(coalesce((SELECT t FROM trg), '')),
        'rls', md5(coalesce((SELECT t FROM rls), '')),      'policies', md5(coalesce((SELECT t FROM pol), '')),
        'functions', md5(coalesce((SELECT t FROM fns), '')),'extensions', md5(coalesce((SELECT t FROM ext), '')),
        'ownership', md5(coalesce((SELECT t FROM own), '')),
        'counts', json_build_object(
          'tables', (SELECT count(*) FROM pg_tables WHERE schemaname='public'),
          'constraints', (SELECT count(*) FROM pg_constraint con JOIN pg_class r ON r.oid=con.conrelid
                          JOIN pg_namespace n ON n.oid=r.relnamespace WHERE n.nspname='public'),
          'policies', (SELECT count(*) FROM pg_policies WHERE schemaname='public'),
          'triggers', (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                       JOIN pg_namespace n ON n.oid=c.relnamespace
                       WHERE n.nspname='public' AND NOT t.tgisinternal),
          'functions', (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                        WHERE n.nspname='public'))
      )::text
    SQL

    desc "Print a deep schema fingerprint (columns, constraints, indexes, triggers, RLS, policies, functions, extensions, ownership)"
    task fingerprint: :environment do
      puts ActiveRecord::Base.connection.select_value(FINGERPRINT_SQL)
    end
  end
end
