#!/bin/bash
# ==============================================================================
# Teardown Script
# Destroys all infrastructure for a given environment
# WARNING: This will delete ALL resources including databases
#
# Usage: ./teardown.sh <environment> <aws-region>
# Example: ./teardown.sh prod us-east-1
#
# Estimated time: 20-30 minutes
# ==============================================================================

set -euo pipefail

ENVIRONMENT=${1:?"Usage: ./teardown.sh <environment> <aws-region>"}
AWS_REGION=${2:?"Usage: ./teardown.sh <environment> <aws-region>"}
WORKING_DIR="environments/${ENVIRONMENT}"

echo "=============================================="
echo "WARNING: Destroying ALL infrastructure for: ${ENVIRONMENT}"
echo "This action is IRREVERSIBLE"
echo "=============================================="
read -p "Type 'destroy' to confirm: " confirm
if [ "$confirm" != "destroy" ]; then
  echo "Aborted."
  exit 1
fi

# ------------------------------------------------------------------------------
# Step 1 — Configure kubectl
# ------------------------------------------------------------------------------
echo "Step 1: Configuring kubectl..."
CLUSTER_NAME=$(cd $WORKING_DIR && terraform output -raw eks_cluster_name)
aws eks update-kubeconfig \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}"
echo "  ✓ kubectl configured"

# ------------------------------------------------------------------------------
# Step 2 — Delete ALB Ingress (not managed by Terraform)
# Must be done BEFORE terraform destroy to avoid VPC deletion failure
# ------------------------------------------------------------------------------
echo "Step 2: Deleting ALB ingress resources..."
kubectl delete ingress --all -n supabase --ignore-not-found
echo "  ✓ Waiting 30s for ALB to be deleted by controller..."
sleep 30

# ------------------------------------------------------------------------------
# Step 3 — Uninstall Helm releases
# Removes Karpenter, ALB controller, ESO, Supabase
# ------------------------------------------------------------------------------
echo "Step 3: Uninstalling Helm releases..."
helm uninstall supabase -n supabase --ignore-not-found
helm uninstall aws-load-balancer-controller -n kube-system --ignore-not-found
helm uninstall karpenter -n karpenter --ignore-not-found
helm uninstall external-secrets -n external-secrets --ignore-not-found
echo "  ✓ Helm releases uninstalled"

# ------------------------------------------------------------------------------
# Step 4 — Drain and delete Karpenter-provisioned nodes
# ------------------------------------------------------------------------------
echo "Step 4: Removing Karpenter-provisioned nodes..."
kubectl delete nodeclaims --all --ignore-not-found
echo "  ✓ Waiting 60s for nodes to terminate..."
sleep 60

# ------------------------------------------------------------------------------
# Step 5 — Empty S3 bucket before deletion
# ------------------------------------------------------------------------------
echo "Step 5: Emptying S3 bucket..."
BUCKET_NAME=$(cd $WORKING_DIR && terraform output -raw storage_bucket_name)
aws s3 rm "s3://${BUCKET_NAME}" --recursive || true
echo "  ✓ S3 bucket emptied"

# ------------------------------------------------------------------------------
# Step 6 — Disable Aurora deletion protection
# ------------------------------------------------------------------------------
echo "Step 6: Disabling Aurora deletion protection..."
cd ${WORKING_DIR}
terraform apply \
  -var-file="terraform.tfvars.ci" \
  -var-file="terraform.tfvars" \
  -target="module.rds.aws_rds_cluster.main" \
  -var="deletion_protection=false" \
  -auto-approve || true
echo "  ✓ Deletion protection disabled"

# ------------------------------------------------------------------------------
# Step 7 — Terraform destroy
# ------------------------------------------------------------------------------
echo "Step 7: Running terraform destroy..."
terraform destroy \
  -var-file="terraform.tfvars.ci" \
  -var-file="terraform.tfvars" \
  -auto-approve

echo ""
echo "=============================================="
echo "Teardown complete for: ${ENVIRONMENT}"
echo ""
echo "Remaining costs to check:"
echo "  - CloudWatch log groups (auto-expire after 30 days)"
echo "  - S3 state bucket (manual deletion if no longer needed)"
echo "  - Aurora final snapshot (manual deletion if not needed)"
echo "    aws rds delete-db-cluster-snapshot \\"
echo "      --db-cluster-snapshot-identifier supabase-${ENVIRONMENT}-aurora-final-snapshot"
echo "=============================================="
