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
