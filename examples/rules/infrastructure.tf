resource "grafana_rule_group" "infrastructure" {
  name               = "Infrastructure"
  folder_uid         = var.folder_uids.infrastructure
  interval_seconds   = 60
  disable_provenance = true

  # Node Memory Pressure
  rule {
    name      = "Node Memory Pressure"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "infrastructure"
    }

    annotations = {
      summary = "Node {{ $labels.instance }} memory usage at 85%"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.85"
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

  # Node CPU High
  rule {
    name      = "Node CPU High"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "infrastructure"
    }

    annotations = {
      summary = "Node {{ $labels.instance }} CPU at 85%"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "1 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) > 0.85"
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

  # Node Disk Usage High
  rule {
    name      = "Node Disk Usage High"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "infrastructure"
    }

    annotations = {
      summary = "Node {{ $labels.instance }} disk {{ $labels.mountpoint }} at 85%"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "(1 - (node_filesystem_avail_bytes{fstype!=\"tmpfs\"} / node_filesystem_size_bytes{fstype!=\"tmpfs\"})) > 0.85"
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

  # Node Disk Pressure Condition
  # Fires when kubelet reports DiskPressure=True, which taints the node
  # and prevents pod scheduling.
  rule {
    name      = "Node Disk Pressure"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "critical"
      category = "infrastructure"
    }

    annotations = {
      summary     = "{{ $labels.cluster }} - Node {{ $labels.node }} has DiskPressure condition (scheduling blocked)"

    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = "kube_node_status_condition{condition=\"DiskPressure\", status=\"true\"} == 1"
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

  # Pod OOMKilled
  rule {
    name      = "Pod OOMKilled"
    condition = "B"
    for       = "0s"

    labels = {
      severity = "critical"
      category = "infrastructure"
    }

    annotations = {
      summary = "{{ $labels.cluster }} - Container {{ $labels.container }} in {{ $labels.namespace }}/{{ $labels.pod }} was OOMKilled"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 900
        to   = 0
      }

      model = jsonencode({
        expr          = "(increase(kube_pod_container_status_restarts_total[15m]) > 0) and on (namespace, pod, container) (kube_pod_container_status_last_terminated_reason{reason=\"OOMKilled\"} == 1)"
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

  # PVC Near Capacity
  rule {
    name      = "PVC Near Capacity"
    condition = "B"
    for       = "10m"

    labels = {
      severity = "warning"
      category = "infrastructure"
    }

    annotations = {
      summary = "PVC {{ $labels.persistentvolumeclaim }} in {{ $labels.namespace }} at 85%"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.85"
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

  # PVC Critical Capacity (>95% for 5m)
  rule {
    name      = "PVC Critical Capacity"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "critical"
      category = "infrastructure"
    }

    annotations = {
      summary = "PVC {{ $labels.persistentvolumeclaim }} in {{ $labels.namespace }} at 95% - resize urgently"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.95"
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

  # Node CPU Request Pressure - schedulable capacity running low
  rule {
    name      = "Node CPU Request Pressure"
    condition = "B"
    for       = "15m"

    labels = {
      severity = "warning"
      category = "infrastructure"
    }

    annotations = {
      summary = "{{ $labels.cluster }} - Node {{ $labels.node }} CPU requests at 95% of allocatable capacity"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 900
        to   = 0
      }

      model = jsonencode({
        expr          = "sum by (cluster, node) (kube_pod_container_resource_requests{resource=\"cpu\"}) / sum by (cluster, node) (kube_node_status_allocatable{resource=\"cpu\"}) > 0.95"
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

  # Node Memory Request Pressure - schedulable capacity running low
  rule {
    name      = "Node Memory Request Pressure"
    condition = "B"
    for       = "15m"

    labels = {
      severity = "warning"
      category = "infrastructure"
    }

    annotations = {
      summary = "{{ $labels.cluster }} - Node {{ $labels.node }} memory requests at 95% of allocatable capacity"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 900
        to   = 0
      }

      model = jsonencode({
        expr          = "sum by (cluster, node) (kube_pod_container_resource_requests{resource=\"memory\"}) / sum by (cluster, node) (kube_node_status_allocatable{resource=\"memory\"}) > 0.95"
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

  # kube-system CrashLoopBackOff - critical system component failing
  rule {
    name      = "kube-system Pod CrashLoopBackOff"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "critical"
      category = "infrastructure"
    }

    annotations = {
      summary = "{{ $labels.cluster }} - {{ $labels.pod }} in kube-system is CrashLoopBackOff ({{ $labels.container }})"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "kube_pod_container_status_waiting_reason{namespace=\"kube-system\", reason=\"CrashLoopBackOff\"} > 0"
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

  # Pod Stuck Pending - early warning
  rule {
    name      = "Pod Stuck Pending"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "warning"
      category = "infrastructure"
    }

    annotations = {
      summary = "{{ $labels.cluster }} - Pod {{ $labels.pod }} in {{ $labels.namespace }} stuck in Pending state"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "kube_pod_status_phase{phase=\"Pending\"} == 1"
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

  # Pod CrashLoopBackOff - any namespace except kube-system
  rule {
    name      = "Pod CrashLoopBackOff"
    condition = "B"
    for       = "5m"

    labels = {
      severity = "critical"
      category = "infrastructure"
    }

    annotations = {
      summary = "{{ $labels.cluster }} - {{ $labels.pod }} in {{ $labels.namespace }} is CrashLoopBackOff ({{ $labels.container }})"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr          = "kube_pod_container_status_waiting_reason{namespace!=\"kube-system\", reason=\"CrashLoopBackOff\"} > 0"
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

  # Pod Stuck Pending Critical - intervention needed
  rule {
    name      = "Pod Stuck Pending Critical"
    condition = "B"
    for       = "15m"

    labels = {
      severity = "critical"
      category = "infrastructure"
    }

    annotations = {
      summary = "{{ $labels.cluster }} - Pod {{ $labels.pod }} in {{ $labels.namespace }} stuck Pending for 15m - intervention needed"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 900
        to   = 0
      }

      model = jsonencode({
        expr          = "kube_pod_status_phase{phase=\"Pending\"} == 1"
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

  # CronJob Consecutive Failures - 3+ failed jobs
  # Counts currently existing failed jobs per CronJob owner.
  # Jobs are retained based on CronJob's failedJobsHistoryLimit (default 1).
  rule {
    name      = "CronJob Consecutive Failures"
    condition = "B"
    for       = "0s"

    labels = {
      severity = "critical"
      category = "infrastructure"
    }

    annotations = {
      summary = "{{ $labels.cluster }} - CronJob {{ $labels.owner_name }} in {{ $labels.namespace }} has 3+ failed jobs"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid

      relative_time_range {
        from = 3600
        to   = 0
      }

      model = jsonencode({
        expr          = "count by (cluster, namespace, owner_name) (kube_job_status_failed == 1 * on(namespace, job_name) group_left(owner_name) kube_job_owner{owner_kind=\"CronJob\"}) >= 3"
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
