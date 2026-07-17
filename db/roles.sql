-- F1 database role hierarchy (schemas/POSTGRESQL_SCHEMA.md § Tenant Isolation
-- And Database Roles). Idempotent; run once per cluster as a superuser:
--
--   psql -p 5433 -d postgres -f db/roles.sql
--
-- Locally the roles use trust auth (Homebrew pg_hba default for localhost); no
-- passwords are set here. In a managed environment each login role receives a
-- password out of band. No login role owns a table or holds BYPASSRLS; only
-- f1_schema_owner owns schema objects, and it is used solely by DDL.

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'f1_schema_owner') THEN
    CREATE ROLE f1_schema_owner LOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'f1_runtime') THEN
    CREATE ROLE f1_runtime NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'f1_web') THEN
    CREATE ROLE f1_web LOGIN IN ROLE f1_runtime;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'f1_worker') THEN
    CREATE ROLE f1_worker LOGIN IN ROLE f1_runtime;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'f1_platform_worker') THEN
    CREATE ROLE f1_platform_worker LOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'f1_lifecycle') THEN
    CREATE ROLE f1_lifecycle LOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'f1_readonly_ops') THEN
    CREATE ROLE f1_readonly_ops LOGIN;
  END IF;
END
$$;

-- None of these roles may bypass row-level security. f1_schema_owner owns tables
-- but FORCE ROW LEVEL SECURITY (set per tenant table) applies to it too.
ALTER ROLE f1_schema_owner    NOBYPASSRLS;
ALTER ROLE f1_runtime         NOBYPASSRLS;
ALTER ROLE f1_web             NOBYPASSRLS;
ALTER ROLE f1_worker          NOBYPASSRLS;
ALTER ROLE f1_platform_worker NOBYPASSRLS;
ALTER ROLE f1_lifecycle       NOBYPASSRLS;
ALTER ROLE f1_readonly_ops    NOBYPASSRLS;
