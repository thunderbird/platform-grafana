# Kubernetes dashboards
resource "grafana_dashboard" "k8s_cluster_overview" {
  folder      = grafana_folder.kubernetes.id
  config_json = file("${path.module}/dashboards/kubernetes/cluster-overview.json")
}

resource "grafana_dashboard" "k8s_namespace_breakdown" {
  folder      = grafana_folder.kubernetes.id
  config_json = file("${path.module}/dashboards/kubernetes/namespace-breakdown.json")
}

resource "grafana_dashboard" "k8s_pod_container_resources" {
  folder      = grafana_folder.kubernetes.id
  config_json = file("${path.module}/dashboards/kubernetes/pod-container-resources.json")
}

resource "grafana_dashboard" "k8s_persistent_volumes" {
  folder      = grafana_folder.kubernetes.id
  config_json = file("${path.module}/dashboards/kubernetes/persistent-volumes.json")
}

resource "grafana_dashboard" "k8s_coredns" {
  folder      = grafana_folder.kubernetes.id
  config_json = file("${path.module}/dashboards/kubernetes/coredns.json")
}

# VictoriaMetrics dashboards
resource "grafana_dashboard" "vm_cluster_overview" {
  folder      = grafana_folder.victoriametrics.id
  config_json = file("${path.module}/dashboards/victoriametrics/cluster-overview.json")
}

resource "grafana_dashboard" "vm_vmagent" {
  folder      = grafana_folder.victoriametrics.id
  config_json = file("${path.module}/dashboards/victoriametrics/vmagent.json")
}

resource "grafana_dashboard" "vm_victorialogs" {
  folder      = grafana_folder.victoriametrics.id
  config_json = file("${path.module}/dashboards/victoriametrics/victorialogs.json")
}

# Traefik dashboards
resource "grafana_dashboard" "traefik_overview" {
  folder      = grafana_folder.traefik.id
  config_json = file("${path.module}/dashboards/traefik/traefik-overview.json")
}

# ArgoCD dashboards
resource "grafana_dashboard" "argocd_application_overview" {
  folder      = grafana_folder.argocd.id
  config_json = file("${path.module}/dashboards/argocd/application-overview.json")
}

resource "grafana_dashboard" "argocd_operational_overview" {
  folder      = grafana_folder.argocd.id
  config_json = file("${path.module}/dashboards/argocd/operational-overview.json")
}

# Teleport dashboards
resource "grafana_dashboard" "teleport_sessions_connections" {
  folder      = grafana_folder.teleport.id
  config_json = file("${path.module}/dashboards/teleport/sessions-connections.json")
}

resource "grafana_dashboard" "teleport_backend_audit" {
  folder      = grafana_folder.teleport.id
  config_json = file("${path.module}/dashboards/teleport/backend-audit.json")
}

# Keycloak dashboards
resource "grafana_dashboard" "keycloak_overview" {
  folder      = grafana_folder.keycloak.id
  config_json = file("${path.module}/dashboards/keycloak/keycloak-overview.json")
}

# Core Services dashboards
resource "grafana_dashboard" "external_secrets_operator" {
  folder      = grafana_folder.core_services.id
  config_json = file("${path.module}/dashboards/core-services/external-secrets-operator.json")
}

resource "grafana_dashboard" "external_dns" {
  folder      = grafana_folder.core_services.id
  config_json = file("${path.module}/dashboards/core-services/external-dns.json")
}

resource "grafana_dashboard" "cert_manager" {
  folder      = grafana_folder.core_services.id
  config_json = file("${path.module}/dashboards/core-services/cert-manager.json")
}

resource "grafana_dashboard" "aws_load_balancer_controller" {
  folder      = grafana_folder.core_services.id
  config_json = file("${path.module}/dashboards/core-services/aws-load-balancer-controller.json")
}

# Bitergia dashboards
resource "grafana_dashboard" "bitergia_infrastructure" {
  folder      = grafana_folder.bitergia.id
  config_json = file("${path.module}/dashboards/bitergia/infrastructure.json")
}
