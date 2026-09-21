resource "grafana_folder" "kubernetes" {
  title = "Kubernetes"
}

resource "grafana_folder" "victoriametrics" {
  title = "VictoriaMetrics"
}

resource "grafana_folder" "traefik" {
  title = "Traefik"
}

resource "grafana_folder" "argocd" {
  title = "ArgoCD"
}

resource "grafana_folder" "teleport" {
  title = "Teleport"
}

resource "grafana_folder" "keycloak" {
  title = "Keycloak"
}

resource "grafana_folder" "core_services" {
  title = "Core Services"
}

resource "grafana_folder" "bitergia" {
  title = "Bitergia"
}

resource "grafana_folder" "twenty" {
  title = "Twenty"
}

resource "grafana_folder" "discourse" {
  title = "Discourse"
}

resource "grafana_folder" "appointment" {
  title = "Appointment"
}

resource "grafana_folder" "send" {
  title = "Send"
}

resource "grafana_folder" "amo" {
  title = "AMO"
}

# Scoped to services still on the legacy (pre-Kubernetes) deployment stack, as distinct
# from the folders above that belong to the new stack. Accounts is the first tenant here;
# send/thundermail/appointment can land their own Celery/Flower dashboards in this same
# folder later if they ever get equivalent monitoring on this exporter instance.
resource "grafana_folder" "legacy_services" {
  title = "Legacy Services"
}
