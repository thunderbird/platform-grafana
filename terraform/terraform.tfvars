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
# appointment_origin_cert_arn and send_origin_cert_arn both pin the Pulumi-managed
# *.main.dev-thundermail.com wildcard (platform-infrastructure #1453) that both origin
# Ingresses use. It is the cert in the CloudFront -> ALB TLS path; the checklist is in
# the .tf header.
appointment_distribution_id     = "E23SXSLKOB1ULS"
appointment_health_check_id     = "c576809f-6068-4cf5-9101-ce4486648ee6"
appointment_origin_cert_arn     = "arn:aws:acm:eu-central-1:718959508124:certificate/474234d8-046c-44df-a25e-e3f35a631968"
appointment_metrics_iam_granted = true

# Send CloudFront edge (platform-infrastructure #1043). Every resource exists today
# (#895 distribution + MonitoringSubscription, #1489 viewer cert, #1453 origin wildcard,
# #1052 health check, #951/#1048 the CloudWatch grant), so every knob is pinned HERE
# rather than defaulted -- including send_metrics_iam_granted, whose variable defaults
# false so another environment cannot inherit a grant it does not have. Viewer cert in
# us-east-1, origin in eu-central-1 (host send-origin.main.dev-thundermail.com).
send_distribution_id     = "E1O1C4QY9LB2MO"
send_health_check_id     = "da628e81-e6ef-41fc-baa1-e48009de8682"
send_viewer_cert_arn     = "arn:aws:acm:us-east-1:718959508124:certificate/81c8b1f4-9a94-424e-8f10-eeb833142f84"
send_origin_cert_arn     = "arn:aws:acm:eu-central-1:718959508124:certificate/474234d8-046c-44df-a25e-e3f35a631968"
send_metrics_iam_granted = true

# AMO production edge (thunderbird/addons-server#394). false until the
# mzla-tb-legacy-grafana-cloudwatch role is created in 768512802988 -- see the IAM diff
# on grafana_data_source.cloudwatch_tb_legacy in datasources.tf, posted in the issue for
# Matthew's go. Until then every query in alerting-amo-edge.tf gets AccessDenied, read as
# exec_err_state = "OK" rather than paging Slack every interval.
amo_metrics_iam_granted = false

thundermail_stage_nlb_arn_suffix      = "net/stalwart-nginx-thundermail/9e5aa027ddc2e8a8"
thundermail_stage_metrics_iam_granted = false
