# BambooHR-fed services on mzla-workloads -> Grafana alert rules
# (platform-infrastructure #1209).
# https://github.com/thunderbird/platform-infrastructure/issues/1209
#
# Both services are daily CronJobs on the mzla-workloads cluster (eu-central-1)
# that push per-run gauges to the in-cluster vmagent. vmalert is DISABLED on
# workloads, so a VMRule shipped with either service would be inert; the alerts
# live here instead. Their READMEs already said so, but the rules were never
# added -- this file is the catch-up for bamboohr-anniversary-mailer and the
# day-one rules for bamboohr-coursera-inviter.
#
# Pattern matches alerting-converted-vmrules.tf: A = PromQL query against the
# VictoriaMetrics datasource (local.victoriametrics_ds_uid, defined there),
# B = reduce(last), C = threshold, disable_provenance = true. Both services are
# HR conveniences, not outage-grade, so every rule is severity=ticket ->
# pagerduty-platform-infra-low -> Slack #mzla-pages, never a page.
#
# Staleness uses `time() - max_over_time(<svc>_last_success_timestamp_seconds[26h])`
# for the same reason as KeycloakRealmBackupStale: the CronJob pushes ONCE a
# day, so a bare instant selector is empty for ~23h59m of every cycle and a
# NoData=Alerting rule would fire in every inter-push gap. max_over_time([26h])
# always yields the real age while a sample exists in the window, and yields NO
# data only when the service has not succeeded for >26h (the genuine "CronJob
# stopped / never ran" case) -> NoData=Alerting fires. 26h tolerates one late
# run without tolerating a missed day.
#
# Errors use `max_over_time(<svc>_errors[26h]) > 0`: each run pushes only its
# own count, so a bare instant selector would miss it between pushes. A failed
# per-employee send/invite does NOT block the run (last_success still advances),
# which is why errors get their own rule. no_data_state=OK here: no push at all
# is the staleness rule's job, not this one's.

# ---------------------------------------------------------------------------
# bamboohr-anniversary-mailer (platform-infrastructure #638)
# Daily at 13:30 UTC, namespace bamboohr-anniversary-mailer on mzla-workloads.
# ---------------------------------------------------------------------------
resource "grafana_rule_group" "bamboohr_anniversary_mailer" {
  name               = "bamboohr-anniversary-mailer"
  folder_uid         = grafana_folder.core_services.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "BambooHRAnniversaryMailerStale"
    condition      = "C"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    labels = {
      severity = "ticket"
      service  = "bamboohr-anniversary-mailer"
    }
    annotations = {
      summary     = "BambooHR anniversary/birthday mailer has not succeeded in over 26h"
      description = "No fully successful bamboohr-anniversary-mailer run has been recorded in over 26h. The CronJob runs daily at 13:30 UTC in namespace bamboohr-anniversary-mailer on mzla-workloads (eu-central-1). Today's work-anniversary and birthday emails from people@thunderbird.net may not have gone out; BambooHR's own emails are disabled, so this service is the sole sender. Check the CronJob / last Job logs (kubectl -n bamboohr-anniversary-mailer get jobs), the BambooHR API key ExternalSecret, and SES. A re-run is safe: the S3 ledger prevents double-sends."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/services/bamboohr-anniversary-mailer/README.md"
    }

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
        expr          = "time() - max_over_time(anniversary_mailer_last_success_timestamp_seconds[26h])"
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

  rule {
    name           = "BambooHRAnniversaryMailerErrors"
    condition      = "C"
    for            = "5m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    labels = {
      severity = "ticket"
      service  = "bamboohr-anniversary-mailer"
    }
    annotations = {
      summary     = "BambooHR anniversary/birthday mailer reported per-employee errors"
      description = "The most recent bamboohr-anniversary-mailer run (daily 13:30 UTC, namespace bamboohr-anniversary-mailer on mzla-workloads) recorded one or more per-employee errors: an SES send or BambooHR lookup failed for someone. The run itself completed, so the staleness rule will not fire. Check the Job logs for the affected employee IDs; because sends are ledgered, re-running the Job only retries the failed ones. Note ledger_write_failures is separate (email went out, receipt did not) and risks a duplicate on the next run."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/services/bamboohr-anniversary-mailer/README.md"
    }

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
        expr          = "max_over_time(anniversary_mailer_errors[26h])"
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
# bamboohr-coursera-inviter (platform-infrastructure #1209)
# Daily CronJob, namespace bamboohr-coursera-inviter on mzla-workloads.
#
# PAUSED: the service is not deployed yet (#1209), so these rules would sit in
# NoData=Alerting forever. is_paused = true keeps them provisioned but not
# evaluated; flip to false in the platform-grafana PR that pairs with the
# platform-infrastructure PR unsuspending the CronJob.
# ---------------------------------------------------------------------------
resource "grafana_rule_group" "bamboohr_coursera_inviter" {
  name               = "bamboohr-coursera-inviter"
  folder_uid         = grafana_folder.core_services.uid
  interval_seconds   = 60
  disable_provenance = true

  rule {
    name           = "BambooHRCourseraInviterStale"
    condition      = "C"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    is_paused      = true
    labels = {
      severity = "ticket"
      service  = "bamboohr-coursera-inviter"
    }
    annotations = {
      summary     = "BambooHR -> Coursera new-hire inviter has not succeeded in over 26h"
      description = "No fully successful bamboohr-coursera-inviter run has been recorded in over 26h. The CronJob runs daily in namespace bamboohr-coursera-inviter on mzla-workloads (eu-central-1) and creates Coursera program invitations for new FTE hires whose BambooHR hire date has passed. A stalled run means a new hire may not get their Coursera invite. Check the CronJob / last Job logs, the BambooHR + Coursera ExternalSecret, and Coursera API auth. A re-run is safe: the S3 ledger prevents duplicate invites."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/services/bamboohr-coursera-inviter/README.md"
    }

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
        expr          = "time() - max_over_time(coursera_inviter_last_success_timestamp_seconds[26h])"
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

  rule {
    name           = "BambooHRCourseraInviterErrors"
    condition      = "C"
    for            = "5m"
    no_data_state  = "OK"
    exec_err_state = "Error"
    is_paused      = true
    labels = {
      severity = "ticket"
      service  = "bamboohr-coursera-inviter"
    }
    annotations = {
      summary     = "BambooHR -> Coursera new-hire inviter reported per-employee errors"
      description = "The most recent bamboohr-coursera-inviter run (daily, namespace bamboohr-coursera-inviter on mzla-workloads) recorded one or more per-employee errors: a Coursera invitation call or BambooHR lookup failed for someone. The run itself completed, so the staleness rule will not fire. Check the Job logs for the affected employee IDs; because invites are ledgered, re-running the Job only retries the failed ones. ledger_write_failures is separate (invite created, receipt not written) and risks a duplicate invite next run."
      runbook_url = "https://github.com/thunderbird/platform-infrastructure/blob/main/services/bamboohr-coursera-inviter/README.md"
    }

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
        expr          = "max_over_time(coursera_inviter_errors[26h])"
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
