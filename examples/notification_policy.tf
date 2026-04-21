resource "grafana_notification_policy" "main" {
  disable_provenance = true
  contact_point      = grafana_contact_point.slack.name
  group_by           = ["alertname", "namespace"]
  group_wait         = "30s"
  group_interval     = "5m"
  repeat_interval    = "4h"

  # Linkerd alerts -> Slack only
  policy {
    contact_point = grafana_contact_point.slack.name
    continue      = false

    matcher {
      label = "category"
      match = "="
      value = "linkerd"
    }
  }

  # Database alerts -> Slack + Email
  policy {
    contact_point = grafana_contact_point.slack_and_email.name
    continue      = false

    matcher {
      label = "category"
      match = "="
      value = "database"
    }
  }
}
