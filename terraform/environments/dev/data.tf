# ==============================================================================
# Data Sources
# Read-only references to existing AWS resources
# ==============================================================================

# Current AWS account ID and region
# Used in locals for unique resource naming
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Available AZs in the region
# Used to validate availability_zones variable
data "aws_availability_zones" "available" {
  state = "available"
}
