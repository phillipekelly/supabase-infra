# ==============================================================================
# Supabase Module
# Deploys Supabase stack via Helm, configures ESO for secrets,
# applies network policies, and configures ingress
# ==============================================================================

# ------------------------------------------------------------------------------
# Kubernetes Namespace
# ------------------------------------------------------------------------------
resource "kubernetes_namespace" "supabase" {
  metadata {
    name = var.namespace

    labels = {
      name        = var.namespace
      managed-by  = "terraform"
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
# ESO SecretStore — AWS Secrets Manager backend
# Replaces the local Fake provider used in development
# ------------------------------------------------------------------------------
resource "kubectl_manifest" "secret_store" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: SecretStore
    metadata:
      name: ${var.secret_store_name}
      namespace: ${var.namespace}
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
# Identical structure to local development, only backend differs
# ------------------------------------------------------------------------------
resource "kubectl_manifest" "external_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: supabase-external-secret
      namespace: ${var.namespace}
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: ${var.secret_store_name}
        kind: SecretStore
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
# Supabase Helm Release
# Uses wrapper chart that includes HPAs and ingress
# All secrets referenced from ESO-created Kubernetes Secret
# ------------------------------------------------------------------------------
resource "helm_release" "supabase" {
  name      = local.release_name
  chart     = local.chart_path
  namespace = var.namespace

  # Wait for ESO to sync secrets before deploying
  depends_on = [
    kubectl_manifest.external_secret,
    helm_release.external_secrets
  ]

  wait    = true
  timeout = 600

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
