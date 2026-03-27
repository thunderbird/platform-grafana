terraform {
  required_version = ">= 1.14.2"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = ">= 2.9.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # No profile — Atlantis uses ECS task role, local dev uses backend-config.hcl
  # Local init: terraform init -backend-config=backend-config.hcl
  backend "s3" {
    bucket         = "platform-grafana-terraform-state"
    key            = "grafana/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "platform-grafana-terraform-lock"
  }
}

# No profile — credentials come from environment (AWS_PROFILE for local, task role for Atlantis)
provider "aws" {
  region = "us-west-2"
}

# Retrieve Grafana service account token from Secrets Manager
data "aws_secretsmanager_secret_version" "grafana" {
  secret_id = "mzla/shared-services/grafana-terraform"
}

locals {
  secrets = jsondecode(data.aws_secretsmanager_secret_version.grafana.secret_string)
}

provider "grafana" {
  url  = var.grafana_url
  auth = local.secrets["grafana_service_account_token"]
}
