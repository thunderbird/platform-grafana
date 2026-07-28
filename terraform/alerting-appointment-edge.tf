# Appointment CloudFront edge — tb-dev alerting (platform-infrastructure #826 / #702).
#
# Covers the CloudFront distribution in front of appointment.tb-dev.thunderbird.dev
# in the tb-dev account (718959508124). Three concerns, one rule group each:
#
#   - CloudFront 5xxErrorRate > 5% for 5m  -> the edge is serving errors
#   - Route53 HealthCheckStatus (synthetic) -> the site is unreachable end-to-end
#   - ACM DaysToExpiry < 21 on BOTH certs   -> a renewal is silently failing
#
# ---------------------------------------------------------------------------
# Region handling: per-query override, NOT a second datasource
# ---------------------------------------------------------------------------
# CloudFront is a global service and publishes AWS/CloudFront only in us-east-1;
# AWS/Route53 HealthCheckStatus is likewise us-east-1 only. The tb-dev datasource
# (grafana_data_source.cloudwatch_tb_dev) defaults to eu-central-1. Rather than add
# a dedicated cloudwatch_tb_dev_use1 datasource, each query overrides `region` in its
# model — the same trick alerting-euc1-dr.tf already uses for Route53 (see its header
# comment). That matters here because this one file legitimately needs BOTH regions:
# the CloudFront viewer cert lives in us-east-1 and the ALB cert in eu-central-1, and
# a us-east-1-only datasource would split a single concern across two datasources
# while adding a duplicate entry to every Explore/panel picker. `defaultRegion` is
# only a default; every CloudWatch query carries its own region.
#
# ---------------------------------------------------------------------------
# Severity: warning, never paging
# ---------------------------------------------------------------------------
# tb-dev is a dev cluster. severity=warning routes via grafana_notification_policy
# "root" (alerting.tf) to the low-urgency PagerDuty contact point — Slack #mzla-pages,
# no phone page — exactly as ArgoCDApplicationDegradedTbDev does. Paging is reserved
# for the eventual tb-prod distribution. Nothing in alerting.tf is touched.
#
# ---------------------------------------------------------------------------
# Not firing on things that do not exist yet
# ---------------------------------------------------------------------------
# The distribution and the health check are created by the Pulumi half of #826
# (distribution: platform-infrastructure PR #844, still draft) and do not exist today.
# Commit 46653cf established that a healthy steady state must not read as NoData; its
# lever there was `or vector(0)`, which is PromQL and has no CloudWatch equivalent.
# The CloudWatch equivalent in this repo is the state fields plus, here, a count gate:
#
#   - The CloudFront and Route53 groups are count-gated on var.appointment_* being
#     non-empty. Until those IDs are set in terraform.tfvars the rules are not created
#     at all, so there is no rule sitting in the UI evaluating a nonexistent resource.
#   - Every rule sets no_data_state = "OK". A CloudFront distribution with no traffic,
#     or an ACM cert not yet attached to anything, publishes no datapoints; that is
#     healthy, not an alert. (Precedent: alerting-catalog-paging.tf:434 and :959.)
#   - Every rule sets exec_err_state = "OK" *for now*, because the cross-account role
#     mzla-tb-dev-grafana-cloudwatch currently grants logs:* only — no
#     cloudwatch:GetMetricData. Every evaluation would otherwise produce a
#     DatasourceError instance and page Slack every 60s. FLIP THESE TO "Error" once
#     the Pulumi half of #826 adds cloudwatch:GetMetricData/ListMetrics to that role;
#     after that point an AccessDenied is a real failure worth surfacing.

# --- CloudFront error rate -------------------------------------------------------
resource "grafana_rule_group" "appointment_edge_cloudfront" {
  count = var.appointment_distribution_id == "" ? 0 : 1

  name               = "appointment-edge-cloudfront"
  folder_uid         = grafana_folder.appointment.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "AppointmentEdgeHigh5xxRate"
    condition      = "C"
    for            = "5m"
    no_data_state  = "OK"
    exec_err_state = "OK" # see header: flip to "Error" once GetMetricData is granted
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "appointment"
    }
    annotations = {
      summary     = "appointment tb-dev CloudFront edge 5xx rate > 5%"
      description = "The CloudFront distribution in front of appointment.tb-dev.thunderbird.dev has been answering more than 5% of viewer requests with a 5xx for 5 minutes. Check the ALB origin and the appointment pods on mzla-eks-tb-dev01 first — CloudFront 5xx is usually the origin's 5xx passed through. tb-dev is a dev environment, so this is warning-only (Slack, no page). Dashboard: Appointment / Appointment — CloudFront Edge (tb-dev)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/826"
    }

    # 5xxErrorRate is published as a percentage 0-100, so the threshold is 5, not 0.05.
    # Average is the only meaningful statistic for the *Rate metrics.
    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_dev.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_dev.uid }
        queryMode        = "Metrics"
        region           = "us-east-1"
        namespace        = "AWS/CloudFront"
        metricName       = "5xxErrorRate"
        dimensions       = { Region = "Global", DistributionId = var.appointment_distribution_id }
        statistic        = "Average"
        period           = "300"
        metricQueryType  = 0
        metricEditorMode = 0
        matchExact       = true
        id               = ""
        expression       = ""
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
          evaluator = { type = "gt", params = [5] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}

# --- Synthetic end-to-end check --------------------------------------------------
resource "grafana_rule_group" "appointment_edge_synthetic" {
  count = var.appointment_health_check_id == "" ? 0 : 1

  name               = "appointment-edge-synthetic"
  folder_uid         = grafana_folder.appointment.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "AppointmentEdgeHealthCheckFailing"
    condition      = "C"
    for            = "3m"
    no_data_state  = "OK"
    exec_err_state = "OK" # see header: flip to "Error" once GetMetricData is granted
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "appointment"
    }
    annotations = {
      summary     = "appointment.tb-dev.thunderbird.dev is failing its Route53 health check"
      description = "The Route53 health check for https://appointment.tb-dev.thunderbird.dev/ is reporting unhealthy — the site is unreachable or no longer returns its SPA marker string. This is the automated 'it came back' signal for the CloudFront cutover: check the distribution, then the ALB origin, then the appointment pods on mzla-eks-tb-dev01. tb-dev is a dev environment, so this is warning-only (Slack, no page)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/826"
    }

    # HealthCheckStatus is 1 (healthy) / 0 (unhealthy) and is published in us-east-1
    # only, regardless of where the checked endpoint lives. Minimum over the period so
    # a single failing checker is not averaged away.
    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_dev.uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_dev.uid }
        queryMode        = "Metrics"
        region           = "us-east-1"
        namespace        = "AWS/Route53"
        metricName       = "HealthCheckStatus"
        dimensions       = { HealthCheckId = var.appointment_health_check_id }
        statistic        = "Minimum"
        period           = "60"
        metricQueryType  = 0
        metricEditorMode = 0
        matchExact       = true
        id               = ""
        expression       = ""
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

# --- ACM certificate expiry ------------------------------------------------------
# Both certs, not just the CloudFront one. They share a DNS-validation CNAME, so a
# single missing Route53 record breaks renewal for BOTH — watching only one would
# leave the other's failure invisible until the TLS outage. Two rules rather than one
# multi-query rule keeps the repo's rigid A -> B -> C shape and gives each cert its
# own alert instance and its own remediation text.
#
# Not count-gated: both certs exist today. The eu-central-1 cert already publishes
# DaysToExpiry; the us-east-1 cert does not yet (InUseBy is empty until CloudFront
# attaches it), which is exactly what no_data_state = "OK" is for.
#
# DaysToExpiry is published once per day, hence the 48h window and 1h `for`.
resource "grafana_rule_group" "appointment_edge_cert_expiry" {
  name               = "appointment-edge-cert-expiry"
  folder_uid         = grafana_folder.appointment.uid
  interval_seconds   = 60
  disable_provenance = true

  # --- us-east-1: CloudFront viewer certificate ---
  rule {
    name           = "AppointmentEdgeViewerCertExpiring"
    condition      = "C"
    for            = "1h"
    no_data_state  = "OK"
    exec_err_state = "OK" # see header: flip to "Error" once GetMetricData is granted
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "appointment"
    }
    annotations = {
      summary     = "appointment tb-dev CloudFront viewer certificate expires in < 21 days"
      description = "ACM certificate 925d197d-5876-4978-b2ad-e685a8f03a19 (us-east-1, the CloudFront viewer cert for appointment.tb-dev.thunderbird.dev) has fewer than 21 days to expiry, so managed renewal has not completed. Check that the DNS validation CNAME still exists in Route53 — this cert shares its validation record with the eu-central-1 ALB cert, so one missing record breaks both. Reports NoData (treated as OK) until CloudFront attaches the cert."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/826"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_dev.uid
      relative_time_range {
        from = 172800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_dev.uid }
        queryMode        = "Metrics"
        region           = "us-east-1"
        namespace        = "AWS/CertificateManager"
        metricName       = "DaysToExpiry"
        dimensions       = { CertificateArn = "arn:aws:acm:us-east-1:718959508124:certificate/925d197d-5876-4978-b2ad-e685a8f03a19" }
        statistic        = "Minimum"
        period           = "86400"
        metricQueryType  = 0
        metricEditorMode = 0
        matchExact       = true
        id               = ""
        expression       = ""
      })
    }
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 172800
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
        from = 172800
        to   = 0
      }
      model = jsonencode({
        refId      = "C"
        type       = "threshold"
        expression = "B"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "lt", params = [21] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  # --- eu-central-1: ALB (origin) certificate ---
  rule {
    name           = "AppointmentOriginCertExpiring"
    condition      = "C"
    for            = "1h"
    no_data_state  = "OK"
    exec_err_state = "OK" # see header: flip to "Error" once GetMetricData is granted
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "appointment"
    }
    annotations = {
      summary     = "appointment tb-dev ALB origin certificate expires in < 21 days"
      description = "ACM certificate d324b88c-174e-4264-81af-a017c981b1a1 (eu-central-1, minted by the AWS Load Balancer Controller for the appointment ALB on mzla-eks-tb-dev01) has fewer than 21 days to expiry, so managed renewal has not completed. Check that the DNS validation CNAME still exists in Route53 — this cert shares its validation record with the us-east-1 CloudFront viewer cert, so one missing record breaks both."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/826"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_dev.uid
      relative_time_range {
        from = 172800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_dev.uid }
        queryMode        = "Metrics"
        region           = "eu-central-1"
        namespace        = "AWS/CertificateManager"
        metricName       = "DaysToExpiry"
        dimensions       = { CertificateArn = "arn:aws:acm:eu-central-1:718959508124:certificate/d324b88c-174e-4264-81af-a017c981b1a1" }
        statistic        = "Minimum"
        period           = "86400"
        metricQueryType  = 0
        metricEditorMode = 0
        matchExact       = true
        id               = ""
        expression       = ""
      })
    }
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 172800
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
        from = 172800
        to   = 0
      }
      model = jsonencode({
        refId      = "C"
        type       = "threshold"
        expression = "B"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "lt", params = [21] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}
