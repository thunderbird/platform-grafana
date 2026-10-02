# Cloudflare Access gate on metabase.thunderbird.net -- inverted probe alerting
# (platform-infrastructure #1200).
#
# The gated CloudflareAccessApplication CR carries no prevent-destroy annotation, so an
# ArgoCD prune, a deleted Application, or an operator that loses its token removes the
# Cloudflare application and ungates the host. Metabase stays up and ArgoCD stays Synced:
# nothing else notices.
#
# The probe is blackbox-exporter on mzla-eks-shared01 (platform-infrastructure
# argocd/observability/vmprobe-cloudflare-access-gate.yaml, job=cloudflare-access-gate).
# It GETs https://metabase.thunderbird.net/api/health without following redirects, with a
# secret x-gate-probe header that a path-scoped WAF rule matches to skip Super Bot Fight
# Mode. Module http_access_gate passes only on a 302 to thunderbird.cloudflareaccess.com.
#
# These rules read probe_http_status_code rather than probe_success, because probe_success
# is 0 both when the gate is OPEN (200) and when the PROBE is broken (403 challenge, timeout),
# and only the first should page:
#
#   200                         -> CloudflareAccessGateOpen         page
#   403 / 0 / 5xx / bad 302     -> CloudflareAccessGateProbeBroken  warning
#   no series                   -> CloudflareAccessGateProbeAbsent  warning
#
# ALL THREE SHIP PAUSED (is_paused = true). Until platform-infrastructure #1205 arms the
# gate, 200 is the CORRECT reading and GateOpen would page continuously. Unpause in a
# follow-up PR:
#   - ProbeBroken + ProbeAbsent once the probe (platform-infrastructure #1261) is running
#     and reads a clean status (200 before #1205, 302 after) -- i.e. the secret and the WAF
#     skip rule both exist and match.
#   - GateOpen only after #1205 is armed and probe_http_status_code has read 302 steadily.
#
# Structure mirrors alerting-kargo.tf: A = PromQL, B = reduce, C = threshold. Each A wraps
# its selector in count by (instance) so the value is 1 per offending host (probe_success == 0
# would otherwise reduce to 0 and never cross the threshold), and so the alert carries just
# the probed URL as a label. Adding a gated host to the VMProbe extends these rules with no
# change here.
#
# Runbook: docs/observability.md "Synthetic probes (blackbox-exporter)" in
# platform-infrastructure.

resource "grafana_rule_group" "cloudflare_access_gate" {
  name               = "cloudflare-access-gate"
  folder_uid         = grafana_folder.core_services.uid
  interval_seconds   = 60
  disable_provenance = true

  # --- The gate is gone: the host answers 200 without a login ---
  #
  # no_data_state = OK: the healthy result is an empty set (no instance reads 200). A missing
  # probe is ProbeAbsent's job, at warning, so a dead exporter can never page through here.
  # for = 5m rides out a single odd scrape; a real fail-open persists.
  rule {
    name      = "CloudflareAccessGateOpen"
    condition = "C"
    for       = "5m"
    # Paused until #1205 arms the gate: today 200 is correct and this would page nonstop.
    is_paused      = true
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "page"
      cluster  = "mzla-eks-shared01"
      service  = "cloudflare-access"
    }
    annotations = {
      summary     = "Cloudflare Access gate is OPEN on {{ $labels.instance }}"
      description = "The gate probe got HTTP 200 from {{ $labels.instance }} for 5 minutes instead of a 302 to thunderbird.cloudflareaccess.com: the host is answering without a Google login. Likely cause: the gated CloudflareAccessApplication CR (argocd/cloudflare-access/applications/) was pruned or deleted, or the operator lost its token and tore the application down. Check: kubectl -n cloudflare-zero-trust-system get cloudflareaccessapplication on mzla-eks-shared01 (every CR needs a non-empty ID and Available=True), the cloudflare-access-applications ArgoCD app, and Zero Trust > Access > Applications. Restore the CR via git, not by hand: selfHeal will revert a hand-made app. Runbook: docs/cloudflare-access.md."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/docs/observability.md#synthetic-probes-blackbox-exporter"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId      = "A"
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        expr       = "count by (instance) (probe_http_status_code{job=\"cloudflare-access-gate\"} == 200)"
        instant    = true

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

  # --- The probe cannot see the gate: challenged, timing out, erroring ---
  #
  # Excludes 200 so a fail-open is never double-reported at a lower severity. A 302 that
  # fails the Location check (redirect somewhere other than Access) lands here, not in
  # GateOpen. 15m because a stale header or deleted WAF rule is a slow-burn blind spot,
  # not an outage.
  rule {
    name           = "CloudflareAccessGateProbeBroken"
    condition      = "C"
    for            = "15m"
    is_paused      = true
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-shared01"
      service  = "cloudflare-access"
    }
    annotations = {
      summary     = "Cloudflare Access gate probe is broken for {{ $labels.instance }}"
      description = "The gate probe for {{ $labels.instance }} has failed for 15 minutes with something other than HTTP 200, so the gate is currently UNMONITORED (this is not a fail-open). Check probe_http_status_code{job=\"cloudflare-access-gate\"}: 403 means Super Bot Fight Mode challenged it, i.e. the WAF skip rule for /api/health is gone or no longer matches mzla/shared-services/metabase-gate-probe (header_value); 0 means timeout, DNS or TLS failure from shared01; 302 with probe_success 0 means the redirect no longer points at thunderbird.cloudflareaccess.com; 5xx means Metabase or the tunnel is down. Runbook: docs/observability.md Synthetic probes."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/docs/observability.md#synthetic-probes-blackbox-exporter"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId      = "A"
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        expr       = "count by (instance) (probe_success{job=\"cloudflare-access-gate\"} == 0 and probe_http_status_code{job=\"cloudflare-access-gate\"} != 200)"
        instant    = true

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

  # --- The probe series is gone entirely: exporter down, VMProbe deleted, ESO failing ---
  #
  # absent() returns 1 only when the series is missing, so no_data_state = OK is right
  # here too: an empty result is the healthy state.
  rule {
    name           = "CloudflareAccessGateProbeAbsent"
    condition      = "C"
    for            = "15m"
    is_paused      = true
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-shared01"
      service  = "cloudflare-access"
    }
    annotations = {
      summary     = "Cloudflare Access gate probe has no data"
      description = "No probe_http_status_code{job=\"cloudflare-access-gate\"} series for 15 minutes: the gate is UNMONITORED. Likely causes on mzla-eks-shared01: the blackbox-exporter pod is down or stuck in ContainerCreating (the blackbox-exporter-config ExternalSecret failed to sync from mzla/shared-services/metabase-gate-probe), the VMProbe cloudflare-access-gate in namespace monitoring was deleted, or VMAgent is not scraping it. Check the blackbox-exporter and observability ArgoCD apps. Runbook: docs/observability.md Synthetic probes."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/docs/observability.md#synthetic-probes-blackbox-exporter"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId      = "A"
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        expr       = "absent(probe_http_status_code{job=\"cloudflare-access-gate\"})"
        instant    = true

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
