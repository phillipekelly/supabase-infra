# ==============================================================================
# Supabase Module Locals
# ==============================================================================

locals {
  # Helm release name
  release_name = "supabase"

  # Chart path relative to terraform root
  chart_path = "${path.root}/../../../helm/supabase-stack"

  # ESO synced secret name - must match external-secret.yaml target name
  k8s_secret_name = "supabase-esm-secrets"
}
