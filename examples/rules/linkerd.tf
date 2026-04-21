resource "grafana_rule_group" "linkerd" {
  name               = "Linkerd"
  folder_uid         = var.folder_uids.linkerd
  interval_seconds   = 60
  disable_provenance = true

  # Success Rate Low
  rule {
    name      = "Linkerd Success Rate Low"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "linkerd"
    }

    annotations = {
      summary = "{{ $labels.deployment }} success rate below 95%"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 1800
        to   = 0
      }

      model = jsonencode({
        expr          = "(sum by (namespace, deployment) (rate(response_total{classification=\"success\", namespace=~\"customer-.*\"}[15m])) / sum by (namespace, deployment) (rate(response_total{namespace=~\"customer-.*\"}[15m])) < 0.95) and (sum by (namespace, deployment) (rate(response_total{namespace=~\"customer-.*\"}[15m])) > 0.5)"
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

  # P99 Latency High (excludes autopilot which has higher expected latency due to AI calls)
  rule {
    name      = "Linkerd P99 Latency High"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "linkerd"
    }

    annotations = {
      summary = "{{ $labels.deployment }} P99 latency exceeds 500ms"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "histogram_quantile(0.99, sum by (namespace, deployment, le) (rate(response_latency_ms_bucket{namespace=~\"customer-.*\", deployment!~\".*autopilot.*\"}[5m]))) > 500"
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

  # P99 Latency High - Autopilot (higher threshold for AI endpoint calls)
  rule {
    name      = "Linkerd P99 Latency High - Autopilot"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "linkerd"
    }

    annotations = {
      summary = "{{ $labels.deployment }} P99 latency exceeds 20000ms"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "histogram_quantile(0.99, sum by (namespace, deployment, le) (rate(response_latency_ms_bucket{namespace=~\"customer-.*\", deployment=~\".*autopilot.*\"}[5m]))) > 20000"
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

  # Control Plane Down
  rule {
    name      = "Linkerd Control Plane Down"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "critical"
      category = "linkerd"
    }

    annotations = {
      summary     = "Linkerd control plane is not running - sidecar injection will fail"

    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "sum(up{job=\"linkerd-proxy\", namespace=\"linkerd\"}) == 0 OR absent(up{job=\"linkerd-proxy\", namespace=\"linkerd\"})"
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

  # Control Plane Pod Not Ready
  rule {
    name      = "Linkerd Control Plane Pod Not Ready"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "critical"
      category = "linkerd"
    }

    annotations = {
      summary     = "Linkerd control plane pod {{ $labels.pod }} is not ready"

    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "kube_pod_status_ready{namespace=\"linkerd\", condition=\"true\"} == 0"
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

  # Customer Pod Missing Sidecar
  rule {
    name      = "Customer Pod Missing Linkerd Sidecar"
    condition = "B"
    for       = "15m"

    labels = {
      severity = "warning"
      category = "linkerd"
    }

    annotations = {
      summary     = "Pod {{ $labels.pod }} in {{ $labels.namespace }} is missing linkerd-proxy sidecar"

    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 900
        to   = 0
      }

      model = jsonencode({
        expr          = <<-EOT
          (
            kube_pod_status_phase{namespace=~"customer-.*", phase="Running"} == 1
            unless on(namespace, pod)
            kube_pod_container_info{namespace=~"customer-.*", container="linkerd-proxy"}
          )
          unless on(namespace, pod)
          kube_pod_labels{namespace=~"customer-.*", label_cnpg_io_cluster!=""}
          unless on(namespace, pod)
          kube_pod_labels{namespace=~"customer-.*", label_cnpg_io_poolerName!=""}
          unless on(namespace, pod)
          kube_pod_labels{namespace=~"customer-.*", label_job_name!=""}
        EOT
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

  # Webhook Certificate Expiring
  rule {
    name      = "Linkerd Webhook Certificate Expiring"
    condition = "B"
    for       = "1h"

    labels = {
      severity = "warning"
      category = "linkerd"
    }

    annotations = {
      summary     = "Linkerd webhook certificate {{ $labels.secret }} expires in less than 30 days"

    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 3600
        to   = 0
      }

      model = jsonencode({
        expr          = "certmanager_certificate_expiration_timestamp_seconds{namespace=\"linkerd\"} - time() < 30 * 24 * 3600"
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
