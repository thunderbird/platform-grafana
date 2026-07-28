grafana_url               = "https://grafana.pi.thunderbird.net"
prometheus_datasource_uid = "P4169E866C3094E38"

# Appointment CloudFront edge (platform-infrastructure #826). Both IDs are produced
# by the Pulumi half of #826 and do not exist yet, so both are empty and the matching
# alert rule groups in alerting-appointment-edge.tf are not created. Filling these in
# is the one-line follow-up PR that arms the alerts once the edge is applied.
appointment_distribution_id = ""
appointment_health_check_id = ""
