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
