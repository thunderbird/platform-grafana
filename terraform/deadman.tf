# Grafana alerting deadman heartbeat -> AWS-native watcher (issue 560).
#
# Closes the "no alerting self-monitoring / deadman" gap left open by the
# Grafana-native paging work. A heartbeat that STOPS is what pages: while the
# alerting stack is healthy this rule fires continuously and POSTs to the
# off-cluster AWS watcher; if Grafana, the ruler, the VictoriaMetrics datasource,
# or shared01 egress is down, the heartbeat stops and the watcher pages.
#
# Two parts, two failure domains:
#   - Grafana side (HERE): the heartbeat rule + webhook contact point + a nested
#     notification-policy route (added in alerting.tf, NOT re-created).
#   - AWS-native watcher: platform-infrastructure/pulumi/environments/grafana-deadman/
#     (mzla-shared/us-east-1, serverless, OFF the mzla-eks-shared01 cluster).
#
# Runbook: docs/observability.md "Alerting & Paging -> Deadman / self-monitoring"
# (platform-infrastructure).

# Webhook target URL + bearer token for the watcher's ingest endpoint. Named
# under the grafana-terraform* prefix so the Atlantis ECS task role can read it
# with NO IAM change (plan B2): the role scopes secretsmanager:GetSecretValue to
# mzla/shared-services/grafana-terraform* and mzla/shared-services/pagerduty-routing-key*.
# Populate this secret AFTER `pulumi up` of the grafana-deadman watcher, with the
# stack's ingest_url + ingest_token outputs:
#   {"url": "<ingest_url>", "token": "<ingest_token>"}
data "aws_secretsmanager_secret_version" "deadman_ingest" {
  secret_id = "mzla/shared-services/grafana-terraform-deadman-url"
}

locals {
  deadman_ingest = jsondecode(data.aws_secretsmanager_secret_version.deadman_ingest.secret_string)
}

# Webhook contact point: every heartbeat notification POSTs to the watcher's
# ingest Function URL with the shared bearer token in an Authorization header.
resource "grafana_contact_point" "deadman_ingest" {
  name = "deadman-ingest"

  # TF-provisioned alerting resources are otherwise read-only in the UI and can
  # error on re-apply; disable_provenance keeps them editable/idempotent.
  disable_provenance = true

  webhook {
    url         = local.deadman_ingest.url
    http_method = "POST"

    # Bearer token in the Authorization header so the URL alone is not the only
    # secret. The watcher's ingest Lambda compares it constant-time.
    authorization_scheme      = "Bearer"
    authorization_credentials = local.deadman_ingest.token
  }
}

# The heartbeat rule. condition C is `vector(1)` reduced + thresholded > 0, so
# it is ALWAYS firing while the chain is healthy.
#
# B1 (correctness): query A is executed AGAINST the VictoriaMetrics datasource
# by UID (var.prometheus_datasource_uid), NOT a pure in-process __expr__ node.
# Only a datasource-traversing query proves ruler + datasource + delivery. A
# wedged vmselect makes this query fail, which stops the heartbeat (intended;
# datasource-coupling is decided in the runbook: a vmselect outage trips the
# deadman as one undifferentiated page).
resource "grafana_rule_group" "deadman_heartbeat" {
  name             = "deadman-heartbeat"
  folder_uid       = grafana_folder.core_services.uid
  interval_seconds = 30 # evaluate ~every 30s

  disable_provenance = true

  rule {
    name           = "GrafanaAlertingDeadmanHeartbeat"
    condition      = "C"
    for            = "0s"
    no_data_state  = "OK"
    exec_err_state = "Error"

    labels = {
      # deadman=true selects the nested route in alerting.tf -> deadman-ingest.
      deadman = "true"
      # Deliberately NOT page|critical so it does NOT hit the real PD route.
      severity = "heartbeat"
    }
    annotations = {
      summary     = "Grafana alerting deadman heartbeat (always firing while healthy)"
      description = "Emits a heartbeat to the AWS-native deadman watcher every cycle. If this stops, the watcher pages on-call. Do NOT pause or delete this rule (issue 560). Runbook: docs/observability.md '## Alerting & Paging' -> Deadman."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/docs/observability.md#deadman--self-monitoring"
    }

    # A: a query EXECUTED AGAINST vmselect (proves the datasource path, B1).
    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid # the VictoriaMetrics UID
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId      = "A"
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        expr       = "vector(1)"
        instant    = true
      })
    }

    # B: reduce A to its last value.
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId      = "B"
        type       = "reduce"
        expression = "A"
        reducer    = "last"
        datasource = { type = "__expr__", uid = "__expr__" }
      })
    }

    # C: threshold > 0 (always true while the chain is healthy).
    data {
      ref_id         = "C"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId      = "C"
        type       = "threshold"
        expression = "B"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}
