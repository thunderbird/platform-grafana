resource "grafana_folder" "thunderbird_platform" {
  title = "Thunderbird Platform"
}

resource "grafana_folder" "argocd" {
  title = "ArgoCD"
}

resource "grafana_folder" "aws" {
  title = "AWS"
}

resource "grafana_folder" "customer_health" {
  title = "Customer Health"
}

resource "grafana_folder" "database" {
  title = "Database"
}

resource "grafana_folder" "infrastructure" {
  title = "Infrastructure"
}

resource "grafana_folder" "kubernetes_infrastructure" {
  title = "Kubernetes Infrastructure"
}

resource "grafana_folder" "linkerd" {
  title = "Linkerd"
}

resource "grafana_folder" "victoriametrics" {
  title = "VictoriaMetrics"
}

resource "grafana_folder" "cost_management" {
  title = "Cost Management"
}
