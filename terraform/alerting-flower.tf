# Celery/Flower monitoring alerts for accounts (thunderbird/platform-infrastructure#1093).
#
# vmalert on mzla-eks-workloads01 is notifier.blackhole -- it evaluates rules but
# delivers nowhere. Grafana is the only alerting path on this platform wired to
# PagerDuty, so these six rules live here rather than as VMRule CRDs, in the same
# grafana_folder.legacy_services folder as the Celery/Flower dashboard (#1092).
# Routing is the existing root policy in alerting.tf, unchanged: severity=critical
# matches the "page|critical" route -> pagerduty-platform-infra -> phone page;
# severity=warning matches the low-urgency route -> Slack #mzla-pages. No new
# contact points or policy changes.
#
# A/B/C pattern copied from alerting-converted-vmrules.tf: A runs the full instant
# PromQL expr against local.victoriametrics_ds_uid, B reduces it to its last value,
# C thresholds on `> 0` (the expr produced a matching series with a positive value).
#
# That pattern requires each A expr to evaluate to a POSITIVE number when firing and
# either 0 or empty otherwise -- a plain `metric == 0` filter does not do this: PromQL
# comparison operators without `bool` return the matched series UNCHANGED, so
# `up{...} == 0` firing still evaluates to literal 0, and 0 > 0 is false. Rules 1-3
# below use `== bool 0` (rule 5 uses `< bool 15`) so the comparison is coerced to a
# real 1/0 series instead of a value-preserving filter, matching the intent described
# in issue #1093. Rules 4 and 6 don't need this: their raw comparisons already keep a
# genuinely positive value (a staleness duration in seconds, a failure count) when
# they fire, so the untouched `> N` / `> 0` in the expr behaves correctly as-is.
#
# no_data_state per rule:
#   - Rules 1/2 (up == bool 0): the `up` series exists for as long as vmagent/VM has
#     the target configured, healthy or not, so NoData means the scrape config itself
#     is gone -- Alerting.
#   - Rules 3/4/5: NoData here means the exporter or its scrape is gone entirely,
#     which rules 1/2 already page on -- OK avoids a duplicate page for the same root
#     cause.
#   - Rule 6: increase() over a filtered counter selector legitimately returns empty
#     when zero critical failures occurred in the window, which is the normal state --
#     MUST be OK or this pages continuously.
# exec_err_state = "Error" on every rule (a real query failure is never expected
# behavior and should always surface).

resource "grafana_rule_group" "accounts_celery_flower" {
  name               = "accounts-celery-flower"
  folder_uid         = grafana_folder.legacy_services.uid
  interval_seconds   = 60
  disable_provenance = true

  # --- Flower native /metrics not scraped ---
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

  # --- Flower exporter pod not scraped ---
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

  # --- Exporter up but its polls of Flower's REST API are failing ---
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

  # --- Exporter scrape loop stalled ---
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

  # --- Reported worker count below baseline ---
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

    # `< bool 15` (not a plain `< 15` filter) so a total outage -- worker count at
    # exactly 0 -- still evaluates to a real 1, not the value-preserving 0 a bare
    # filter would keep; see the file header for why this matters for the C threshold.
    # `or vector(0)` guards a second, worse gap: if NO workers are registered at all,
    # flower_worker_online has zero series, so sum() over it is itself empty -- not
    # 0 -- and `< bool 15` on an empty input is still empty. That would go to NoData,
    # which this rule maps to OK (see the file header), leaving total worker loss
    # silent. `or vector(0)` substitutes a literal 0 whenever the sum side is empty,
    # so the `< bool 15` always has a real input to evaluate.
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

  # --- Critical-classified task failure ---
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

    # The severity="critical" selector inside this PromQL expr is the exporter's own
    # task-classification label (from exporter/severity.yml), unrelated to the
    # Grafana `labels.severity = "critical"` above that drives PagerDuty routing --
    # same name, two different label namespaces.
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
