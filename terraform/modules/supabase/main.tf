# ==============================================================================
# Supabase Module
# Deploys Supabase stack via Helm, configures ESO for secrets,
# applies network policies, and configures ingress
# Bootstrap is handled by a Kubernetes Job running inside the cluster
# so Aurora can stay fully private (no public endpoint needed)
# ==============================================================================

# ------------------------------------------------------------------------------
# Kubernetes Namespace
# ------------------------------------------------------------------------------
resource "kubernetes_namespace" "supabase" {
  metadata {
    name = var.namespace

    labels = {
      name       = var.namespace
      managed-by = "terraform"
    }
  }
}

# ------------------------------------------------------------------------------
# Install External Secrets Operator
# Must be installed before SecretStore and ExternalSecret resources
# ------------------------------------------------------------------------------
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.10.0"
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  # Annotate ESO service account with IRSA role
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.eso_role_arn
  }

  wait    = true
  timeout = 300
}

# ------------------------------------------------------------------------------
# ESO ClusterSecretStore — AWS Secrets Manager backend
# Using ClusterSecretStore (not SecretStore) so it can reference the
# external-secrets service account across namespaces
# ------------------------------------------------------------------------------
resource "kubectl_manifest" "secret_store" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: ${var.secret_store_name}
    spec:
      provider:
        aws:
          service: SecretsManager
          region: ${var.aws_region}
          auth:
            jwt:
              serviceAccountRef:
                name: external-secrets
                namespace: external-secrets
  YAML

  depends_on = [
    kubernetes_namespace.supabase,
    helm_release.external_secrets
  ]
}

# ------------------------------------------------------------------------------
# ESO ExternalSecret — syncs secrets from Secrets Manager into K8s Secret
# ------------------------------------------------------------------------------
resource "kubectl_manifest" "external_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: supabase-external-secret
      namespace: ${var.namespace}
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: ${var.secret_store_name}
        kind: ClusterSecretStore
      target:
        name: ${local.k8s_secret_name}
        creationPolicy: Owner
      data:
        - secretKey: db-username
          remoteRef:
            key: ${var.secret_names.db}
            property: username
        - secretKey: db-password
          remoteRef:
            key: ${var.secret_names.db}
            property: password
        - secretKey: db-database
          remoteRef:
            key: ${var.secret_names.db}
            property: database
        - secretKey: jwt-anonKey
          remoteRef:
            key: ${var.secret_names.jwt}
            property: anonKey
        - secretKey: jwt-serviceKey
          remoteRef:
            key: ${var.secret_names.jwt}
            property: serviceKey
        - secretKey: jwt-secret
          remoteRef:
            key: ${var.secret_names.jwt}
            property: secret
        - secretKey: dashboard-username
          remoteRef:
            key: ${var.secret_names.dashboard}
            property: username
        - secretKey: dashboard-password
          remoteRef:
            key: ${var.secret_names.dashboard}
            property: password
        - secretKey: openAiApiKey
          remoteRef:
            key: ${var.secret_names.dashboard}
            property: openAiApiKey
        - secretKey: analytics-publicAccessToken
          remoteRef:
            key: ${var.secret_names.analytics}
            property: publicAccessToken
        - secretKey: analytics-privateAccessToken
          remoteRef:
            key: ${var.secret_names.analytics}
            property: privateAccessToken
        - secretKey: realtime-secretKeyBase
          remoteRef:
            key: ${var.secret_names.realtime}
            property: secretKeyBase
        - secretKey: meta-cryptoKey
          remoteRef:
            key: ${var.secret_names.meta}
            property: cryptoKey
  YAML

  depends_on = [
    kubectl_manifest.secret_store
  ]
}

# ------------------------------------------------------------------------------
# Aurora Bootstrap Job
#
# Runs inside the cluster so it can reach Aurora on the private network.
# This is why publicly_accessible = false works — no external access needed.
#
# Design decisions:
#   - Uses the official postgres:15-alpine image (matches Aurora PG15)
#   - All SQL is idempotent (IF NOT EXISTS / $BLOCK$ dollar-quoting)
#     so it is safe to re-run on every apply without side effects
#   - Reads DB credentials from the ESO-synced Kubernetes Secret
#     so no secrets are hardcoded in the manifest
#   - restartPolicy: OnFailure — retries if Aurora isn't ready yet
#   - backoffLimit: 5 — gives Aurora enough time to finish initialising
#   - The Supabase Helm release depends_on this Job completing successfully
#     so pods never start before the DB is ready
#   - $BLOCK$ used instead of $$ for dollar-quoting to avoid shell
#     heredoc interpretation stripping the dollar signs
#   - pgjwt omitted — not available on Aurora (third-party extension,
#     not on AWS's approved extension list)
#   - Role passwords set to 'placeholder' inside heredoc SQL then updated
#     via separate psql calls — env vars cannot be referenced inside
#     a heredoc SQL block
# ------------------------------------------------------------------------------
resource "kubectl_manifest" "aurora_bootstrap" {
  yaml_body = <<-YAML
    apiVersion: batch/v1
    kind: Job
    metadata:
      name: aurora-bootstrap
      namespace: ${var.namespace}
      labels:
        app: aurora-bootstrap
        managed-by: terraform
      annotations:
        bootstrap-version: "1"
    spec:
      backoffLimit: 5
      ttlSecondsAfterFinished: 600
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: bootstrap
              image: postgres:15-alpine
              command: ["/bin/sh", "-c"]
              args:
                - |
                  set -e
                  echo "Waiting for Aurora to be ready..."
                  until pg_isready -h $DB_HOST -p 5432 -U $DB_USER; do
                    echo "Aurora not ready, retrying in 5s..."
                    sleep 5
                  done
                  echo "Aurora is ready. Running bootstrap SQL..."

                  PGPASSWORD=$DB_PASSWORD psql \
                    "sslmode=require host=$DB_HOST port=5432 user=$DB_USER dbname=postgres" <<'SQL'

                  -- Extensions schema
                  CREATE SCHEMA IF NOT EXISTS extensions;

                  -- Extensions (pgjwt omitted - not available on Aurora)
                  CREATE EXTENSION IF NOT EXISTS pgcrypto           WITH SCHEMA extensions;
                  CREATE EXTENSION IF NOT EXISTS "uuid-ossp"        WITH SCHEMA extensions;
                  CREATE EXTENSION IF NOT EXISTS pg_stat_statements  WITH SCHEMA extensions;

                  -- Roles (idempotent via named dollar-quoting $BLOCK$)
                  DO $BLOCK$ BEGIN
                    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
                      CREATE ROLE anon NOLOGIN NOINHERIT;
                    END IF;
                  END $BLOCK$;

                  DO $BLOCK$ BEGIN
                    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
                      CREATE ROLE authenticated NOLOGIN NOINHERIT;
                    END IF;
                  END $BLOCK$;

                  DO $BLOCK$ BEGIN
                    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
                      CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
                    END IF;
                  END $BLOCK$;

                  DO $BLOCK$ BEGIN
                    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
                      CREATE ROLE authenticator LOGIN NOINHERIT;
                    END IF;
                  END $BLOCK$;

                  DO $BLOCK$ BEGIN
                    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dashboard_user') THEN
                      CREATE ROLE dashboard_user NOLOGIN CREATEROLE CREATEDB;
                    END IF;
                  END $BLOCK$;

                  DO $BLOCK$ BEGIN
                    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pgbouncer') THEN
                      CREATE ROLE pgbouncer LOGIN PASSWORD 'placeholder';
                    END IF;
                  END $BLOCK$;

                  DO $BLOCK$ BEGIN
                    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
                      CREATE ROLE supabase_auth_admin LOGIN NOINHERIT CREATEROLE PASSWORD 'placeholder';
                    END IF;
                  END $BLOCK$;

                  DO $BLOCK$ BEGIN
                    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
                      CREATE ROLE supabase_storage_admin LOGIN NOINHERIT CREATEROLE PASSWORD 'placeholder';
                    END IF;
                  END $BLOCK$;

                  DO $BLOCK$ BEGIN
                    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_read_only_user') THEN
                      CREATE ROLE supabase_read_only_user LOGIN BYPASSRLS PASSWORD 'placeholder';
                    END IF;
                  END $BLOCK$;
                  
                  DO $BLOCK$ BEGIN
                    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'postgres') THEN
                      CREATE ROLE postgres LOGIN PASSWORD 'placeholder';
                    END IF;
                  END $BLOCK$;

                  GRANT ${var.db_master_username} TO postgres;

                  -- Role memberships
                  GRANT anon          TO authenticator;
                  GRANT authenticated TO authenticator;
                  GRANT service_role  TO authenticator;
                  GRANT authenticator TO supabase_storage_admin;

                  -- Schemas
                  GRANT supabase_auth_admin    TO ${var.db_master_username};
                  GRANT supabase_storage_admin TO ${var.db_master_username};
                  CREATE SCHEMA IF NOT EXISTS auth;
                  CREATE SCHEMA IF NOT EXISTS storage;
                  ALTER SCHEMA auth    OWNER TO supabase_auth_admin;
                  ALTER SCHEMA storage OWNER TO supabase_storage_admin;
                  ALTER ROLE supabase_auth_admin    SET search_path TO auth, extensions, public;
                  ALTER ROLE supabase_storage_admin SET search_path TO storage, extensions, public;
                  ALTER ROLE authenticator          SET search_path TO public, extensions;                  
                  CREATE SCHEMA IF NOT EXISTS realtime;
                  CREATE SCHEMA IF NOT EXISTS _realtime;
                  CREATE SCHEMA IF NOT EXISTS graphql_public;
                  CREATE SCHEMA IF NOT EXISTS vault;

                  -- Schema grants
                  GRANT USAGE ON SCHEMA public     TO anon, authenticated, service_role;
                  GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
                  
                  -- Database connection and schema grants
                  GRANT CONNECT ON DATABASE postgres TO supabase_storage_admin;
                  GRANT CONNECT ON DATABASE postgres TO supabase_auth_admin;
                  GRANT CONNECT ON DATABASE postgres TO authenticator;
                  GRANT CONNECT ON DATABASE postgres TO postgres;
                  GRANT ALL ON DATABASE postgres TO supabase_storage_admin;
                  GRANT ALL ON SCHEMA storage TO supabase_storage_admin;
                  GRANT ALL ON SCHEMA public TO supabase_storage_admin;

                  -- Search path
                  ALTER ROLE ${var.db_master_username} SET search_path TO _realtime, public;

                  SQL

                  echo "Bootstrap SQL completed successfully."

                  # Update role passwords from environment variable
                  # (env vars cannot be used inside a heredoc SQL block)
                  for role in pgbouncer supabase_auth_admin supabase_storage_admin supabase_read_only_user authenticator postgres; do
                    PGPASSWORD=$DB_PASSWORD psql \
                      "sslmode=require host=$DB_HOST port=5432 user=$DB_USER dbname=postgres" \
                      -c "ALTER ROLE $role PASSWORD '$DB_PASSWORD';"
                  done

                  # Create _supabase database if not exists
                  DB_EXISTS=$(PGPASSWORD=$DB_PASSWORD psql \
                    "sslmode=require host=$DB_HOST port=5432 user=$DB_USER dbname=postgres" \
                    -tAc "SELECT 1 FROM pg_database WHERE datname = '_supabase'")

                  if [ "$DB_EXISTS" != "1" ]; then
                    PGPASSWORD=$DB_PASSWORD psql \
                      "sslmode=require host=$DB_HOST port=5432 user=$DB_USER dbname=postgres" \
                      -c "CREATE DATABASE \"_supabase\" OWNER $DB_USER;"
                    echo "_supabase database created."
                  else
                    echo "_supabase database already exists, skipping."
                  fi

                  # _analytics schema inside _supabase database
                  PGPASSWORD=$DB_PASSWORD psql \
                    "sslmode=require host=$DB_HOST port=5432 user=$DB_USER dbname=_supabase" \
                    -c "CREATE SCHEMA IF NOT EXISTS _analytics;"

                  echo "All bootstrap steps completed."
              env:
                - name: DB_HOST
                  value: "${var.db_host}"
                - name: DB_USER
                  valueFrom:
                    secretKeyRef:
                      name: ${local.k8s_secret_name}
                      key: db-username
                - name: DB_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: ${local.k8s_secret_name}
                      key: db-password
  YAML

  depends_on = [
    kubernetes_namespace.supabase,
    kubectl_manifest.external_secret
  ]
}

# ------------------------------------------------------------------------------
# Supabase Helm Release
# Uses wrapper chart that includes HPAs and ingress
# All secrets referenced from ESO-created Kubernetes Secret
# depends_on aurora_bootstrap ensures DB is ready before pods start
# cleanup_on_fail = false prevents Terraform from hanging on failed uninstall
# ------------------------------------------------------------------------------
resource "helm_release" "supabase" {
  name            = local.release_name
  chart           = local.chart_path
  namespace       = var.namespace
  cleanup_on_fail = false
  force_update    = true
  wait            = true
  timeout         = 600

  depends_on = [
    kubectl_manifest.external_secret,
    helm_release.external_secrets,
    kubectl_manifest.aurora_bootstrap
  ]

  values = [
    templatefile("${path.module}/values-aws.yaml.tpl", {
      db_host             = var.db_host
      db_port             = var.db_port
      db_name             = var.db_name
      aws_region          = var.aws_region
      storage_bucket_name = var.storage_bucket_name
      storage_role_arn    = var.storage_role_arn
      k8s_secret_name     = local.k8s_secret_name
      supabase_domain     = var.supabase_domain
      studio_domain       = var.studio_domain
      release_name        = local.release_name
    })
  ]
}

# ------------------------------------------------------------------------------
# Network Policies
# Applied after Supabase is deployed
# Requires VPC CNI with network policy support enabled
# ------------------------------------------------------------------------------
resource "kubectl_manifest" "network_policies" {
  for_each = fileset("${path.root}/../../k8s/network-policies", "*.yaml")

  yaml_body = file("${path.root}/../../k8s/network-policies/${each.value}")

  depends_on = [
    helm_release.supabase
  ]
}
