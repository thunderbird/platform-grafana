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

resource "grafana_folder" "thundermail" {
  title = "Thundermail"
}

# Scoped to services still on the legacy (pre-Kubernetes) deployment stack, as distinct
# from the folders above that belong to the new stack. Accounts is the first tenant here;
# send/thundermail/appointment can land their own Celery/Flower dashboards in this same
# folder later if they ever get equivalent monitoring on this exporter instance.
resource "grafana_folder" "legacy_services" {
  title = "Legacy Services"
}

# UI-built developer dashboards; Terraform manages only the folder, never its dashboards.
# To stop managing it, replace this resource with a `removed` block (from = grafana_folder.developers) whose lifecycle sets destroy = false.
# Never set prevent_destroy_if_not_empty to false: that force-deletes the contents.
resource "grafana_folder" "developers" {
  title = "Developers"

  # Deleting a folder deletes its dashboards; refuse if anything is in it.
  prevent_destroy_if_not_empty = true
}
