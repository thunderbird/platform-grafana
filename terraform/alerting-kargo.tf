# Grafana alerting for Kargo promotion gating.
# platform-infrastructure#831 (phantom verification), #846 + #847 (the metrics this depends on).
#
# WHY THIS FILE EXISTS: a Kargo Stage with no `spec.verification` marks Freight verified
# INSTANTLY on promotion, without running anything. Downstream Stages request Freight with
# `sources.stages: [<upstream>]`, so production eligibility rests entirely on that upstream
# mark -- and a phantom mark is byte-indistinguishable from an earned one on the Freight
# object. `verifiedIn.verifiedAt` retains the FIRST mark rather than the most recent, so the
# timestamp does not help either. The only real evidence lives in
# Stage.status.freightHistory[].verificationHistory[].analysisRun, which is capped at 10
# entries and garbage-collects. 15 Freight were falsely eligible for production before those
# marks were purged on 2026-07-28, and nothing would ever have told us.
#
# Kargo exposes no metrics endpoint of its own, so the series below come from
# kube-state-metrics CustomResourceState against the Kargo Stage CRD -- see
# argocd/helm-values/victoriametrics.yaml in platform-infrastructure (#846, #847).
#
# Structure mirrors alerting-victorialogs.tf: A = PromQL, B = reduce, C = threshold (the
# alert `condition`), disable_provenance = true so the rules stay editable/idempotent.

resource "grafana_folder" "kargo" {
  title = "Kargo"
}

resource "grafana_rule_group" "catalog_kargo" {
  name       = "catalog-kargo-verification"
  folder_uid = grafana_folder.kargo.uid
  # 5m, not 60s: this detects a committed configuration gap, not an outage. Nothing about it
  # changes between scrapes.
  interval_seconds   = 300
  disable_provenance = true

  # --- A Stage that gates promotion performs no verification ---
  #
  # UNION OF TWO SIGNALS, because each alone has a blind spot:
  #
  #   kargo_stage_freight_direct == 1
  #     A Stage ingesting straight from a Warehouse. Flags it regardless of whether any
  #     downstream Stage exists yet -- but would miss a mid-pipeline Stage that is itself fed
  #     by another Stage.
  #
  #   label_replace(kargo_stage_freight_upstream, "stage", "$1", "upstream", "(.*)")
  #     Follows the real dependency edge: rewrites the label so the series identifies the
  #     UPSTREAM Stage being depended on, not the downstream one declaring it. Catches
  #     mid-pipeline Stages -- but stops flagging an upstream Stage the moment its only
  #     downstream consumer is deleted, even though the gap still exists.
  #
  # `count by (namespace, stage)` is NOT cosmetic. A bare `or` between these two does not
  # deduplicate, because the label_replace side carries an extra `upstream` label and so has a
  # different label set: measured live, the un-normalised union returned 4 series for 2 real
  # Stages, which would raise two alert instances per Stage. Collapsing to (namespace, stage)
  # yields one instance per Stage, valued 2 when both signals agree and 1 when only one does.
  #
  # `unless on (namespace, stage) kargo_stage_verification_template` removes any Stage that
  # has at least one AnalysisTemplate configured. Absence of that series is the whole signal.
  #
  # DELIBERATELY EXCLUDES tb-prod. Both tb-prod Stages have no verification and that is
  # intended -- tb-prod is deliberately degraded with no infra, is never auto-promoted to
  # (ProjectConfig autoPromotionEnabled: false), and the manual promotion gate is the control.
  # They are excluded structurally rather than by name matching: `freight_direct` emits no
  # series for them (their sources use `stages`, not `direct`), and the label_replace side
  # points AT their upstream rather than at them. No `stage!~".*prod"` regex to rot on rename.
  #
  # LIVE-VALIDATED on shared01, 2026-07-28 -- this expression returned exactly ONE series,
  # {namespace="tb-appointment", stage="tb-dev"} value 2, which is the single real defect:
  # tb-appointment has zero AnalysisTemplates and has never run a Kargo verification, so every
  # mark it has ever issued was phantom. tb-accounts/tb-dev was correctly NOT flagged (it
  # gained accounts-signin-e2e in #795).
  rule {
    name      = "KargoStageMissingVerification"
    condition = "C"
    # 30m so a Stage mid-bring-up does not raise a ticket before its AnalysisTemplate lands.
    for = "30m"
    # no_data_state = OK is LOAD-BEARING here, and this rule differs from every other rule in
    # this repo on that point. The healthy state of an `unless` offender-list is an EMPTY
    # result: when every gating Stage verifies, the query returns no series at all. With
    # no_data_state = "Alerting" this would fire permanently while the fleet is CORRECT --
    # precisely the spurious-NoData class that #31 existed to remove. Note the fix here is
    # no_data_state, NOT the `or vector(0)` idiom #31 used: this rule must carry per-Stage
    # namespace/stage labels to be actionable, and vector(0) produces a bare labelless series.
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      # ticket, NOT page. A missing verification block is a persistent config gap, not an
      # outage -- there is no 3am action. Per the live notification policy, severity=ticket
      # routes to pagerduty-platform-infra-low, while severity=page would go to
      # pagerduty-platform-infra. Paging on this is how an alert earns itself a mute.
      severity = "ticket"
      cluster  = "mzla-eks-shared01"
      service  = "kargo"
    }
    annotations = {
      summary     = "Kargo Stage {{ $labels.namespace }}/{{ $labels.stage }} gates promotion but runs no verification"
      description = "This Stage has no spec.verification.analysisTemplates, so Kargo marks every Freight promoted to it as verified instantly without running anything. Any downstream Stage requesting Freight with sources.stages:[this] is therefore ungated -- its production eligibility rests on a mark that was never earned. Phantom and earned marks are indistinguishable on the Freight object (verifiedIn.verifiedAt keeps the FIRST mark, not the latest); the only real evidence is Stage.status.freightHistory[].verificationHistory[].analysisRun, which is capped at 10 entries and garbage-collects, so audit from the Stage side and promptly. FIX: add spec.verification.analysisTemplates to the Stage and an AnalysisTemplate in the Kargo PROJECT namespace (not the app namespace) -- see argocd/kargo/tb-accounts/ for the accounts-signin-e2e pattern from #795. Verify a real AnalysisRun appears in freightHistory afterwards; a Stage with no AnalysisTemplate in its namespace cannot earn a mark at all. NOT expected to fire for tb-prod Stages: they are excluded structurally because they source from an upstream Stage rather than direct from a Warehouse."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/issues/831"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.prometheus_datasource_uid
      relative_time_range {
        from = 1800
        to   = 0
      }
      model = jsonencode({
        refId      = "A"
        datasource = { type = "prometheus", uid = var.prometheus_datasource_uid }
        expr       = "count by (namespace, stage) (label_replace(kargo_stage_freight_upstream, \"stage\", \"$1\", \"upstream\", \"(.*)\") or kargo_stage_freight_direct == 1) unless on (namespace, stage) kargo_stage_verification_template"
        instant    = true

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
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }
  }
}
