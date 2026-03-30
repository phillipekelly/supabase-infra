# Be aware this is an old approach that was replaced by running a k8 job to bootstrap the aws managed db, this document serves only as a reference as to what the Supabase application expects to be provisioned on an empty postgres setup!


# Aurora PostgreSQL Bootstrap Reference

This document describes the database initialization that Terraform performs automatically via the `cyrilgdn/postgresql` provider during `terraform apply`.

> **Note:** This is a reference document only. You do not need to run these scripts manually. The Terraform RDS module handles all of this automatically. These scripts are provided for transparency and for manual recovery scenarios.

---

## What Gets Created

When `terraform apply` runs the RDS module, it bootstraps the Aurora PostgreSQL cluster with everything Supabase needs:

- **10 PostgreSQL roles** with correct permissions and login settings
- **8 schemas** with correct ownership
- **4 extensions** (`pgcrypto`, `uuid-ossp`, `pg_stat_statements`, `pgjwt`)
- **Role memberships and grants** as required by Supabase internals

---

## Manual Bootstrap (Recovery Only)

If you need to re-run the bootstrap manually (e.g. after a database restore), follow these steps.

### Prerequisites

```bash
# Install psql client
sudo apt-get install postgresql-client-15

# Ensure you have network access to Aurora
# Aurora is in private subnets — run from within VPC or via bastion/VPN
```

### Step 1 — Create the `_supabase` database

```sql
psql -h <aurora-endpoint> -U <master-user> -d postgres \
  -c "CREATE DATABASE _supabase;"
```

### Step 2 — Run against the `postgres` database

```sql
-- =============================================
-- Connect to: postgres database
-- User: RDS master user
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
    -- NOTE: Aurora does not support true SUPERUSER
    -- rds_superuser is the closest equivalent
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
CREATE EXTENSION IF NOT EXISTS pgcrypto       WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"    WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgjwt          WITH SCHEMA extensions;

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
ALTER SCHEMA auth      OWNER TO supabase_auth_admin;
ALTER SCHEMA storage   OWNER TO supabase_storage_admin;
ALTER SCHEMA realtime  OWNER TO supabase_admin;
ALTER SCHEMA _realtime OWNER TO supabase_admin;

-- GRANTS
GRANT USAGE ON SCHEMA public     TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
GRANT ALL   ON SCHEMA auth       TO supabase_auth_admin;
GRANT ALL   ON SCHEMA storage    TO supabase_storage_admin;
GRANT ALL   ON SCHEMA realtime   TO supabase_admin;
GRANT ALL   ON SCHEMA _realtime  TO supabase_admin;

-- SEARCH PATH
ALTER ROLE supabase_admin SET search_path TO _realtime, public;
```

### Step 3 — Run against the `_supabase` database

```sql
-- =============================================
-- Connect to: _supabase database
-- User: RDS master user
-- =============================================

CREATE SCHEMA IF NOT EXISTS _analytics;
GRANT ALL ON SCHEMA _analytics TO supabase_admin;
```

### Run via psql

```bash
# Step 1 — postgres database init
psql \
  -h <aurora-endpoint> \
  -U <master-user> \
  -d postgres \
  -f aws-db-init-postgres.sql

# Step 2 — _supabase database init
psql \
  -h <aurora-endpoint> \
  -U <master-user> \
  -d _supabase \
  -f aws-db-init-supabase.sql
```

---

## Why Aurora Requires This Bootstrap

Standard Supabase uses a custom Docker image (`supabase/postgres:15.8.1.085`) that pre-configures all roles and schemas at container startup. Aurora PostgreSQL is a managed service — you bring your own PostgreSQL instance and must initialize it yourself.

The key difference from standard PostgreSQL is that **Aurora does not support `SUPERUSER`**. The `supabase_admin` role is granted `rds_superuser` instead, which provides equivalent privileges within the Aurora permission model.

---

## Related Terraform Code

The Terraform implementation of this bootstrap lives in:

```
terraform/modules/rds/main.tf
```

Specifically the `postgresql_role`, `postgresql_database`, `postgresql_schema`, and `postgresql_grant` resources at the bottom of that file.
