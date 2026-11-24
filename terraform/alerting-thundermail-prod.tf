# Thundermail (Stalwart) on mzla-eks-tb-prod01 (platform-infrastructure#1814).
#
# The first rules in this repo that query VictoriaLogs. Stalwart's Prometheus counters carry no
# labels, so anything per listener, per domain or per pod-lifecycle event comes from its logs.
#
# VictoriaLogs rules, two things to know before editing:
#   - queryType "stats" sends start/end from relative_time_range as well as `time`, and VictoriaLogs
#     applies that window to in(...) subqueries too. relative_time_range must be at least as long
#     as the longest _time filter in the query, or the subquery is clipped and the rule cannot fire.
#   - `| stats by (...)` returns no rows when nothing matches, so no_data_state is OK. Missing logs
#     are not detected here; the scrape rule below covers Stalwart itself being gone.
#
# All rules are severity=warning: low-urgency PagerDuty -> Slack, no page.

locals {
  # VictoriaLogs datasource. Provisioned by the Grafana chart, not managed in this Terraform.
  victorialogs_ds_uid = "PD775F2863313E6C7"

  thundermail_prod_logs = "cluster:\"mzla-eks-tb-prod01\" namespace:\"thundermail\" container:\"stalwart\""

  # Both queries are instant and evaluate over their own _time filter.
  thundermail_prod_log_rules = {
    ThundermailProdLocalRecipientRejected = {
      # Excludes the port 25 listener rather than naming the submission listeners: JMAP submission
      # runs an internal SMTP session, so its log lines have no listenerId at all.
      expr      = <<-EOT
        _time:6h ${local.thundermail_prod_logs} "smtp.mailbox-does-not-exist" -"listenerId = \"smtp\"" | extract_regexp "to = \"[^\"@]*@(?P<rcpt_domain>[^\"]+)\"" | stats by (rcpt_domain) count() rejected
      EOT
      window    = 21600
      threshold = 2
      for       = "0s"
      summary   = "Stalwart rejected 3 or more recipients at {{ $labels.rcpt_domain }} from signed-in senders in 6h"
      detail    = "Over the last 6 hours Stalwart on tb-prod answered 'Mailbox does not exist' to signed-in senders (SMTP submission or JMAP) at least 3 times for recipients at {{ $labels.rcpt_domain }}. The message is never queued or retried. Check how {{ $labels.rcpt_domain }} is configured on each Stalwart pod directly, not through the load balancer; the linked issue has the steps. Mistyped recipients at a hosted domain can also trigger this."
    }
    ThundermailProdClusterCoordinatorNotRunning = {
      # Pods that logged in the last 10m and logged server.startup, but never cluster.subscriber-start.
      # 29d because VictoriaLogs keeps 30d. A pod older than that matches neither list: no alert.
      expr      = <<-EOT
        _time:10m ${local.thundermail_prod_logs} pod:in(_time:29d ${local.thundermail_prod_logs} "server.startup" | fields pod) -pod:in(_time:29d ${local.thundermail_prod_logs} "cluster.subscriber-start" | fields pod) | stats by (pod) count() log_lines
      EOT
      window    = 2505600
      threshold = 0
      for       = "15m"
      summary   = "Stalwart pod {{ $labels.pod }} is running without the cluster coordinator"
      detail    = "Pod {{ $labels.pod }} on tb-prod started but never logged cluster.subscriber-start. It does not receive directory changes made through another pod, so aliases, domains and accounts can differ between pods. The coordinator only starts at boot: check the Coordinator setting, then restart the pods one at a time and look for cluster.startup, cluster.publisher-start and cluster.subscriber-start in each startup log."
    }
  }

  thundermail_prod_metric_rules = {
    ThundermailProdClusterErrors = {
      # Stalwart 1.x renames counters to stalwart_*_total; match both so an upgrade does not silence this.
      expr      = "sum by (pod) (increase_pure({cluster=\"mzla-eks-tb-prod01\",namespace=\"thundermail\",__name__=~\"(stalwart_)?cluster_(subscriber_error|subscriber_disconnected|publisher_error)(_total)?\"}[15m]))"
      threshold = 0
      for       = "0s"
      no_data   = "OK"
      summary   = "Stalwart pod {{ $labels.pod }} reports cluster coordination errors"
      detail    = "Pod {{ $labels.pod }} on tb-prod counted cluster publish, subscribe or disconnect errors in the last 15 minutes. A publish error drops that batch of cache invalidations, so the other pod can keep stale domains, aliases or accounts. Check Redis (the coordinator backend) and the cluster.* lines in the pod's log."
    }
    ThundermailProdStalwartScrapeDown = {
      # `or vector(0)` makes a vanished target read as 0 instead of no data.
      expr      = "sum(up{cluster=\"mzla-eks-tb-prod01\",namespace=\"thundermail\",job=\"stalwart-mgmt\"}) or vector(0)"
      threshold = 1
      lt        = true
      for       = "10m"
      no_data   = "Alerting"
      summary   = "No Stalwart pod on tb-prod is being scraped"
      detail    = "No Stalwart metrics target on tb-prod has been up for 10 minutes. Either Stalwart is down or its metrics endpoint is off (Stalwart disables it when the stalwart-metrics-scrape Secret does not resolve). The cluster error rule cannot fire while this is firing."
    }
    ThundermailProdDeploymentUnavailable = {
      expr      = "count by (deployment) (kube_deployment_spec_replicas{cluster=\"mzla-eks-tb-prod01\",namespace=\"thundermail\"} > 0 and on (namespace, deployment) kube_deployment_status_replicas_available{cluster=\"mzla-eks-tb-prod01\",namespace=\"thundermail\"} == 0)"
      threshold = 0
      for       = "5m"
      no_data   = "OK"
      summary   = "thundermail/{{ $labels.deployment }} on tb-prod has 0 available replicas"
      detail    = "Deployment {{ $labels.deployment }} in namespace thundermail on mzla-eks-tb-prod01 wants at least one replica but has had none available for 5 minutes. Mail is down. Check pod events and container logs; a deliberate scale to zero does not match."
    }
  }
}

resource "grafana_rule_group" "thundermail_prod_logs" {
  name               = "thundermail-prod-logs"
  folder_uid         = grafana_folder.thundermail.uid
  interval_seconds   = 300
  disable_provenance = true

  dynamic "rule" {
    for_each = local.thundermail_prod_log_rules
    content {
      name           = rule.key
      condition      = "C"
      for            = rule.value.for
      no_data_state  = "OK"
      exec_err_state = "Error"
      labels = {
        severity = "warning"
        cluster  = "mzla-eks-tb-prod01"
        service  = "thundermail"
      }
      annotations = {
        summary     = rule.value.summary
        description = rule.value.detail
        runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1814"
      }

      data {
        ref_id         = "A"
        datasource_uid = local.victorialogs_ds_uid
        # Grafana copies the model's queryType here; unset, every plan shows a diff.
        query_type = "stats"
        relative_time_range {
          from = rule.value.window
          to   = 0
        }
        model = jsonencode({
          refId         = "A"
          datasource    = { type = "victoriametrics-logs-datasource", uid = local.victorialogs_ds_uid }
          editorMode    = "code"
          expr          = trimspace(rule.value.expr)
          queryType     = "stats"
          intervalMs    = 1000
          maxDataPoints = 43200
        })
      }
      data {
        ref_id         = "B"
        datasource_uid = "__expr__"
        relative_time_range {
          from = rule.value.window
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
          from = rule.value.window
          to   = 0
        }
        model = jsonencode({
          refId      = "C"
          type       = "threshold"
          expression = "B"
          datasource = { type = "__expr__", uid = "__expr__" }
          conditions = [{
            type      = "query"
            evaluator = { type = "gt", params = [rule.value.threshold] }
            operator  = { type = "and" }
            query     = { params = ["C"] }
            reducer   = { type = "last", params = [] }
          }]
        })
      }
    }
  }
}

resource "grafana_rule_group" "thundermail_prod" {
  name               = "thundermail-prod"
  folder_uid         = grafana_folder.thundermail.uid
  interval_seconds   = 60
  disable_provenance = true

  dynamic "rule" {
    for_each = local.thundermail_prod_metric_rules
    content {
      name           = rule.key
      condition      = "C"
      for            = rule.value.for
      no_data_state  = rule.value.no_data
      exec_err_state = "Error"
      labels = {
        severity = "warning"
        cluster  = "mzla-eks-tb-prod01"
        service  = "thundermail"
      }
      annotations = {
        summary     = rule.value.summary
        description = rule.value.detail
        runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1814"
      }

      data {
        ref_id         = "A"
        datasource_uid = var.prometheus_datasource_uid
        relative_time_range {
          from = 900
          to   = 0
        }
        model = jsonencode({
          refId         = "A"
          datasource    = { type = "prometheus", uid = var.prometheus_datasource_uid }
          expr          = rule.value.expr
          instant       = true
          intervalMs    = 1000
          maxDataPoints = 43200
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
            evaluator = { type = lookup(rule.value, "lt", false) ? "lt" : "gt", params = [rule.value.threshold] }
            operator  = { type = "and" }
            query     = { params = ["C"] }
            reducer   = { type = "last", params = [] }
          }]
        })
      }
    }
  }
}
