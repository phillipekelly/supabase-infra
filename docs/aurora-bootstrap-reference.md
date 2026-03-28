File 1: aws-db-init-postgres.sql (run against the postgres database)
sql-- =============================================
-- AWS RDS/Aurora PostgreSQL Setup
-- Run this connected to the "postgres" database
-- as your RDS master user
-- =============================================

-- ROLES
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'your-password';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dashboard_user') THEN
    CREATE ROLE dashboard_user CREATEROLE CREATEDB NOLOGIN;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pgbouncer') THEN
    CREATE ROLE pgbouncer LOGIN PASSWORD 'your-password';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_admin') THEN
    -- NOTE: On RDS you cannot create a true SUPERUSER
    -- Use your RDS master user instead, or grant rds_superuser
    CREATE ROLE supabase_admin LOGIN REPLICATION BYPASSRLS PASSWORD 'your-password';
    GRANT rds_superuser TO supabase_admin;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    CREATE ROLE supabase_auth_admin NOINHERIT LOGIN CREATEROLE PASSWORD 'your-password';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
    CREATE ROLE supabase_storage_admin NOINHERIT LOGIN CREATEROLE PASSWORD 'your-password';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_read_only_user') THEN
    CREATE ROLE supabase_read_only_user BYPASSRLS LOGIN PASSWORD 'your-password';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_replication_admin') THEN
    CREATE ROLE supabase_replication_admin REPLICATION LOGIN PASSWORD 'your-password';
  END IF;
END $$;

-- ROLE MEMBERSHIPS
GRANT authenticated, anon, service_role TO authenticator;
GRANT pg_read_all_data, pg_monitor, pg_signal_backend, authenticated, anon, service_role TO postgres;
GRANT pg_read_all_data TO supabase_read_only_user;
GRANT authenticator TO supabase_storage_admin;

-- EXTENSIONS
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgjwt WITH SCHEMA extensions;

-- SCHEMAS
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS realtime;
CREATE SCHEMA IF NOT EXISTS _realtime;
CREATE SCHEMA IF NOT EXISTS _analytics;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS graphql_public;
CREATE SCHEMA IF NOT EXISTS vault;

-- SCHEMA OWNERSHIP
ALTER SCHEMA auth OWNER TO supabase_auth_admin;
ALTER SCHEMA storage OWNER TO supabase_storage_admin;
ALTER SCHEMA realtime OWNER TO supabase_admin;
ALTER SCHEMA _realtime OWNER TO supabase_admin;

-- GRANTS
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
GRANT ALL ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON SCHEMA storage TO supabase_storage_admin;
GRANT ALL ON SCHEMA realtime TO supabase_admin;
GRANT ALL ON SCHEMA _realtime TO supabase_admin;

-- SEARCH PATH
ALTER ROLE supabase_admin SET search_path TO _realtime, public;
File 2: aws-db-init-supabase.sql (run against the _supabase database)
sql-- =============================================
-- AWS RDS/Aurora PostgreSQL Setup
-- Run this connected to the "_supabase" database
-- as your RDS master user
-- =============================================

-- SCHEMAS
CREATE SCHEMA IF NOT EXISTS _analytics;

-- GRANTS
GRANT ALL ON SCHEMA _analytics TO supabase_admin;

How to run on AWS:
bash# Step 1 — create the _supabase database first
psql -h <rds-endpoint> -U <master-user> -d postgres -c "CREATE DATABASE _supabase;"

# Step 2 — run the postgres init script
psql -h <rds-endpoint> -U <master-user> -d postgres -f aws-db-init-postgres.sql

# Step 3 — run the _supabase init script
psql -h <rds-endpoint> -U <master-user> -d _supabase -f aws-db-init-supabase.sql
