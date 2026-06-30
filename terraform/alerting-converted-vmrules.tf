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
      summary     = "Tailscale operator down >5m on shared01"
      description = "The tailscale-operator Deployment on shared01 has <1 available replica. Tailnet admin access (operator-managed proxies and ingress) may be impaired. Check: kubectl -n tailscale get deploy operator; kubectl -n tailscale describe deploy operator."
    }

    # A = 1 when the operator Deployment has 0 available replicas, 0 when healthy.
    # The original `sum(up{namespace="tailscale", job=~".*tailscale-operator.*"})`
    # was a conversion artifact: the operator is NOT scraped (no `up` series exists
    # for the tailscale namespace on any cluster), so the verbatim port returned an
    # empty result -> NoData -> no_data_state=Alerting -> a permanent spurious fire.
    # kube_deployment_status_replicas_available is continuously scraped by
    # kube-state-metrics and yields a real value while the Deployment exists; it
    # goes NoData only if the Deployment is deleted (a genuine outage) -> Alerting.
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
        expr          = "1 - max(kube_deployment_status_replicas_available{cluster=\"mzla-eks-shared01\", namespace=\"tailscale\", deployment=\"operator\"})"
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

    # No `> 5` in query A: keep one series per pod with its 15m restart increase
    # (0 when stable) so the healthy state returns data (Normal) instead of an empty
    # result (NoData). The >5 threshold lives in node C below.
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
        expr          = "sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace=\"tailscale\", pod=~\"ts-.*\"}[15m]))"
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
          evaluator = { type = "gt", params = [5] }
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
      summary     = "operator-oauth ExternalSecret not Ready in tailscale namespace"
      description = "The operator-oauth ExternalSecret (tailscale namespace) has Ready=False, so ESO is not reconciling the OAuth client secret. If the secret goes stale the Tailscale operator loses tailnet auth. Check: kubectl -n tailscale describe externalsecret operator-oauth and its SecretStore."
    }

    # A = 1 when the operator-oauth ExternalSecret is Ready=False, 0 when Ready.
    # The original `rate(external_secrets_sync_calls_error_total{namespace="tailscale"...})`
    # never matched anything: the metric is `externalsecret_sync_calls_error` (no
    # `external_secrets`/`_total` form exists), and ESO labels the target namespace
    # as `exported_namespace`, not `namespace` (which is ESO's own ns). The rule was
    # silently blind (no_data_state=OK). externalsecret_status_condition is
    # continuously scraped and present whether Ready or not.
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
        expr          = "externalsecret_status_condition{exported_namespace=\"tailscale\", name=\"operator-oauth\", condition=\"Ready\", status=\"False\"}"
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
    no_data_state  = "OK"
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
        expr          = "((certmanager_certificate_expiration_timestamp_seconds{namespace=\"keycloak\", name=\"keycloak-tls\"} - time()) < 14 * 24 * 3600) or vector(0)"
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
    no_data_state  = "OK"
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

    # condition="False" series = 1 when the cert's Ready condition is False, 0 when
    # Ready. The previous `{condition="True"} == 0` was a real logic bug: not-ready
    # made it emit value 0, which never crosses the `gt 0` threshold (and ready made
    # it empty), so the alert could never fire. This form emits 1 (fires) when not
    # Ready and 0 (Normal) when Ready.
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
        expr          = "certmanager_certificate_ready_status{namespace=\"keycloak\", name=\"keycloak-tls\", condition=\"False\"}"
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
