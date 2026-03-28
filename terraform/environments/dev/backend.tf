# ==============================================================================
# Terraform State Backend — Development
# ==============================================================================
terraform {
  backend "s3" {
    bucket       = "supabase-terraform-state-904667241500"
    key          = "environments/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
