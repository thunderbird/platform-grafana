resource "grafana_rule_group" "thundermail_stage" {
  name               = "thundermail-stage"
  folder_uid         = grafana_folder.thundermail.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "ThundermailStageProbeFailed"
    condition      = "C"
    for            = "10m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-stage01"
      service  = "thundermail"
    }
    annotations = {
      summary     = "Stage mail probe {{ $labels.instance }} has been failing for 10m"
      description = "blackbox-exporter has reported probe_success=0 for {{ $labels.instance }} for 10 minutes. Targets are the VMProbe in platform-infrastructure argocd/tb-stage/observability: mail.stage-thundermail.com on 993 (IMAPS), 465 (SMTPS) and 443 (JMAP/HTTPS) behind the stalwart-nginx-thundermail NLB, plus HTTPS on accounts. and auth.stage-thundermail.com. During the #1536 cutover window Stalwart is scaled to 0 on purpose, so expect this to fire then. Otherwise check the Thundermail / Stalwart (tb-stage) dashboard: NLB unhealthy targets, then the nginx and stalwart pods in namespace thundermail. tb-stage is a staging environment, so this is warning-only (Slack, no page)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1545"
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
        expr          = "count by (instance) (probe_success{instance=~\".*stage-thundermail\\\\.com.*\"} == 0)"
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

  rule {
    name           = "ThundermailStageDeploymentUnavailable"
    condition      = "C"
    for            = "15m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-stage01"
      service  = "thundermail"
    }
    annotations = {
      summary     = "thundermail/{{ $labels.deployment }} on tb-stage has 0 available replicas"
      description = "Deployment {{ $labels.deployment }} in namespace thundermail on mzla-eks-tb-stage01 wants at least one replica but has had none available for 15 minutes. A deliberate scale-to-zero (the #1536 freeze) sets spec replicas to 0 and does not match this rule. Check the pod events and the stalwart container logs on the Thundermail / Stalwart (tb-stage) dashboard; a stuck Neon connection or a bad config promotion are the usual causes. tb-stage is a staging environment, so this is warning-only (Slack, no page)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1545"
    }

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
        expr          = "count by (deployment) (kube_deployment_spec_replicas{cluster=\"mzla-eks-tb-stage01\",namespace=\"thundermail\"} > 0 and kube_deployment_status_replicas_available{cluster=\"mzla-eks-tb-stage01\",namespace=\"thundermail\"} == 0)"
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
}

resource "grafana_rule_group" "thundermail_stage_nlb" {
  count = var.thundermail_stage_nlb_arn_suffix == "" ? 0 : 1

  name               = "thundermail-stage-nlb"
  folder_uid         = grafana_folder.thundermail.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "ThundermailStageNlbUnhealthyTargets"
    condition      = "C"
    for            = "10m"
    no_data_state  = "OK"
    exec_err_state = var.thundermail_stage_metrics_iam_granted ? "Error" : "OK"
    labels = {
      severity = "warning"
      cluster  = "mzla-eks-tb-stage01"
      service  = "thundermail"
    }
    annotations = {
      summary     = "Stage mail NLB target group {{ $labels.TargetGroup }} has unhealthy targets"
      description = "AWS/NetworkELB UnHealthyHostCount has been above 0 for 10 minutes on the stalwart-nginx-thundermail NLB in 539160020475 (one target group per listener: 25, 443, 465, 587, 993, 4190). The NLB health check is HTTP on nginx pod port 8081, so this means the nginx pod in namespace thundermail on mzla-eks-tb-stage01 is not answering, or the lb security group no longer reaches it. Check the nginx deployment and the stalwart-nginx-lb-thundermail security group. tb-stage is a staging environment, so this is warning-only (Slack, no page)."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/1545"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.cloudwatch_tb_stage.uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId            = "A"
        datasource       = { type = "cloudwatch", uid = grafana_data_source.cloudwatch_tb_stage.uid }
        queryMode        = "Metrics"
        region           = "eu-central-1"
        namespace        = "AWS/NetworkELB"
        metricName       = "UnHealthyHostCount"
        dimensions       = { LoadBalancer = var.thundermail_stage_nlb_arn_suffix, TargetGroup = "*" }
        statistic        = "Maximum"
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
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}
