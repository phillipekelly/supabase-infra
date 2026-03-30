#!/bin/bash
# ==============================================================================
# Teardown Script
# Destroys all infrastructure for a given environment
# WARNING: This will delete ALL resources including databases
#
# Usage: ./teardown.sh <environment> <aws-region>
# Example: ./teardown.sh dev us-east-1
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
CLUSTER_NAME=$(cd $WORKING_DIR && terraform output -raw eks_cluster_name 2>/dev/null) || true
if [ -n "${CLUSTER_NAME}" ]; then
  aws eks update-kubeconfig \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" 2>/dev/null || true
  echo "  ✓ kubectl configured for ${CLUSTER_NAME}"
else
  echo "  ! Could not get cluster name — skipping kubectl config"
fi

# ------------------------------------------------------------------------------
# Step 2 — Delete ALB Ingress (removes the ALB before VPC deletion)
# ------------------------------------------------------------------------------
echo "Step 2: Deleting ALB ingress and waiting for ALB removal..."
kubectl delete ingress --all -n supabase 2>/dev/null || true
echo "  ✓ Waiting 45s for ALB controller to delete the load balancer..."
sleep 45

# ------------------------------------------------------------------------------
# Step 3 — Force-delete any remaining ALBs
# ALB controller creates ALBs that Terraform does not manage — must be deleted
# manually or VPC deletion will fail with DependencyViolation
# ------------------------------------------------------------------------------
echo "Step 3: Deleting any remaining load balancers..."
LB_ARNS=$(aws elbv2 describe-load-balancers \
  --region "${AWS_REGION}" \
  --query 'LoadBalancers[*].LoadBalancerArn' \
  --output text 2>/dev/null) || true
if [ -n "${LB_ARNS}" ]; then
  for ARN in $LB_ARNS; do
    echo "  Deleting load balancer: ${ARN}"
    aws elbv2 delete-load-balancer --load-balancer-arn "${ARN}" --region "${AWS_REGION}" 2>/dev/null || true
  done
  echo "  ✓ Waiting 30s for load balancers to delete..."
  sleep 30
else
  echo "  ✓ No load balancers found"
fi

# ------------------------------------------------------------------------------
# Step 4 — Uninstall application Helm releases
# Done before Karpenter so nodes are still available for graceful pod eviction
# ------------------------------------------------------------------------------
echo "Step 4: Uninstalling application Helm releases..."
helm uninstall supabase -n supabase 2>/dev/null || true
helm uninstall external-secrets -n external-secrets 2>/dev/null || true
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
echo "  ✓ Application Helm releases uninstalled"

# ------------------------------------------------------------------------------
# Step 5 — Force-remove stuck Kubernetes namespace finalizers
# Supabase namespace can get stuck in Terminating if ESO webhooks are gone
# ------------------------------------------------------------------------------
echo "Step 5: Cleaning up Kubernetes namespace..."
NS_STATUS=$(kubectl get namespace supabase -o jsonpath='{.status.phase}' 2>/dev/null) || true
if [ "${NS_STATUS}" == "Terminating" ]; then
  echo "  ! Namespace stuck in Terminating — force removing finalizers..."
  kubectl get namespace supabase -o json | \
    python3 -c "import sys,json; d=json.load(sys.stdin); d['spec']['finalizers']=[]; print(json.dumps(d))" | \
    kubectl replace --raw "/api/v1/namespaces/supabase/finalize" -f - 2>/dev/null || true
fi
echo "  ✓ Namespace cleaned up"

# ------------------------------------------------------------------------------
# Step 6 — Drain and delete Karpenter-provisioned nodes
# Must be done BEFORE uninstalling Karpenter
# ------------------------------------------------------------------------------
echo "Step 6: Removing Karpenter-provisioned nodes..."
kubectl delete nodeclaims --all 2>/dev/null || true
echo "  ✓ Waiting 90s for Karpenter nodes to terminate..."
sleep 90

# ------------------------------------------------------------------------------
# Step 7 — Uninstall Karpenter
# Done after nodes are drained to avoid orphaned EC2 instances
# ------------------------------------------------------------------------------
echo "Step 7: Uninstalling Karpenter..."
helm uninstall karpenter -n karpenter 2>/dev/null || true
echo "  ✓ Karpenter uninstalled"

# ------------------------------------------------------------------------------
# Step 8 — Remove stuck Terraform state entries for ESO resources
# ESO webhook blocks kubectl_manifest deletion after ESO is uninstalled
# ------------------------------------------------------------------------------
echo "Step 8: Cleaning up stuck Terraform state entries..."
cd ${WORKING_DIR}
terraform state rm module.supabase.kubectl_manifest.external_secret 2>/dev/null || true
terraform state rm module.supabase.kubectl_manifest.secret_store 2>/dev/null || true
terraform state rm module.supabase.kubernetes_namespace.supabase 2>/dev/null || true
echo "  ✓ State entries cleaned"

# ------------------------------------------------------------------------------
# Step 9 — Hide oidc-github.tf to avoid data source lookup failure
# The GitHub OIDC provider may not exist in dev/sit environments
# ------------------------------------------------------------------------------
echo "Step 9: Hiding oidc-github.tf to avoid OIDC lookup failure..."
if [ -f "oidc-github.tf" ]; then
  mv oidc-github.tf oidc-github.tf.bak
  echo "  ✓ oidc-github.tf renamed to oidc-github.tf.bak"
fi

# ------------------------------------------------------------------------------
# Step 10 — Empty S3 bucket before deletion
# ------------------------------------------------------------------------------
echo "Step 10: Emptying S3 bucket..."
BUCKET_NAME=$(terraform output -raw storage_bucket_name 2>/dev/null) || true
if [ -n "${BUCKET_NAME}" ]; then
  aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null || true
  echo "  ✓ S3 bucket emptied"
else
  echo "  ! Could not get bucket name — skipping"
fi

# ------------------------------------------------------------------------------
# Step 11 — Delete Aurora final snapshot if it already exists
# terraform destroy creates a final snapshot — fails if one already exists
# ------------------------------------------------------------------------------
echo "Step 11: Deleting existing Aurora final snapshot if present..."
aws rds delete-db-cluster-snapshot \
  --db-cluster-snapshot-identifier "supabase-${ENVIRONMENT}-aurora-final-snapshot" \
  --region "${AWS_REGION}" 2>/dev/null || true
echo "  ✓ Snapshot cleanup done"

# ------------------------------------------------------------------------------
# Step 12 — Disable Aurora deletion protection
# deletion_protection is hardcoded in the module — must use AWS CLI directly
# ------------------------------------------------------------------------------
echo "Step 12: Disabling Aurora deletion protection..."
aws rds modify-db-cluster \
  --db-cluster-identifier "supabase-${ENVIRONMENT}-aurora" \
  --no-deletion-protection \
  --apply-immediately \
  --region "${AWS_REGION}" 2>/dev/null || true
echo "  ✓ Waiting 30s for modification to apply..."
sleep 30

# ------------------------------------------------------------------------------
# Step 13 — Terraform destroy
# ------------------------------------------------------------------------------
echo "Step 13: Running terraform destroy..."
terraform destroy \
  -var-file="terraform.tfvars.ci" \
  -var-file="terraform.tfvars" \
  -auto-approve

# ------------------------------------------------------------------------------
# Step 14 — Clean up leftover ALB security groups
# ALB controller creates SGs Terraform doesn't manage — they block VPC deletion
# ------------------------------------------------------------------------------
echo "Step 14: Cleaning up any leftover ALB security groups..."
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=supabase-${ENVIRONMENT}-vpc" \
  --region "${AWS_REGION}" \
  --query 'Vpcs[0].VpcId' \
  --output text 2>/dev/null) || true

if [ -n "${VPC_ID}" ] && [ "${VPC_ID}" != "None" ]; then
  echo "  ! VPC still exists — cleaning up remaining security groups..."
  SG_IDS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --region "${AWS_REGION}" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
    --output text 2>/dev/null) || true
  for SG_ID in $SG_IDS; do
    echo "  Deleting security group: ${SG_ID}"
    aws ec2 delete-security-group --group-id "${SG_ID}" --region "${AWS_REGION}" 2>/dev/null || true
  done
  sleep 10
  echo "  Attempting final VPC deletion..."
  aws ec2 delete-vpc --vpc-id "${VPC_ID}" --region "${AWS_REGION}" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# Step 15 — Restore oidc-github.tf
# ------------------------------------------------------------------------------
echo "Step 15: Restoring oidc-github.tf..."
if [ -f "oidc-github.tf.bak" ]; then
  mv oidc-github.tf.bak oidc-github.tf
  echo "  ✓ oidc-github.tf restored"
fi

echo ""
echo "=============================================="
echo "Teardown complete for: ${ENVIRONMENT}"
echo ""
echo "Post-teardown cost verification:"
echo "  1. Check no load balancers remain:"
echo "     aws elbv2 describe-load-balancers --region ${AWS_REGION}"
echo "  2. Check no NAT gateways remain:"
echo "     aws ec2 describe-nat-gateways --region ${AWS_REGION} --query 'NatGateways[?State==\`available\`]'"
echo "  3. CloudWatch log groups auto-expire after 30 days"
echo "  4. S3 state bucket kept — delete manually if no longer needed:"
echo "     aws s3 rb s3://supabase-terraform-state-<account-id> --force"
echo "=============================================="

# ------------------------------------------------------------------------------
# Post-teardown resource check
# Scans for any remaining billable resources and prints a clear summary
# ------------------------------------------------------------------------------
ISSUES_FOUND=0

echo ""
echo "Checking for remaining billable resources..."
echo ""

# EKS clusters
EKS=$(aws eks list-clusters --region "${AWS_REGION}" --query 'clusters' --output text 2>/dev/null) || true
if [ -n "${EKS}" ]; then
  echo "  WARNING: EKS clusters still running:"
  aws eks list-clusters --region "${AWS_REGION}" --output table
  ISSUES_FOUND=1
else
  echo "  OK: No EKS clusters"
fi

# NAT Gateways
NATS=$(aws ec2 describe-nat-gateways \
  --region "${AWS_REGION}" \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[*].NatGatewayId' \
  --output text 2>/dev/null) || true
if [ -n "${NATS}" ]; then
  echo "  WARNING: NAT Gateways still running (~\$0.045/hr each):"
  aws ec2 describe-nat-gateways \
    --region "${AWS_REGION}" \
    --filter "Name=state,Values=available" \
    --query 'NatGateways[*].[NatGatewayId,State]' \
    --output table
  ISSUES_FOUND=1
else
  echo "  OK: No NAT Gateways"
fi

# RDS/Aurora clusters
RDS=$(aws rds describe-db-clusters \
  --region "${AWS_REGION}" \
  --query 'DBClusters[*].DBClusterIdentifier' \
  --output text 2>/dev/null) || true
if [ -n "${RDS}" ]; then
  echo "  WARNING: RDS/Aurora clusters still running:"
  aws rds describe-db-clusters \
    --region "${AWS_REGION}" \
    --query 'DBClusters[*].[DBClusterIdentifier,Status]' \
    --output table
  ISSUES_FOUND=1
else
  echo "  OK: No RDS/Aurora clusters"
fi

# EC2 instances
EC2=$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --filters "Name=instance-state-name,Values=running,pending,stopped" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text 2>/dev/null) || true
if [ -n "${EC2}" ]; then
  echo "  WARNING: EC2 instances still running:"
  aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --filters "Name=instance-state-name,Values=running,pending,stopped" \
    --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name]' \
    --output table
  ISSUES_FOUND=1
else
  echo "  OK: No EC2 instances"
fi

# Load balancers
LBS=$(aws elbv2 describe-load-balancers \
  --region "${AWS_REGION}" \
  --query 'LoadBalancers[*].LoadBalancerArn' \
  --output text 2>/dev/null) || true
if [ -n "${LBS}" ]; then
  echo "  WARNING: Load balancers still running (~\$0.023/hr each):"
  aws elbv2 describe-load-balancers \
    --region "${AWS_REGION}" \
    --query 'LoadBalancers[*].[LoadBalancerName,State.Code,Type]' \
    --output table
  ISSUES_FOUND=1
else
  echo "  OK: No load balancers"
fi

# VPCs (excluding default)
VPCS=$(aws ec2 describe-vpcs \
  --region "${AWS_REGION}" \
  --filters "Name=isDefault,Values=false" \
  --query 'Vpcs[*].VpcId' \
  --output text 2>/dev/null) || true
if [ -n "${VPCS}" ]; then
  echo "  WARNING: Non-default VPCs still exist:"
  aws ec2 describe-vpcs \
    --region "${AWS_REGION}" \
    --filters "Name=isDefault,Values=false" \
    --query 'Vpcs[*].[VpcId,CidrBlock]' \
    --output table
  ISSUES_FOUND=1
else
  echo "  OK: No non-default VPCs"
fi

# Final summary
echo ""
echo "=============================================="
if [ "${ISSUES_FOUND}" -eq 0 ]; then
  echo "  ALL CLEAR — no billable resources remaining"
  echo "  AWS costs will stop accruing immediately"
else
  echo "  WARNING — some resources still exist, manual cleanup required"
  echo "  Costs are still accruing for the resources listed above"
  echo ""
  echo "  View current costs:"
  echo "  https://console.aws.amazon.com/cost-management/home#/cost-explorer"
fi
echo ""
echo "  Note: S3 state bucket and CloudWatch log groups kept intentionally."
echo "  Delete state bucket manually when no longer needed:"
echo "  aws s3 rb s3://supabase-terraform-state-<account-id> --force"
echo "=============================================="
