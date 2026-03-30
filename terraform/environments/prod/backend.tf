# ==============================================================================
# Terraform State Backend
# State stored in S3 with file-based locking
# Bucket must be created by bootstrap.sh before running terraform init
# See: terraform/bootstrap.sh
# ==============================================================================
terraform {
  backend "s3" {
    bucket       = "supabase-terraform-state-904667241500"
    key          = "environments/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
