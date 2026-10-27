# Appointment CloudFront edge — tb-dev alerting (platform-infrastructure #826 / #702).
#
# Covers the CloudFront distribution in front of appointment.main.dev-thundermail.com
# in the tb-dev account (718959508124). Three concerns:
#
#   - CloudFront 5xx/4xx error rate            -> the edge is serving errors
#   - Route53 HealthCheckStatus (synthetic)    -> the site is unreachable end-to-end
#   - ACM DaysToExpiry < 21 on BOTH certs      -> a renewal is silently failing
#     (us-east-1 viewer and eu-central-1 origin ALB: two distinct objects with two
#     distinct failure modes; see the ACM section)
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
# the CloudFront viewer cert lives in us-east-1 and the origin ALB cert in eu-central-1,
# and a us-east-1-only datasource would split a single concern across two datasources
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
# Not firing on things that do not exist yet, and not going green while blind
# ---------------------------------------------------------------------------
# The distribution and the health check are created by the Pulumi half of #826
# (distribution: platform-infrastructure PR #844, still draft) and do not exist today.
# Commit 46653cf established that a healthy steady state must not read as NoData; its
# lever there was `or vector(0)`, which is PromQL and has no CloudWatch equivalent.
# The CloudWatch equivalent in this repo is the state fields plus, here, count gates:
#
#   - Every group is count-gated on a var.appointment_* ID/ARN being non-empty.
#     Until those are set in terraform.tfvars the rules are not created at all, so
#     "not yet covered" reads as *absent* in the Grafana UI rather than as a green
#     rule that is structurally incapable of firing.
#   - no_data_state = "OK" ONLY where no data is a legitimately healthy state, which
#     here is exactly the two CloudFront *ErrorRate ratios (a distribution with no
#     traffic publishes no datapoints, and a ratio over zero requests is not an
#     error) and the us-east-1 viewer cert (publishes nothing until CloudFront
#     attaches it). Precedent: alerting-catalog-paging.tf:434 and :959.
#   - no_data_state = "Alerting" everywhere silence is itself a fault, i.e. every
#     rule whose target publishes unconditionally once it exists:
#       * the Route53 synthetic check. Route53 publishes HealthCheckStatus every 60s
#         for every health check that exists, with no traffic dependency, and the
#         group is already count-gated on the ID — so NoData can only mean the check
#         was deleted or re-created under a new ID. This is the cutover's automated
#         "it came back" signal, so it is the last rule that may go quietly green.
#         (alerting-euc1-dr.tf:30 uses "NoData" for the same metric; "Alerting" is
#         chosen here so the notification carries the rule name and annotations
#         rather than routing as alertname=DatasourceNoData.)
#       * the in-use origin ALB cert, which publishes DaysToExpiry. NoData means the
#         pinned CertificateArn no longer publishes, i.e. the cert was replaced and
#         the rule has gone blind. Nothing else can surface a stale pin.
#     All of these keep severity = warning, so "Alerting" notifies Slack, not a page.
#   - exec_err_state is driven by var.appointment_metrics_iam_granted rather than by
#     a comment asking a human to remember. The cross-account role
#     mzla-tb-dev-grafana-cloudwatch currently grants logs:* only — no
#     cloudwatch:GetMetricData — so every evaluation would otherwise produce a
#     DatasourceError instance and notify Slack every interval. While the flag is
#     false, execution errors read as OK. Flipping it to true is the same one-line
#     terraform.tfvars change as filling in the two IDs, in the same follow-up PR.
#
# ---------------------------------------------------------------------------
# Follow-up PR checklist (one file: terraform/terraform.tfvars)
# ---------------------------------------------------------------------------
#   0. appointment_origin_cert_arn      = "<ARN of the CloudFront ORIGIN ALB cert>".
#      This is the cert in the CloudFront -> ALB TLS path: the Pulumi-managed
#      *.main.dev-thundermail.com wildcard (platform-infrastructure #1453) that the
#      appointment-origin-main Ingress names in its certificate-arn annotation.
#      Until this is set the CloudFront->origin handshake has no expiry coverage.
#   1. appointment_distribution_id     = "<id from platform-infrastructure PR #844>"
#   2. appointment_health_check_id     = "<id from the Pulumi half of #826>"
#   3. appointment_metrics_iam_granted = true   — only once BOTH
#      cloudwatch:GetMetricData and cloudwatch:ListMetrics are on
#      mzla-tb-dev-grafana-cloudwatch. ListMetrics is what the dashboard's
#      Distribution picker (a dimension_values query) needs; GetMetricData alone
#      arms the alerts but leaves the picker empty.
#   4. Re-run `aws cloudwatch list-metrics --namespace AWS/CertificateManager
#      --region us-east-1` in 718959508124 and confirm the viewer cert
#      d62f83c9-70c6-4334-b070-3de8718dbc1e now appears. It publishes nothing today
#      (InUseBy is empty). If it still does not publish once CloudFront has attached
#      it, AppointmentEdgeViewerCertExpiring is not providing the coverage it claims
#      and needs replacing with a non-CloudWatch check.

# --- CloudFront error rates ------------------------------------------------------
# Both rules carry a volume guard. 5xxErrorRate/4xxErrorRate are *ratios*, and tb-dev
# appointment has near-zero traffic: without a guard, one 500 from a scanner in a
# bucket holding 2 requests is 50% and notifies Slack. Query B (Requests, Sum) is the
# denominator, and the math node requires the ratio AND the volume to be breached.
#
# `for` is 15m against a 300s period, so at least three distinct CloudWatch buckets
# have to be bad before the rule fires. A `for` shorter than the period adds no
# debouncing whatsoever — Grafana just re-reads the same unchanged newest bucket every
# interval — which is why alerting-euc1-dr.tf also keeps `for` at >= 3x period.
resource "grafana_rule_group" "appointment_edge_cloudfront" {
  count = var.appointment_distribution_id == "" ? 0 : 1

  name               = "appointment-edge-cloudfront"
  folder_uid         = grafana_folder.appointment.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "AppointmentEdgeHigh5xxRate"
    condition      = "F"
    for            = "15m"
    no_data_state  = "OK"
    exec_err_state = var.appointment_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "appointment"
    }
    annotations = {
      summary     = "appointment tb-dev CloudFront edge 5xx rate > 5%"
      description = "The CloudFront distribution in front of appointment.main.dev-thundermail.com has been answering more than 5% of viewer requests with a 5xx for 15 minutes, in 5-minute buckets holding more than 50 requests. Check the ALB origin and the appointment pods on mzla-eks-tb-dev01 first — CloudFront 5xx is usually the origin's 5xx passed through. tb-dev is a dev environment, so this is warning-only (Slack, no page). Dashboard: Appointment / Appointment — CloudFront Edge (tb-dev)."
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
    # Volume guard denominator. CloudFront publishes Requests as Sum only.
    data {
      ref_id         = "B"
      datasource_uid = grafana_data_source.cloudwatch_tb_dev.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "B"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_dev.uid }
        queryMode        = "Metrics"
        region           = "us-east-1"
        namespace        = "AWS/CloudFront"
        metricName       = "Requests"
        dimensions       = { Region = "Global", DistributionId = var.appointment_distribution_id }
        statistic        = "Sum"
        period           = "300"
        metricQueryType  = 0
        metricEditorMode = 0
        matchExact       = true
        id               = ""
        expression       = ""
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
        type       = "reduce"
        expression = "A"
        reducer    = "last"
        datasource = { type = "__expr__", uid = "__expr__" }
      })
    }
    data {
      ref_id         = "D"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId      = "D"
        type       = "reduce"
        expression = "B"
        reducer    = "last"
        datasource = { type = "__expr__", uid = "__expr__" }
      })
    }
    data {
      ref_id         = "E"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId      = "E"
        type       = "math"
        expression = "($C > 5) && ($D > 50)"
        datasource = { type = "__expr__", uid = "__expr__" }
      })
    }
    data {
      ref_id         = "F"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId      = "F"
        type       = "threshold"
        expression = "E"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["F"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  # 4xx is the parity item: the legacy prod distribution got a 4xxErrorRate alarm for
  # free from tb_pulumi, and #826 called that gap out. The threshold is deliberately
  # much looser than the 5xx one — a healthy SPA edge emits 404s for favicons and
  # probes all day — so this targets a structural break (e.g. the deep-link fallback
  # stops working and every /booking/* 403s at the edge), not background noise.
  rule {
    name           = "AppointmentEdgeHigh4xxRate"
    condition      = "F"
    for            = "15m"
    no_data_state  = "OK"
    exec_err_state = var.appointment_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "appointment"
    }
    annotations = {
      summary     = "appointment tb-dev CloudFront edge 4xx rate > 25%"
      description = "The CloudFront distribution in front of appointment.main.dev-thundermail.com has been answering more than 25% of viewer requests with a 4xx for 15 minutes, in 5-minute buckets holding more than 50 requests. At that rate this is structural rather than background 404 noise — suspect the SPA deep-link fallback (custom error responses mapping 403/404 to /index.html) or a cache behaviour that stopped matching. tb-dev is a dev environment, so this is warning-only (Slack, no page). Dashboard: Appointment / Appointment — CloudFront Edge (tb-dev)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/826"
    }

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
        metricName       = "4xxErrorRate"
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
      datasource_uid = grafana_data_source.cloudwatch_tb_dev.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "B"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_dev.uid }
        queryMode        = "Metrics"
        region           = "us-east-1"
        namespace        = "AWS/CloudFront"
        metricName       = "Requests"
        dimensions       = { Region = "Global", DistributionId = var.appointment_distribution_id }
        statistic        = "Sum"
        period           = "300"
        metricQueryType  = 0
        metricEditorMode = 0
        matchExact       = true
        id               = ""
        expression       = ""
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
        type       = "reduce"
        expression = "A"
        reducer    = "last"
        datasource = { type = "__expr__", uid = "__expr__" }
      })
    }
    data {
      ref_id         = "D"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId      = "D"
        type       = "reduce"
        expression = "B"
        reducer    = "last"
        datasource = { type = "__expr__", uid = "__expr__" }
      })
    }
    data {
      ref_id         = "E"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId      = "E"
        type       = "math"
        expression = "($C > 25) && ($D > 50)"
        datasource = { type = "__expr__", uid = "__expr__" }
      })
    }
    data {
      ref_id         = "F"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId      = "F"
        type       = "threshold"
        expression = "E"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["F"] }
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
    name      = "AppointmentEdgeHealthCheckFailing"
    condition = "C"
    for       = "3m"
    # Deliberately NOT "OK". Route53 publishes HealthCheckStatus unconditionally at
    # 60s granularity for every health check that exists — it has no dependence on site
    # traffic, unlike the CloudFront *ErrorRate ratios above where an empty result
    # genuinely is healthy. This group is also count-gated on
    # var.appointment_health_check_id, so by the time this rule exists at all an ID has
    # been pinned. NoData therefore cannot mean "healthy and idle"; it can only mean the
    # health check was deleted, Pulumi re-created it under a new ID, or cross-account
    # read access was lost. Reading that as green would make the one rule that is
    # supposed to be the cutover's automated "it came back" signal the rule most able to
    # go quietly blind. "Alerting" rather than the weaker "NoData" of
    # alerting-euc1-dr.tf:30 so the notification carries this rule's own name and
    # annotations instead of routing as alertname=DatasourceNoData — the same choice the
    # cert rules below make. `for = 3m` absorbs the first few evaluations after a new
    # health check is created but has not yet published. severity is still warning, so
    # this notifies Slack and does not page.
    no_data_state  = "Alerting"
    exec_err_state = var.appointment_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "appointment"
    }
    annotations = {
      summary     = "appointment.main.dev-thundermail.com is failing its Route53 health check, or is no longer being measured"
      description = "The Route53 health check for https://appointment.main.dev-thundermail.com/ is reporting unhealthy — the site is unreachable or no longer returns its SPA marker string. This is the automated 'it came back' signal for the CloudFront cutover: check the distribution, then the ALB origin, then the appointment pods on mzla-eks-tb-dev01. If this fired on NoData instead, the health check ID pinned as appointment_health_check_id in terraform/terraform.tfvars has stopped publishing HealthCheckStatus — it was most likely deleted, or re-created under a new ID by a pulumi up on the edge stack — and the pin must be updated before this rule means anything again. tb-dev is a dev environment, so this is warning-only (Slack, no page)."
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
# TWO certificates are in play for this edge, and they fail in different ways:
#
#   1. us-east-1 d62f83c9-…: the CloudFront VIEWER cert for
#      appointment.main.dev-thundermail.com (Pulumi, platform-infrastructure #1489).
#      Renewal failure = TLS error for every viewer. Publishes nothing until
#      CloudFront attaches it, so count-gated. It renews against its own Cloudflare
#      validation CNAME (DNSEndpoint appointment-cloudfront-acm-validation in
#      platform-infrastructure argocd/tb-dev/resources/dns/).
#   2. eu-central-1 474234d8-…: the cert on the DEDICATED ORIGIN Ingress
#      (appointment-origin-main, host appointment-origin.main.dev-thundermail.com).
#      THIS is the cert in the CloudFront -> ALB TLS path: the distribution connects
#      with OriginProtocolPolicy https-only and originSSLProtocols [TLSv1.2], so if
#      this cert lapses CloudFront cannot complete the origin handshake and every
#      viewer gets a hard 502. It is the Pulumi-managed *.main.dev-thundermail.com
#      wildcard (#1453), shared with the Send origin and the auth and accounts
#      Ingresses, validated by the main-wildcard-acm-validation DNSEndpoint. Its group
#      is count-gated on var.appointment_origin_cert_arn.
#
# Two rule *groups* rather than one because the two certs have different lifecycles
# and therefore different gating decisions. Deliberately NOT solved by
# dropping matchExact and taking a min across all dimensions in the namespace: that
# would alert on every cert in the tb-dev account, including keycloak's and accounts',
# which is outside this folder's ownership.
#
# interval_seconds is 600, not 60: ACM publishes DaysToExpiry roughly every 12 hours,
# so evaluating once a minute is ~2,880 cross-account GetMetricData calls a day (each
# behind an STS AssumeRole) to observe a value that moves once. 600 still divides the
# 1h `for` exactly, which Grafana requires.

# --- us-east-1: CloudFront viewer certificate ---
# Count-gated on the distribution ID. Verified read-only against ACM in 718959508124:
# us-east-1 publishes no AWS/CertificateManager metrics at all today, because the
# cert's InUseBy is empty. Creating this rule before CloudFront attaches the cert
# would put a permanently green, permanently dataless rule in the UI; gating it means
# the coverage gap shows up as a missing rule instead. no_data_state stays "OK" until
# step 4 of the header checklist confirms the metric really appears post-attach.
resource "grafana_rule_group" "appointment_edge_viewer_cert_expiry" {
  count = var.appointment_distribution_id == "" ? 0 : 1

  name               = "appointment-edge-viewer-cert-expiry"
  folder_uid         = grafana_folder.appointment.uid
  interval_seconds   = 600
  disable_provenance = true

  rule {
    name           = "AppointmentEdgeViewerCertExpiring"
    condition      = "C"
    for            = "1h"
    no_data_state  = "OK"
    exec_err_state = var.appointment_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "appointment"
    }
    annotations = {
      summary     = "appointment tb-dev CloudFront viewer certificate expires in < 21 days"
      description = "ACM certificate d62f83c9-70c6-4334-b070-3de8718dbc1e (us-east-1, the CloudFront viewer cert for appointment.main.dev-thundermail.com) has fewer than 21 days to expiry, so managed renewal has not completed. Check that its DNS validation CNAME still exists in Cloudflare (DNSEndpoint appointment-cloudfront-acm-validation in platform-infrastructure argocd/tb-dev/resources/dns/)."
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
        dimensions       = { CertificateArn = "arn:aws:acm:us-east-1:718959508124:certificate/d62f83c9-70c6-4334-b070-3de8718dbc1e" }
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

# --- eu-central-1: ORIGIN ALB certificate (the CloudFront -> ALB TLS path) --------
# Cert 2 in the list above, and the one whose lapse actually breaks the edge: the
# distribution dials appointment-origin.main.dev-thundermail.com with
# OriginProtocolPolicy https-only, so a failed renewal here is a hard 502 for every
# viewer, with no cover from the viewer rule above.
#
# Count-gated on var.appointment_origin_cert_arn rather than pinned inline, so a cert
# replacement can be handled by emptying one tfvars line. A guessed ARN would produce
# a rule that queries a non-existent dimension and, with no_data_state = "Alerting",
# fires immediately and permanently. Absent is honest; wrong is not.
#
# Once the ARN IS pinned, no_data_state = "Alerting": an in-use cert publishes
# DaysToExpiry, so silence means the cert was replaced under a new ARN and this rule
# has gone blind.
resource "grafana_rule_group" "appointment_edge_origin_alb_cert_expiry" {
  count = var.appointment_origin_cert_arn == "" ? 0 : 1

  name               = "appointment-edge-origin-alb-cert-expiry"
  folder_uid         = grafana_folder.appointment.uid
  interval_seconds   = 600
  disable_provenance = true

  rule {
    name           = "AppointmentOriginAlbCertExpiring"
    condition      = "C"
    for            = "1h"
    no_data_state  = "Alerting"
    exec_err_state = var.appointment_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "appointment"
    }
    annotations = {
      summary     = "appointment tb-dev CloudFront ORIGIN ALB certificate expires in < 21 days, or is no longer being measured"
      description = "The ACM certificate on the dedicated CloudFront origin Ingress (eu-central-1, appointment-origin-main, host appointment-origin.main.dev-thundermail.com) has fewer than 21 days to expiry, so managed renewal has not completed. This is the certificate in the CloudFront -> ALB TLS path: CloudFront connects with OriginProtocolPolicy https-only, so if it lapses the origin handshake fails and EVERY viewer gets a 502, not just a TLS warning. It is the Pulumi-managed *.main.dev-thundermail.com wildcard (platform-infrastructure #1453), also used by the Send origin, auth and accounts, so SendOriginAlbCertExpiring fires with this rule. Check its DNS validation CNAME in Cloudflare (DNSEndpoint main-wildcard-acm-validation in platform-infrastructure argocd/tb-dev/resources/dns/). If this fired as NoData instead, appointment_origin_cert_arn in terraform/terraform.tfvars is stale (the cert was replaced under a new ARN) and the pin must be updated. tb-dev is a dev environment, so this is warning-only (Slack, no page)."
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
        dimensions       = { CertificateArn = var.appointment_origin_cert_arn }
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
