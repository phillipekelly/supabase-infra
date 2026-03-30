# ==============================================================================
# Supabase AWS Values Template
# Variables injected by Terraform templatefile()
# Secrets referenced from ESO-created Kubernetes Secret
# ==============================================================================

# ------------------------------------------------------------------------------
# HPA Configuration
# ------------------------------------------------------------------------------
hpa:
  rest:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80
  auth:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80
  storage:
    enabled: true
    minReplicas: 1
    maxReplicas: 6
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80
  functions:
    enabled: true
    minReplicas: 1
    maxReplicas: 6
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80
  imgproxy:
    enabled: true
    minReplicas: 1
    maxReplicas: 6
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80

# ------------------------------------------------------------------------------
# Ingress — AWS ALB
# ------------------------------------------------------------------------------
ingress:
  enabled: true
  className: alb
  host: ${studio_domain}
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'

# ------------------------------------------------------------------------------
# Supabase Chart Values
# All secrets from ESO-synced Kubernetes Secret
# ------------------------------------------------------------------------------
supabase:
  ingress:
    enabled: false
  secret:
    dashboard:
      secretRef: ${k8s_secret_name}
      secretRefKey:
        username: dashboard-username
        password: dashboard-password
        openAiApiKey: openAiApiKey
    db:
      secretRef: ${k8s_secret_name}
      secretRefKey:
        password: db-password
        database: db-database
    jwt:
      secretRef: ${k8s_secret_name}
      secretRefKey:
        anonKey: jwt-anonKey
        serviceKey: jwt-serviceKey
        secret: jwt-secret
    analytics:
      secretRef: ${k8s_secret_name}
      secretRefKey:
        publicAccessToken: analytics-publicAccessToken
        privateAccessToken: analytics-privateAccessToken
    realtime:
      secretRef: ${k8s_secret_name}
      secretRefKey:
        secretKeyBase: realtime-secretKeyBase
    meta:
      secretRef: ${k8s_secret_name}
      secretRefKey:
        cryptoKey: meta-cryptoKey

  deployment:
    db:
      enabled: false
    rest:
      resources:
        requests:
          cpu: 200m
          memory: 256Mi
        limits:
          cpu: 1000m
          memory: 1Gi
    auth:
      resources:
        requests:
          cpu: 200m
          memory: 256Mi
        limits:
          cpu: 1000m
          memory: 1Gi
    realtime:
      resources:
        requests:
          cpu: 200m
          memory: 256Mi
        limits:
          cpu: 1000m
          memory: 1Gi
    storage:
      resources:
        requests:
          cpu: 200m
          memory: 256Mi
        limits:
          cpu: 1000m
          memory: 1Gi
    kong:
      resources:
        requests:
          cpu: 200m
          memory: 256Mi
        limits:
          cpu: 1000m
          memory: 1Gi
    meta:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
    analytics:
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
        limits:
          cpu: 1000m
          memory: 2Gi
    studio:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
    functions:
      resources:
        requests:
          cpu: 200m
          memory: 256Mi
        limits:
          cpu: 1000m
          memory: 1Gi
    imgproxy:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
    vector:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi

  environment:
    auth:
      DB_HOST: "${db_host}"
      DB_PORT: "${db_port}"
      DB_DRIVER: postgres
      DB_SSL: require
      API_EXTERNAL_URL: https://${supabase_domain}
      GOTRUE_API_HOST: "0.0.0.0"
      GOTRUE_API_PORT: "9999"
      GOTRUE_SITE_URL: https://${supabase_domain}
      GOTRUE_URI_ALLOW_LIST: "https://${supabase_domain}"
      GOTRUE_DISABLE_SIGNUP: "false"
      GOTRUE_JWT_DEFAULT_GROUP_NAME: authenticated
      GOTRUE_JWT_ADMIN_ROLES: service_role
      GOTRUE_JWT_AUD: authenticated
      GOTRUE_JWT_EXP: "3600"
      GOTRUE_EXTERNAL_EMAIL_ENABLED: "true"
      GOTRUE_MAILER_AUTOCONFIRM: "true"
    rest:
      DB_HOST: "${db_host}"
      DB_PORT: "${db_port}"
      DB_DRIVER: postgres
      DB_SSL: require
      PGRST_DB_SCHEMAS: public,storage,graphql_public
      PGRST_DB_ANON_ROLE: anon
      PGRST_DB_USE_LEGACY_GUCS: "false"
      PGRST_APP_SETTINGS_JWT_EXP: "3600"
    realtime:
      DB_HOST: "${db_host}"
      DB_PORT: "${db_port}"
      DB_USER: supabase_admin
      DB_SSL: "true"
      PORT: "4000"
      FLY_ALLOC_ID: fly123
      FLY_APP_NAME: realtime
      ENABLE_TAILSCALE: "false"
      DB_AFTER_CONNECT_QUERY: "SET search_path TO _realtime"
      DB_ENC_KEY: supabaserealtime
      ERL_AFLAGS: -proto_dist inet_tcp
      DNS_NODES: "''"
      RLIMIT_NOFILE: "10000"
      APP_NAME: realtime
      SEED_SELF_HOST: "true"
    meta:
      DB_HOST: "${db_host}"
      DB_PORT: "${db_port}"
      DB_DRIVER: postgres
      DB_SSL: require
    storage:
      DB_HOST: "${db_host}"
      DB_PORT: "${db_port}"
      DB_DRIVER: postgres
      DB_SSL: require
      STORAGE_BACKEND: s3
      GLOBAL_S3_BUCKET: ${storage_bucket_name}
      REGION: ${aws_region}
      AWS_DEFAULT_REGION: ${aws_region}
      AWS_SDK_LOAD_CONFIG: "1"
      NODE_TLS_REJECT_UNAUTHORIZED: "0"
    analytics:
      DB_HOST: "${db_host}"
      DB_PORT: "${db_port}"
    studio:
      POSTGRES_HOST: "${db_host}"
      DEFAULT_ORGANIZATION_NAME: "Default Organization"
      SUPABASE_URL: https://${supabase_domain}
      STUDIO_PG_META_URL: http://${release_name}-supabase-meta:8080
