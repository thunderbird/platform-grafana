# platform-grafana

Terraform-managed Grafana dashboards for [grafana.pi.thunderbird.net](https://grafana.pi.thunderbird.net). Dashboards are provisioned via the Grafana API using the [Grafana Terraform provider](https://registry.terraform.io/providers/grafana/grafana/latest).

## Repo Structure

```text
platform-grafana/
├── .github/CODEOWNERS
├── terraform/
│   ├── main.tf                 # Provider config (Grafana + AWS), S3 backend
│   ├── variables.tf            # Input variables
│   ├── terraform.tfvars        # Grafana URL, datasource UID
│   ├── folders.tf              # Grafana folders
│   ├── dashboards.tf           # Dashboard resources
│   └── dashboards/             # Dashboard JSON files
│       ├── kubernetes/          # Cluster, namespace, pods, PVs, CoreDNS
│       ├── victoriametrics/     # VMCluster, VMAgent, VictoriaLogs
│       ├── traefik/             # Request rate, latency, status codes
│       ├── argocd/              # App sync/health, operational metrics
│       ├── teleport/            # Sessions, backend/audit
│       ├── keycloak/            # Login rates, sessions, JVM
│       └── core-services/       # ESO, external-dns, cert-manager, AWS LB
```

## Running Locally

Requires AWS profile `mzla-shared` (shared-services account `826971876779`).

```bash
cd terraform
terraform init -backend-config=backend-config.hcl
terraform plan
terraform apply
```

## Dashboards

Dashboard JSON files live in `terraform/dashboards/`. Each file is loaded by a `grafana_dashboard` resource in `dashboards.tf`.

Datasource references in JSON use the VictoriaMetrics datasource UID (`P4169E866C3094E38`). If the datasource is ever recreated, update `terraform.tfvars` and the JSON files.

### Modifying a Dashboard

The easiest workflow for complex changes:

1. Edit the dashboard in the Grafana UI
2. Go to dashboard settings > **JSON Model** > copy the full JSON
3. Paste it into the corresponding file in `terraform/dashboards/`, replacing the existing content
4. Run `terraform plan` to verify, then `terraform apply`

UI edits are **not persisted** — the next `terraform apply` will revert them. Always save changes back to this repo.

### Adding a New Dashboard

1. Create or export the dashboard JSON from Grafana
2. Ensure all datasource references use `{"type": "prometheus", "uid": "P4169E866C3094E38"}`
3. Save to `terraform/dashboards/<folder>/<name>.json`
4. Add a folder in `folders.tf` if needed:
   ```hcl
   resource "grafana_folder" "my_folder" {
     title = "My Folder"
   }
   ```
5. Add a dashboard resource in `dashboards.tf`:
   ```hcl
   resource "grafana_dashboard" "my_dashboard" {
     folder      = grafana_folder.my_folder.id
     config_json = file("${path.module}/dashboards/my-folder/my-dashboard.json")
   }
   ```
6. Run `terraform plan` to verify, then `terraform apply`

### Adding a New Folder

Add a `grafana_folder` resource to `folders.tf`. The resource name is used as the reference in `dashboards.tf`.

## Infrastructure

| Component | Detail |
|-----------|--------|
| **Grafana** | [grafana.pi.thunderbird.net](https://grafana.pi.thunderbird.net) — deployed via ArgoCD on mzla-eks-shared01 |
| **Auth** | GitHub OAuth (thunderbird org), `platform-infrastructure` team = Admin |
| **Datasource** | VictoriaMetrics (Prometheus-compatible) at `vmselect-victoriametrics-victoria-metrics-k8s-stack.monitoring.svc:8481` |
| **Terraform state** | S3: `platform-grafana-terraform-state` / DynamoDB: `platform-grafana-terraform-lock` |
| **Grafana API token** | Secrets Manager: `mzla/shared-services/grafana-terraform` |
| **AWS account** | shared-services (`826971876779`), profile `mzla-shared` |

## Configuration

| Variable | Description |
|----------|-------------|
| `grafana_url` | Grafana instance URL |
| `prometheus_datasource_uid` | UID of the VictoriaMetrics datasource |

Values are set in `terraform/terraform.tfvars`. Look up the datasource UID from Grafana: **Connections > Data sources > VictoriaMetrics** > copy the UID from the URL.

## Bootstrap (one-time setup)

These steps were already completed during initial setup. Documented here for reference.

<details>
<summary>S3 state backend</summary>

```bash
aws s3api create-bucket --bucket platform-grafana-terraform-state \
  --region us-west-2 --create-bucket-configuration LocationConstraint=us-west-2
aws s3api put-bucket-versioning --bucket platform-grafana-terraform-state \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket platform-grafana-terraform-state \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'
aws s3api put-public-access-block --bucket platform-grafana-terraform-state \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws dynamodb create-table --table-name platform-grafana-terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-west-2
```
</details>

<details>
<summary>Grafana service account token</summary>

1. Log into [grafana.pi.thunderbird.net](https://grafana.pi.thunderbird.net) as Admin
2. **Administration > Service accounts > Add service account**: name `terraform`, role `Admin`
3. **Add service account token** > generate and copy

```bash
aws secretsmanager create-secret \
  --name mzla/shared-services/grafana-terraform \
  --secret-string '{"grafana_service_account_token":"<TOKEN>"}' \
  --region us-west-2
```
</details>
