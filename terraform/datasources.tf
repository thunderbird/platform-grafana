# CloudWatch Logs datasources — added for #122
# Grafana reads logs via IRSA (same-account) and cross-account assume role.

# Application logs (Vector dual-ship) — eu-central-1
resource "grafana_data_source" "cloudwatch_shared" {
  type = "cloudwatch"
  name = "CloudWatch Logs — shared01"

  json_data_encoded = jsonencode({
    defaultRegion = "eu-central-1"
    authType      = "default"
  })
}

# EKS control plane logs — us-east-1 (cluster region)
resource "grafana_data_source" "cloudwatch_shared_control_plane" {
  type = "cloudwatch"
  name = "CloudWatch Logs — shared01 control plane"

  json_data_encoded = jsonencode({
    defaultRegion = "us-east-1"
    authType      = "default"
  })
}

# Application + control plane logs (both eu-central-1)
resource "grafana_data_source" "cloudwatch_workloads" {
  type = "cloudwatch"
  name = "CloudWatch Logs — workloads01"

  json_data_encoded = jsonencode({
    defaultRegion = "eu-central-1"
    authType      = "assumeRole"
    assumeRoleArn = "arn:aws:iam::668807881758:role/workloads-prod-grafana-cloudwatch"
  })
}

# Cross-account CloudWatch Logs — tb-dev (718959508124) — added for #195
# Grafana IRSA → sts:AssumeRole → mzla-tb-dev-grafana-cloudwatch
resource "grafana_data_source" "cloudwatch_tb_dev" {
  type = "cloudwatch"
  name = "CloudWatch Logs — tb-dev01"

  json_data_encoded = jsonencode({
    defaultRegion = "eu-central-1"
    authType      = "assumeRole"
    assumeRoleArn = "arn:aws:iam::718959508124:role/mzla-tb-dev-grafana-cloudwatch"
  })
}

# Cross-account CloudWatch Logs — tb-prod (689951664252) — added for #195
# Grafana IRSA → sts:AssumeRole → mzla-tb-prod-grafana-cloudwatch
resource "grafana_data_source" "cloudwatch_tb_prod" {
  type = "cloudwatch"
  name = "CloudWatch Logs — tb-prod01"

  json_data_encoded = jsonencode({
    defaultRegion = "eu-central-1"
    authType      = "assumeRole"
    assumeRoleArn = "arn:aws:iam::689951664252:role/mzla-tb-prod-grafana-cloudwatch"
  })
}

# Cross-account CloudWatch - thunderbird-legacy (768512802988) - added for
# thunderbird/addons-server#394. This account holds live AMO production (amo-prod,
# amo-prod-versioncheck ALBs; the atn-web-stream9 EC2 fleet; the versioncheck/services
# CloudFront distributions), NOT just old leftovers despite the account name.
#
# The role this datasource assumes, mzla-tb-legacy-grafana-cloudwatch, does NOT exist
# yet as of this PR. Unlike cloudwatch_tb_dev/cloudwatch_tb_prod above, no prior work
# created a cross-account CloudWatch grant into this account. Creating this Grafana
# datasource resource is itself safe and reversible (it only stores config in Grafana;
# Atlantis apply touches nothing in AWS), but until the role below is created by hand in
# 768512802988 every query through it returns AccessDenied. alerting-amo-edge.tf gates
# on var.amo_metrics_iam_granted (default false, see terraform.tfvars) so that failure
# reads as exec_err_state = "OK" instead of notifying Slack every interval.
#
# Exact IAM to create in 768512802988 (posted in thunderbird/addons-server#394 for
# Matthew's "go" -- NOT applied by this PR):
#
#   Trust policy (role: mzla-tb-legacy-grafana-cloudwatch):
#     {
#       "Version": "2012-10-17",
#       "Statement": [{
#         "Effect": "Allow",
#         "Principal": { "AWS": "arn:aws:iam::826971876779:role/shared-services-prod-grafana" },
#         "Action": "sts:AssumeRole"
#       }]
#     }
#
#   Inline policy (mirrors mzla-tb-dev-grafana-cloudwatch's metrics statement; no logs
#   access requested here, since #394 only needs metrics):
#     {
#       "Version": "2012-10-17",
#       "Statement": [{
#         "Effect": "Allow",
#         "Action": [
#           "cloudwatch:GetMetricData",
#           "cloudwatch:GetMetricStatistics",
#           "cloudwatch:ListMetrics",
#           "cloudwatch:GetMetricWidgetImage"
#         ],
#         "Resource": "*"
#       }]
#     }
#
# Once created, flip amo_metrics_iam_granted to true in the same follow-up PR.
resource "grafana_data_source" "cloudwatch_tb_legacy" {
  type = "cloudwatch"
  name = "CloudWatch: tb-legacy (AMO prod)"

  json_data_encoded = jsonencode({
    defaultRegion = "us-west-2"
    authType      = "assumeRole"
    assumeRoleArn = "arn:aws:iam::768512802988:role/mzla-tb-legacy-grafana-cloudwatch"
  })
}

# Provisioned by the Grafana Helm chart in platform-infrastructure with a server-assigned UID, so look it up by name.
data "grafana_data_source" "victorialogs" {
  name = "VictoriaLogs"
}
