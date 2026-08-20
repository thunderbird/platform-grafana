# Send CloudFront edge — tb-dev alerting (platform-infrastructure #1043).
#
# Covers the CloudFront distribution E1O1C4QY9LB2MO in front of
# send.tb-dev.thunderbird.dev in the tb-dev account (718959508124). Concerns:
#
#   - CloudFront 5xx/4xx error rate            -> the edge is serving errors
#   - CloudFront OriginLatency (p90)           -> the origin chain is slow (#1043 asks
#                                                 for this explicitly; appointment has no
#                                                 equivalent — a hand-written Pulumi
#                                                 distribution inherits no tb_pulumi alarm)
#   - Route53 HealthCheckStatus (synthetic)    -> the site is unreachable end-to-end
#   - Route53 HealthCheckPercentageHealthy     -> a REGIONAL edge failure, which the
#                                                 aggregate Status hides until <18% of
#                                                 checkers are healthy (#1052 handoff)
#   - ACM DaysToExpiry < 21 on all THREE certs -> a renewal is silently failing
#     (us-east-1 viewer, eu-central-1 public ALB, eu-central-1 origin ALB)
#
# The region-handling, severity and no-data/pin discipline are identical to the
# appointment edge and are documented at length in the header of
# alerting-appointment-edge.tf, which is NORMATIVE here and not restated
# (us-east-1 per-query override; severity=warning -> Slack-only; groups count-gated on
# their id/ARN pin).
#
# ---------------------------------------------------------------------------
# What differs from appointment: Send's edge is already fully live
# ---------------------------------------------------------------------------
# Appointment shipped its rules before the Pulumi half existed, so it left ids empty and
# used no_data_state="OK"/exec_err_state="OK" as placeholders. For Send every resource
# exists TODAY and was verified read-only against 718959508124:
#
#   - The distribution, its MonitoringSubscription and all three certs shipped with #895;
#     the health check with #1052. All ids are pinned in terraform.tfvars from the start.
#   - The cross-account role mzla-tb-dev-grafana-cloudwatch already reads CloudWatch
#     (#951 granted cloudwatch:GetMetricData on "*", #1048 extended it), so
#     var.send_metrics_iam_granted defaults true and exec_err_state is "Error": an
#     AccessDenied here is a real regression, not the benign not-yet-granted state it was
#     for appointment.
#   - The us-east-1 VIEWER cert publishes DaysToExpiry now (its InUseBy is the
#     distribution), unlike appointment's which published nothing pre-attach. So its group
#     uses no_data_state="Alerting" (NoData = the pin went stale), not "OK".

# --- CloudFront error rates ------------------------------------------------------
# Both rules carry a Requests volume guard: the *ErrorRate metrics are ratios and tb-dev
# Send has near-zero organic traffic, so without a denominator one 500 from a scanner in
# a two-request bucket is 50%. See alerting-appointment-edge.tf for the `for` >= 3x
# period debouncing rationale.
resource "grafana_rule_group" "send_edge_cloudfront" {
  count = var.send_distribution_id == "" ? 0 : 1

  name               = "send-edge-cloudfront"
  folder_uid         = grafana_folder.send.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "SendEdgeHigh5xxRate"
    condition      = "F"
    for            = "15m"
    no_data_state  = "OK"
    exec_err_state = var.send_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "send"
    }
    annotations = {
      summary     = "send tb-dev CloudFront edge 5xx rate > 5%"
      description = "The CloudFront distribution in front of send.tb-dev.thunderbird.dev has been answering more than 5% of viewer requests with a 5xx for 15 minutes, in 5-minute buckets holding more than 50 requests. Check the origin ALB and the send-backend/nginx pods on mzla-eks-tb-dev01 first — CloudFront 5xx is usually the origin's 5xx passed through, and nginx returns a hard 500 via error_page when send-backend is down. tb-dev is a dev environment, so this is warning-only (Slack, no page). Dashboard: Send / Send — CloudFront Edge (tb-dev)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1043"
    }

    # 5xxErrorRate is a percentage 0-100, so the threshold is 5, not 0.05. Average is the
    # only meaningful statistic for the *Rate metrics.
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
        dimensions       = { Region = "Global", DistributionId = var.send_distribution_id }
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
        dimensions       = { Region = "Global", DistributionId = var.send_distribution_id }
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

  # 4xx threshold is deliberately much looser than 5xx: a healthy edge emits 404s for
  # probes all day, so this targets a structural break (e.g. the /api/* behaviour starts
  # 403-ing at the edge), not background noise.
  rule {
    name           = "SendEdgeHigh4xxRate"
    condition      = "F"
    for            = "15m"
    no_data_state  = "OK"
    exec_err_state = var.send_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "send"
    }
    annotations = {
      summary     = "send tb-dev CloudFront edge 4xx rate > 25%"
      description = "The CloudFront distribution in front of send.tb-dev.thunderbird.dev has been answering more than 25% of viewer requests with a 4xx for 15 minutes, in 5-minute buckets holding more than 50 requests. At that rate this is structural rather than background 404 noise — suspect a cache behaviour or ALB host-rule that stopped matching, or the /api/* path 403-ing at the edge. tb-dev is a dev environment, so this is warning-only (Slack, no page). Dashboard: Send / Send — CloudFront Edge (tb-dev)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1043"
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
        dimensions       = { Region = "Global", DistributionId = var.send_distribution_id }
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
        dimensions       = { Region = "Global", DistributionId = var.send_distribution_id }
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

# --- CloudFront origin latency ---------------------------------------------------
# #1043 asks for an OriginLatency alert explicitly; appointment has none. OriginLatency
# is time-to-last-byte for origin-bound (cache-miss) requests, published only because the
# MonitoringSubscription is live (#895). p90 rather than Average so a slow tail is not
# hidden, and the same Requests volume guard as the error rules: at ~0 traffic a single
# cache-miss must not define p90. no_data_state="OK" — with nothing missing the cache
# there is legitimately no origin-bound traffic and thus no datapoint, exactly like the
# *ErrorRate ratios. 3000ms is a loose dev-edge ceiling (the origin chain is
# CloudFront -> ALB -> nginx -> Express /api/*), meant to catch a stuck origin, not to
# SLO-tune.
resource "grafana_rule_group" "send_edge_origin_latency" {
  count = var.send_distribution_id == "" ? 0 : 1

  name               = "send-edge-origin-latency"
  folder_uid         = grafana_folder.send.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "SendEdgeHighOriginLatency"
    condition      = "F"
    for            = "15m"
    no_data_state  = "OK"
    exec_err_state = var.send_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "send"
    }
    annotations = {
      summary     = "send tb-dev CloudFront origin latency p90 > 3s"
      description = "The CloudFront distribution in front of send.tb-dev.thunderbird.dev has had a p90 OriginLatency above 3000ms for 15 minutes, in 5-minute buckets holding more than 50 requests. OriginLatency covers cache-miss requests only (CloudFront -> origin ALB -> nginx -> send-backend/Express), so a rise points at the origin chain rather than the edge: check the send-backend pods and their DB/B2 dependencies on mzla-eks-tb-dev01. tb-dev is a dev environment, so this is warning-only (Slack, no page). Dashboard: Send / Send — CloudFront Edge (tb-dev)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1043"
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
        metricName       = "OriginLatency"
        dimensions       = { Region = "Global", DistributionId = var.send_distribution_id }
        statistic        = "p90"
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
        dimensions       = { Region = "Global", DistributionId = var.send_distribution_id }
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
        expression = "($C > 3000) && ($D > 50)"
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
# Two rules on the one #1052 health check. HealthCheckStatus is the aggregate and holds
# at 1 while >18% of checkers are healthy, so on its own it is a GLOBAL-outage detector
# and a regional edge failure is invisible on it. The #1052 handoff calls that out; the
# second rule below reads HealthCheckPercentageHealthy to close the gap.
resource "grafana_rule_group" "send_edge_synthetic" {
  count = var.send_health_check_id == "" ? 0 : 1

  name               = "send-edge-synthetic"
  folder_uid         = grafana_folder.send.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name      = "SendEdgeHealthCheckFailing"
    condition = "C"
    for       = "3m"
    # no_data_state="Alerting", not "OK": Route53 publishes HealthCheckStatus every 60s
    # for every health check that exists, with no traffic dependence, and this group is
    # count-gated on the id — so NoData can only mean the check was deleted or re-created
    # under a new id. This is the cutover's automated "it came back" signal, so it must
    # not go quietly green. "Alerting" over the weaker "NoData" so the notification
    # carries this rule's own name/annotations. See alerting-appointment-edge.tf for the
    # full rationale.
    no_data_state  = "Alerting"
    exec_err_state = var.send_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "send"
    }
    annotations = {
      summary     = "send.tb-dev.thunderbird.dev is failing its Route53 health check, or is no longer being measured"
      description = "The Route53 health check for https://send.tb-dev.thunderbird.dev/api/health is reporting unhealthy — the full chain (CloudFront -> origin ALB -> nginx -> Express) no longer returns 200 with the \"API is alive\" marker. This is the automated 'it came back' signal for the CloudFront cutover: check the distribution, then the origin ALB, then the send-backend pods on mzla-eks-tb-dev01. Note the probe only exercises the /api/* cache behaviour, so an AllViewer flip or ALB host-rule change on the DEFAULT behaviour that serves page loads leaves this green (known gap, #1052). If this fired on NoData instead, send_health_check_id in terraform/terraform.tfvars has stopped publishing HealthCheckStatus — it was deleted or re-created under a new id by a pulumi up on the edge stack — and the pin must be updated before this rule means anything again. tb-dev is a dev environment, so this is warning-only (Slack, no page)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1043"
    }

    # HealthCheckStatus is 1 (healthy) / 0 (unhealthy), published in us-east-1 only.
    # Minimum over the period so a single failing bucket is not averaged away.
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
        dimensions       = { HealthCheckId = var.send_health_check_id }
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

  # The regional-failure rule the #1052 handoff asks for. HealthCheckPercentageHealthy is
  # the fraction of Route53 checkers reporting healthy; it drops as individual checkers
  # fail, well before the aggregate Status flips at the 18% line. < 75% for 15m catches a
  # sustained regional degradation while tolerating a transient single-checker blip.
  # no_data_state="OK" here (not "Alerting"): the SendEdgeHealthCheckFailing rule above is
  # the canonical stale-pin/deleted-check detector, and duplicating "Alerting" on NoData
  # would double-notify on the same fault. The `for`=15m against a 60s metric period is
  # the debounce; Average, not Minimum, so one checker flapping for one minute does not
  # count as 15m of degradation.
  rule {
    name           = "SendEdgeHealthCheckRegionalDegraded"
    condition      = "C"
    for            = "15m"
    no_data_state  = "OK"
    exec_err_state = var.send_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "send"
    }
    annotations = {
      summary     = "send.tb-dev.thunderbird.dev Route53 checkers < 75% healthy (regional edge failure)"
      description = "Fewer than 75% of Route53 checkers report https://send.tb-dev.thunderbird.dev/api/health healthy, sustained for 15 minutes. The aggregate HealthCheckStatus holds at 1 until <18% of checkers are healthy, so this rule is what surfaces a REGIONAL edge failure — a single CloudFront POP or region degrading — that SendEdgeHealthCheckFailing cannot see. Check for a region-specific CloudFront or origin-ALB problem. tb-dev is a dev environment, so this is warning-only (Slack, no page). Dashboard: Send / Send — CloudFront Edge (tb-dev)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1043"
    }

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
        metricName       = "HealthCheckPercentageHealthy"
        dimensions       = { HealthCheckId = var.send_health_check_id }
        statistic        = "Average"
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
          evaluator = { type = "lt", params = [75] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}

# --- ACM certificate expiry ------------------------------------------------------
# THREE certificates are in play for this edge, all live and all publishing DaysToExpiry
# today (verified read-only against ACM in 718959508124). Unlike appointment — where the
# viewer cert published nothing pre-attach and the origin ARN was unknown — every ARN
# here is confirmed, so all three groups ship armed. The three-cert model, the reason for
# three groups rather than one min-across-namespace query, and the interval_seconds=600
# choice are documented in alerting-appointment-edge.tf and not restated.
#
#   1. us-east-1 a8e5927e-… — CloudFront VIEWER cert for send.tb-dev.thunderbird.dev.
#   2. eu-central-1 18b15f16-… — cert on the PUBLIC Ingress (host
#      send.tb-dev.thunderbird.dev). Co-holder of the DNS-validation CNAME the viewer
#      cert also renews against — both cover the same domain, so ACM derives the same
#      validation record for both and one deleted record breaks renewal on both.
#   3. eu-central-1 8d6677fc-… (var.send_origin_cert_arn) — cert on the DEDICATED ORIGIN
#      Ingress (host send-origin.tb-dev.thunderbird.dev). THIS is the cert in the
#      CloudFront -> ALB TLS path; if it lapses every viewer gets a hard 502.

# --- eu-central-1: PUBLIC ALB certificate (co-holder of the shared validation CNAME) ---
# Pinned inline, neither count-gated nor no_data_state="OK": this cert exists and
# publishes DaysToExpiry today, so absence of data means the pinned ARN is wrong — most
# likely the AWS Load Balancer Controller re-minted it — and a blind rule must not read
# as green.
resource "grafana_rule_group" "send_edge_public_alb_cert_expiry" {
  name               = "send-edge-public-alb-cert-expiry"
  folder_uid         = grafana_folder.send.uid
  interval_seconds   = 600
  disable_provenance = true

  rule {
    name           = "SendPublicAlbCertExpiring"
    condition      = "C"
    for            = "1h"
    no_data_state  = "Alerting"
    exec_err_state = var.send_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "send"
    }
    annotations = {
      summary     = "send tb-dev PUBLIC ALB certificate expires in < 21 days, or is no longer being measured"
      description = "ACM certificate 18b15f16-6f5e-416a-bcea-e250ea5cae61 (eu-central-1, minted by the AWS Load Balancer Controller for the PUBLIC send Ingress on mzla-eks-tb-dev01, host send.tb-dev.thunderbird.dev) has fewer than 21 days to expiry, so managed renewal has not completed. This is NOT the CloudFront origin cert — see SendOriginAlbCertExpiring for that one. It co-holds the single Route53 DNS-validation CNAME that the us-east-1 CloudFront viewer cert renews against, so one missing record breaks renewal on both: check that validation CNAME first, and that an Ingress still serves send.tb-dev.thunderbird.dev, because the LB Controller garbage-collects the record if none does. If this fired as NoData instead, the certificate ARN pinned in terraform/alerting-send-edge.tf has stopped publishing DaysToExpiry: the load balancer controller has almost certainly re-minted the cert under a new ARN, and the pin must be updated. tb-dev is a dev environment, so this is warning-only (Slack, no page)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1043"
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
        dimensions       = { CertificateArn = "arn:aws:acm:eu-central-1:718959508124:certificate/18b15f16-6f5e-416a-bcea-e250ea5cae61" }
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

# --- us-east-1: CloudFront viewer certificate ---
# Count-gated on the distribution id for symmetry with the CloudFront groups, but unlike
# appointment's viewer rule this uses no_data_state="Alerting": the cert is in use by the
# distribution and publishes DaysToExpiry today (verified read-only), so NoData means the
# pinned ARN went stale, not "healthy and idle".
resource "grafana_rule_group" "send_edge_viewer_cert_expiry" {
  count = var.send_distribution_id == "" ? 0 : 1

  name               = "send-edge-viewer-cert-expiry"
  folder_uid         = grafana_folder.send.uid
  interval_seconds   = 600
  disable_provenance = true

  rule {
    name           = "SendEdgeViewerCertExpiring"
    condition      = "C"
    for            = "1h"
    no_data_state  = "Alerting"
    exec_err_state = var.send_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "send"
    }
    annotations = {
      summary     = "send tb-dev CloudFront viewer certificate expires in < 21 days, or is no longer being measured"
      description = "ACM certificate a8e5927e-a6fe-4a8b-8dac-8d72e579d05c (us-east-1, the CloudFront viewer cert for send.tb-dev.thunderbird.dev) has fewer than 21 days to expiry, so managed renewal has not completed. Check that the DNS validation CNAME still exists in Route53 — this cert shares its validation record with the eu-central-1 public ALB cert, so one missing record breaks both. If this fired as NoData instead, the cert stopped publishing DaysToExpiry and the ARN pinned in terraform/alerting-send-edge.tf must be updated. tb-dev is a dev environment, so this is warning-only (Slack, no page)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1043"
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
        dimensions       = { CertificateArn = "arn:aws:acm:us-east-1:718959508124:certificate/a8e5927e-a6fe-4a8b-8dac-8d72e579d05c" }
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
# The one whose lapse actually breaks the edge: the distribution dials
# send-origin.tb-dev.thunderbird.dev with OriginProtocolPolicy https-only, so a failed
# renewal here is a hard 502 for every viewer. Count-gated on var.send_origin_cert_arn
# (pinned in terraform.tfvars from a live lookup) rather than inline, because the LB
# Controller can re-mint it under a new ARN; no_data_state="Alerting" so a stale pin
# surfaces rather than reading green.
resource "grafana_rule_group" "send_edge_origin_alb_cert_expiry" {
  count = var.send_origin_cert_arn == "" ? 0 : 1

  name               = "send-edge-origin-alb-cert-expiry"
  folder_uid         = grafana_folder.send.uid
  interval_seconds   = 600
  disable_provenance = true

  rule {
    name           = "SendOriginAlbCertExpiring"
    condition      = "C"
    for            = "1h"
    no_data_state  = "Alerting"
    exec_err_state = var.send_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-dev01"
      service  = "send"
    }
    annotations = {
      summary     = "send tb-dev CloudFront ORIGIN ALB certificate expires in < 21 days, or is no longer being measured"
      description = "The ACM certificate on the dedicated CloudFront origin Ingress (eu-central-1, host send-origin.tb-dev.thunderbird.dev, minted by the AWS Load Balancer Controller) has fewer than 21 days to expiry, so managed renewal has not completed. This is the certificate in the CloudFront -> ALB TLS path: CloudFront connects with OriginProtocolPolicy https-only, so if it lapses the origin handshake fails and EVERY viewer gets a 502, not just a TLS warning. Unlike the public ALB cert it has its own single-SAN DNS-validation CNAME, so check that record specifically. If this fired as NoData instead, send_origin_cert_arn in terraform/terraform.tfvars is stale — the load balancer controller re-minted the cert under a new ARN — and the pin must be updated. tb-dev is a dev environment, so this is warning-only (Slack, no page)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1043"
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
        dimensions       = { CertificateArn = var.send_origin_cert_arn }
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
