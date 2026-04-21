resource "grafana_rule_group" "customer_health" {
  name               = "Customer Health"
  folder_uid         = var.folder_uids.customer_health
  interval_seconds   = 60
  disable_provenance = true

  # Pod Restart Rate High
  rule {
    name      = "Customer Pod Restart Rate High"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "critical"
      category = "customer-health"
    }

    annotations = {
      summary = "Pod {{ $labels.pod }} in {{ $labels.namespace }} has restarted multiple times in 15 minutes"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 900
        to   = 0
      }

      model = jsonencode({
        expr          = "sum by (namespace, pod) (increase(kube_pod_container_status_restarts_total{namespace=~\"customer-.*\"}[15m])) > 3"
        instant       = true
        refId         = "A"
        intervalMs    = 1000
        maxDataPoints = 43200
      })
    }

    data {
      ref_id         = "B"
      datasource_uid = "__expr__"

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        conditions = [{
          evaluator = { params = [0], type = "gt" }
          operator  = { type = "and" }
          query     = { params = ["B"] }
          reducer   = { params = [], type = "last" }
          type      = "query"
        }]
        datasource = {
          type = "__expr__"
          uid  = "__expr__"
        }
        expression    = "A"
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "B"
        type          = "threshold"
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Error"
  }

  # Pod Not Ready
  rule {
    name      = "Customer Pod Not Ready"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "customer-health"
    }

    annotations = {
      summary = "Pod {{ $labels.pod }} in {{ $labels.namespace }} is not ready"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "kube_pod_status_ready{condition=\"true\", namespace=~\"customer-.*\"} == 0"
        instant       = true
        refId         = "A"
        intervalMs    = 1000
        maxDataPoints = 43200
      })
    }

    data {
      ref_id         = "B"
      datasource_uid = "__expr__"

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        conditions = [{
          evaluator = { params = [0], type = "gt" }
          operator  = { type = "and" }
          query     = { params = ["B"] }
          reducer   = { params = [], type = "last" }
          type      = "query"
        }]
        datasource = {
          type = "__expr__"
          uid  = "__expr__"
        }
        expression    = "A"
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "B"
        type          = "threshold"
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Error"
  }

  # High Error Rate (5xx)
  rule {
    name      = "Customer High Error Rate"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "critical"
      category = "customer-health"
    }

    annotations = {
      summary = "{{ $labels.deployment }} in {{ $labels.namespace }} has high error rate"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "sum by (namespace, deployment) (rate(http_requests_total{status=~\"5..\", namespace=~\"customer-.*\"}[5m])) / sum by (namespace, deployment) (rate(http_requests_total{namespace=~\"customer-.*\"}[5m])) > 0.05"
        instant       = true
        refId         = "A"
        intervalMs    = 1000
        maxDataPoints = 43200
      })
    }

    data {
      ref_id         = "B"
      datasource_uid = "__expr__"

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        conditions = [{
          evaluator = { params = [0], type = "gt" }
          operator  = { type = "and" }
          query     = { params = ["B"] }
          reducer   = { params = [], type = "last" }
          type      = "query"
        }]
        datasource = {
          type = "__expr__"
          uid  = "__expr__"
        }
        expression    = "A"
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "B"
        type          = "threshold"
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Error"
  }

  # High Latency (P99)
  rule {
    name      = "Customer High Latency P99"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "customer-health"
    }

    annotations = {
      summary = "{{ $labels.namespace }} P99 latency exceeds 2s threshold"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "histogram_quantile(0.99, sum by (namespace, le) (rate(http_request_duration_seconds_bucket{namespace=~\"customer-.*\"}[5m]))) > 2"
        instant       = true
        refId         = "A"
        intervalMs    = 1000
        maxDataPoints = 43200
      })
    }

    data {
      ref_id         = "B"
      datasource_uid = "__expr__"

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        conditions = [{
          evaluator = { params = [0], type = "gt" }
          operator  = { type = "and" }
          query     = { params = ["B"] }
          reducer   = { params = [], type = "last" }
          type      = "query"
        }]
        datasource = {
          type = "__expr__"
          uid  = "__expr__"
        }
        expression    = "A"
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "B"
        type          = "threshold"
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Error"
  }
}
