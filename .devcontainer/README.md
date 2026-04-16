# Devcontainer — Platform Grafana

Preconfigured development environment with all required tools pre-installed.
No manual setup required beyond Docker and VS Code (or the devcontainer CLI).
All tools are pinned to specific versions in `devcontainer.json` via devcontainer features.

## Tools included

| Tool | Version | How installed |
|------|---------|---------------|
| AWS CLI | 2.34.13 | `devcontainers/features/aws-cli:1` |
| GitHub CLI (`gh`) | 2.88.1 | `devcontainers/features/github-cli:1` |
| Terraform | 1.14.2 | `devcontainers/features/terraform:1` |
| tflint | 0.57.0 | `devcontainers/features/terraform:1` (bundled) |
| Python | 3.13 | `devcontainers/features/python:1` |
| checkov | latest | `pip install checkov` (postCreateCommand) |

---

## Opening in VS Code

1. Install the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension.
2. Open the repo, then `Ctrl+Shift+P` → **Dev Containers: Reopen in Container**.

VS Code will build the image and drop you into the container.

---

## Using the devcontainer CLI

Install once:

```bash
npm install -g @devcontainers/cli
```

### Start the container

```bash
devcontainer up --workspace-folder .
```

### Run a command

```bash
devcontainer exec --workspace-folder . bash
```

---

## Credentials

### AWS SSO

AWS credentials are **not** mounted by default (they contain tokens that should not be baked into images). Pass `~/.aws` at container start time:

```bash
devcontainer up --workspace-folder . \
  --mount "type=bind,source=${HOME}/.aws,target=/home/vscode/.aws"
```

Then log in inside the container as normal:

```bash
aws sso login --profile mzla-shared
```

Or log in on the host first — the bind mount means tokens are shared immediately without restarting.

> **Headless / no port forwarding:** On a remote or headless machine where the OAuth callback port isn't forwarded, use device code flow instead:
>
> ```bash
> aws sso login --profile mzla-shared --no-browser --use-device-code
> ```
>
> AWS will print a URL and a one-time code. Open the URL in any browser, enter the code, and the token is written to `~/.aws/sso/cache/` — available inside the container immediately via the bind mount.

---

## Running Terraform

Atlantis handles plan/apply in CI, but for local development:

```bash
cd terraform
terraform init -backend-config=backend-config.hcl
terraform plan
terraform apply
```

> **Note:** You need an active AWS SSO session for the `mzla-shared` profile (shared-services account) since the S3 backend and Secrets Manager lookups run in that account.

---

## Linting

The CI pipeline runs four checks. Run them locally in the devcontainer to catch issues before pushing:

```bash
# Format check (recursive from repo root)
terraform fmt -check -recursive

# Validate (from terraform/ directory)
cd terraform
terraform init -backend=false
terraform validate

# tflint
tflint --recursive --config "$(git rev-parse --show-toplevel)/.tflint.hcl" --chdir terraform

# checkov
checkov --config-file .checkov.yml
```

---

## Troubleshooting

**AWS `Token does not exist` error**
The SSO session has expired. Run `aws sso login --profile mzla-shared` on the host (tokens are shared immediately via the bind mount).

**`terraform init` fails with backend errors**
Ensure you have `backend-config.hcl` in the `terraform/` directory with the correct profile. For local dev:
```hcl
profile = "mzla-shared"
```

**checkov not found**
The `postCreateCommand` runs `pip install checkov` on first container build. If it failed, run `pip install checkov` manually inside the container.
