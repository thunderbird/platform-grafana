# CloudWatch Logs datasources — added for #122
# Grafana reads logs via IRSA (same-account) and cross-account assume role.

resource "grafana_data_source" "cloudwatch_shared" {
  type = "cloudwatch"
  name = "CloudWatch Logs — shared01"

  json_data_encoded = jsonencode({
    defaultRegion = "eu-central-1"
    authType      = "default"
  })
}

resource "grafana_data_source" "cloudwatch_workloads" {
  type = "cloudwatch"
  name = "CloudWatch Logs — workloads01"

  json_data_encoded = jsonencode({
    defaultRegion = "eu-central-1"
    authType      = "assumeRole"
    assumeRoleArn = "arn:aws:iam::668807881758:role/workloads-prod-grafana-cloudwatch"
  })
}
