variable "prometheus_datasource_uid" {
  description = "UID of the Prometheus/VictoriaMetrics datasource in Grafana"
  type        = string
}

variable "folder_uids" {
  description = "Map of folder names to UIDs"
  type = object({
    thunderbird_platform = string
    argocd          = string
    customer_health = string
    database        = string
    infrastructure  = string
    linkerd         = string
  })
}
