# Celery/Flower monitoring alerts for accounts (thunderbird/platform-infrastructure#1093),
# in the same grafana_folder.legacy_services folder as the dashboard (#1092). Routing
# uses the existing root policy in alerting.tf, unchanged: severity=critical pages,
# severity=warning goes to Slack via the low-urgency route. No new contact points or
# policy changes.
#
# Two PromQL quirks these rules rely on:
#   - A comparison without `bool` filters the series but keeps its original value, so
#     a firing `metric == 0` still evaluates to literal 0 (not true), and a `> 0`
#     threshold never trips; `== bool` / `< bool` coerce it to a real 1/0 instead.
#   - Rule 6's increase() over a filtered counter is empty in the normal, no-failures
#     case, so its no_data_state must be OK or it pages continuously.

resource "grafana_rule_group" "accounts_celery_flower" {
  name               = "accounts-celery-flower"
  folder_uid         = grafana_folder.legacy_services.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "FlowerNativeMetricsScrapeDown"
    condition      = "C"
    for            = "5m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity  = "critical"
      service   = "accounts"
      component = "celery-flower"
      cluster   = "mzla-eks-workloads01"
    }
    annotations = {
      summary     = "Flower's native /metrics is not being scraped from workloads01"
      description = "vmagent on workloads01 scrapes Flower's internal ALB over VPC peering; 0 for 5m means Flower is down or the peering/SG path broke."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1093"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.victoriametrics_ds_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = local.victoriametrics_ds_uid }
        expr          = "up{job=\"flower-native\"} == bool 0"
        instant       = true
        range         = false
        intervalMs    = 1000
        maxDataPoints = 43200
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
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  rule {
    name           = "FlowerExporterTargetDown"
    condition      = "C"
    for            = "5m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity  = "critical"
      service   = "accounts"
      component = "celery-flower"
      cluster   = "mzla-eks-workloads01"
    }
    annotations = {
      summary     = "celery-flower-monitor exporter pod is not being scraped"
      description = "The exporter pod is unreachable or not being scraped: check kubectl -n legacy-celery-flower-monitor get pods and the pod's own /metrics endpoint."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1093"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.victoriametrics_ds_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = local.victoriametrics_ds_uid }
        expr          = "up{namespace=\"legacy-celery-flower-monitor\", container=\"celery-flower-monitor\"} == bool 0"
        instant       = true
        range         = false
        intervalMs    = 1000
        maxDataPoints = 43200
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
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  rule {
    name           = "FlowerExporterUpstreamFetchFailing"
    condition      = "C"
    for            = "5m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity  = "warning"
      service   = "accounts"
      component = "celery-flower"
      cluster   = "mzla-eks-workloads01"
    }
    annotations = {
      summary     = "Flower exporter's polls of the Flower REST API are failing"
      description = "The exporter is up but every poll of Flower's REST API fails; task/severity data is stale. Check exporter logs and connectivity to the internal Flower ALB."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1093"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.victoriametrics_ds_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = local.victoriametrics_ds_uid }
        expr          = "flower_exporter_scrape_success{namespace=\"legacy-celery-flower-monitor\"} == bool 0"
        instant       = true
        range         = false
        intervalMs    = 1000
        maxDataPoints = 43200
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
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  rule {
    name           = "FlowerExporterScrapeStale"
    condition      = "C"
    for            = "1m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity  = "warning"
      service   = "accounts"
      component = "celery-flower"
      cluster   = "mzla-eks-workloads01"
    }
    annotations = {
      summary     = "Flower exporter scrape loop appears stalled"
      description = "No poll attempt has been recorded for over 2 minutes; the exporter's scrape loop may be hung. Check exporter liveness/logs."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1093"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.victoriametrics_ds_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = local.victoriametrics_ds_uid }
        expr          = "time() - flower_exporter_last_scrape_timestamp_seconds{namespace=\"legacy-celery-flower-monitor\"} > 120"
        instant       = true
        range         = false
        intervalMs    = 1000
        maxDataPoints = 43200
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
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  rule {
    name           = "FlowerWorkerCountLow"
    condition      = "C"
    for            = "5m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity  = "warning"
      service   = "accounts"
      component = "celery-flower"
      cluster   = "mzla-eks-workloads01"
    }
    annotations = {
      summary     = "Flower-reported Celery worker count is below baseline"
      description = "The observed baseline is 17 to 20 online workers (as of 2026-09-21); adjust the 15 threshold here if the fleet size changes intentionally."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1093"
    }

    # `or vector(0)`: with zero workers registered, sum() has no input and is empty
    # (not 0), so this substitutes a literal 0 to keep `< bool 15` evaluable.
    data {
      ref_id         = "A"
      datasource_uid = local.victoriametrics_ds_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = local.victoriametrics_ds_uid }
        expr          = "(sum(flower_worker_online{job=\"flower-native\"}) or vector(0)) < bool 15"
        instant       = true
        range         = false
        intervalMs    = 1000
        maxDataPoints = 43200
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
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  rule {
    name           = "FlowerCriticalTaskFailure"
    condition      = "C"
    for            = "1m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity  = "critical"
      service   = "accounts"
      component = "celery-flower"
      cluster   = "mzla-eks-workloads01"
    }
    annotations = {
      summary     = "A critical-classified Celery task failed"
      description = "A task classified critical in exporter/severity.yml (create_stalwart_account, paddle_subscription_event) failed in the last 10 minutes."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1093"
    }

    # severity="critical" in this expr is the exporter's own task-classification
    # label (exporter/severity.yml), not the Grafana routing label above.
    data {
      ref_id         = "A"
      datasource_uid = local.victoriametrics_ds_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = local.victoriametrics_ds_uid }
        expr          = "sum(increase(flower_task_state_transitions_total{namespace=\"legacy-celery-flower-monitor\", state=\"FAILURE\", severity=\"critical\"}[10m])) > 0"
        instant       = true
        range         = false
        intervalMs    = 1000
        maxDataPoints = 43200
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
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}
