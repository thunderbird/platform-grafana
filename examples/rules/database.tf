resource "grafana_rule_group" "database" {
  name               = "Database"
  folder_uid         = var.folder_uids.database
  interval_seconds   = 60
  disable_provenance = true

  # Postgres Replication Lag
  rule {
    name      = "CNPG Replication Lag High"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "Postgres replica {{ $labels.pod }} in {{ $labels.namespace }} lag exceeds 30s"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "cnpg_pg_replication_lag{namespace=~\"customer-.*\"} > 30"
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

  # Connection Pool Near Limit
  rule {
    name      = "CNPG Connection Pool Near Limit"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "{{ $labels.pg_cluster }} in {{ $labels.namespace }} connection pool at 80% capacity"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "cnpg_backends_total / cnpg_pg_settings_setting{name=\"max_connections\"} > 0.8"
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

  # Storage High
  rule {
    name      = "CNPG Storage High"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "Postgres {{ $labels.pg_cluster }} in {{ $labels.namespace }} storage at 85% capacity"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "cnpg_pg_database_size_bytes / (cnpg_pg_database_size_bytes + cnpg_pg_wal_storage_free_bytes) > 0.85"
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

  # Instance Down
  rule {
    name      = "CNPG Instance Down"
    condition = "B"
    for       = "2m"

    labels = {
      severity = "critical"
      category = "database"
    }

    annotations = {
      summary = "CNPG instance {{ $labels.pg_cluster }} in {{ $labels.namespace }} is down"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = "cnpg_collector_up == 0"
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

  # Storage Critical (95%)
  rule {
    name      = "CNPG Storage Critical"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "critical"
      category = "database"
    }

    annotations = {
      summary = "Postgres {{ $labels.pg_cluster }} in {{ $labels.namespace }} storage at 95% - immediate action required"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "(1 - kubelet_volume_stats_available_bytes{persistentvolumeclaim=~\".*-postgres-.*\"} / kubelet_volume_stats_capacity_bytes{persistentvolumeclaim=~\".*-postgres-.*\"}) > 0.95"
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

  # Connection Exhaustion (90%)
  rule {
    name      = "CNPG Connection Exhaustion"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "critical"
      category = "database"
    }

    annotations = {
      summary = "{{ $labels.pg_cluster }} in {{ $labels.namespace }} connections at 90% - applications may fail to connect"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "sum by (namespace, pg_cluster) (cnpg_backends_total) / sum by (namespace, pg_cluster) (cnpg_pg_settings_setting{name=\"max_connections\"}) > 0.9"
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

  # Long Running Transaction
  rule {
    name      = "CNPG Long Running Transaction"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "{{ $labels.pg_cluster }} in {{ $labels.namespace }} has transaction running > 5 minutes"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "max by (namespace, pg_cluster) (cnpg_backends_max_tx_duration_seconds) > 300"
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

  # Deadlocks Detected
  rule {
    name      = "CNPG Deadlocks Detected"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "{{ $labels.pg_cluster }} in {{ $labels.namespace }} experiencing deadlocks"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "rate(cnpg_pg_stat_database_deadlocks[5m]) > 0"
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

  # Pod Restarted
  rule {
    name      = "CNPG Pod Restarted"
    condition = "B"
    for       = "1m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "CNPG pod {{ $labels.pod }} in {{ $labels.namespace }} restarted"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "increase(kube_pod_container_status_restarts_total{container=\"postgres\"}[10m]) > 0"
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

  # High CPU Usage
  rule {
    name      = "CNPG High CPU Usage"
    condition = "B"
    for       = "15m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "CNPG pod {{ $labels.pod }} in {{ $labels.namespace }} CPU usage above 80%"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 900
        to   = 0
      }

      model = jsonencode({
        expr          = "sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container=\"postgres\"}[5m])) / sum by (namespace, pod) (kube_pod_container_resource_limits{container=\"postgres\", resource=\"cpu\"}) > 0.8"
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

  # High Memory Usage
  rule {
    name      = "CNPG High Memory Usage"
    condition = "B"
    for       = "15m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "CNPG pod {{ $labels.pod }} in {{ $labels.namespace }} memory usage above 80%"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 900
        to   = 0
      }

      model = jsonencode({
        expr          = "sum by (namespace, pod) (container_memory_working_set_bytes{container=\"postgres\"}) / sum by (namespace, pod) (kube_pod_container_resource_limits{container=\"postgres\", resource=\"memory\"}) > 0.8"
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

  # ===========================================
  # PgBouncer Pooler Alerts (CNPG Pooler)
  # ===========================================

  # Pooler Clients Waiting
  rule {
    name      = "PgBouncer Clients Waiting"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "PgBouncer pooler {{ $labels.pooler }} in {{ $labels.namespace }} has clients waiting for connections"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "sum by (namespace, pooler) (cnpg_pgbouncer_pools_cl_waiting) > 0"
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

  # Pooler High Wait Time
  rule {
    name      = "PgBouncer High Wait Time"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "PgBouncer pooler {{ $labels.pooler }} in {{ $labels.namespace }} avg wait time exceeds 1ms"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "max by (namespace, pooler) (cnpg_pgbouncer_stats_avg_wait_time) > 1000"
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

  # Pooler No Server Connections
  rule {
    name      = "PgBouncer No Server Connections"
    condition = "B"
    for       = "2m"

    labels = {
      severity = "critical"
      category = "database"
    }

    annotations = {
      summary = "PgBouncer pooler {{ $labels.pooler }} in {{ $labels.namespace }} has no backend connections but clients are connected"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = "sum by (namespace, pooler) (cnpg_pgbouncer_pools_sv_active) == 0 and sum by (namespace, pooler) (cnpg_pgbouncer_pools_cl_active) > 0"
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

  # Pooler Down
  rule {
    name      = "PgBouncer Pooler Down"
    condition = "B"
    for       = "1m"

    labels = {
      severity = "critical"
      category = "database"
    }

    annotations = {
      summary = "PgBouncer pooler {{ $labels.pooler }} in {{ $labels.namespace }} is unreachable"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = "up{job=\"cnpg-pooler\"} == 0"
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

  # CNPG Cluster Degraded - HA compromised (missing replicas)
  rule {
    name      = "CNPG Cluster Degraded"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "{{ $labels.cluster }} - CNPG cluster {{ $labels.pg_cluster }} in {{ $labels.namespace }} lost all streaming replicas"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 3600
        to   = 0
      }

      model = jsonencode({
        expr          = "cnpg_pg_replication_streaming_replicas{role=\"primary\"} == 0 and max_over_time(cnpg_pg_replication_streaming_replicas{role=\"primary\"}[1h]) > 0"
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

  # ===========================================
  # Backup & WAL Archiving Alerts
  # ===========================================

  # WAL Archiving Failing - primary has WAL files stuck in ready state
  # Would have caught the staging outage (3 days of silent WAL accumulation)
  rule {
    name      = "CNPG WAL Archiving Failing"
    condition = "B"
    for       = "15m"

    labels = {
      severity = "critical"
      category = "database"
    }

    annotations = {
      summary = "{{ $labels.cluster }} - CNPG cluster in {{ $labels.namespace }} has WAL files waiting to be archived for 15+ minutes"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 900
        to   = 0
      }

      model = jsonencode({
        expr          = "cnpg_collector_pg_wal_archive_status{value=\"ready\",namespace=~\"customer-.*\"} > 0"
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

  # WAL Archive Queue High - more than 10 WAL files waiting to be archived
  # Indicates archiving cannot keep up with WAL generation, disk fill risk
  rule {
    name      = "CNPG WAL Archive Queue High"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "{{ $labels.cluster }} - CNPG cluster in {{ $labels.namespace }} has {{ $value }} WAL files queued for archiving"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "cnpg_collector_pg_wal_archive_status{value=\"ready\",namespace=~\"customer-.*\"} > 10"
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

  # No Recent Backup - last successful base backup older than 36 hours
  # Would have caught bondi's stuck backups (~9 days without completion)
  # Uses barman-cloud plugin metric (not deprecated cnpg_collector_last_available_backup_timestamp
  # which stays at 0 for plugin-based backups)
  rule {
    name      = "CNPG No Recent Backup"
    condition = "B"
    for       = "30m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "{{ $labels.cluster }} - CNPG cluster in {{ $labels.namespace }} last successful backup is older than 36 hours"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 3600
        to   = 0
      }

      model = jsonencode({
        expr          = "(time() - barman_cloud_cloudnative_pg_io_last_available_backup_timestamp{namespace=~\"customer-.*\"}) > 129600 and barman_cloud_cloudnative_pg_io_last_available_backup_timestamp{namespace=~\"customer-.*\"} > 0"
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

  # Backup Failed - most recent backup attempt failed
  # Fires when last_failed_backup is newer than last_available_backup
  # Uses barman-cloud plugin metrics (not deprecated cnpg_collector_last_failed_backup_timestamp
  # which stays at 0 for plugin-based backups)
  rule {
    name      = "CNPG Backup Failed"
    condition = "B"
    for       = "15m"

    labels = {
      severity = "critical"
      category = "database"
    }

    annotations = {
      summary = "{{ $labels.cluster }} - CNPG cluster in {{ $labels.namespace }} most recent backup attempt has failed"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 3600
        to   = 0
      }

      model = jsonencode({
        expr          = "barman_cloud_cloudnative_pg_io_last_failed_backup_timestamp{namespace=~\"customer-.*\"} > barman_cloud_cloudnative_pg_io_last_available_backup_timestamp{namespace=~\"customer-.*\"} and barman_cloud_cloudnative_pg_io_last_failed_backup_timestamp{namespace=~\"customer-.*\"} > 0"
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

  # ===========================================
  # Operator Health Alerts
  # ===========================================

  # CNPG Operator Reconciliation Errors
  # Fires when the operator repeatedly fails to reconcile cluster state,
  # meaning configuration drift or cluster issues are not being corrected.
  rule {
    name      = "CNPG Operator Reconciliation Errors"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "CNPG operator controller {{ $labels.controller }} has sustained reconciliation errors"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "rate(controller_runtime_reconcile_errors_total{namespace=\"cnpg-system\"}[5m]) > 0"
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
