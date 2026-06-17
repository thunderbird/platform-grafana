# TEMPORARY: end-to-end PagerDuty paging test (issue 136). Remove immediately
# after verification -- this rule always fires and, with repeat_interval 4h on
# the root policy, will re-page on-call until deleted.
resource "grafana_folder" "alerting" {
  title = "Alerting"
}

resource "grafana_rule_group" "pagerduty_pipeline_test" {
  name               = "pagerduty-pipeline-test"
  folder_uid         = grafana_folder.alerting.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name      = "PagerDutyPipelineTest"
    condition = "C"

    # A: query vector(1) from the VictoriaMetrics datasource
    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = var.prometheus_datasource_uid }
        expr          = "vector(1)"
        instant       = true
        intervalMs    = 1000
        maxDataPoints = 43200
      })
    }

    # B: reduce A to a single number (expression datasource = "-100" in v4)
    data {
      ref_id         = "B"
      datasource_uid = "-100"
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId      = "B"
        type       = "reduce"
        datasource = { type = "__expr__", uid = "-100" }
        expression = "A"
        reducer    = "last"
      })
    }

    # C: threshold B > 0 (always true)
    data {
      ref_id         = "C"
      datasource_uid = "-100"
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId      = "C"
        type       = "threshold"
        datasource = { type = "__expr__", uid = "-100" }
        expression = "B"
        conditions = [{
          type      = "query"
          evaluator = { type = "gt", params = [0] }
        }]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Error"
    for            = "0s"

    labels = {
      severity = "page"
    }
    annotations = {
      summary     = "Synthetic PagerDuty pipeline test - safe to resolve"
      description = "Always-firing test verifying Grafana to PagerDuty Events API v2. Removed after verification (issue 136)."
    }
  }
}
