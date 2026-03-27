# platform-grafana

Terraform-managed Grafana dashboards for [grafana.pi.thunderbird.net](https://grafana.pi.thunderbird.net). Dashboards are provisioned via the Grafana API using the [Grafana Terraform provider](https://registry.terraform.io/providers/grafana/grafana/latest).

## Prerequisites

### 1. S3 State Backend (one-time)

Create the S3 bucket and DynamoDB lock table in the shared-services account (`826971876779`):

```bash
export AWS_PROFILE=mzla-shared

# S3 bucket for Terraform state
aws s3api create-bucket --bucket platform-grafana-terraform-state \
  --region us-west-2 --create-bucket-configuration LocationConstraint=us-west-2
aws s3api put-bucket-versioning --bucket platform-grafana-terraform-state \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket platform-grafana-terraform-state \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'
aws s3api put-public-access-block --bucket platform-grafana-terraform-state \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# DynamoDB lock table
aws dynamodb create-table --table-name platform-grafana-terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-west-2
```

### 2. Grafana Service Account Token

1. Log into [grafana.pi.thunderbird.net](https://grafana.pi.thunderbird.net) as Admin
2. Navigate to **Administration > Service accounts**
3. Create a service account: name `terraform`, role `Admin`
4. Generate a token and copy it

### 3. Store Token in Secrets Manager

```bash
export AWS_PROFILE=mzla-shared

aws secretsmanager create-secret \
  --name mzla/shared-services/grafana-terraform \
  --secret-string '{"grafana_service_account_token":"<PASTE_TOKEN_HERE>"}' \
  --region us-west-2
```

## Usage

```bash
export AWS_PROFILE=mzla-shared
cd terraform

terraform init
terraform plan
terraform apply
```

## Adding a Dashboard

1. Export the dashboard JSON from the Grafana UI (Dashboard settings > JSON Model) or create one from scratch
2. Save it to `terraform/dashboards/<folder>/<name>.json`
3. Add a `grafana_dashboard` resource to `terraform/dashboards.tf`:
   ```hcl
   resource "grafana_dashboard" "my_dashboard" {
     folder      = grafana_folder.<folder_name>.id
     config_json = file("${path.module}/dashboards/<folder>/<name>.json")
   }
   ```
4. Run `terraform plan` to verify, then `terraform apply`

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `grafana_url` | Grafana instance URL | — |
| `prometheus_datasource_uid` | UID of the VictoriaMetrics datasource | — |

Values are set in `terraform/terraform.tfvars`. Look up the datasource UID from Grafana: **Connections > Data sources > VictoriaMetrics > copy the UID from the URL**.
