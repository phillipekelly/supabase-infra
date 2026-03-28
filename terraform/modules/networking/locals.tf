# ==============================================================================
# Networking Module Locals
# ==============================================================================

locals {
  # Number of AZs determines number of subnets and NAT gateways
  az_count = length(var.availability_zones)
}
