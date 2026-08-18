grafana_url               = "https://grafana.pi.thunderbird.net"
prometheus_datasource_uid = "P4169E866C3094E38"

# Appointment CloudFront edge (platform-infrastructure #826). The distribution and the
# health check are produced by the Pulumi half of #826 and do not exist yet, so both IDs
# are empty and the matching alert rule groups in alerting-appointment-edge.tf are not
# created at all. The IAM flag stays false until that same Pulumi half grants
# cloudwatch:GetMetricData and cloudwatch:ListMetrics on mzla-tb-dev-grafana-cloudwatch;
# while it is false, a datasource error reads as OK instead of notifying Slack every
# interval.
#
# appointment_origin_cert_arn is different in kind: that certificate exists TODAY (the
# AWS Load Balancer Controller minted it for the appointment-origin-tb-dev Ingress in
# appointment-deploy), it simply has to be looked up in 718959508124 / eu-central-1. It
# is empty here only because it could not be resolved from this repo without AWS
# credentials, and a guessed ARN would fire the rule permanently. It is the cert in the
# CloudFront -> ALB TLS path, so leaving it empty means that handshake has no expiry
# coverage — resolve it first. Setting all four is the follow-up PR that arms
# everything; the checklist is in the .tf header.
appointment_distribution_id     = ""
appointment_health_check_id     = ""
appointment_origin_cert_arn     = ""
appointment_metrics_iam_granted = false
