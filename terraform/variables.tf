variable "grafana_url" {
  description = "Grafana instance URL"
  type        = string
}

variable "prometheus_datasource_uid" {
  description = "UID of the VictoriaMetrics (Prometheus) datasource in Grafana"
  type        = string
}

# --- Appointment CloudFront edge (platform-infrastructure #826) -----------------
# Both resources below are created by the Pulumi half of #826 and do not exist yet.
# The alert rule groups in alerting-appointment-edge.tf are count-gated on these
# being non-empty, so until they are filled in no rule is created and nothing can
# fire NoData/Error against a resource that does not exist.

variable "appointment_distribution_id" {
  description = "CloudFront distribution ID for the tb-dev appointment edge (created by platform-infrastructure PR #844). Empty string disables the CloudFront rule group."
  type        = string
  default     = ""
}

variable "appointment_health_check_id" {
  description = "Route53 health check ID for https://appointment.tb-dev.thunderbird.dev/ (created by the Pulumi half of platform-infrastructure #826). Empty string disables the synthetic-check rule group."
  type        = string
  default     = ""
}
