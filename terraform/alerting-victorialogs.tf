# Grafana paging rules for the VictoriaLogs stack and the shared vmauth proxy.
# platform-infrastructure#841 (gap), #829 (root issue), #840 (silent-partial reads).
#
# WHY THIS FILE EXISTS: the logging half of the observability stack had NO alert rule of any
# kind, while the metrics half has had catalog-victoriametrics-paging since #80. Several
# platform-infrastructure PRs asserted "there is no alerting on this stack", citing
# alertmanager.enabled: false and notifier.blackhole: true. Both are true and both are
# irrelevant -- paging here deliberately bypasses Alertmanager and runs through Grafana
# unified alerting to the pagerduty-platform-infra contact point. Only the RULES were missing.
#
# Structure mirrors alerting-catalog-paging.tf exactly: A = PromQL, B = reduce, C = threshold
# (the alert `condition`), disable_provenance = true so the rules stay editable/idempotent.
#
# LIVE-VALIDATED SELECTORS (queried against VictoriaMetrics on shared01, 2026-07-28):
#
#   count(up{job="victoria-logs"}         == 1)  -> 2
#   count(up{job="victoria-logs-insert"}  == 1)  -> 2
#   count(up{job="victoria-logs-select"}  == 1)  -> 2
#   min(increase(vmauth_config_last_reload_total[15m]))  -> 30
#   max(vmauth_config_last_reload_errors_total)          -> 0
#
# *** DO NOT use the regex selector idiom from alerting-catalog-paging.tf here. ***
# That file matches jobs as job=~".*vminsert.*" etc., which is safe there. The equivalent
# here is a trap:
#
#   count(up{job=~".*victoria-logs.*"} == 1)  -> 8
#
# because the VictoriaMetrics operator derives `job` from the SERVICE name, and four Services
# select these pods: victoria-logs (headless), victoria-logs-lb (the deprecated round-robin
# Service, pending deletion in #829, which double-scrapes both storage pods),
# victoria-logs-insert and victoria-logs-select. A "< 2" threshold against 8 could never fire --
# not even with BOTH storage nodes dead, since the two frontends alone still contribute 4.
# Exact job matching is deliberate. It also stays correct after victoria-logs-lb is deleted.
#
# TOPOLOGY THIS ALERTS ON (see argocd/observability/victorialogs.yaml in platform-infrastructure):
# 2 vlstorage nodes holding DISJOINT data -- VictoriaLogs has no replication, there is no
# replication-factor flag in the binary at all -- behind a stateless vlinsert (shards writes)
# and a stateless vlselect (fans out reads and merges). vlselect returns the SUM of both nodes
# (measured 38,967,831 + 38,348,539 = 77,316,278 over 30d), which is why losing ONE storage node
# is a read outage rather than a degradation.

resource "grafana_folder" "victorialogs" {
  title = "VictoriaLogs"
}

resource "grafana_rule_group" "catalog_victorialogs" {
  name               = "catalog-victorialogs-paging"
  folder_uid         = grafana_folder.victorialogs.uid
  interval_seconds   = 60
  disable_provenance = true

  # --- Fewer than both vlstorage nodes up ---
  #
  # NOTE this deliberately departs from the total-down gating used for vminsert/vmselect in
  # alerting-catalog-paging.tf ("Gated on total-down to avoid paging on a rolling restart").
  # That gating is right for vminsert, whose replicas are interchangeable: losing one costs
  # nothing. It is wrong here, because these two pods are NOT replicas of each other -- they hold
  # disjoint halves of the corpus, so losing either one is already a query outage:
  #   - aggregating queries (| stats, /select/logsql/hits) fail with 502/503
  #   - bounded queries (| limit N) are WORSE: they return HTTP 200 with roughly half the
  #     corpus and no partial marker, because the response streams (#840)
  # The second case is the reason this needs to page at all -- nothing else surfaces it, and
  # bounded queries are exactly what Grafana Explore issues.
  #
  # for = 10m is what keeps this from paging on planned maintenance. A StatefulSet image bump
  # takes one pod at a time and costs a pod restart plus an AZ-bound EBS detach/attach, ~1-3
  # minutes; a genuinely wedged volume takes ~7-10 (6-minute force-detach path). So 10m
  # distinguishes "moving" from "stuck", and a read outage that outlasts 10m should page.
  # Note StatefulSet updates bypass PodDisruptionBudgets entirely, so nothing else bounds this.
  rule {
    name           = "VictoriaLogsStorageNodeDown"
    condition      = "C"
    for            = "10m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "victorialogs"
    }
    annotations = {
      summary     = "A VictoriaLogs storage node has been down for 10m — log queries are incomplete"
      description = "Fewer than 2 of 2 vlstorage nodes are up on shared01. VictoriaLogs does NOT replicate, so each node holds ~half the corpus and vlselect returns the sum: with one node gone, aggregating log queries fail (502/503) and — worse — bounded queries (| limit N) return HTTP 200 with about half the matching rows and no indication anything is missing (#840). All five clusters' logs are affected. Writes are unaffected while at least one node is up; vlinsert routes around the missing node. If ZERO nodes are up, ingestion also stops and Vector's on-disk buffers begin draining (hours of headroom). for=10m tolerates a rolling restart / EBS re-attach; sustained means a stuck volume, an unschedulable pod (each storage pod has exactly ONE alternative node in its AZ — the third node in each AZ is tainted dedicated=keycloak:NoSchedule), or a crash-loop. Check pod status, EBS attachment, and whether general-arm64 and system node groups were upgraded concurrently."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/841"
    }

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
        expr          = "count(up{job=\"victoria-logs\"} == 1)"
        instant       = true
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
          evaluator = { type = "lt", params = [2] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  # --- vlinsert fully down: log ingestion stops for every cluster ---
  # Total-down gating here IS correct (unlike the storage rule above): vlinsert replicas are
  # stateless and interchangeable, so one is enough to serve all writes.
  rule {
    name           = "VictoriaLogsIngestFrontendDown"
    condition      = "C"
    for            = "3m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "victorialogs"
    }
    annotations = {
      summary     = "All vlinsert replicas are down on shared01 — no logs are being ingested"
      description = "No victoria-logs-insert replica is up. vlinsert is the sole ingestion entrypoint for log writes from ALL FIVE clusters (shared01, shared-euc1, tb-dev, tb-prod, workloads route /insert/* through vmauth to it), so all replicas down = fleet-wide log ingestion stop. Not immediate data loss: Vector buffers to disk (2 GiB per pod) and at the current ~36 rows/s fleet-wide that is hours of headroom — but the clock is running, and when a Vector buffer fills, back-pressure also stalls its CloudWatch sink, removing the independent oracle. Gated on total-down to avoid paging on a rolling restart."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/841"
    }

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
        expr          = "count(up{job=\"victoria-logs-insert\"} == 1)"
        instant       = true
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
          evaluator = { type = "lt", params = [1] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  # --- vlselect fully down: no log queries at all ---
  rule {
    name           = "VictoriaLogsQueryFrontendDown"
    condition      = "C"
    for            = "3m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "victorialogs"
    }
    annotations = {
      summary     = "All vlselect replicas are down on shared01 — log search is unavailable"
      description = "No victoria-logs-select replica is up. vlselect is the only complete log read path: it fans out to both vlstorage nodes and merges, and both the Grafana VictoriaLogs datasource and vmauth's /select/* route point at it. All down = log search returns nothing for every cluster, and Kargo AnalysisRun log streaming (#815) breaks with it. Ingestion is unaffected. Querying a storage pod directly is a valid break-glass workaround but returns only that pod's half of the data — do not leave anything pointed there. Gated on total-down to avoid paging on a rolling restart."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/841"
    }

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
        expr          = "count(up{job=\"victoria-logs-select\"} == 1)"
        instant       = true
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
          evaluator = { type = "lt", params = [1] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}

# ---------------------------------------------------------------------------
# vmauth — the shared bearer-token proxy in front of BOTH VictoriaMetrics and
# VictoriaLogs, hence the VictoriaMetrics folder rather than the new one above.
#
# These two rules exist because of a specific, measured 118-day failure. vmauth's
# -configCheckInterval defaults to 0 (disabled: "send SIGHUP for config refresh"), there was no
# reloader sidecar, and no Stakater Reloader annotation. So ArgoCD synced the vmauth-config
# ConfigMap, kubelet updated the mounted file, and vmauth kept serving the config it had parsed
# at startup -- vmauth_config_last_reload_total sat at 0 with a config loaded 2026-03-31, and a
# routing fix was inert in production until both replicas were SIGHUP'd by hand. Fixed by adding
# -configCheckInterval=30s (platform-infrastructure#832), which makes the counter a heartbeat:
# it increments on every check, not only when the file changes (measured: increase over 15m = 30).
#
# That makes "config declared in git but not running" DETECTABLE, which is the general class of
# failure that bit this platform four separate times in one day (vmauth's unread config, a frozen
# Grafana checksum/config, a Grafana sync reporting Synced while operationState was Failed, and a
# stale Kargo desiredRevision skipping verification). Every one was found by a human looking.
# ---------------------------------------------------------------------------
resource "grafana_rule_group" "catalog_vmauth" {
  name               = "catalog-vmauth-paging"
  folder_uid         = grafana_folder.victoriametrics.uid
  interval_seconds   = 60
  disable_provenance = true

  # --- vmauth has stopped re-reading its config ---
  # min() across replicas so ONE stalled replica is enough to fire: a replica that is not
  # reloading is serving stale routing, which is silent and indistinguishable from working.
  rule {
    name           = "VmauthConfigReloadStalled"
    condition      = "C"
    for            = "5m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "vmauth"
    }
    annotations = {
      summary     = "A vmauth replica has stopped re-reading its config"
      description = "vmauth_config_last_reload_total has not increased in 15m on at least one replica. With -configCheckInterval=30s this counter is a heartbeat (~30 increments per 15m), so a flat counter means that replica is serving whatever routing it last parsed and will silently ignore every future change to the vmauth-config ConfigMap — including a revert. This exact condition persisted undetected for 118 days before #832 (counter stuck at 0, config loaded 2026-03-31), during which an ArgoCD-synced routing fix had no effect in production. Check: the -configCheckInterval flag is still present in the vmauth args (flag{name=\"configCheckInterval\"} in /metrics should read 30s, is_set=true), and the pod is not wedged. Manual recovery: POST /-/reload on each replica."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/841"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = var.prometheus_datasource_uid }
        expr          = "min(increase(vmauth_config_last_reload_total[15m]))"
        instant       = true
        intervalMs    = 1000
        maxDataPoints = 43200
      })
    }
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 1800
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
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId      = "C"
        type       = "threshold"
        expression = "B"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "lt", params = [1] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  # --- vmauth is rejecting its config ---
  # no_data_state = OK here on purpose: if vmauth is gone entirely the metric disappears, and
  # VmauthConfigReloadStalled above already pages for that. This rule is only about a config
  # that vmauth has read and refused.
  rule {
    name           = "VmauthConfigReloadFailing"
    condition      = "C"
    for            = "5m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "vmauth"
    }
    annotations = {
      summary     = "vmauth is failing to load its config"
      description = "vmauth_config_last_reload_errors_total is non-zero: vmauth read the vmauth-config ConfigMap and REJECTED it, so it is still serving the last config that parsed cleanly. Every consumer keeps working on stale routing while git and the live ConfigMap show something else — the change looks applied and is not. Almost always a malformed -auth.config: check the vmauth pod logs for the parse error, and note that the bearer-token placeholder in that config is interpolated at load time from the VMAUTH_TOKEN env var (via -envflag.enable), which arrives from the vmauth-token Secret through ESO — so a failed ExternalSecret sync can also surface here."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/841"
    }

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
        expr          = "max(vmauth_config_last_reload_errors_total)"
        instant       = true
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
