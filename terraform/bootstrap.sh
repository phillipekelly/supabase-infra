#!/bin/bash
# ==============================================================================
# Bootstrap Script
# Creates prerequisites for Terraform state management
# Run ONCE before terraform init on any environment
# One S3 bucket serves all environments (dev/sit/prod) via different state keys
#
# Usage: ./bootstrap.sh <aws-account-id> <aws-region>
# Example: ./bootstrap.sh 904667241500 us-east-1
# ==============================================================================

set -euo pipefail

AWS_ACCOUNT_ID=${1:?"Usage: ./bootstrap.sh <aws-account-id> <aws-region>"}
AWS_REGION=${2:?"Usage: ./bootstrap.sh <aws-account-id> <aws-region>"}

BUCKET_NAME="supabase-terraform-state-${AWS_ACCOUNT_ID}"

echo "=============================================="
echo "Bootstrapping Terraform state infrastructure"
echo "Account: ${AWS_ACCOUNT_ID}"
echo "Region:  ${AWS_REGION}"
echo "Bucket:  ${BUCKET_NAME}"
echo ""
echo "This bucket will store state for ALL environments:"
echo "  - environments/dev/terraform.tfstate"
echo "  - environments/sit/terraform.tfstate"
echo "  - environments/prod/terraform.tfstate"
echo "=============================================="

# S3 bucket
echo "Creating S3 state bucket..."
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "  ✓ Bucket already exists: ${BUCKET_NAME}"
else
  aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
  echo "  ✓ Bucket created: ${BUCKET_NAME}"
fi

# Versioning
echo "Enabling bucket versioning..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled
echo "  ✓ Versioning enabled"

# Encryption
echo "Enabling bucket encryption..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }'
echo "  ✓ Encryption enabled"

# Block public access
echo "Blocking public access..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration '{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
  }'
echo "  ✓ Public access blocked"

# Update backend configs
echo "Updating backend.tf files..."
for env in dev sit prod; do
  BACKEND_FILE="environments/${env}/backend.tf"
  if [ -f "${BACKEND_FILE}" ]; then
    sed -i "s/supabase-terraform-state-[0-9]*/supabase-terraform-state-${AWS_ACCOUNT_ID}/g" \
      "${BACKEND_FILE}"
    echo "  ✓ Updated ${BACKEND_FILE}"
  fi
done

echo ""
echo "=============================================="
echo "Bootstrap complete!"
echo ""
echo "Next steps for each environment (dev/sit/prod):"
echo "  1. cd environments/<env>"
echo "  2. cp terraform.tfvars.example terraform.tfvars"
echo "  3. Edit terraform.tfvars with real secret values"
echo "  4. terraform init"
echo "  5. terraform plan -var-file=terraform.tfvars.ci -var-file=terraform.tfvars"
echo "  6. terraform apply -var-file=terraform.tfvars.ci -var-file=terraform.tfvars"
echo "=============================================="
