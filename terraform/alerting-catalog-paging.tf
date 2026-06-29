# Grafana alert-rule catalog — PHASE 1 paging rules (platform-infrastructure #80).
# https://github.com/thunderbird/platform-infrastructure/issues/80
#
# Grafana-managed alert rules querying the VictoriaMetrics datasource
# (var.prometheus_datasource_uid = P4169E866C3094E38). Every rule carries
# labels.severity = "page" so it routes via the EXISTING
# grafana_notification_policy.root child route (severity =~ "page|critical") to
# the pagerduty-platform-infra contact point (PagerDuty Events API v2, from
# #136). This file does NOT touch the notification policy or contact points.
#
# Pattern mirrors the proven structure in alerting-euc1-dr.tf:
#   A = PromQL query against the VictoriaMetrics datasource
#   B = reduce expression  (datasource_uid = "__expr__", model uid "__expr__")
#   C = threshold expression (the alert `condition`)
#   disable_provenance = true so TF-provisioned rules stay editable/idempotent.
#
# DESIGN DECISIONS (issue-80 plan):
#   D1 — does NOT re-author the victoria-metrics-k8s-stack chart's generic
#        kube/node/VM alerts wholesale. Only a thin outage-grade subset is
#        promoted to severity=page (the chart copies carry info/warning and
#        route nowhere). The chart copies double-evaluate harmlessly.
#   D2 — proceeds on fork (a): hand-authored Grafana copies at severity=page
#        for the small kube + VictoriaMetrics outage subset.
#   D7 — VMClusterSelectPathDown self-deadman blind spot: a rule querying the
#        VM datasource cannot fire if the VM read path (vmselect) is fully
#        down. Noted in that rule's description; true external deadman is out
#        of scope (tracked in the self-monitoring follow-up).
#
# LIVE-VALIDATED label model (queried against VictoriaMetrics 2026-06-23):
#   - `up` DOES carry `namespace` here. kube-state-metrics is shared across
#     shared01 AND the euc1 DR cluster, so node/PV/argocd rules are scoped to
#     cluster="mzla-eks-shared01" to avoid catching euc1 series.
#   - vminsert/vmselect/vmstorage job = "<role>-victoriametrics-victoria-metrics-k8s-stack"
#     (matched by .*vminsert.* / .*vmselect.* / .*vmstorage.*).
#   - Traefik on shared01 has NO dedicated `up` job; it is scraped via the
#     catch-all pods-with-annotations VMPodScrape, so it surfaces as
#     up{namespace="traefik"} (NOT job=~".*traefik.*", which is empty).
#   - argocd `up` carries `container` (application-controller / repo-server /
#     server / ...), NOT a sanitized app_kubernetes_io_component label.
#   - teleport process_state is UNPREFIXED (not teleport_process_state).
#   - keycloak http_server_requests_seconds_count carries a `status` label.
#
# DROPPED from Phase 1 (selector NOT confirmed live):
#   - TraefikNoHealthyBackends: traefik_service_server_up returns 0 series on
#     shared01 (the metric is only emitted with a configured backend health
#     check). Needs the health check configured + a scrape before authoring.

# ---------------------------------------------------------------------------
# Kubernetes (paging subset — D1/D2). Crash/PV rules scoped to issue-80 core
# namespaces + cluster="mzla-eks-shared01".
# ---------------------------------------------------------------------------
resource "grafana_rule_group" "catalog_kubernetes" {
  name               = "catalog-kubernetes-paging"
  folder_uid         = grafana_folder.kubernetes.uid
  interval_seconds   = 60
  disable_provenance = true

  # --- Node stuck NotReady (and not cordoned) ---
  rule {
    name           = "KubeNodeNotReady (shared01)"
    condition      = "C"
    for            = "10m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "kubernetes"
    }
    annotations = {
      summary     = "A shared01 node has been NotReady for 10m"
      description = "At least one mzla-eks-shared01 node is NotReady and not cordoned (kube_node_spec_unschedulable==0) for 10m. Workloads are evicting and cluster capacity is shrinking. Chart ships this at warning/15m and routes nowhere; this Grafana copy pages. Check node health, kubelet, and EC2 instance status."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "count(kube_node_status_condition{cluster=\"mzla-eks-shared01\",condition=\"Ready\",status=\"true\"} == 0 and on(node) kube_node_spec_unschedulable{cluster=\"mzla-eks-shared01\"} == 0)"
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

  # --- Kubelet down on a node ---
  rule {
    name           = "KubeletDown (shared01)"
    condition      = "C"
    for            = "10m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "kubernetes"
    }
    annotations = {
      summary     = "A shared01 node has no live kubelet scrape target for 10m"
      description = "node count minus live kubelet targets > 0 on mzla-eks-shared01: at least one node's kubelet is down/unscraped, so its pods are unmanaged and the control plane has lost ground truth for that node. Highest-signal node-plane outage. Chart classifies KubeletDown critical/15m but it never reaches PagerDuty."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "count(kube_node_info{cluster=\"mzla-eks-shared01\"}) - count(up{cluster=\"mzla-eks-shared01\",job=\"kubelet\",metrics_path=\"/metrics\"} == 1)"
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

  # --- PersistentVolume critically full (<5%) ---
  rule {
    name           = "KubePersistentVolumeFillingUpCritical (shared01)"
    condition      = "C"
    for            = "5m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "kubernetes"
    }
    annotations = {
      summary     = "A shared01 PersistentVolume is under 5% free"
      description = "A PVC on mzla-eks-shared01 has less than 5% free space and is minutes from write failures. These back stateful core infra (vmstorage 100Gi, VictoriaLogs, Keycloak, Teleport). A full volume = metrics/log ingestion loss or auth-plane corruption. Only the critical <5% variant is promoted to page; the chart's 15%-prediction warning stays on the chart path. Expand the PVC."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "count((kubelet_volume_stats_available_bytes{cluster=\"mzla-eks-shared01\"} / kubelet_volume_stats_capacity_bytes{cluster=\"mzla-eks-shared01\"}) < 0.05 and kubelet_volume_stats_used_bytes{cluster=\"mzla-eks-shared01\"} > 0)"
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

  # --- CrashLoopBackOff in a core namespace ---
  rule {
    name           = "KubePodCrashLoopingCoreNamespaces (shared01)"
    condition      = "C"
    for            = "15m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "kubernetes"
    }
    annotations = {
      summary     = "A core-namespace pod is CrashLoopBackOff for 15m on shared01"
      description = "A container in a user-facing core namespace (monitoring/keycloak/teleport/argocd/external-secrets/kube-system/traefik) has been CrashLoopBackOff for 15m on mzla-eks-shared01. Namespace-scoped so a crashlooping Keycloak/Traefik/ArgoCD/ESO/VM pod pages while general app workloads stay on the chart's warning path. for=15m survives a rolling deploy."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "count(max_over_time(kube_pod_container_status_waiting_reason{cluster=\"mzla-eks-shared01\",reason=\"CrashLoopBackOff\",namespace=~\"monitoring|keycloak|teleport|argocd|external-secrets|kube-system|traefik\"}[5m]) >= 1)"
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

# ---------------------------------------------------------------------------
# Traefik (greenfield — no chart rules). shared01 Traefik is scraped via the
# pods-with-annotations VMPodScrape -> up{namespace="traefik"} (no traefik job).
# ---------------------------------------------------------------------------
resource "grafana_rule_group" "catalog_traefik" {
  name               = "catalog-traefik-paging"
  folder_uid         = grafana_folder.traefik.uid
  interval_seconds   = 60
  disable_provenance = true

  # --- Traefik ingress fully down ---
  rule {
    name           = "TraefikDown (shared01)"
    condition      = "C"
    for            = "5m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "traefik"
    }
    annotations = {
      summary     = "Traefik ingress is down on shared01"
      description = "No Traefik pod is reporting up{namespace=\"traefik\"} for 5m on mzla-eks-shared01. Traefik is the single NLB ingress for shared01 (victoriametrics.infra.thunderbird.net, sso.infra.thunderbird.net) — all externally-routed services are unreachable. no_data_state=Alerting so a vanished scrape target also fires."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "sum(up{cluster=\"mzla-eks-shared01\",namespace=\"traefik\"})"
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

  # --- Sustained 5xx at the entrypoint ---
  rule {
    name           = "TraefikHighEntrypointErrorRate (shared01)"
    condition      = "C"
    for            = "10m"
    no_data_state  = "OK"
    exec_err_state = "OK"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "traefik"
    }
    annotations = {
      summary     = "Traefik entrypoint 5xx rate > 5% on shared01"
      description = "Sustained >5% 5xx at the web/websecure entrypoints on mzla-eks-shared01 for 10m = Traefik or all backends failing user-facing requests. Entrypoint-level (not per-service) so a single noisy backend won't trip it. no_data_state=OK so no traffic does not fire."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "sum(rate(traefik_entrypoint_requests_total{cluster=\"mzla-eks-shared01\",code=~\"5..\",entrypoint=~\"web|websecure\"}[5m])) / sum(rate(traefik_entrypoint_requests_total{cluster=\"mzla-eks-shared01\",entrypoint=~\"web|websecure\"}[5m]))"
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
          evaluator = { type = "gt", params = [0.05] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}

# ---------------------------------------------------------------------------
# VictoriaMetrics (paging subset — D1/D2). Replica thresholds assume current
# sizing: vminsert=2, vmselect=2, vmstorage=3, replicationFactor=2.
# ---------------------------------------------------------------------------
resource "grafana_rule_group" "catalog_victoriametrics" {
  name               = "catalog-victoriametrics-paging"
  folder_uid         = grafana_folder.victoriametrics.uid
  interval_seconds   = 60
  disable_provenance = true

  # --- vminsert ingestion path fully down ---
  rule {
    name           = "VMClusterInsertPathDown"
    condition      = "C"
    for            = "3m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "victoriametrics"
    }
    annotations = {
      summary     = "All vminsert replicas are down on shared01"
      description = "No vminsert replica is up. vminsert is the sole ingestion entrypoint for ALL clusters remote-writing to shared01 — all replicas down = fleet-wide observability blackout. Gated on total-down to avoid paging on a rolling restart."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "count(up{job=~\".*vminsert.*\"} == 1)"
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

  # --- vmselect read path fully down (D7 self-deadman caveat) ---
  rule {
    name           = "VMClusterSelectPathDown"
    condition      = "C"
    for            = "3m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "victoriametrics"
    }
    annotations = {
      summary     = "All vmselect replicas are down on shared01"
      description = "No vmselect replica is up. vmselect serves every query — Grafana, vmalert evaluation, the external read path. All down = dashboards and alert eval go blind. D7 CAVEAT: this rule queries the VM datasource, so if vmselect is the eval backend and it is fully down this rule may not fire reliably; true external deadman is tracked in the self-monitoring follow-up."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "count(up{job=~\".*vmselect.*\"} == 1)"
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

  # --- vmstorage below replication-factor quorum ---
  rule {
    name           = "VMStorageInsufficientReplicas"
    condition      = "C"
    for            = "5m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "victoriametrics"
    }
    annotations = {
      summary     = "Fewer than 2 vmstorage replicas up on shared01"
      description = "3 vmstorage replicas, replicationFactor=2. Losing one is tolerated; losing two means writes cannot satisfy RF and queries may return partial results — active data-loss risk. Single-node-down is intentionally NOT paged."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "count(up{job=~\".*vmstorage.*\"} == 1)"
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

  # --- vmstorage disk filling ---
  rule {
    name           = "VMStorageDiskRunsOutOfSpace"
    condition      = "C"
    for            = "30m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "victoriametrics"
    }
    annotations = {
      summary     = "vmstorage disk > 85% full on shared01"
      description = "vmstorage flips read-only when disk fills, stalling fleet-wide ingestion. 85% used (data / (data + free)) sustained for 30m so it only fires on a real fill, leaving runway to expand the PVC."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "sum(vm_data_size_bytes{job=~\".*vmstorage.*\"}) / (sum(vm_free_disk_space_bytes{job=~\".*vmstorage.*\"}) + sum(vm_data_size_bytes{job=~\".*vmstorage.*\"}))"
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
          evaluator = { type = "gt", params = [0.85] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  # --- vmagent remote-write dropping samples ---
  rule {
    name           = "VMAgentRemoteWriteDroppingData"
    condition      = "C"
    for            = "10m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "victoriametrics"
    }
    annotations = {
      summary     = "A vmagent is dropping remote-write samples"
      description = "A cluster's vmagent is DROPPING samples (queue full / persistently rejected) — that data is gone forever and the cluster silently disappears from observability with no backfill. The firing series' `cluster` label identifies which. for=10m rides out a brief queue blip during a shared01 restart."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "sum(increase(vmagent_remotewrite_packets_dropped_total[5m])) by (cluster)"
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

# ---------------------------------------------------------------------------
# Keycloak. up carries namespace="keycloak". Only true user-facing outages page.
# ---------------------------------------------------------------------------
resource "grafana_rule_group" "catalog_keycloak" {
  name               = "catalog-keycloak-paging"
  folder_uid         = grafana_folder.keycloak.uid
  interval_seconds   = 60
  disable_provenance = true

  # --- All Keycloak replicas down ---
  rule {
    name           = "KeycloakAllReplicasDown"
    condition      = "C"
    for            = "2m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "keycloak"
    }
    annotations = {
      summary     = "All Keycloak replicas are down on shared01"
      description = "No Keycloak pod is up in namespace keycloak on shared01 — total staff-SSO outage, including AWS Identity Center SAML federation (aws-sso realm). The 3-replica HA StatefulSet tolerates losing 1-2 pods, so this pages only on full-fleet loss. for=2m for fast paging without flapping on rolling restarts."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/docs/keycloak-staff-sso.md"
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
        expr          = "sum(up{cluster=\"mzla-eks-shared01\",namespace=\"keycloak\"} == 1)"
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

  # --- Keycloak serving 5xx ---
  rule {
    name           = "KeycloakHigh5xxRate"
    condition      = "C"
    for            = "10m"
    no_data_state  = "OK"
    exec_err_state = "OK"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "keycloak"
    }
    annotations = {
      summary     = "Keycloak 5xx rate > 5% on shared01"
      description = ">5% 5xx responses from Keycloak on shared01 for 10m = serving errors (DB failover, cache split-brain, OOM) even though pods are up — missed by the pod-down rule. http_server_requests_seconds_count carries a `status` label; the denominator is guarded against divide-by-zero by no_data_state=OK."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/docs/keycloak-staff-sso.md"
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
        expr          = "sum(rate(http_server_requests_seconds_count{cluster=\"mzla-eks-shared01\",namespace=\"keycloak\",status=~\"5..\"}[5m])) / sum(rate(http_server_requests_seconds_count{cluster=\"mzla-eks-shared01\",namespace=\"keycloak\"}[5m]))"
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
          evaluator = { type = "gt", params = [0.05] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}

# ---------------------------------------------------------------------------
# Teleport. Standalone single-process; up carries namespace="teleport",
# endpoint="diag". process_state is UNPREFIXED (0=ok,1=recovering,2=degraded,
# 3=starting).
# ---------------------------------------------------------------------------
resource "grafana_rule_group" "catalog_teleport" {
  name               = "catalog-teleport-paging"
  folder_uid         = grafana_folder.teleport.uid
  interval_seconds   = 60
  disable_provenance = true

  # --- Teleport down ---
  rule {
    name           = "TeleportDown"
    condition      = "C"
    for            = "5m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "teleport"
    }
    annotations = {
      summary     = "Teleport is down on shared01"
      description = "The Teleport process is down/unscrapeable on shared01 (standalone single-replica). ALL SSO-mediated kube and SSH access to the fleet is gone — break-glass-adjacent blast radius, hence a Teleport-specific page even though chart KubePodNotReady also fires. no_data_state=Alerting catches a vanished target."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "max(up{cluster=\"mzla-eks-shared01\",namespace=\"teleport\"})"
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

  # --- Teleport process degraded ---
  rule {
    name           = "TeleportProcessDegraded"
    condition      = "C"
    for            = "10m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "teleport"
    }
    annotations = {
      summary     = "Teleport process_state is degraded on shared01"
      description = "Teleport's own health verdict (process_state) is sustained degraded (>=2) for 10m: up enough to scrape but not serving correctly (backend unreachable, cert problems). More precise than up==0. for=10m avoids paging on transient recovering/starting during a restart."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "max(process_state{cluster=\"mzla-eks-shared01\",namespace=\"teleport\"})"
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
          evaluator = { type = "gt", params = [1] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}

# ---------------------------------------------------------------------------
# ArgoCD. argocd_app_info confirmed scraped; up carries `container`
# (application-controller / repo-server / ...), NOT app_kubernetes_io_component.
# ---------------------------------------------------------------------------
resource "grafana_rule_group" "catalog_argocd" {
  name               = "catalog-argocd-paging"
  folder_uid         = grafana_folder.argocd.uid
  interval_seconds   = 60
  disable_provenance = true

  # --- App Degraded ---
  rule {
    name           = "ArgoCDApplicationDegraded"
    condition      = "C"
    for            = "15m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "argocd"
    }
    annotations = {
      summary     = "ArgoCD application {{ $labels.name }} is Degraded on shared01"
      description = "ArgoCD application {{ $labels.name }} has been health_status=Degraded for 15m — a tracked resource failed its runtime health check (crash-loop, failed readiness, stuck PVC) even if Git-synced. Sustained >15m usually means a real managed service (Traefik/Keycloak/vmauth) is broken. Matches only Degraded (excludes transient Progressing/Missing)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
    }

    # `sum by (name)` keeps one series per ArgoCD app so the alert fires as a
    # separate instance per degraded app (label `name`), surfaced in the page
    # via {{ $labels.name }} and the per-app notification route in alerting.tf.
    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid
      relative_time_range {
        from = 900
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = var.prometheus_datasource_uid }
        expr          = "sum by (name) (argocd_app_info{cluster=\"mzla-eks-shared01\",health_status=\"Degraded\"})"
        instant       = true
        intervalMs    = 1000
        maxDataPoints = 43200
      })
    }
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 900
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
        from = 900
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

  # --- application-controller or repo-server down ---
  rule {
    name           = "ArgoCDControllerOrRepoServerDown"
    condition      = "C"
    for            = "10m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "argocd"
    }
    annotations = {
      summary     = "ArgoCD application-controller or repo-server is down on shared01"
      description = "The application-controller (reconcile/self-heal) or repo-server (manifest rendering) is fully down on shared01 — the fleet's GitOps loop stalls, drift goes uncorrected, no app can sync/self-heal across all clusters. Selector uses the live `container` label (no app_kubernetes_io_component here)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "min(max by (container) (up{cluster=\"mzla-eks-shared01\",namespace=\"argocd\",container=~\"application-controller|repo-server\"}))"
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
# ESO (External Secrets Operator). Only the fleet-wide controller-down pages —
# ESO keeps serving the last-synced Secret value when reconciliation fails.
# Live ns = external-secrets; up via job=monitoring/external-secrets.
# ---------------------------------------------------------------------------
resource "grafana_rule_group" "catalog_eso" {
  name               = "catalog-eso-paging"
  folder_uid         = grafana_folder.core_services.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "ESOControllerDown"
    condition      = "C"
    for            = "10m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "external-secrets"
    }
    annotations = {
      summary     = "External Secrets Operator is down on shared01"
      description = "The ESO controller is down fleet-wide on shared01 (namespace external-secrets) — no ExternalSecret reconciles. Existing Secrets keep serving, but any rotation / new ExternalSecret / token refresh (vmauth bearer tokens, Keycloak/Tailscale OAuth) silently stops. for=10m tolerates a rollout blip (60s scrape interval)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/80"
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
        expr          = "sum(up{cluster=\"mzla-eks-shared01\",namespace=\"external-secrets\"} == 1)"
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
