# Node.js Runtime Alert Rules
# Monitors heap memory, GC activity, and event loop health for
# backend, copilot, and autopilot services.
#
# Metrics exposed by @thunderbird/metrics library:
# - nodejs_heap_used_percent: Heap usage as % of max-old-space-size
# - nodejs_gc_duration_seconds: GC pause duration histogram
# - nodejs_eventloop_lag_p99_seconds: Event loop lag P99

resource "grafana_rule_group" "nodejs" {
  name               = "Node.js Runtime"
  folder_uid         = var.folder_uids.thunderbird_platform
  interval_seconds   = 60
  disable_provenance = true

  # Heap Usage Warning (85%)
  # Early warning before heap exhaustion. At 85%, GC pressure is
  # increasing and performance may degrade.
  rule {
    name      = "Node.js Heap Usage Warning"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "nodejs"
    }

    annotations = {
      summary     = "{{ $labels.namespace }}/{{ $labels.pod }} heap at 85%"
      description = "Node.js service is using 85%+ of configured heap. Consider increasing memory limits or investigating memory leaks."
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "nodejs_heap_used_percent{namespace=~\"customer-.*\"} > 85"
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

  # Heap Usage Critical (95%)
  # Imminent heap exhaustion. Service will crash with OOM if not addressed.
  rule {
    name      = "Node.js Heap Usage Critical"
    condition = "B"
    for       = "2m"

    labels = {
      severity = "critical"
      category = "nodejs"
    }

    annotations = {
      summary     = "{{ $labels.namespace }}/{{ $labels.pod }} heap at 95% - imminent OOM"
      description = "Node.js service is critically low on heap memory. Crash imminent. Check for memory leaks or increase container memory."
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = "nodejs_heap_used_percent{namespace=~\"customer-.*\"} > 95"
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

  # Event Loop Lag Warning (100ms P99)
  # Event loop blocked for >100ms indicates CPU-bound work or
  # synchronous operations blocking the main thread.
  rule {
    name      = "Node.js Event Loop Lag Warning"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "nodejs"
    }

    annotations = {
      summary     = "{{ $labels.namespace }}/{{ $labels.pod }} event loop lag >100ms"
      description = "Node.js event loop P99 latency exceeds 100ms. This indicates blocking operations or high CPU load affecting responsiveness."
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "nodejs_eventloop_lag_p99_seconds{namespace=~\"customer-.*\"} > 0.1"
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

  # Event Loop Lag Critical (500ms P99)
  # Severe event loop blocking. Service is effectively unresponsive.
  rule {
    name      = "Node.js Event Loop Lag Critical"
    condition = "B"
    for       = "2m"

    labels = {
      severity = "critical"
      category = "nodejs"
    }

    annotations = {
      summary     = "{{ $labels.namespace }}/{{ $labels.pod }} event loop lag >500ms - service unresponsive"
      description = "Node.js event loop P99 latency exceeds 500ms. Service is effectively unresponsive. Investigate CPU-bound operations or infinite loops."
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = "nodejs_eventloop_lag_p99_seconds{namespace=~\"customer-.*\"} > 0.5"
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

  # Major GC Duration High
  # Frequent long major GCs indicate memory pressure. Major GCs
  # pause the entire application (stop-the-world).
  rule {
    name      = "Node.js Major GC Duration High"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "nodejs"
    }

    annotations = {
      summary     = "{{ $labels.namespace }}/{{ $labels.pod }} major GC pauses >500ms avg"
      description = "Average major GC pause duration exceeds 500ms. This causes noticeable application pauses and request latency spikes."
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "rate(nodejs_gc_duration_seconds_sum{gc_type=\"major\", namespace=~\"customer-.*\"}[5m]) / rate(nodejs_gc_duration_seconds_count{gc_type=\"major\", namespace=~\"customer-.*\"}[5m]) > 0.5"
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

  # Frequent Major GCs
  # More than 10 major GCs per minute indicates severe memory pressure.
  # The heap is nearly full and V8 is aggressively collecting garbage.
  rule {
    name      = "Node.js Frequent Major GC"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "nodejs"
    }

    annotations = {
      summary     = "{{ $labels.namespace }}/{{ $labels.pod }} >10 major GCs/min"
      description = "High frequency of major garbage collections indicates memory pressure. Service is spending significant time in GC instead of processing requests."
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "rate(nodejs_gc_duration_seconds_count{gc_type=\"major\", namespace=~\"customer-.*\"}[1m]) * 60 > 10"
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

  # Heap Growth Rate High
  # Rapid heap growth may indicate a memory leak. If heap is growing
  # faster than 50MB/min consistently, investigate.
  rule {
    name      = "Node.js Heap Growth Rate High"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "nodejs"
    }

    annotations = {
      summary     = "{{ $labels.namespace }}/{{ $labels.pod }} heap growing >50MB/min"
      description = "Heap memory is growing rapidly. This may indicate a memory leak. Investigate object retention and consider heap snapshots."
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 900
        to   = 0
      }

      model = jsonencode({
        expr          = "deriv(nodejs_heap_used_bytes{namespace=~\"customer-.*\"}[5m]) * 60 > 50000000"
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
