resource "grafana_contact_point" "slack" {
  name               = "Slack"
  disable_provenance = true

  slack {
    url   = local.secrets["slack_webhook_url"]
    title = "[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}"
    text  = <<-EOT
      {{ range .Alerts }}
      *{{ .Labels.severity | toUpper }}* - {{ .Annotations.summary }}
      Namespace: {{ .Labels.namespace }}
      {{ if .Annotations.runbook_url }}<{{ .Annotations.runbook_url }}|Runbook>{{ end }}
      {{ end }}
    EOT
  }
}

resource "grafana_contact_point" "incidents_io" {
  name               = "incidents.io"
  disable_provenance = true

  webhook {
    url                       = local.secrets["incidents_io_url"]
    http_method               = "POST"
    authorization_scheme      = "Bearer"
    authorization_credentials = local.secrets["incidents_io_auth_header"]
  }
}

resource "grafana_contact_point" "email" {
  name               = "Email"
  disable_provenance = true

  email {
    addresses = var.alert_email_addresses
  }
}

resource "grafana_contact_point" "slack_and_email" {
  name               = "Slack + Email"
  disable_provenance = true

  slack {
    url   = local.secrets["slack_webhook_url"]
    title = "[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}"
    text  = <<-EOT
      {{ range .Alerts }}
      *{{ .Labels.severity | toUpper }}* - {{ .Annotations.summary }}
      Namespace: {{ .Labels.namespace }}
      {{ if .Annotations.runbook_url }}<{{ .Annotations.runbook_url }}|Runbook>{{ end }}
      {{ end }}
    EOT
  }

  email {
    addresses = var.alert_email_addresses
  }
}
