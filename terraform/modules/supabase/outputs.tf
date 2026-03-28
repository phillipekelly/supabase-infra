# ==============================================================================
# Supabase Module Outputs
# ==============================================================================

output "namespace" {
  description = "Kubernetes namespace where Supabase is deployed"
  value       = kubernetes_namespace.supabase.metadata[0].name
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.supabase.name
}

output "supabase_status" {
  description = "Status of the Supabase Helm release"
  value       = helm_release.supabase.status
}
