variable "grafana_url" {
  description = "Grafana instance URL"
  type        = string
}

variable "prometheus_datasource_uid" {
  description = "UID of the VictoriaMetrics (Prometheus) datasource in Grafana"
  type        = string
}
