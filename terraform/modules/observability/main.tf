# ==============================================================================
# Observability Module
# Centralizes all monitoring and logging infrastructure
#
# Currently implemented:
#   - CloudWatch Log Group for EKS control plane logs (30-day retention)
#
# Designed for extension — see commented sections below for:
#   - Prometheus + Grafana (kube-prometheus-stack)
#   - Fluent Bit log aggregation
#   - CloudWatch metric alarms
# ==============================================================================

# ------------------------------------------------------------------------------
# CloudWatch Log Group — EKS Control Plane
# Captures: api, audit, authenticator, controllerManager, scheduler logs
# Retention set to 30 days to prevent indefinite accumulation
# Without retention: logs accumulate at $0.50/GB/month indefinitely
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "eks_control_plane" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "/aws/eks/${var.cluster_name}/cluster"
  })

  lifecycle {
    ignore_changes = all
  }
}

# ------------------------------------------------------------------------------
# CloudWatch Log Group — Supabase Application Logs
# Placeholder for application-level log aggregation
# Populated by Fluent Bit DaemonSet (see future improvements)
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "supabase_app" {
  name              = "/supabase/${var.environment}/application"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "/supabase/${var.environment}/application"
  })
}

# ==============================================================================
# FUTURE IMPROVEMENTS — Uncomment to enable full observability stack
# ==============================================================================

# ------------------------------------------------------------------------------
# Prometheus + Grafana via kube-prometheus-stack Helm chart
# Provides: metrics collection, alerting, dashboards
#
# resource "helm_release" "kube_prometheus_stack" {
#   name             = "kube-prometheus-stack"
#   repository       = "https://prometheus-community.github.io/helm-charts"
#   chart            = "kube-prometheus-stack"
#   version          = "65.1.1"
#   namespace        = "monitoring"
#   create_namespace = true
#
#   set {
#     name  = "grafana.adminPassword"
#     value = var.grafana_admin_password
#   }
#
#   set {
#     name  = "prometheus.prometheusSpec.retention"
#     value = "15d"
#   }
#
#   set {
#     name  = "alertmanager.enabled"
#     value = "true"
#   }
#
#   depends_on = [var.eks_node_group_dependency]
# }
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Fluent Bit DaemonSet — Pod Log Aggregation to CloudWatch
# Ships stdout/stderr from all pods to CloudWatch Log Groups
#
# resource "helm_release" "fluent_bit" {
#   name             = "aws-for-fluent-bit"
#   repository       = "https://aws.github.io/eks-charts"
#   chart            = "aws-for-fluent-bit"
#   version          = "0.1.34"
#   namespace        = "logging"
#   create_namespace = true
#
#   set {
#     name  = "cloudWatch.region"
#     value = var.aws_region
#   }
#
#   set {
#     name  = "cloudWatch.logGroupName"
#     value = aws_cloudwatch_log_group.supabase_app.name
#   }
#
#   depends_on = [var.eks_node_group_dependency]
# }
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# CloudWatch Metric Alarms
# Alerts on key production health indicators
#
# resource "aws_cloudwatch_metric_alarm" "pod_cpu_high" {
#   alarm_name          = "${var.cluster_name}-pod-cpu-high"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = 2
#   metric_name         = "pod_cpu_utilization"
#   namespace           = "ContainerInsights"
#   period              = 300
#   statistic           = "Average"
#   threshold           = 85
#   alarm_description   = "Pod CPU utilization exceeds 85%"
#   alarm_actions       = [var.sns_alert_topic_arn]
# }
#
# resource "aws_cloudwatch_metric_alarm" "aurora_connections_high" {
#   alarm_name          = "${var.cluster_name}-aurora-connections-high"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = 2
#   metric_name         = "DatabaseConnections"
#   namespace           = "AWS/RDS"
#   period              = 300
#   statistic           = "Average"
#   threshold           = 160
#   alarm_description   = "Aurora connections exceeding 80% of max_connections=200"
#   alarm_actions       = [var.sns_alert_topic_arn]
# }
# ------------------------------------------------------------------------------
