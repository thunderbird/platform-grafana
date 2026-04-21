resource "grafana_rule_group" "rds" {
  name               = "RDS"
  folder_uid         = var.folder_uids.database
  interval_seconds   = 60
  disable_provenance = true

  # RDS CPU High (>80% for 10m)
  rule {
    name      = "RDS CPU High"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "RDS instance {{ $labels.dimension_DBInstanceIdentifier }} CPU at {{ $value }}%"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "aws_rds_cpuutilization_average > 80"
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

  # RDS CPU Critical (>95% for 5m)
  rule {
    name      = "RDS CPU Critical"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "critical"
      category = "database"
    }

    annotations = {
      summary = "RDS instance {{ $labels.dimension_DBInstanceIdentifier }} CPU at {{ $value }}% - immediate action required"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "aws_rds_cpuutilization_average > 95"
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

  # RDS Free Storage Low (<4GB remaining)
  # Standalone RDS instances are 20GB allocated → 4GB = ~20%.
  # Aurora auto-scales storage so this alert primarily catches standalone RDS.
  # Aurora instances may trigger this only under extreme write amplification.
  rule {
    name      = "RDS Free Storage Low"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "RDS instance {{ $labels.dimension_DBInstanceIdentifier }} free storage below ~20% (< 4GB of 20GB allocated)"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "aws_rds_free_storage_space_average < 4294967296"
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

  # RDS Freeable Memory Low (<256MB)
  rule {
    name      = "RDS Freeable Memory Low"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "RDS instance {{ $labels.dimension_DBInstanceIdentifier }} freeable memory below 256MB"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "aws_rds_freeable_memory_average < 268435456"
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

  # RDS Connection Count High (>80% of max)
  # CloudWatch doesn't expose max_connections as a metric.
  # db.t4g.small max_connections ~171 → 80% = ~137
  # Aurora db.t4g.medium max_connections ~337 → 80% = ~270
  # Threshold set for smallest current instance class (db.t4g.small).
  rule {
    name      = "RDS Connection Count High"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "RDS instance {{ $labels.dimension_DBInstanceIdentifier }} connections at {{ $value }} (~80% of t4g.small max)"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "aws_rds_database_connections_average > 137"
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

  # RDS Disk Queue Depth High (sustained I/O pressure)
  rule {
    name      = "RDS Disk Queue Depth High"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "RDS instance {{ $labels.dimension_DBInstanceIdentifier }} disk queue depth at {{ $value }}"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "aws_rds_disk_queue_depth_average > 5"
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

  # RDS Read Latency High (>20ms sustained)
  rule {
    name      = "RDS Read Latency High"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "RDS instance {{ $labels.dimension_DBInstanceIdentifier }} read latency above 20ms"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "aws_rds_read_latency_average > 0.02"
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

  # RDS Write Latency High (>20ms sustained)
  rule {
    name      = "RDS Write Latency High"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "RDS instance {{ $labels.dimension_DBInstanceIdentifier }} write latency above 20ms"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "aws_rds_write_latency_average > 0.02"
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

  # RDS Swap Usage High (>128MB - indicates memory pressure)
  rule {
    name      = "RDS Swap Usage High"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "database"
    }

    annotations = {
      summary = "RDS instance {{ $labels.dimension_DBInstanceIdentifier }} swap usage above 128MB"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "aws_rds_swap_usage_average > 134217728"
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
