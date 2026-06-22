# euc1 warm-passive Keycloak HA — DR paging rules (platform-infrastructure #481 / #367).
#
# Grafana-native alert rules that query the CloudWatch datasource directly (the
# `grafana` IRSA role was granted cloudwatch:GetMetricData/ListMetrics in
# platform-infrastructure #568 so this datasource can read metrics, not just logs).
# This replaces the YACE/CloudWatch-exporter plan — no exporter needed.
#
#   - SSO primary health (Route53 HealthCheckStatus, us-east-1): severity=page
#     -> the pagerduty-platform-infra contact point (wake on-call to DECIDE
#     failover; euc1 promotion is a manual one-way step).
#   - euc1 RDS read-replica lag (ReplicaLag, eu-central-1): severity=ticket
#     -> falls through to the default receiver (non-paging; warm-passive lag is
#     not an active outage). A dedicated non-paging contact point is added in #559.
#
# Route53 HealthCheckStatus is published only in us-east-1; the euc1 ReplicaLag
# metric lives in eu-central-1 (the datasource default region), so the Route53
# query overrides region to us-east-1.

resource "grafana_rule_group" "euc1_federation_ha" {
  name               = "euc1-federation-ha-dr"
  folder_uid         = grafana_folder.keycloak.uid
  interval_seconds   = 60
  disable_provenance = true

  # --- SSO primary endpoint health (PAGE) ---
  rule {
    name           = "euc1: Keycloak SSO primary endpoint failing (Route53 health check)"
    condition      = "C"
    for            = "3m"
    no_data_state  = "NoData"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "keycloak"
    }
    annotations = {
      summary     = "sso.infra.thunderbird.net is failing its Route53 health check — primary Keycloak IdP may be down"
      description = "The Route53 health check for sso.infra.thunderbird.net (shared01) is reporting unhealthy. The production staff-SSO IdP may be down. Assess for failover to the euc1 warm-passive standby. Runbook: docs/keycloak-staff-sso.md '## Federation HA — DB failover' (platform-infrastructure). Step 0: confirm mzla.awsapps.com reachability before promoting."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/docs/keycloak-staff-sso.md"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_shared.uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_shared.uid }
        queryMode        = "Metrics"
        region           = "us-east-1"
        namespace        = "AWS/Route53"
        metricName       = "HealthCheckStatus"
        dimensions       = { HealthCheckId = "0c8be94d-7d83-4950-9e08-84920d5842fa" }
        statistic        = "Minimum"
        period           = "60"
        metricQueryType  = 0
        metricEditorMode = 0
        matchExact       = true
        id               = ""
        expression       = ""
      })
    }
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
          evaluator = { type = "lt", params = [1] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  # --- euc1 RDS read-replica lag (TICKET, non-paging) ---
  rule {
    name           = "euc1: Keycloak DB read-replica lag high"
    condition      = "C"
    for            = "15m"
    no_data_state  = "NoData"
    exec_err_state = "Error"
    labels = {
      severity = "ticket"
      cluster  = "mzla-eks-shared-euc01"
      service  = "keycloak"
    }
    annotations = {
      summary     = "euc1 Keycloak RDS read replica lag > 300s — RPO degrading"
      description = "mzla-keycloak-staff-euc1 (eu-central-1 cross-region read replica) ReplicaLag has exceeded 300s. This widens the data-loss window (RPO) on a failover promotion. Check the source DB write load and cross-region replication. Non-urgent while warm-passive."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/docs/keycloak-staff-sso.md"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_shared.uid
      relative_time_range {
        from = 900
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_shared.uid }
        queryMode        = "Metrics"
        region           = "eu-central-1"
        namespace        = "AWS/RDS"
        metricName       = "ReplicaLag"
        dimensions       = { DBInstanceIdentifier = "mzla-keycloak-staff-euc1" }
        statistic        = "Average"
        period           = "300"
        metricQueryType  = 0
        metricEditorMode = 0
        matchExact       = true
        id               = ""
        expression       = ""
      })
    }
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 900
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
    data {
      ref_id         = "C"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 900
        to   = 0
      }
      model = jsonencode({
        refId      = "C"
        type       = "threshold"
        expression = "B"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "gt", params = [300] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}
