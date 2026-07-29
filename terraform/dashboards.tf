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

resource "grafana_dashboard" "bamboohr_cal_sync" {
  folder      = grafana_folder.core_services.id
  config_json = file("${path.module}/dashboards/core-services/bamboohr-cal-sync.json")
}

resource "grafana_dashboard" "thundermail_ticket_spike_monitor" {
  folder      = grafana_folder.core_services.id
  config_json = file("${path.module}/dashboards/core-services/thundermail-ticket-spike-monitor.json")
}

# Bitergia dashboards
resource "grafana_dashboard" "bitergia_infrastructure" {
  folder      = grafana_folder.bitergia.id
  config_json = file("${path.module}/dashboards/bitergia/infrastructure.json")
}

# Twenty dashboards
resource "grafana_dashboard" "twenty_overview" {
  folder      = grafana_folder.twenty.id
  config_json = file("${path.module}/dashboards/twenty/overview.json")
}

# Discourse dashboards
resource "grafana_dashboard" "discourse_overview" {
  folder      = grafana_folder.discourse.id
  config_json = file("${path.module}/dashboards/discourse/overview.json")
}

# Appointment dashboards
#
# First dashboard in this repo that queries CloudWatch rather than VictoriaMetrics,
# and the first loaded with templatefile() rather than file(). Two values have to come
# from Terraform rather than be hand-copied into the JSON:
#
#   - cloudwatch_tb_dev_uid: grafana_data_source.cloudwatch_tb_dev does not set uid, so
#     the UID is server-assigned. Hardcoding it would mean a wrong character produces a
#     clean apply and six panels reading "Datasource ... was not found". The other
#     dashboards' P4169E866C3094E38 literal is not a precedent — that datasource is
#     pre-existing and unmanaged, this one is a managed resource with a computed .uid.
#   - appointment_distribution_id: seeds both the default value and the filter regex of
#     the Distribution picker, so the dashboard opens on the appointment distribution
#     (matching what the alert rules query) instead of whichever distribution the
#     dimension_values query happens to sort first. Empty leaves the picker unfiltered.
#
# Region is overridden to us-east-1 per query — see the header comment in
# alerting-appointment-edge.tf for why there is no separate us-east-1 datasource.
resource "grafana_dashboard" "appointment_cloudfront_edge" {
  folder = grafana_folder.appointment.id
  config_json = templatefile("${path.module}/dashboards/appointment/cloudfront-edge.json.tftpl", {
    cloudwatch_tb_dev_uid       = grafana_data_source.cloudwatch_tb_dev.uid
    appointment_distribution_id = var.appointment_distribution_id
  })
}
