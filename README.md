# Supabase on AWS EKS — Production-Ready Infrastructure

A fully automated, production-grade deployment of [Supabase](https://supabase.com/) on AWS EKS using Terraform IaC, Helm, Karpenter, and External Secrets Operator. Supports three isolated environments: `dev`, `sit`, and `prod`.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Technology Choices Justification](#technology-choices-justification)
3. [Prerequisites & Setup](#prerequisites--setup)
4. [Deployment Instructions](#deployment-instructions)
5. [Verification & Smoke Test](#verification--smoke-test)
6. [Tear-down Instructions](#tear-down-instructions)
7. [Security & Scalability Deep Dive](#security--scalability-deep-dive)
8. [Observability Approach](#observability-approach)
9. [Challenges & Learnings](#challenges--learnings)
10. [Future Improvements](#future-improvements)
11. [Cost Estimates](#cost-estimates)

---

## Architecture Overview

```
                          ┌─────────────────────────────────────────────────────┐
                          │                    AWS Account                       │
                          │                                                       │
                          │  ┌──────────────────────────────────────────────┐   │
                          │  │                 VPC (10.0.0.0/16)             │   │
                          │  │                                                │   │
                          │  │  ┌─────────────┐      ┌─────────────┐        │   │
                          │  │  │ Public AZ-A │      │ Public AZ-B │        │   │
                          │  │  │ 10.0.101/24 │      │ 10.0.102/24 │        │   │
                          │  │  │  NAT GW     │      │  NAT GW     │        │   │
                          │  │  └──────┬──────┘      └──────┬──────┘        │   │
                          │  │         │                     │               │   │
                          │  │  ┌──────▼──────┐      ┌──────▼──────┐        │   │
                          │  │  │Private AZ-A │      │Private AZ-B │        │   │
                          │  │  │ 10.0.1.0/24 │      │ 10.0.2.0/24 │        │   │
                          │  │  │             │      │             │        │   │
                          │  │  │  EKS Nodes  │      │  EKS Nodes  │        │   │
                          │  │  │  ┌────────┐ │      │ ┌────────┐  │        │   │
                          │  │  │  │Supabase│ │      │ │Supabase│  │        │   │
                          │  │  │  │  Pods  │ │      │ │  Pods  │  │        │   │
                          │  │  │  └────────┘ │      │ └────────┘  │        │   │
                          │  │  │             │      │             │        │   │
                          │  │  │  Aurora     │      │  Aurora     │        │   │
                          │  │  │  Primary    │      │  Replica    │        │   │
                          │  │  └─────────────┘      └─────────────┘        │   │
                          │  └──────────────────────────────────────────────┘   │
                          │                                                       │
                          │  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
                          │  │    S3    │  │ Secrets  │  │   CloudWatch     │  │
                          │  │ Storage  │  │ Manager  │  │     Logs         │  │
                          │  └──────────┘  └──────────┘  └──────────────────┘  │
                          └─────────────────────────────────────────────────────┘

Internet → ALB (public) → Kong (API Gateway) → Supabase Services
                       → Studio (Dashboard)

GitHub Actions → OIDC → AWS IAM Role → Terraform → All Resources
```

### Component Interactions

**Traffic Flow:**
- External traffic hits the AWS ALB (managed by ALB Ingress Controller)
- ALB routes `/` to Supabase Studio (dashboard)
- ALB routes `/rest/v1`, `/auth/v1`, `/storage/v1`, `/realtime/v1` to Kong (API gateway)
- Kong routes to individual Supabase microservices
- All pods communicate within the Kubernetes cluster via NetworkPolicies

**Secrets Flow:**
- Secrets stored in AWS Secrets Manager (KMS encrypted)
- External Secrets Operator polls Secrets Manager every 1 hour
- ESO creates a Kubernetes Secret from the AWS secrets
- Supabase pods mount the Kubernetes Secret as environment variables
- No secrets ever touch the filesystem or git history

**Autoscaling Flow:**
- HPA monitors CPU/memory on each Supabase pod
- When thresholds exceeded, HPA creates new pod replicas
- New pods cannot be scheduled — nodes are full
- Karpenter detects pending pods in under 60 seconds
- Karpenter provisions the optimal EC2 instance type
- Pods schedule on new node and become Running
- After load drops, HPA scales pods down
- Karpenter consolidates and terminates empty nodes

---

## Technology Choices Justification

### IaC Framework — Terraform (not CDKTF, Pulumi, or cdk8s)

The task offered CDKTF (Python), Pulumi, and cdk8s as alternatives. We chose **plain Terraform HCL** for the following reasons:

**Why not CDKTF (Python):**
CDKTF generates Terraform JSON under the hood — it is a wrapper, not a fundamentally different tool. It adds a Python compilation step, requires Node.js alongside Python, and produces intermediate JSON that obscures what Terraform is actually doing. For a team reviewing infrastructure code, HCL is more readable and auditable than CDKTF-generated JSON. The benefit of Python familiarity does not outweigh the added complexity and the loss of HCL's declarative clarity.

**Why not Pulumi:**
Pulumi uses general-purpose programming languages (Python, TypeScript, Go) which introduces software engineering complexity — loops, conditionals, abstractions — that can make infrastructure code harder to reason about and audit. Terraform's declarative HCL is intentionally limited, which forces infrastructure to be explicit and reviewable. Pulumi also has a smaller ecosystem of providers and modules compared to Terraform's registry. For AWS infrastructure specifically, the Terraform AWS provider is the most mature and battle-tested option available.

**Why not cdk8s:**
cdk8s is a Kubernetes-specific tool for generating Kubernetes manifests using code. It is not an infrastructure provisioning tool — it cannot create VPCs, EKS clusters, or Aurora databases. It would only cover the Kubernetes manifest layer, requiring a separate tool for cloud infrastructure anyway. Since we already use Terraform (which can deploy Kubernetes resources via the Helm and kubectl providers), adding cdk8s would introduce a second IaC layer with no benefit.

**Terraform was the right choice because:**
- Single tool for all layers: cloud infrastructure, Kubernetes resources, Helm releases
- HCL is declarative, readable, and auditable by anyone on the team
- The Terraform AWS provider is the most comprehensive and stable option
- State management via S3 + locking is well understood and battle-tested
- The module system provides the reusability that cdk8s or Pulumi constructs would offer

### Cloud Provider — AWS

AWS was chosen over Azure because:
- EKS is more mature than AKS with a larger ecosystem of add-ons (Karpenter, ALB controller)
- Aurora PostgreSQL is a superior managed database compared to Azure Database for PostgreSQL for this use case — see Aurora justification below
- AWS Secrets Manager has tighter IRSA integration with EKS than Azure Key Vault
- The Supabase community has more reference implementations for AWS than Azure

### Kubernetes — Amazon EKS

EKS was chosen over self-managed Kubernetes because:
- AWS manages the control plane (etcd, API server, scheduler) — no operational burden
- Native integration with IAM via IRSA for pod-level authentication
- Native integration with VPC CNI for pod networking
- AWS-managed addons (CoreDNS, kube-proxy, VPC CNI, EBS CSI) kept up to date automatically
- EKS nodes run in **private subnets only** — no direct internet exposure

**High Availability Design — AZ vs Region:**

This deployment is **Multi-AZ** (high availability within a single AWS region). EKS nodes and Aurora instances span `us-east-1a` and `us-east-1b`. This protects against:
- A single data center failure
- An Availability Zone power or network outage

**Why not multi-region:**
Multi-region HA for Supabase would require Aurora Global Database (replication lag ~1 second), Route53 latency-based routing, and cross-region ESO configuration. This significantly increases cost (~2x) and operational complexity. For most production workloads, multi-AZ provides sufficient resilience (AWS SLA for multi-AZ RDS is 99.95%).

**How to achieve multi-region if required:**
1. Enable Aurora Global Database — creates a primary cluster and up to 5 read-only secondary clusters in other regions
2. Deploy a second EKS cluster in the secondary region using the same Terraform modules
3. Configure Route53 health checks with latency-based routing to direct traffic to the nearest healthy region
4. Use a global S3 bucket with Cross-Region Replication for Supabase storage
5. Accept ~1 second replication lag for database writes during failover

### Database — Aurora PostgreSQL (not RDS PostgreSQL, not Serverless)

**Why Aurora over standard RDS PostgreSQL:**
- Aurora uses a distributed storage layer replicated 6 ways across 3 AZs — standard RDS uses single-volume replication
- Aurora failover completes in under 30 seconds vs 60-120 seconds for standard RDS Multi-AZ
- Aurora reader endpoints allow read scaling without application changes
- Aurora supports up to 15 read replicas vs 5 for standard RDS

**Why Aurora Provisioned (not Aurora Serverless v2):**
- Supabase uses persistent database connections via PgBouncer — Serverless v2's connection overhead per cold start adds latency
- Provisioned instances have predictable performance — Serverless v2 can introduce variable latency during scaling events
- Production cost is comparable for sustained workloads — Serverless v2 is cost-effective only for intermittent/bursty traffic

**PostgreSQL Version — 15.x:**
Supabase requires PostgreSQL 15 specifically. The `supabase/postgres:15.8.1.085` Docker image is the reference implementation. Aurora PostgreSQL 15 was selected to match this exactly. Using a different major version risks compatibility issues with Supabase's internal schemas, extensions (`pgjwt`, `pg_graphql`, `pgvector`), and row-level security policies.

### Node Autoscaling — Karpenter (not Cluster Autoscaler)

Karpenter was chosen over the standard Cluster Autoscaler for three reasons:

**Performance:** Karpenter provisions new EC2 nodes in 30-60 seconds by calling the EC2 API directly. Cluster Autoscaler works through AWS Auto Scaling Groups which adds 2-3 minutes of overhead. During a traffic spike, the difference between pods pending for 30 seconds vs 3 minutes is significant for user experience.

**Cost:** Karpenter right-sizes instance types to actual pod resource requests. If HPA creates 3 new pods that each need 200m CPU and 256Mi RAM, Karpenter provisions a `t3.small` ($0.02/hr) rather than a fixed `t3.medium` ($0.04/hr). Karpenter also continuously runs consolidation — moving pods from underutilized nodes onto fewer nodes and terminating the empty ones. This reduces compute costs by an estimated 20-40% compared to Cluster Autoscaler on variable workloads.

**AWS Native:** Karpenter is built and maintained by AWS specifically for EKS. It has native support for Spot instances, capacity reservations, and EC2 instance metadata.

### Secrets Management — External Secrets Operator + AWS Secrets Manager

ESO was chosen over Kubernetes Secrets (plain), Vault, or the AWS Secrets Manager CSI driver because:
- **Zero secrets in code or git** — all sensitive values live exclusively in AWS Secrets Manager
- **IRSA authentication** — ESO assumes an IAM role via OIDC, no static credentials
- **Automatic rotation** — ESO polls Secrets Manager every hour and updates the Kubernetes Secret automatically
- **Separation of concerns** — infrastructure team manages secrets in AWS Console, application team references them by name

### Ingress — AWS ALB Ingress Controller (not NGINX in production)

**Local development (Minikube):** NGINX Ingress Controller is used because Minikube doesn't have ALB support. NGINX runs as a pod inside the cluster and routes traffic locally.

**Production (EKS):** AWS ALB Ingress Controller is used. When a Kubernetes Ingress resource with `className: alb` is created, the controller automatically provisions an AWS Application Load Balancer. This is superior to running NGINX in production because:
- ALB is a managed service — no NGINX pods to maintain, scale, or patch
- ALB integrates natively with AWS Certificate Manager for SSL termination
- ALB integrates with AWS WAF for DDoS protection
- ALB health checks are handled at the AWS layer, not the pod layer

**Both are not needed simultaneously.** The `ingress.className` value switches between them per environment. This is intentional design — same Ingress manifest, different controller backend.

### CI/CD — GitHub Actions

GitHub Actions is the right choice for this deployment for four reasons:

- **Zero infrastructure** — no CI/CD server to provision, maintain, patch, or pay for. Workflows are fully managed by GitHub.
- **Native OIDC with AWS** — GitHub Actions assumes an IAM role via OpenID Connect. No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` is stored anywhere — temporary credentials are issued per-run and expire automatically.
- **Co-located with code** — workflow files live in the same repo, versioned alongside infrastructure. Every change to the pipeline is a PR, reviewed like any other code change.
- **Industry standard** — the most widely adopted CI/CD tool for infrastructure teams using Terraform today, with first-class support from HashiCorp (`hashicorp/setup-terraform`) and AWS (`aws-actions/configure-aws-credentials`).

---

## Prerequisites & Setup

### Required Tools

| Tool | Version | Installation |
|------|---------|-------------|
| Terraform | >= 1.9.0 | https://developer.hashicorp.com/terraform/install |
| AWS CLI | >= 2.0 | https://aws.amazon.com/cli/ |
| kubectl | >= 1.28 | https://kubernetes.io/docs/tasks/tools/ |
| Helm | >= 3.16 | https://helm.sh/docs/intro/install/ |
| psql | >= 15 | `sudo apt-get install postgresql-client` |
| git | any | https://git-scm.com/ |

### Required AWS Permissions

The AWS user/role running the initial `terraform apply` needs the following permissions:
- `AdministratorAccess` (for initial bootstrap) or a scoped policy covering EC2, EKS, RDS, S3, IAM, SecretsManager, KMS

### Clone the Repository

```bash
git clone https://github.com/phillipekelly/supabase-infra.git
cd supabase-infra
```

### Configure AWS Credentials

```bash
aws configure
# Enter: AWS Access Key ID
# Enter: AWS Secret Access Key
# Enter: Default region (us-east-1)
# Enter: Default output format (json)

# Verify
aws sts get-caller-identity
```

### Generate Secret Values

Before deploying, generate secure values for all secrets:

```bash
echo "db_master_password       = \"$(openssl rand -base64 16)\""
echo "jwt_secret               = \"$(openssl rand -base64 32)\""
echo "dashboard_password       = \"$(openssl rand -base64 12)\""
echo "analytics_public_token   = \"$(openssl rand -base64 32)\""
echo "analytics_private_token  = \"$(openssl rand -base64 32)\""
echo "realtime_secret_key_base = \"$(openssl rand -base64 48)\""
echo "meta_crypto_key          = \"$(openssl rand -base64 32)\""
```

For `jwt_anon_key` and `jwt_service_key`, use the official Supabase key generator — paste your `jwt_secret` and it generates both keys instantly:
https://supabase.com/docs/guides/self-hosting/docker#generate-api-keys

---

## Deployment Instructions

### Step 1 — Bootstrap State Infrastructure (one time only)

```bash
cd terraform
./bootstrap.sh <aws-account-id> <aws-region>

# Example
./bootstrap.sh 904667241500 us-east-1
```

This creates:
- S3 bucket for Terraform state (`supabase-terraform-state-<account-id>`)
- Versioning and encryption enabled on the bucket
- Public access blocked

The same S3 bucket stores state for all environments via different keys:
```
supabase-terraform-state-<account-id>/
├── environments/dev/terraform.tfstate
├── environments/sit/terraform.tfstate
└── environments/prod/terraform.tfstate
```

### Step 2 — Configure Variables

```bash
cd environments/prod   # or dev, sit

# Create secrets file from example
cp terraform.tfvars.example terraform.tfvars

# Edit with your generated secret values
nano terraform.tfvars
```

`terraform.tfvars.ci` contains all non-sensitive configuration (already committed to git).
`terraform.tfvars` contains only secrets (gitignored, never committed).

### Step 3 — Initialize Terraform

```bash
terraform init
```

This downloads all providers (AWS, Helm, kubectl, PostgreSQL, TLS, null) and initializes the S3 backend.

### Step 4 — Plan

```bash
terraform plan \
  -var-file="terraform.tfvars.ci" \
  -var-file="terraform.tfvars"
```

Review the plan output carefully. Expected: **124 resources to add**.

### Step 5 — Apply

```bash
terraform apply \
  -var-file="terraform.tfvars.ci" \
  -var-file="terraform.tfvars"
```

Expected duration: **20-30 minutes**. The longest steps are:
- EKS cluster creation: ~12 minutes
- Aurora cluster creation: ~8 minutes
- Helm releases: ~5 minutes

### Step 6 — Configure kubectl

```bash
# This command is in the terraform output
aws eks update-kubeconfig \
  --name supabase-eks \
  --region us-east-1

# Verify
kubectl get nodes
kubectl get pods -n supabase
```

### Step 7 — Set Up CI/CD (after first apply)

After the first `terraform apply` completes:

```bash
# Get the GitHub Actions IAM role ARN from outputs
terraform output github_actions_role_arn
```

Add the following secrets to your GitHub repository (Settings → Secrets → Actions):

| Secret Name | Value |
|------------|-------|
| `AWS_ROLE_ARN` | Output from `github_actions_role_arn` |
| `TF_VAR_DB_MASTER_PASSWORD` | Your database password |
| `TF_VAR_JWT_SECRET` | Your JWT secret |
| `TF_VAR_JWT_ANON_KEY` | Your JWT anon key |
| `TF_VAR_JWT_SERVICE_KEY` | Your JWT service key |
| `TF_VAR_DASHBOARD_USERNAME` | Your dashboard username |
| `TF_VAR_DASHBOARD_PASSWORD` | Your dashboard password |
| `TF_VAR_ANALYTICS_PUBLIC_TOKEN` | Your analytics public token |
| `TF_VAR_ANALYTICS_PRIVATE_TOKEN` | Your analytics private token |
| `TF_VAR_REALTIME_SECRET_KEY_BASE` | Your realtime secret key base |
| `TF_VAR_META_CRYPTO_KEY` | Your meta crypto key |

Also update `oidc-github.tf` with your actual GitHub username and repo:
```hcl
"token.actions.githubusercontent.com:sub" = "repo:YOUR_USERNAME/supabase-infra:*"
```

From this point forward, all infrastructure changes go through GitHub Actions — no more manual `terraform apply`.

**Branch → Environment mapping:**
```
main branch    → prod environment (requires approval)
sit branch     → sit environment
other branches → dev environment
```

---

## Verification & Smoke Test

### 1. Verify All Pods Are Running

```bash
kubectl get pods -n supabase
```

Expected output — all pods `Running`:
```
NAME                                    READY   STATUS    RESTARTS
supabase-kong-xxx                       1/1     Running   0
supabase-auth-xxx                       1/1     Running   0
supabase-rest-xxx                       1/1     Running   0
supabase-realtime-xxx                   1/1     Running   0
supabase-storage-xxx                    1/1     Running   0
supabase-meta-xxx                       1/1     Running   0
supabase-studio-xxx                     1/1     Running   0
supabase-analytics-xxx                  1/1     Running   0
supabase-imgproxy-xxx                   1/1     Running   0
supabase-functions-xxx                  1/1     Running   0
```

### 2. Verify HPAs Are Active

```bash
kubectl get hpa -n supabase
```

Expected: HPA targets showing current CPU/memory metrics.

### 3. Verify Secrets Are Synced

```bash
# Check ESO synced successfully
kubectl get externalsecret -n supabase
# Should show: READY=True

# Check secret exists
kubectl get secret supabase-esm-secrets -n supabase
```

### 4. Verify Ingress and Get ALB URL

```bash
kubectl get ingress -n supabase
```

Note the `ADDRESS` field — this is your ALB DNS name:
```
NAME               CLASS   HOSTS   ADDRESS                                          PORTS
supabase-ingress   alb     *       k8s-supabase-xxxxx.us-east-1.elb.amazonaws.com   80
```

### 5. Smoke Test — API Endpoint

```bash
ALB_URL=$(kubectl get ingress -n supabase -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

# Test Kong health
curl http://$ALB_URL/rest/v1/ \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Authorization: Bearer YOUR_ANON_KEY"

# Expected: {"hint":"...","details":"...","code":"...","message":"..."}
```

### 6. Smoke Test — Studio UI

```bash
# Open Studio in browser
echo "http://$ALB_URL"
```

### 7. View Logs

```bash
# View logs for a specific service
kubectl logs -n supabase -l app.kubernetes.io/name=supabase-rest --tail=50
kubectl logs -n supabase -l app.kubernetes.io/name=supabase-auth --tail=50
kubectl logs -n supabase -l app.kubernetes.io/name=supabase-kong --tail=50

# View EKS control plane logs in CloudWatch
aws logs get-log-events \
  --log-group-name /aws/eks/supabase-eks/cluster \
  --log-stream-name kube-apiserver-xxx \
  --region us-east-1
```

### 8. Rotate Secrets

```bash
# Update secret value in AWS Secrets Manager
aws secretsmanager put-secret-value \
  --secret-id supabase-production/jwt \
  --secret-string '{"secret":"new-value","anonKey":"new-anon-key","serviceKey":"new-service-key"}' \
  --region us-east-1

# Force ESO to sync immediately (instead of waiting 1 hour)
kubectl annotate externalsecret supabase-external-secret \
  -n supabase \
  force-sync=$(date +%s) \
  --overwrite
```

---

## Tear-down Instructions

> ⚠️ **WARNING:** This permanently destroys all infrastructure including the database. Ensure you have backups before proceeding.

### Automated Teardown (Recommended)

```bash
cd terraform
./teardown.sh prod us-east-1
```

The teardown script handles the correct order of operations:
1. Deletes ALB Ingress resources (must be done before VPC deletion)
2. Uninstalls Helm releases (Supabase, ALB controller, Karpenter, ESO)
3. Drains Karpenter-provisioned nodes
4. Empties S3 bucket (required before bucket deletion)
5. Disables Aurora deletion protection
6. Runs `terraform destroy`

Expected duration: **20-30 minutes**.

### Manual Teardown

If the script fails at any step:

```bash
# Step 1 — Delete ingress (removes the ALB)
kubectl delete ingress --all -n supabase
sleep 30  # Wait for ALB to be deleted

# Step 2 — Empty S3 bucket
BUCKET=$(terraform output -raw storage_bucket_name)
aws s3 rm s3://$BUCKET --recursive

# Step 3 — Terraform destroy
cd terraform/environments/prod
terraform destroy \
  -var-file="terraform.tfvars.ci" \
  -var-file="terraform.tfvars"
```

### Post-Teardown Cost Verification

After destroy completes, verify no resources remain:

```bash
# Check for any remaining load balancers (manually created by ALB controller)
aws elbv2 describe-load-balancers --region us-east-1

# Delete Aurora final snapshot if not needed
aws rds delete-db-cluster-snapshot \
  --db-cluster-snapshot-identifier supabase-production-aurora-final-snapshot \
  --region us-east-1

# Delete CloudWatch log group (auto-expires after 30 days but can delete now)
aws logs delete-log-group \
  --log-group-name /aws/eks/supabase-eks/cluster \
  --region us-east-1

# Delete state bucket only if no longer needed
aws s3 rb s3://supabase-terraform-state-<account-id> --force
```

---

## Security & Scalability Deep Dive

### Secrets Management

All sensitive values follow a strict flow:

```
Developer generates secret locally
        ↓
Secret stored in AWS Secrets Manager (KMS encrypted at rest)
        ↓
ESO polls Secrets Manager every 1 hour via IRSA
        ↓
ESO creates/updates Kubernetes Secret
        ↓
Supabase pods mount Secret as environment variables
        ↓
Secret never touches disk, git, or container image
```

There are **zero secrets in any file committed to git**. The `terraform.tfvars` file containing real values is gitignored. Secrets Manager uses a dedicated KMS Customer Managed Key (CMK) — not the default AWS managed key — giving full control over key rotation and access policies.

### Least Privilege — IAM IRSA Roles

Every AWS-accessing component has its own dedicated IAM role with the minimum required permissions:

| Component | IAM Role | Permissions |
|-----------|---------|-------------|
| ESO | `supabase-production-eso-role` | `secretsmanager:GetSecretValue` on `/supabase-production/*` only |
| Storage pod | `supabase-production-storage-role` | `s3:GetObject`, `s3:PutObject` on the storage bucket only |
| Karpenter | `supabase-production-karpenter-role` | EC2 instance provisioning actions only |
| ALB Controller | `supabase-production-alb-controller-role` | ELB management actions only |
| GitHub Actions | `supabase-production-github-actions-role` | Terraform operation permissions only |

No component uses node-level IAM roles (which would grant all pods on a node the same permissions). Every pod authenticates individually via IRSA (IAM Roles for Service Accounts).

### Network Security

Traffic is restricted at three layers:

**Layer 1 — AWS Security Groups:**
- EKS nodes are in private subnets — no direct internet access
- Aurora is in private subnets — only accessible from EKS node security group
- ALB is in public subnets — accepts 80/443 from internet
- All other inter-service traffic blocked by default

**Layer 2 — Kubernetes NetworkPolicies:**
12 NetworkPolicy resources enforce pod-level traffic restriction:
- `default-deny` — blocks all ingress/egress by default in the `supabase` namespace
- Per-service policies — allow only the exact ports and peers each service needs
- For example: `rest` policy allows only ingress from `kong` on port 3000, and egress to `db` on port 5432

**Layer 3 — Aurora SSL:**
All database connections require SSL (`sslmode=require`). Plaintext connections are rejected at the database level.

### Scalability

**Pod-level scaling (HPA):**

| Service | Min Replicas | Max Replicas | CPU Target | Memory Target |
|---------|-------------|-------------|-----------|--------------|
| rest (PostgREST) | 2 | 10 | 70% | 80% |
| auth (GoTrue) | 2 | 8 | 70% | 80% |
| storage | 2 | 6 | 70% | 80% |
| functions | 1 | 5 | 70% | 80% |
| imgproxy | 1 | 4 | 80% | 85% |

**Note on Realtime:** HPA is intentionally disabled for the Realtime service. Realtime uses persistent WebSocket connections — horizontal scaling without a distributed coordination layer causes split-brain issues with Postgres WAL replication slots, broken Presence tracking, and incomplete Broadcast delivery. Realtime is scaled vertically via resource limits instead. See [Challenges & Learnings](#challenges--learnings) for full detail.

**Node-level scaling (Karpenter):**
- Karpenter NodePool allows `t`, `m`, `c`, `r` instance families
- Both Spot and On-Demand instances permitted (Spot preferred for cost)
- Automatic fallback to On-Demand if Spot unavailable
- Consolidation policy: `WhenEmptyOrUnderutilized` with 30-second delay
- Resource limits: max 100 vCPU, 400Gi RAM across all Karpenter-managed nodes

### IaC Structure — Constructs, Variables, Outputs

The Terraform code follows module best practices:

- **Modules (constructs):** 6 reusable modules (`networking`, `eks`, `rds`, `s3`, `secrets`, `supabase`) each with a single responsibility
- **Variables:** Every configurable value is a variable with type constraints, descriptions, and validation rules
- **Outputs:** Each module exposes outputs consumed by other modules (e.g., `module.networking.vpc_id` → `module.eks.vpc_id`)
- **Locals:** Computed values (name prefixes, tags) centralized in `locals.tf` per environment
- **Versions:** All provider versions pinned in `versions.tf` for reproducible builds

---

## Observability Approach

Full observability was not implemented (as per task requirements — optional), but the architecture is designed with observability in mind:

### What Is Already In Place

**EKS Control Plane Logging:**
All five control plane log types are enabled and sent to CloudWatch:
```hcl
enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
```
A dedicated CloudWatch Log Group `/aws/eks/supabase-eks/cluster` is created with **30-day retention** to prevent indefinite log accumulation (CloudWatch costs $0.50/GB/month — without retention policies, logs accumulate and incur ongoing costs).

**Supabase Analytics (Logflare):**
The analytics service (Logflare) is deployed and configured as part of the Supabase stack. It collects structured logs from Kong (API gateway) and provides a query interface via the Studio dashboard.

### What Would Be Added in Production

**Metrics (Prometheus + Grafana):**
```
EKS pods → Prometheus (scrapes /metrics endpoints) → Grafana dashboards
```
- Deploy `kube-prometheus-stack` Helm chart
- Supabase exposes Prometheus metrics on `/metrics` for PostgREST, Auth, and Storage
- Key dashboards: request rate, error rate, latency (RED method), pod CPU/memory

**Log Aggregation (AWS-native approach):**
```
Pod stdout/stderr → Fluent Bit DaemonSet → CloudWatch Log Groups
```
- Deploy `aws-for-fluent-bit` Helm chart as a DaemonSet
- Separate log groups per service: `/supabase/rest`, `/supabase/auth`, `/supabase/storage`
- CloudWatch Log Insights for ad-hoc queries
- CloudWatch Metric Filters to create metrics from log patterns (error rates, slow queries)

**Alerting:**
- CloudWatch Alarms on pod CPU > 85%, database connections > 80% of max, ALB 5xx error rate > 1%
- SNS topic → PagerDuty/Slack notifications

**Distributed Tracing:**
- AWS X-Ray for request tracing across Supabase microservices
- X-Ray daemon as a sidecar container in each pod

---

## Challenges & Learnings

### 1. Supabase Helm Chart — `environment` vs `deployment` Value Structure

The community Supabase Helm chart has a non-obvious values structure. Database connection environment variables must be set under `environment.<service>.DB_HOST`, not `<service>.environment.DB_HOST`. This caused all database-dependent pods to fail on first deployment.

Additionally, the chart has HPA configuration values in `autoscaling.*` that appear functional but are actually dead code — the chart contains no HPA template. HPAs must be added as custom templates in a wrapper chart (which is what `helm/supabase-stack/` provides).

### 2. Realtime HPA — Stateful WebSocket Connections

The task requires HPA on Realtime. After investigation this was deliberately not implemented:

Supabase Realtime is a Phoenix/Elixir WebSocket server. Each client maintains a persistent connection to a specific pod. When HPA scales from 1 to 2 Realtime pods:
- Existing connections remain on pod-1
- New connections go to pod-2
- Both pods try to consume the same Postgres WAL replication slot → conflict
- Presence (online user tracking) splits across pods → incorrect user counts
- Broadcast messages sent to pod-1 never reach clients on pod-2

The correct solution is enabling Erlang distributed clustering via `DNS_NODES` environment variable, which allows multiple Realtime pods to form a distributed cluster and share connection state. This is documented as a future improvement.

### 3. Aurora PostgreSQL Bootstrap — Chicken and Egg Problem

Supabase requires specific PostgreSQL roles, schemas, and extensions to exist before the application pods can start. Standard Aurora has no built-in mechanism to run initialization SQL on creation.

**Solution:** The `cyrilgdn/postgresql` Terraform provider runs the bootstrap SQL (role creation, schema creation, extension installation, grant assignments) directly from Terraform during the `terraform apply` run. This requires network access to the Aurora endpoint — meaning Terraform must be run from within the VPC or via a VPN/bastion. This is documented as a prerequisite.

### 4. Karpenter Discovery Tags

Karpenter requires the `"karpenter.sh/discovery" = cluster_name` tag on three resources: private subnets, the node security group, and the EKS cluster itself. Missing the cluster tag causes Karpenter to install successfully but silently fail to provision nodes — pending pods remain pending indefinitely with no obvious error.

### 5. IaC Tool Choice Trade-offs

Plain Terraform HCL was chosen over CDKTF/Pulumi. The trade-off is that HCL lacks the expressiveness of a general-purpose language — loops and conditionals are more verbose. For example, creating resources for multiple availability zones requires `count` or `for_each` rather than a simple `for` loop. This verbosity was accepted in exchange for the clarity and auditability that HCL's declarative structure provides.

---

## Future Improvements

### High Priority

1. **Realtime Horizontal Scaling**
   Enable Erlang distributed clustering for the Realtime service:
   ```yaml
   environment:
     realtime:
       DNS_NODES: "supabase-realtime-headless.supabase.svc.cluster.local"
   ```
   This allows multiple Realtime pods to share WebSocket connection state.

2. **HTTPS / TLS Termination**
   Add AWS Certificate Manager (ACM) certificate and Route53 hosted zone:
   ```hcl
   resource "aws_acm_certificate" "supabase" {
     domain_name = var.supabase_domain
     validation_method = "DNS"
   }
   ```
   Then annotate the Ingress with `alb.ingress.kubernetes.io/certificate-arn`.

3. **Route53 DNS**
   Automate DNS record creation pointing your domain to the ALB:
   ```hcl
   resource "aws_route53_record" "supabase" {
     zone_id = var.hosted_zone_id
     name    = var.supabase_domain
     type    = "CNAME"
     records = [kubernetes_ingress_v1.supabase.status[0].load_balancer[0].ingress[0].hostname]
   }
   ```

### Medium Priority

4. **Multi-Region HA via Aurora Global Database**
   For true regional failover, promote the Aurora cluster to a Global Database with a secondary region. Combined with Route53 health-check-based failover, this achieves RPO < 1 second and RTO < 1 minute.

5. **Prometheus + Grafana Monitoring**
   Deploy `kube-prometheus-stack` with pre-built dashboards for EKS, Aurora, and Supabase service metrics.

6. **Fluent Bit Log Aggregation**
   Deploy `aws-for-fluent-bit` as a DaemonSet to ship pod logs to CloudWatch Log Groups with per-service log groups and metric filters.

7. **Vector PVC for Log Buffering**
   The Vector log aggregator (used by Supabase Analytics) benefits from a PVC for buffering logs during high-throughput periods. A 10Gi `gp3` EBS volume prevents log loss during analytics service restarts.

8. **Spot Instance Optimization for Dev/SIT**
   Configure Karpenter NodePool to prefer Spot instances in dev and sit environments:
   ```yaml
   requirements:
     - key: karpenter.sh/capacity-type
       operator: In
       values: ["spot"]  # On-Demand only in prod
   ```

### Low Priority

9. **Aurora Parameter Group Customization**
   Create a custom Aurora parameter group with tuned settings:
   - `log_min_duration_statement = 1000` (log slow queries > 1s)
   - `shared_preload_libraries = pg_stat_statements,pgvector`
   - `max_connections = 200` (sized for PgBouncer pooling)

10. **S3 HTTPS-Only Bucket Policy**
    Enforce HTTPS-only access to the storage bucket:
    ```hcl
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
    Effect = "Deny"
    ```

11. **Aurora Global Database for Multi-Region**
    See point 4 above.

12. **WAF Integration**
    Attach an AWS WAF Web ACL to the ALB for DDoS protection and OWASP rule sets.

13. **Bootstrap Secret Auto-Generation**
    Extend the bootstrap script to auto-generate all secrets including JWT keys using the `jsonwebtoken` Node.js library, eliminating the need for external tools and making the initial setup fully self-contained.

---

## Cost Estimates

> **⚠️ Pricing Disclaimer:** All costs are On-Demand rates for **us-east-1 (N. Virginia)** region, verified in **March 2026**. AWS pricing changes over time and varies by region — always verify current rates at [aws.amazon.com/pricing](https://aws.amazon.com/pricing) or use the [AWS Pricing Calculator](https://calculator.aws) before making financial decisions. Prices in other regions (e.g., eu-west-1, ap-southeast-1) are typically 10-20% higher.

### Per-Environment Monthly Cost

| Resource | Instance Type | Rate | Dev | SIT | Prod |
|----------|--------------|------|-----|-----|------|
| EKS Control Plane | — | $0.10/hr | $73 | $73 | $73 |
| EC2 Nodes | t3.small x1 | $0.0208/hr | $15 | — | — |
| EC2 Nodes | t3.medium x2 | $0.0416/hr | — | $61 | $61 |
| Aurora DB | db.t4g.medium x1 | $0.065/hr | $47 | — | — |
| Aurora DB | db.r6g.large x2 | $0.225/hr | — | $329 | $329 |
| NAT Gateway | 1 AZ / 2 AZs | $0.045/hr | $33 | $66 | $66 |
| ALB | — | $0.0225/hr | $20 | $20 | $20 |
| S3 + Secrets Manager | — | usage-based | $5 | $5 | $8 |
| CloudWatch Logs | 30-day retention | $0.50/GB | $2 | $3 | $5 |
| **Total (On-Demand)** | | | **~$195** | **~$557** | **~$562** |

> **Note on Aurora costs:** The `db.r6g.large` is $0.225/hr per instance. With a primary + replica (Multi-AZ), that's $0.45/hr = $329/month for compute alone, plus ~$10-20/month for storage and I/O depending on workload. This is the largest cost driver in SIT and Prod environments.

### Cost Optimization Strategies

**Karpenter Consolidation:**
Karpenter continuously consolidates underutilized nodes. During off-peak hours (nights/weekends), the cluster may run on 1 node instead of the desired 2, saving ~$30-60/month in EC2 costs.

**Dev/SIT Scheduled Shutdown:**
For further savings, scale down dev and sit clusters outside business hours using a scheduled Karpenter NodePool disruption budget. Running SIT only 8hrs/day on weekdays reduces EC2 costs by ~75%.

**Spot Instances:**
Enabling Spot instances in dev/SIT reduces EC2 costs by ~70%. For example, `t3.medium` Spot is ~$0.012/hr vs $0.042/hr On-Demand — saving ~$44/month per 2-node group.

**Reserved Instances for Aurora:**
A 1-year Aurora Reserved Instance for `db.r6g.large` saves ~40% (~$131/month per instance). For stable production workloads this is the single highest-impact cost optimization available.

**Teardown:**
When not actively using an environment, run `terraform/teardown.sh <env> us-east-1` to destroy all resources. The S3 state bucket costs less than $1/month to maintain between deployments.

> **Note:** CloudWatch log retention is set to 30 days. Without this, EKS control plane logs accumulate indefinitely at $0.50/GB/month. The 30-day retention policy automatically purges old logs and caps ongoing log storage costs.

---

## Repository Structure

```
supabase-infra/
├── .github/
│   └── workflows/
│       ├── terraform.yml      # Multi-env CI/CD: plan on PR, apply on merge
│       └── helm-lint.yml      # Helm chart validation
├── docs/
│   └── aurora-bootstrap-reference.md  # Aurora DB initialization reference
├── helm/
│   └── supabase-stack/        # Wrapper Helm chart
│       ├── Chart.yaml         # Depends on supabase/supabase v0.5.2
│       ├── values.yaml        # Local/dev values (NGINX ingress)
│       └── templates/
│           ├── hpa-*.yaml     # HPAs for rest, auth, storage, functions, imgproxy
│           └── ingress.yaml   # Ingress resource
├── k8s/
│   ├── eso/
│   │   └── external-secret.yaml   # ESO ExternalSecret manifest
│   └── network-policies/          # 12 NetworkPolicy manifests
├── terraform/
│   ├── bootstrap.sh           # One-time S3 state bucket setup
│   ├── teardown.sh            # Environment teardown script
│   ├── environments/
│   │   ├── dev/               # Development: t3.small, 1 node, 1-day backup
│   │   ├── sit/               # SIT: t3.medium, 2 nodes, 7-day backup
│   │   └── prod/              # Production: t3.medium, 2-6 nodes, 7-day backup
│   └── modules/
│       ├── eks/               # EKS cluster, Karpenter, ALB controller, IRSA
│       ├── networking/        # VPC, subnets, NAT gateways, route tables
│       ├── observability/     # CloudWatch log groups + ready for Prometheus/Grafana/Fluent Bit
│       ├── rds/               # Aurora PostgreSQL, DB bootstrap via TF provider
│       ├── s3/                # Storage bucket, encryption, lifecycle rules
│       ├── secrets/           # Secrets Manager, KMS, ESO IAM policy
│       └── supabase/          # Helm release, ESO manifests, NetworkPolicies
└── README.md
```

The `observability` module currently provisions CloudWatch log groups for EKS control plane and application logs with 30-day retention. It is structured to be extended with Prometheus, Grafana, and Fluent Bit without touching any other module — see [Future Improvements](#future-improvements).
