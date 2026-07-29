variable "grafana_url" {
  description = "Grafana instance URL"
  type        = string
}

variable "prometheus_datasource_uid" {
  description = "UID of the VictoriaMetrics (Prometheus) datasource in Grafana"
  type        = string
}

# --- Appointment CloudFront edge (platform-infrastructure #826) -----------------
# The distribution, health check and IAM grant below are produced by the Pulumi half of
# #826 and do not exist yet. The alert rule groups in alerting-appointment-edge.tf are
# count-gated on the ID/ARN variables being non-empty, so until they are filled in no
# rule is created and nothing can fire NoData/Error against a resource that does not
# exist. appointment_origin_cert_arn is the exception in origin: that cert exists today
# (appointment-deploy created it), it just has to be looked up. All four are set
# together in one follow-up PR — see the checklist in that file's header.

variable "appointment_distribution_id" {
  description = "CloudFront distribution ID for the tb-dev appointment edge (created by platform-infrastructure PR #844). Also seeds the Distribution picker's default and filter regex on the cloudfront-edge dashboard. Empty string disables the CloudFront and viewer-cert rule groups."
  type        = string
  default     = ""
}

variable "appointment_health_check_id" {
  description = "Route53 health check ID for https://appointment.tb-dev.thunderbird.dev/ (created by the Pulumi half of platform-infrastructure #826). Empty string disables the synthetic-check rule group."
  type        = string
  default     = ""
}

variable "appointment_origin_cert_arn" {
  description = "Full ACM ARN of the certificate on the DEDICATED CloudFront ORIGIN Ingress (eu-central-1, appointment-origin-tb-dev, host appointment-origin.tb-dev.thunderbird.dev). This is the certificate in the CloudFront -> ALB TLS path, and it is a DIFFERENT object from the live PUBLIC Ingress cert d324b88c-… that alerting-appointment-edge.tf pins inline. It is minted by the AWS Load Balancer Controller from thunderbird/appointment-deploy, so the ARN is not knowable from this repo and must be looked up — step 0 of the checklist in that file's header. Empty string disables the origin-ALB cert-expiry rule group; a guessed value would query a non-existent dimension and, given no_data_state = \"Alerting\", fire permanently, so absent is preferred to wrong."
  type        = string
  default     = ""
}

variable "appointment_metrics_iam_granted" {
  description = "Whether the cross-account role mzla-tb-dev-grafana-cloudwatch has been granted cloudwatch:GetMetricData and cloudwatch:ListMetrics (Pulumi half of platform-infrastructure #826). While false, the appointment edge rules use exec_err_state = \"OK\" so the guaranteed AccessDenied does not notify Slack every interval. Set to true in the same follow-up PR that fills in the IDs, so that from then on an AccessDenied is surfaced as a real failure instead of read as healthy."
  type        = bool
  default     = false
}
