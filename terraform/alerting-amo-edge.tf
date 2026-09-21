# AMO production edge alerts (thunderbird/addons-server#394).
#
# Covers PRODUCTION resources in thunderbird-legacy (768512802988, us-west-2 unless
# noted), which despite the account name holds live AMO prod, not just old leftovers:
#
#   - ALB TargetResponseTime p50           -> amo-prod, amo-prod-versioncheck are slow
#   - ALB 502 rate (self-computed, ELB-generated 502s / RequestCount)
#                                           -> the ALB itself is failing requests, not
#                                              just passing through origin errors
#   - EC2 CPUUtilization                   -> the six atn-web-stream9 instances behind
#                                              amo-prod are pegged
#   - CloudFront 5xxErrorRate               -> the versioncheck/services edges are
#                                              serving errors (us-east-1, CloudFront is
#                                              global)
#
# ---------------------------------------------------------------------------
# Thresholds are from real traffic, read read-only against 768512802988 while writing
# this file (aws elbv2/cloudwatch describe/get-metric-statistics, profile
# mzla-tb-legacy). Baselines observed over the prior three days:
#
#   - amo-prod:              ~270k-420k req/hour, TargetResponseTime p50 ~35-42ms
#   - amo-prod-versioncheck: ~190k-410k req/hour, TargetResponseTime p50 ~4-5ms
#   - amo-prod 502 count:    normally single digits to tens per 5-minute bucket, but
#     with isolated one-bucket spikes into the thousands (e.g. 4850 in one 5m bucket)
#     that do not recur in adjacent buckets -- transient noise, not incidents. The
#     30-day daily history also shows a real multi-day sustained outage (millions of
#     502s/day, 2026-08-28 through 2026-09-14) that a rate-based, `for`-debounced rule
#     below would have caught without paging on the one-bucket blips.
#   - atn-web-stream9 CPU:   ~21-35% average, transient peaks to ~76% max, across all
#     six instances.
#   - CloudFront (E1PQMC7BGJOP5E, EGX44RIFURRUW): ~450k-780k req/hour each,
#     5xxErrorRate baseline 0.001-0.13%.
#
# All four groups use no_data_state = "Alerting", unlike the tb-dev edge files
# (alerting-appointment-edge.tf, alerting-send-edge.tf) where OK is used because a
# near-zero-traffic dev edge legitimately publishes nothing. These are PRODUCTION
# resources carrying hundreds of thousands of requests an hour around the clock, so
# every metric here publishes unconditionally once the datasource can reach it; silence
# is itself a fault (deleted resource, or the cross-account grant went away), per the
# same "no_data_state = Alerting everywhere silence is itself a fault" rule the
# appointment-edge header states. Until var.amo_metrics_iam_granted flips true, every
# evaluation is an AccessDenied (exec_err_state, gated OK) rather than NoData, so this
# has no effect yet -- see grafana_data_source.cloudwatch_tb_legacy in datasources.tf.
#
# severity = "warning" everywhere (Slack via the low-urgency PagerDuty contact point,
# alerting.tf -- no phone page), matching every other edge alert in this repo. These are
# new rules against production with thresholds set from three days of observation and no
# on-call has reviewed them yet; upgrading any of these to severity = "page" once the
# thresholds have proven themselves is a deliberate follow-up, not part of this PR.
#
# cluster label is "aws-tb-legacy", not an EKS cluster name -- these resources are plain
# EC2/ELB/CloudFront in the legacy AWS account, not Kubernetes-hosted.

# --- ALB TargetResponseTime p50 --------------------------------------------------
resource "grafana_rule_group" "amo_alb_latency" {
  name               = "amo-alb-latency"
  folder_uid         = grafana_folder.amo.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "AmoProdAlbHighLatency"
    condition      = "C"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = var.amo_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "aws-tb-legacy"
      service  = "amo"
    }
    annotations = {
      summary     = "amo-prod ALB TargetResponseTime p50 > 1s"
      description = "The amo-prod ALB (app/amo-prod/c089cbd004f1c9c0, us-west-2) has had a p50 TargetResponseTime above 1 second for 15 minutes. Baseline is ~35-42ms, so this is a ~25x regression. Check the AMO Django backend and its DB/cache dependencies first. Slack-only (severity=warning), no phone page."
      runbook_url = "https://github.com/thunderbird/addons-server/issues/394"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-west-2"
        namespace        = "AWS/ApplicationELB"
        metricName       = "TargetResponseTime"
        dimensions       = { LoadBalancer = "app/amo-prod/c089cbd004f1c9c0" }
        statistic        = "p50"
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
          evaluator = { type = "gt", params = [1] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  rule {
    name           = "AmoProdVersioncheckAlbHighLatency"
    condition      = "C"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = var.amo_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "aws-tb-legacy"
      service  = "amo"
    }
    annotations = {
      summary     = "amo-prod-versioncheck ALB TargetResponseTime p50 > 500ms"
      description = "The amo-prod-versioncheck ALB (app/amo-prod-versioncheck/4e942fe767db2956, us-west-2) has had a p50 TargetResponseTime above 500ms for 15 minutes. Baseline is ~4-5ms -- versioncheck is a lightweight endpoint, so this is a >100x regression. This ALB fronts /update/VersionCheck.php; check the versioncheck backend first. Slack-only (severity=warning), no phone page."
      runbook_url = "https://github.com/thunderbird/addons-server/issues/394"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-west-2"
        namespace        = "AWS/ApplicationELB"
        metricName       = "TargetResponseTime"
        dimensions       = { LoadBalancer = "app/amo-prod-versioncheck/4e942fe767db2956" }
        statistic        = "p50"
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
          evaluator = { type = "gt", params = [0.5] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}

# --- ALB 502 rate -----------------------------------------------------------------
# HTTPCode_ELB_502_Count is an ELB-generated error (as opposed to a 502 the origin
# itself returned), so it isolates ALB-level failures (e.g. no healthy targets,
# origin connection reset) from application 5xxs. ALB publishes no built-in *Rate
# metric for this the way CloudFront does, so the ratio is computed here: Sum(502) /
# Sum(RequestCount) * 100, guarded by a request-volume floor exactly like the
# CloudFront *ErrorRate rules elsewhere in this repo (alerting-appointment-edge.tf,
# alerting-send-edge.tf). The volume guard is 1000 requests/5m; real traffic here never
# drops below ~20k requests/5m, so it is a no-op today and exists only for
# consistency/safety.
#
# 1% (not 5%, unlike the CloudFront rules) because baseline here is far lower
# (0.04-0.2% of requests) and the known Aug 28-Sep 14 incident ran sustained rates far
# above 1%, so this loses little sensitivity while staying comfortably above noise.
# `for` = 15m against a 300s period is the same >= 3x-period debounce used throughout
# this repo, which is also what keeps this rule from firing on the single-bucket blips
# (e.g. 4850 502s in one 5-minute bucket, gone by the next) seen in the 3-day sample.
resource "grafana_rule_group" "amo_alb_502_rate" {
  name               = "amo-alb-502-rate"
  folder_uid         = grafana_folder.amo.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "AmoProdAlbHigh502Rate"
    condition      = "G"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = var.amo_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "aws-tb-legacy"
      service  = "amo"
    }
    annotations = {
      summary     = "amo-prod ALB 502 rate > 1%"
      description = "The amo-prod ALB (us-west-2) has answered more than 1% of requests with an ELB-generated 502 for 15 minutes, in 5-minute buckets holding more than 1000 requests. This is the ALB itself failing (no healthy target, connection reset), not an application-level error passed through. Check target group health for amo-prod first. Slack-only (severity=warning), no phone page."
      runbook_url = "https://github.com/thunderbird/addons-server/issues/394"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-west-2"
        namespace        = "AWS/ApplicationELB"
        metricName       = "HTTPCode_ELB_502_Count"
        dimensions       = { LoadBalancer = "app/amo-prod/c089cbd004f1c9c0" }
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
      ref_id         = "B"
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "B"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-west-2"
        namespace        = "AWS/ApplicationELB"
        metricName       = "RequestCount"
        dimensions       = { LoadBalancer = "app/amo-prod/c089cbd004f1c9c0" }
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
        expression = "($C / $D) * 100"
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
        type       = "math"
        expression = "($E > 1) && ($D > 1000)"
        datasource = { type = "__expr__", uid = "__expr__" }
      })
    }
    data {
      ref_id         = "G"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId      = "G"
        type       = "threshold"
        expression = "F"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["G"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  rule {
    name           = "AmoProdVersioncheckAlbHigh502Rate"
    condition      = "G"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = var.amo_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "aws-tb-legacy"
      service  = "amo"
    }
    annotations = {
      summary     = "amo-prod-versioncheck ALB 502 rate > 1%"
      description = "The amo-prod-versioncheck ALB (us-west-2, fronting /update/VersionCheck.php) has answered more than 1% of requests with an ELB-generated 502 for 15 minutes, in 5-minute buckets holding more than 1000 requests. Check target group health for amo-prod-versioncheck first. Slack-only (severity=warning), no phone page."
      runbook_url = "https://github.com/thunderbird/addons-server/issues/394"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-west-2"
        namespace        = "AWS/ApplicationELB"
        metricName       = "HTTPCode_ELB_502_Count"
        dimensions       = { LoadBalancer = "app/amo-prod-versioncheck/4e942fe767db2956" }
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
      ref_id         = "B"
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "B"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-west-2"
        namespace        = "AWS/ApplicationELB"
        metricName       = "RequestCount"
        dimensions       = { LoadBalancer = "app/amo-prod-versioncheck/4e942fe767db2956" }
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
        expression = "($C / $D) * 100"
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
        type       = "math"
        expression = "($E > 1) && ($D > 1000)"
        datasource = { type = "__expr__", uid = "__expr__" }
      })
    }
    data {
      ref_id         = "G"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId      = "G"
        type       = "threshold"
        expression = "F"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["G"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}

# --- atn-web-stream9 EC2 CPU -------------------------------------------------------
# One rule per instance rather than a single maxed-across-six rule, so a single hot
# instance (e.g. one node stuck behind a slow query while the other five idle normally)
# is not averaged/maxed away or, worse, hidden behind which instance happened to be
# hottest at evaluation time. Threshold 85% for 15m: observed max over the prior day
# peaked at ~76% without incident, so 85% sits above that noise floor. These are the six
# atn-web-stream9 instances behind amo-prod -- see the hard limit against changing them;
# this rule only reads CPUUtilization, no configuration of the instances themselves.
resource "grafana_rule_group" "amo_web_stream9_cpu" {
  name               = "amo-web-stream9-cpu"
  folder_uid         = grafana_folder.amo.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "AmoWebStream9HighCpu-0849417b39e5cd75e"
    condition      = "C"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = var.amo_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "aws-tb-legacy"
      service  = "amo"
    }
    annotations = {
      summary     = "atn-web-stream9 instance i-0849417b39e5cd75e CPU > 85%"
      description = "EC2 instance i-0849417b39e5cd75e (atn-web-stream9, one of six behind amo-prod, us-west-2) has averaged more than 85% CPU for 15 minutes. Observed max over the prior day peaked at ~76% without incident. Slack-only (severity=warning), no phone page. Do not modify this instance -- see the ATN hard limits in thunderbird/addons-server#394."
      runbook_url = "https://github.com/thunderbird/addons-server/issues/394"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-west-2"
        namespace        = "AWS/EC2"
        metricName       = "CPUUtilization"
        dimensions       = { InstanceId = "i-0849417b39e5cd75e" }
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
          evaluator = { type = "gt", params = [85] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  rule {
    name           = "AmoWebStream9HighCpu-075985a014e760311"
    condition      = "C"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = var.amo_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "aws-tb-legacy"
      service  = "amo"
    }
    annotations = {
      summary     = "atn-web-stream9 instance i-075985a014e760311 CPU > 85%"
      description = "EC2 instance i-075985a014e760311 (atn-web-stream9, one of six behind amo-prod, us-west-2) has averaged more than 85% CPU for 15 minutes. Observed max over the prior day peaked at ~52% without incident. Slack-only (severity=warning), no phone page. Do not modify this instance -- see the ATN hard limits in thunderbird/addons-server#394."
      runbook_url = "https://github.com/thunderbird/addons-server/issues/394"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-west-2"
        namespace        = "AWS/EC2"
        metricName       = "CPUUtilization"
        dimensions       = { InstanceId = "i-075985a014e760311" }
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
          evaluator = { type = "gt", params = [85] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  rule {
    name           = "AmoWebStream9HighCpu-09a11d743640d180f"
    condition      = "C"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = var.amo_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "aws-tb-legacy"
      service  = "amo"
    }
    annotations = {
      summary     = "atn-web-stream9 instance i-09a11d743640d180f CPU > 85%"
      description = "EC2 instance i-09a11d743640d180f (atn-web-stream9, one of six behind amo-prod, us-west-2) has averaged more than 85% CPU for 15 minutes. Observed max over the prior day peaked at ~76% without incident. Slack-only (severity=warning), no phone page. Do not modify this instance -- see the ATN hard limits in thunderbird/addons-server#394."
      runbook_url = "https://github.com/thunderbird/addons-server/issues/394"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-west-2"
        namespace        = "AWS/EC2"
        metricName       = "CPUUtilization"
        dimensions       = { InstanceId = "i-09a11d743640d180f" }
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
          evaluator = { type = "gt", params = [85] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  rule {
    name           = "AmoWebStream9HighCpu-0a028de0ae13a553d"
    condition      = "C"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = var.amo_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "aws-tb-legacy"
      service  = "amo"
    }
    annotations = {
      summary     = "atn-web-stream9 instance i-0a028de0ae13a553d CPU > 85%"
      description = "EC2 instance i-0a028de0ae13a553d (atn-web-stream9, one of six behind amo-prod, us-west-2) has averaged more than 85% CPU for 15 minutes. Observed max over the prior day peaked at ~60% without incident. Slack-only (severity=warning), no phone page. Do not modify this instance -- see the ATN hard limits in thunderbird/addons-server#394."
      runbook_url = "https://github.com/thunderbird/addons-server/issues/394"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-west-2"
        namespace        = "AWS/EC2"
        metricName       = "CPUUtilization"
        dimensions       = { InstanceId = "i-0a028de0ae13a553d" }
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
          evaluator = { type = "gt", params = [85] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  rule {
    name           = "AmoWebStream9HighCpu-09f6e881c22059948"
    condition      = "C"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = var.amo_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "aws-tb-legacy"
      service  = "amo"
    }
    annotations = {
      summary     = "atn-web-stream9 instance i-09f6e881c22059948 CPU > 85%"
      description = "EC2 instance i-09f6e881c22059948 (atn-web-stream9, one of six behind amo-prod, us-west-2) has averaged more than 85% CPU for 15 minutes. Observed max over the prior day peaked at ~55% without incident. Slack-only (severity=warning), no phone page. Do not modify this instance -- see the ATN hard limits in thunderbird/addons-server#394."
      runbook_url = "https://github.com/thunderbird/addons-server/issues/394"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-west-2"
        namespace        = "AWS/EC2"
        metricName       = "CPUUtilization"
        dimensions       = { InstanceId = "i-09f6e881c22059948" }
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
          evaluator = { type = "gt", params = [85] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }

  rule {
    name           = "AmoWebStream9HighCpu-0de43f666a95415d0"
    condition      = "C"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = var.amo_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "aws-tb-legacy"
      service  = "amo"
    }
    annotations = {
      summary     = "atn-web-stream9 instance i-0de43f666a95415d0 CPU > 85%"
      description = "EC2 instance i-0de43f666a95415d0 (atn-web-stream9, one of six behind amo-prod, us-west-2) has averaged more than 85% CPU for 15 minutes. Observed max over the prior day peaked at ~49% without incident. Slack-only (severity=warning), no phone page. Do not modify this instance -- see the ATN hard limits in thunderbird/addons-server#394."
      runbook_url = "https://github.com/thunderbird/addons-server/issues/394"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-west-2"
        namespace        = "AWS/EC2"
        metricName       = "CPUUtilization"
        dimensions       = { InstanceId = "i-0de43f666a95415d0" }
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
          evaluator = { type = "gt", params = [85] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}

# --- CloudFront 5xx rate (versioncheck + services) --------------------------------
# Same shape as the tb-dev CloudFront rules in alerting-appointment-edge.tf /
# alerting-send-edge.tf: 5xxErrorRate is a built-in AWS/CloudFront percentage metric,
# guarded by a Requests volume floor, region forced to us-east-1 per-query (CloudFront
# is global and only publishes there) while the datasource's defaultRegion stays
# us-west-2 for the ALB/EC2 rules above. 5% threshold matches the existing convention in
# this repo; baseline observed here is 0.001-0.13%, so 5% is a wide margin above noise
# while still catching a structural break.
resource "grafana_rule_group" "amo_cloudfront_5xx" {
  name               = "amo-cloudfront-5xx"
  folder_uid         = grafana_folder.amo.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "AmoVersioncheckEdgeHigh5xxRate"
    condition      = "F"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = var.amo_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "aws-tb-legacy"
      service  = "amo"
    }
    annotations = {
      summary     = "versioncheck.addons.thunderbird.net CloudFront edge 5xx rate > 5%"
      description = "The CloudFront distribution E1PQMC7BGJOP5E in front of versioncheck.addons.thunderbird.net (and versioncheck-bg.addons.thunderbird.net) has answered more than 5% of viewer requests with a 5xx for 15 minutes, in 5-minute buckets holding more than 50 requests. This fronts /update/VersionCheck.php -- check the amo-prod-versioncheck ALB and its target group first; CloudFront 5xx is usually the origin's error passed through. Slack-only (severity=warning), no phone page."
      runbook_url = "https://github.com/thunderbird/addons-server/issues/394"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-east-1"
        namespace        = "AWS/CloudFront"
        metricName       = "5xxErrorRate"
        dimensions       = { Region = "Global", DistributionId = "E1PQMC7BGJOP5E" }
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
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "B"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-east-1"
        namespace        = "AWS/CloudFront"
        metricName       = "Requests"
        dimensions       = { Region = "Global", DistributionId = "E1PQMC7BGJOP5E" }
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

  rule {
    name           = "AmoServicesEdgeHigh5xxRate"
    condition      = "F"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = var.amo_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "aws-tb-legacy"
      service  = "amo"
    }
    annotations = {
      summary     = "services.addons.thunderbird.net CloudFront edge 5xx rate > 5%"
      description = "The CloudFront distribution EGX44RIFURRUW in front of services.addons.thunderbird.net has answered more than 5% of viewer requests with a 5xx for 15 minutes, in 5-minute buckets holding more than 50 requests. Check the amo-prod ALB and its target group first; CloudFront 5xx is usually the origin's error passed through. Slack-only (severity=warning), no phone page."
      runbook_url = "https://github.com/thunderbird/addons-server/issues/394"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-east-1"
        namespace        = "AWS/CloudFront"
        metricName       = "5xxErrorRate"
        dimensions       = { Region = "Global", DistributionId = "EGX44RIFURRUW" }
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
      datasource_uid = grafana_data_source.cloudwatch_tb_legacy.uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId            = "B"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_legacy.uid }
        queryMode        = "Metrics"
        region           = "us-east-1"
        namespace        = "AWS/CloudFront"
        metricName       = "Requests"
        dimensions       = { Region = "Global", DistributionId = "EGX44RIFURRUW" }
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
}
