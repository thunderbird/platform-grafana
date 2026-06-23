# Converted VMRules -> Grafana alert rules (platform-infrastructure #559).
#
# These three alert groups replace hand-authored VMRule CRDs that were
# vmalert-evaluated and had no non-paging delivery path. They now query the
# VictoriaMetrics datasource (Prometheus-compatible) directly via Grafana and
# route through the EXISTING non-paging policy added in alerting.tf:
#   severity=warning / severity=ticket
#     -> pagerduty-platform-infra-low (low-urgency PD) -> Slack #mzla-pages.
#
# The source VMRule PromQL exprs already return a boolean-ish series (the
# comparison is baked into the expr), so each Grafana rule runs the full expr
# in the A (query) step, reduces to the last value in B, and the C threshold
# fires on `> 0` (i.e. the expr produced a matching series / a `1`).
#
# Pattern matches the proven alerting-euc1-dr.tf in this repo: A=query
# (datasource_uid = VM datasource), B=reduce(last), C=threshold, all on the
# `__expr__` server-side expression datasource, disable_provenance=true.
#
# The VMRule YAMLs are removed in a paired platform-infrastructure PR that must
# merge AFTER these rules are applied, to avoid an alerting gap.

# VictoriaMetrics datasource (Prometheus-compatible). UID is stable/live; this
# datasource is not (yet) managed in this Terraform, so reference it by UID.
locals {
  victoriametrics_ds_uid = "P4169E866C3094E38"
}

# ---------------------------------------------------------------------------
# Keycloak realm DR backup staleness
# Source: argocd/keycloak/dr-backup-vmrule.yaml (KeycloakRealmBackupStale)
# ---------------------------------------------------------------------------
resource "grafana_rule_group" "keycloak_dr_backup" {
  name               = "keycloak-dr-backup"
  folder_uid         = grafana_folder.keycloak.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "KeycloakRealmBackupStale"
    condition      = "C"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "ticket"
      service  = "keycloak"
    }
    annotations = {
      summary     = "Keycloak aws-sso realm DR backup is stale or missing"
      description = "No successful aws-sso realm export has been recorded in over 26h (the CronJob runs every 6h). The realm config backup in s3://mzla-keycloak-dr-use1/realm-exports/ may be out of date. Check the keycloak-dr-backup CronJob in the keycloak namespace. NOTE: this backup is realm CONFIG only — the SAML signing keypair is owned by #370; a full restore also needs that (see the #4 runbook)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/docs/keycloak-staff-sso.md"
    }

    # A = seconds since the last successful aws-sso backup, computed with a 26h
    # range (max_over_time) so it tolerates the SPARSE push cadence: the backup
    # pushes keycloak_backup_* once per 6h run, so a bare instant selector is
    # empty for ~5h55m of every cycle. The original VMRule's
    # `(time()-max(...) > 26h) or absent_over_time([26h])` returns a series only
    # when firing; ported verbatim into a Grafana instant query that empty result
    # became NoData -> no_data_state=Alerting -> a spurious page every inter-push
    # gap. max_over_time([26h]) instead always yields the real age while a sample
    # exists in 26h, and yields NO data only when the backup has been absent for
    # >26h (the genuine "CronJob stopped" case) -> NoData=Alerting then fires.
    data {
      ref_id         = "A"
      datasource_uid = local.victoriametrics_ds_uid
      relative_time_range {
        from = 94320
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = local.victoriametrics_ds_uid }
        expr          = "time() - max_over_time(keycloak_backup_last_success_timestamp_seconds{realm=\"aws-sso\"}[26h])"
        instant       = true
        range         = false
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
          evaluator = { type = "gt", params = [93600] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}

# ---------------------------------------------------------------------------
# Tailscale operator / proxy / OAuth secret sync
# Source: argocd/tailscale/vmrule.yaml
# (TailscaleOperatorDown / TailscaleProxyCrashLoop / TailscaleOAuthSecretSyncErrors)
# ---------------------------------------------------------------------------
resource "grafana_rule_group" "tailscale" {
  name               = "tailscale-operator"
  folder_uid         = grafana_folder.core_services.uid
  interval_seconds   = 60
  disable_provenance = true

  # --- Operator pod down ---
  rule {
    name           = "TailscaleOperatorDown"
    condition      = "C"
    for            = "5m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "warning"
      service  = "tailscale"
    }
    annotations = {
      summary     = "Tailscale operator pod down >5m on shared01"
      description = "The Tailscale operator is reporting fewer than 1 up target in the tailscale namespace on shared01. Tailnet admin access (operator-managed proxies and ingress) may be impaired. Check the tailscale-operator deployment in the tailscale namespace."
    }

    data {
      ref_id         = "A"
      datasource_uid = local.victoriametrics_ds_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = local.victoriametrics_ds_uid }
        expr          = "sum(up{namespace=\"tailscale\", job=~\".*tailscale-operator.*\"}) < 1"
        instant       = true
        range         = false
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

  # --- Proxy CrashLoop ---
  rule {
    name           = "TailscaleProxyCrashLoop"
    condition      = "C"
    for            = "10m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "warning"
      service  = "tailscale"
    }
    annotations = {
      summary     = "Tailscale proxy pod {{ $labels.pod }} restarted >5 times in 15m"
      description = "A Tailscale proxy pod (ts-*) in the tailscale namespace has restarted more than 5 times in the last 15m. The corresponding tailnet-exposed service may be flapping. increase(...[15m]) is used so the alert clears once the pod stabilizes."
    }

    data {
      ref_id         = "A"
      datasource_uid = local.victoriametrics_ds_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = local.victoriametrics_ds_uid }
        expr          = "sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace=\"tailscale\", pod=~\"ts-.*\"}[15m])) > 5"
        instant       = true
        range         = false
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

  # --- OAuth ExternalSecret sync errors ---
  rule {
    name           = "TailscaleOAuthSecretSyncErrors"
    condition      = "C"
    for            = "15m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "warning"
      service  = "tailscale"
    }
    annotations = {
      summary     = "operator-oauth ExternalSecret returning sync errors"
      description = "The operator-oauth ExternalSecret in the tailscale namespace is returning sync errors (external_secrets_sync_calls_error_total rate > 0 over 15m). If the OAuth client secret goes stale the Tailscale operator loses tailnet auth. Check the ExternalSecret and its SecretStore in the tailscale namespace."
    }

    data {
      ref_id         = "A"
      datasource_uid = local.victoriametrics_ds_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = local.victoriametrics_ds_uid }
        expr          = "rate(external_secrets_sync_calls_error_total{namespace=\"tailscale\", name=\"operator-oauth\"}[15m]) > 0"
        instant       = true
        range         = false
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
# euc1 standby keycloak-tls cert expiry / not-ready
# Source: argocd/shared-euc1/observability/vmrule-cert-expiry.yaml
# (EUC1CertExpiringIn14Days / EUC1CertNotReady)
# ---------------------------------------------------------------------------
resource "grafana_rule_group" "euc1_cert_expiry" {
  name               = "cert-expiry-euc1"
  folder_uid         = grafana_folder.core_services.uid
  interval_seconds   = 60
  disable_provenance = true

  # --- Cert expiring within 14 days ---
  rule {
    name           = "EUC1CertExpiringIn14Days"
    condition      = "C"
    for            = "1h"
    no_data_state  = "NoData"
    exec_err_state = "Error"
    labels = {
      severity = "ticket"
      cluster  = "mzla-eks-shared-euc01"
      service  = "cert-manager"
    }
    annotations = {
      summary     = "euc1 keycloak-tls certificate expires in < 14 days"
      description = "The keycloak-tls certificate in the keycloak namespace on mzla-eks-shared-euc01 (euc1 standby) expires in less than 14 days. cert-manager renews via Route53 DNS-01; check the Certificate and CertificateRequest objects for failed challenges. A promoted standby with an expired cert will break SSO for all users. Force-renew: kubectl -n keycloak annotate certificate keycloak-tls cert-manager.io/issue-temporary-certificate=\"\""
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/docs/keycloak-staff-sso.md"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.victoriametrics_ds_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = local.victoriametrics_ds_uid }
        expr          = "(certmanager_certificate_expiration_timestamp_seconds{namespace=\"keycloak\", name=\"keycloak-tls\"} - time()) < 14 * 24 * 3600"
        instant       = true
        range         = false
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

  # --- Cert not ready ---
  rule {
    name           = "EUC1CertNotReady"
    condition      = "C"
    for            = "15m"
    no_data_state  = "NoData"
    exec_err_state = "Error"
    labels = {
      severity = "ticket"
      cluster  = "mzla-eks-shared-euc01"
      service  = "cert-manager"
    }
    annotations = {
      summary     = "euc1 keycloak-tls certificate is not ready"
      description = "The keycloak-tls certificate in the keycloak namespace on mzla-eks-shared-euc01 (euc1 standby) is reporting ready=False. cert-manager may be waiting on a DNS-01 challenge or the cert could be in a failed renewal state. Check: kubectl -n keycloak describe certificate keycloak-tls; kubectl -n keycloak get certificaterequest. A not-ready cert means the standby cannot be safely promoted."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/docs/keycloak-staff-sso.md"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.victoriametrics_ds_uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId         = "A"
        datasource    = { type = "prometheus", uid = local.victoriametrics_ds_uid }
        expr          = "certmanager_certificate_ready_status{namespace=\"keycloak\", name=\"keycloak-tls\", condition=\"True\"} == 0"
        instant       = true
        range         = false
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
