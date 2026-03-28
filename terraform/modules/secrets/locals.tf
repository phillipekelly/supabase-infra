# ==============================================================================
# Secrets Module Locals
# ==============================================================================

locals {
  # Secret names match what ESO SecretStore will reference
  secret_names = {
    db        = "${var.name_prefix}/db"
    jwt       = "${var.name_prefix}/jwt"
    dashboard = "${var.name_prefix}/dashboard"
    analytics = "${var.name_prefix}/analytics"
    realtime  = "${var.name_prefix}/realtime"
    meta      = "${var.name_prefix}/meta"
  }
}
