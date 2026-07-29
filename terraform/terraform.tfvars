grafana_url               = "https://grafana.pi.thunderbird.net"
prometheus_datasource_uid = "P4169E866C3094E38"

# Appointment CloudFront edge (platform-infrastructure #826). The IDs are produced by
# the Pulumi half of #826 and do not exist yet, so both are empty and the matching
# alert rule groups in alerting-appointment-edge.tf are not created at all. The IAM
# flag stays false until that same Pulumi half grants cloudwatch:GetMetricData and
# cloudwatch:ListMetrics on mzla-tb-dev-grafana-cloudwatch; while it is false, a
# datasource error reads as OK instead of notifying Slack every interval. Setting all
# three is the follow-up PR that arms the alerts — checklist in the .tf header.
appointment_distribution_id     = ""
appointment_health_check_id     = ""
appointment_metrics_iam_granted = false
