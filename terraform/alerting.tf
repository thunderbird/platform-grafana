# Grafana alerting -> PagerDuty (issues 136 / 80).
# Native PagerDuty contact point (Events API v2). Routing key from Secrets
# Manager; never committed. NOTE: the key WILL be written to Terraform state
# in plaintext (state bucket is SSE-KMS + locked down -- accepted risk).

data "aws_secretsmanager_secret_version" "pagerduty_routing_key" {
  secret_id = "mzla/shared-services/pagerduty-routing-key"
}

locals {
  # sensitive() so the value renders as (sensitive value) anywhere it surfaces.
  pagerduty_routing_key = sensitive(data.aws_secretsmanager_secret_version.pagerduty_routing_key.secret_string)
}

resource "grafana_contact_point" "pagerduty_platform_infra" {
  name = "pagerduty-platform-infra"

  # TF-provisioned alerting resources are otherwise read-only in the UI and can
  # error on re-apply; disable_provenance keeps them editable/idempotent.
  disable_provenance = true

  pagerduty {
    integration_key = local.pagerduty_routing_key
    severity        = "critical"
    class           = "grafana-alert"
    component       = "platform-infra"
    summary         = "{{ template \"default.message\" . }}"
    # Resolved events are sent by default (disable_resolve_message defaults to
    # false), so PD incidents auto-resolve when the alert clears.
  }
}

# NOTE: grafana_notification_policy is a per-org SINGLETON managing the root
# tree. It MUST be `terraform import`ed before the first apply, otherwise a
# clean "create" plan silently overwrites any UI-managed routing (and revert
# does not restore it). See the plan's Blocker B3 / Task 6 Step 1:
#   terraform import grafana_notification_policy.root "policy"
# Reproduce any imported UI child routes ABOVE the PagerDuty route below, and
# set contact_point to the actual live default observed from the import.
resource "grafana_notification_policy" "root" {
  disable_provenance = true

  # Match the live root ordering ([grafana_folder, alertname]) and default
  # receiver exactly, so the apply only ADDS the PagerDuty child route below.
  # Snapshot 2026-06-16: root = grafana-default-email, no child routes.
  group_by      = ["grafana_folder", "alertname"]
  contact_point = "grafana-default-email"

  group_wait      = "30s"
  group_interval  = "5m"
  repeat_interval = "4h"

  policy {
    contact_point = grafana_contact_point.pagerduty_platform_infra.name
    group_by      = ["alertname"]
    continue      = false

    # Grafana auto-anchors regex matchers to ^(?:...)$ -- this matches EXACTLY
    # "page" or "critical", not substrings. Do NOT "fix" this to .*page.*
    matcher {
      label = "severity"
      match = "=~"
      value = "page|critical"
    }
  }
}
