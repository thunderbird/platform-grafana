# Thunderbird Platform dashboards
resource "grafana_dashboard" "customer_dashboard" {
  folder      = grafana_folder.thunderbird_platform.id
  config_json = file("${path.module}/dashboards/thunderbird-platform/customer-dashboard.json")
}

resource "grafana_dashboard" "customer_overview" {
  folder      = grafana_folder.thunderbird_platform.id
  config_json = file("${path.module}/dashboards/thunderbird-platform/customer-overview.json")
}

resource "grafana_dashboard" "global_security_graph" {
  folder      = grafana_folder.thunderbird_platform.id
  config_json = file("${path.module}/dashboards/thunderbird-platform/global-security-graph.json")
}

resource "grafana_dashboard" "tenant_deep_dive" {
  folder      = grafana_folder.thunderbird_platform.id
  config_json = file("${path.module}/dashboards/thunderbird-platform/tenant-deep-dive.json")
}

resource "grafana_dashboard" "fleet_overview" {
  folder      = grafana_folder.thunderbird_platform.id
  config_json = file("${path.module}/dashboards/thunderbird-platform/fleet-overview.json")
}

resource "grafana_dashboard" "nodejs_memory" {
  folder      = grafana_folder.thunderbird_platform.id
  config_json = file("${path.module}/dashboards/thunderbird-platform/nodejs-memory.json")
}

resource "grafana_dashboard" "workers_autopilot_operations" {
  folder      = grafana_folder.thunderbird_platform.id
  config_json = file("${path.module}/dashboards/thunderbird-platform/workers-autopilot-operations.json")
}

resource "grafana_dashboard" "connector_runs" {
  folder      = grafana_folder.thunderbird_platform.id
  config_json = file("${path.module}/dashboards/thunderbird-platform/connector-runs.json")
}

resource "grafana_dashboard" "housekeeping_jobs" {
  folder      = grafana_folder.thunderbird_platform.id
  config_json = file("${path.module}/dashboards/thunderbird-platform/housekeeping-jobs.json")
}

# ArgoCD dashboards
resource "grafana_dashboard" "argocd_application_overview" {
  folder      = grafana_folder.argocd.id
  config_json = file("${path.module}/dashboards/argocd/argocd-application-overview.json")
}

resource "grafana_dashboard" "argocd_operational_overview" {
  folder      = grafana_folder.argocd.id
  config_json = file("${path.module}/dashboards/argocd/argocd-operational-overview.json")
}

# AWS dashboards
resource "grafana_dashboard" "aws_ebs_volumes" {
  folder      = grafana_folder.aws.id
  config_json = file("${path.module}/dashboards/aws/aws-ebs-volumes.json")
}

resource "grafana_dashboard" "aws_ec2_instances" {
  folder      = grafana_folder.aws.id
  config_json = file("${path.module}/dashboards/aws/aws-ec2-instances.json")
}

resource "grafana_dashboard" "aws_ecs_services" {
  folder      = grafana_folder.aws.id
  config_json = file("${path.module}/dashboards/aws/aws-ecs-services.json")
}

resource "grafana_dashboard" "cloudwatch_exporter" {
  folder      = grafana_folder.aws.id
  config_json = file("${path.module}/dashboards/aws/cloudwatch-exporter.json")
}

resource "grafana_dashboard" "kubernetes_eks_cluster_prometheus" {
  folder      = grafana_folder.aws.id
  config_json = file("${path.module}/dashboards/aws/kubernetes-eks-cluster-prometheus.json")
}

resource "grafana_dashboard" "yace" {
  folder      = grafana_folder.aws.id
  config_json = file("${path.module}/dashboards/aws/yace.json")
}

# Database dashboards
resource "grafana_dashboard" "cloudnativepg" {
  folder      = grafana_folder.database.id
  config_json = file("${path.module}/dashboards/database/cloudnativepg.json")
  overwrite   = true
}

resource "grafana_dashboard" "cnpg_pooler_pgbouncer" {
  folder      = grafana_folder.database.id
  config_json = file("${path.module}/dashboards/database/cnpg-pooler-pgbouncer.json")
}

resource "grafana_dashboard" "rds_performance_insights" {
  folder      = grafana_folder.database.id
  config_json = file("${path.module}/dashboards/database/rds-performance-insights.json")
}

# General dashboards (root folder, no folder specified)
resource "grafana_dashboard" "argocd_general" {
  config_json = file("${path.module}/dashboards/general/argocd.json")
}

resource "grafana_dashboard" "victorialogs_explorer" {
  config_json = file("${path.module}/dashboards/general/victorialogs-explorer.json")
}

# Infrastructure dashboards
resource "grafana_dashboard" "litellm" {
  folder      = grafana_folder.infrastructure.id
  config_json = file("${path.module}/dashboards/infrastructure/litellm.json")
}

resource "grafana_dashboard" "keda" {
  folder      = grafana_folder.infrastructure.id
  config_json = file("${path.module}/dashboards/infrastructure/keda.json")
}

# Kubernetes Infrastructure dashboards
resource "grafana_dashboard" "cloudflare_tunnels_cloudflared" {
  folder      = grafana_folder.kubernetes_infrastructure.id
  config_json = file("${path.module}/dashboards/kubernetes-infrastructure/cloudflare-tunnels-cloudflared.json")
}

resource "grafana_dashboard" "k8s_dashboard" {
  folder      = grafana_folder.kubernetes_infrastructure.id
  config_json = file("${path.module}/dashboards/kubernetes-infrastructure/k8s-dashboard.json")
}

resource "grafana_dashboard" "kubernetes_views_global" {
  folder      = grafana_folder.kubernetes_infrastructure.id
  config_json = file("${path.module}/dashboards/kubernetes-infrastructure/kubernetes-views-global.json")
}

resource "grafana_dashboard" "kubernetes_views_namespaces" {
  folder      = grafana_folder.kubernetes_infrastructure.id
  config_json = file("${path.module}/dashboards/kubernetes-infrastructure/kubernetes-views-namespaces.json")
}

resource "grafana_dashboard" "kubernetes_views_nodes" {
  folder      = grafana_folder.kubernetes_infrastructure.id
  config_json = file("${path.module}/dashboards/kubernetes-infrastructure/kubernetes-views-nodes.json")
}

resource "grafana_dashboard" "kubernetes_views_pods" {
  folder      = grafana_folder.kubernetes_infrastructure.id
  config_json = file("${path.module}/dashboards/kubernetes-infrastructure/kubernetes-views-pods.json")
}

resource "grafana_dashboard" "traefik_2" {
  folder      = grafana_folder.kubernetes_infrastructure.id
  config_json = file("${path.module}/dashboards/kubernetes-infrastructure/traefik-2.json")
}

# Langfuse dashboards
resource "grafana_dashboard" "langfuse_llm_analytics" {
  folder      = grafana_folder.langfuse.id
  config_json = file("${path.module}/dashboards/langfuse/langfuse-llm-analytics.json")
}

# Linkerd dashboards
resource "grafana_dashboard" "linkerd_deployment" {
  folder      = grafana_folder.linkerd.id
  config_json = file("${path.module}/dashboards/linkerd/linkerd-deployment.json")
}

resource "grafana_dashboard" "linkerd_health" {
  folder      = grafana_folder.linkerd.id
  config_json = file("${path.module}/dashboards/linkerd/linkerd-health.json")
}

resource "grafana_dashboard" "linkerd_namespace" {
  folder      = grafana_folder.linkerd.id
  config_json = file("${path.module}/dashboards/linkerd/linkerd-namespace.json")
}

resource "grafana_dashboard" "linkerd_pod" {
  folder      = grafana_folder.linkerd.id
  config_json = file("${path.module}/dashboards/linkerd/linkerd-pod.json")
}

resource "grafana_dashboard" "linkerd_route" {
  folder      = grafana_folder.linkerd.id
  config_json = file("${path.module}/dashboards/linkerd/linkerd-route.json")
}

resource "grafana_dashboard" "linkerd_service" {
  folder      = grafana_folder.linkerd.id
  config_json = file("${path.module}/dashboards/linkerd/linkerd-service.json")
}

resource "grafana_dashboard" "linkerd_top_line" {
  folder      = grafana_folder.linkerd.id
  config_json = file("${path.module}/dashboards/linkerd/linkerd-top-line.json")
}

# VictoriaMetrics dashboards
resource "grafana_dashboard" "victoriametrics_cluster" {
  folder      = grafana_folder.victoriametrics.id
  config_json = file("${path.module}/dashboards/victoriametrics/victoriametrics-cluster.json")
}

resource "grafana_dashboard" "victoriametrics_operator" {
  folder      = grafana_folder.victoriametrics.id
  config_json = file("${path.module}/dashboards/victoriametrics/victoriametrics-operator.json")
}

resource "grafana_dashboard" "victoriametrics_vmagent" {
  folder      = grafana_folder.victoriametrics.id
  config_json = file("${path.module}/dashboards/victoriametrics/victoriametrics-vmagent.json")
}

resource "grafana_dashboard" "victoriametrics_vmalert" {
  folder      = grafana_folder.victoriametrics.id
  config_json = file("${path.module}/dashboards/victoriametrics/victoriametrics-vmalert.json")
}

# Cost Management dashboards
resource "grafana_dashboard" "tenant_infrastructure_costs" {
  folder      = grafana_folder.cost_management.id
  config_json = file("${path.module}/dashboards/cost-management/tenant-infrastructure-costs.json")
}
