# Building a Modular Terraform Infrastructure with GitOps and CI/CD

---

## Background

A growing SaaS company needed to modernize its infrastructure: automate multi-environment deployments, containerize microservices, and build a GitOps pipeline for reliable, continuous delivery.

This blog documents the architectural decisions, implementation details, and lessons learned while building a production-ready platform on Google Cloud Platform using Terraform, Docker, and GitHub Actions.

---

## Project Goals

- **Simplicity over complexity** — Clean module organization without over-engineering
- **Full automation** — Push code → automated builds → GitOps deployment
- **Observability** — Metrics, dashboards, and alerts for everything
- **Security** — Integrated scanning, no long-lived keys, secrets in vaults
- **Multi-environment** — Isolated dev/staging/production with minimal overhead

---

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| **Infrastructure as Code** | Terraform (modular) | Declarative, state management, workspace isolation |
| **Containerization** | Docker + Docker Compose | Simple multi-service orchestration |
| **CI/CD** | GitHub Actions | Native GitHub integration, matrix builds |
| **GitOps** | Custom systemd agent | Lightweight, no external dependencies |
| **Monitoring** | Prometheus + Grafana | Open source, extensible, industry standard |
| **Alerting** | Alertmanager + Slack | Configurable routing, silencing |
| **Security Scanning** | Gitleaks, Trivy, tfsec, Snyk, SonarCloud | Comprehensive coverage |
| **Application** | Node.js + MySQL + Nginx | Full-stack reference implementation |

---

## Architecture Overview

```
GitHub (main branch)
  ├─ CI Pipeline
  │   ├─ lint (ESLint)
  │   ├─ security-scan (5 scanners)
  │   └─ build-and-push (Docker images → Artifact Registry)
  └─ CD Pipeline
      └─ Updates image tags in gitops/docker-compose.yml → commit

GitOps Sync (systemd on VM, polls every 60s)
  └─ Detects changes → pulls images → redeploys containers
```

Each environment (dev/staging/production) is a separate Terraform workspace with isolated state.

---

## Phase 1: Modular Terraform Design

### The Module Structure

Instead of a monolithic `main.tf` or an over-engineered 8-module setup, I settled on **5 focused modules**:

```
infra/
  main.tf              — Root orchestrator (APIs, Artifact Registry, module calls)
  variables.tf         — 10 input variables
  outputs.tf           — References module outputs
  modules/
    networking/        — VPC, subnet, 2 firewalls (4 resources)
    iam/               — Service account, IAM bindings (6 resources)
    secrets/           — 3 secrets + versions (6 resources)
    compute/           — Static IP, VM instance (2 resources)
    wif/               — Workload Identity Pool, provider, binding (3 resources)
  moved.tf             — State migration blocks (removed after successful apply)
  env/
    dev.tfvars.example
    staging.tfvars
    production.tfvars
```

Each module is self-contained (main.tf, variables.tf, outputs.tf) and ~30-40 lines. The root `main.tf` reads like a recipe and stays under 50 lines.

### Shared Resources & `create_artifact_registry`

The Docker Artifact Registry has no environment suffix (e.g., `myproject-docker`, not `myproject-docker-staging`). It's a shared resource created once by the first environment.

```hcl
variable "create_artifact_registry" {
  description = "Create the shared Docker registry? Set true only for the first environment."
  type        = bool
  default     = true
}

resource "google_artifact_registry_repository" "docker" {
  count         = var.create_artifact_registry ? 1 : 0
  location      = var.region
  repository_id = "${var.project_name}-docker"
  format        = "DOCKER"
}
```

First environment: `create_artifact_registry = true` → creates the repo.
Subsequent environments: `false` → skip creation, no conflicts.
No manual `terraform import` needed for replicators.

### Configuration Layout: `infra/env/`

Environment-specific `.tfvars` files live in `infra/env/` for professional organization:

```
infra/env/
  dev.tfvars.example       # Template (create_artifact_registry = true)
  staging.tfvars           # Actual values (gitignored, contains secrets)
  production.tfvars        # Actual values (gitignored, contains secrets)
```

Users copy the `.example` files and fill in their own values. Real `.tfvars` are gitignored for security.

---

## What Terraform Provisions

A single `terraform apply -var-file=env/<env>.tfvars` creates:

| Category | Resources | Qty |
|----------|-----------|-----|
| Networking | VPC, Subnet, 2 Firewall rules | 4 |
| IAM | Service Account, 4 IAM bindings, cicd_writer | 6 |
| Secrets | 3 secrets + 3 versions (DB, Grafana, Slack) | 6 |
| Compute | Static IP, VM instance | 2 |
| WIF | Workload Identity Pool, Provider, SA binding | 3 |
| APIs + AR | Auto-enabled APIs, Artifact Registry | 1+ |
| **Total** | | **28** |

All resources are tagged with the environment name (e.g., `myproject-vpc-dev`, `myproject-app-prod`).

---

## Workload Identity Federation (No Service Account Keys)

CI/CD uses **Workload Identity Federation** instead of long-lived service account keys:

```
GitHub Actions (OIDC token)
    ↓ GCP Workload Identity Pool (myproject-github-<env>)
    ↓ Maps to Service Account (myproject-app-<env>)
    ↓ Temporary credentials (1 hour)
```

Benefits:
- No JSON key files to generate, store, or rotate
- Compromise is time-limited (1 hour tokens)
- Audit trail in GCP IAM logs
- No secret leakage risk in GitHub

The CI/CD workflow sets these GitHub secrets once per environment:
- `GCP_WIF_PROVIDER` (from `terraform output wif_provider`)
- `GCP_SA_EMAIL` (from `terraform output service_account_email`)

---

## Phase 2: CI/CD Pipeline

### CI Workflow (3 parallel jobs)

**1. Lint** (Node.js)
```bash
npm ci
npm run lint
```
Must pass for build to proceed.

**2. Security Scan** (runs regardless of lint)
- Gitleaks — Git history scanning
- Trivy (FS) — Dependency vulnerabilities
- tfsec (via Trivy) — Terraform misconfigurations
- Snyk Code — SAST on application code
- SonarCloud — Code quality + security

All use `continue-on-error: true` — pipeline doesn't block if scanners fail (tokens may not be configured).

**3. Build & Push**
- Builds 3 images: backend, frontend, database
- Tags: `<commit-sha>` and `latest`
- Pushes to Artifact Registry: `region-docker.pkg.dev/<project-id>/<repo>`

### CD Workflow

Triggered after CI success:
1. Read current `gitops/docker-compose.yml`
2. Replace image tags with new commit SHA
3. Commit with `[skip ci]` and push

That's all — no manual approvals, no complex promotion. GitOps sync handles the rest.

---

## Phase 3: GitOps Deployment

### Why Not ArgoCD or Flux?

For a single-VM deployment, these tools are overkill. I built an **80-line bash systemd service** that:

- Runs as root, polls Git every 60s
- Refreshes Artifact Registry auth token (2h TTL)
- Detects commits via `git fetch` and comparing HEAD
- On change: `git pull`, inject secrets, `docker compose pull && up -d`

The service automatically recovers from failures and logs to `journalctl`.

### Docker Compose Stack

7 services defined in `gitops/docker-compose.yml`:

| Service | Port | Description |
|---------|------|-------------|
| `frontend` | 80 | Nginx reverse proxy + static files |
| `backend`  | 8080 | Node.js Express API (health checks enabled) |
| `database` | 3306 | MySQL with persistent volume |
| `prometheus` | 9090 | Metrics collection (15s scrape interval) |
| `grafana` | 3000 | Dashboards (auto-provisioned from JSON) |
| `alertmanager` | 9093 | Alert routing to Slack |
| `node-exporter` | 9100 | Host metrics (CPU, memory, disk, network) |

All configuration (Prometheus rules, Grafana dashboards, Alertmanager routes) lives in `gitops/<env>/monitoring/` and is environment-specific.

### Secret Injection Pattern

Sensitive values (Slack webhook, DB passwords) live in Secret Manager, not Git. The `gitops-sync` script fetches secrets at deploy time and uses `sed` to replace placeholders:

```yaml
# In alertmanager.yml (committed to Git):
slack_api_url: "SLACK_WEBHOOK_PLACEHOLDER"
```

```bash
# In gitops-sync:
REAL_WEBHOOK=$(gcloud secrets versions access latest --project=$PROJECT_ID --secret=$SLACK_SECRET_NAME)
sed -i "s|SLACK_WEBHOOK_PLACEHOLDER|$REAL_WEBHOOK|" gitops/$ENV/monitoring/alertmanager.yml
```

Keeps secrets out of version control while maintaining config-as-code.

---

## Phase 4: Monitoring & Alerting

### Prometheus

Scrapes three targets:

| Target | Metrics |
|--------|---------|
| Node Exporter (`:9100`) | CPU, memory, disk I/O, network, processes |
| Backend (`:8080/metrics`) | Request rate, latency, errors (Express middlewares) |
| Self (`:9090/metrics`) | Storage, scrape duration, ingestion rate |

**Alert Rules** (in `gitops/<env>/monitoring/alert.rules.yml`):

```yaml
- alert: ServiceDown
  expr: up{job!="alertmanager"} == 0
  for: 1m
  severity: critical

- alert: HighCPU
  expr: 100 - (avg by(instance)(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
  for: 5m
  severity: warning

- alert: HighMemory
  expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
  for: 5m
  severity: warning
```

### Grafana

3 pre-provisioned dashboards (JSON in `gitops/<env>/monitoring/dashboards/`):

1. **Infrastructure Overview** — System metrics (CPU, memory, disk, network, load)
2. **Application & Monitoring Health** — Service status, active alerts, Prometheus TSDB stats
3. **Epicbook** — App-specific metrics (requests, errors, latency, DB connections)

Dashboards auto-import on Grafana startup via provisioning config.

### Alertmanager

Routes all alerts to Slack:

```yaml
receivers:
  - name: slack-notifications
    slack_configs:
      - api_url: "${SLACK_WEBHOOK}"  # injected by gitops-sync
        channel: "#alerts"
        send_resolved: true
```

Grouping: 30s wait, 5m group interval. Inhibitions: critical alerts inhibit warnings with same name.

---

## Phase 5: Security Scanning in CI

All scanners run on every push. None block the pipeline (`continue-on-error: true`), but results are visible in GitHub Actions logs.

| Scanner | Scope | Detects | Token Needed |
|---------|-------|---------|--------------|
| **Gitleaks** | Entire git history | Committed secrets (API keys, passwords) | No |
| **Trivy** | Source files | Dependency vulnerabilities (npm packages) | No |
| **tfsec** | Terraform configs | Overly permissive IAM, public resources | No |
| **Snyk Code** | App code (Node.js) | SAST: SQLi, XSS, insecure crypto | Yes |
| **SonarCloud** | Whole repo | Code quality, bugs, hotspots, coverage | Yes |

Setting tokens is optional — without them, those two scanners are skipped but the pipeline still builds and deploys.

---

## Challenges & Solutions

### 1. Terraform Template Escaping

The startup script uses `templatefile()`. Terraform interprets `${VAR}` as interpolation, conflicting with bash `${VAR}`. Solution: `$${VAR}` → renders literal `${VAR}` in the script.

### 2. Docker Config Doesn't Reload on Restart

`docker compose restart` uses cached bind mounts. Must remove and recreate:
```bash
docker compose stop alertmanager
docker compose rm -f alertmanager
docker compose up -d alertmanager
```

GitOps sync does this automatically when config changes are detected.

### 3. Systemd HOME Mismatch

Docker stores credentials at `$HOME/.docker/config.json`. Startup script used `HOME=/var/lib`; systemd service used `HOME=/root`. Fix: add `Environment=HOME=/var/lib` to the systemd unit file.

### 4. Sequelize NODE_ENV Mismatch

App reads `config/config.json` by `NODE_ENV`. Deploying with `NODE_ENV=staging` crashed because config had no `staging` key. Fixed by adding entries for all environments (dev, staging, production).

### 5. Non-Destructive Secret Management

Can't commit Slack webhook to Git, but must have placeholder for GitOps to replace. Solution: Use a unique sentinel string (`SLACK_WEBHOOK_PLACEHOLDER`) in Git, replace at deploy time via `sed`. Works because `gitops-sync` fetches the real secret from Secret Manager before redeploying.

---

## Deployment Guide for New Projects

### 1. Prepare GCP Project

```bash
# Create project, enable billing
gcloud projects create myproject --name="MyProject"
gcloud config set project myproject

# Create Terraform state bucket (must be globally unique)
gsutil mb -p myproject -l us-central1 gs://myproject-tf-state

# Enable APIs (Terraform will do this automatically on first apply, but you can pre-enable)
gcloud services enable compute.googleapis.com secretmanager.googleapis.com artifactregistry.googleapis.com iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com
```

### 2. Clone and Configure

```bash
git clone https://github.com/your-username/CloudOpsHub.git
cd CloudOpsHub

# Copy environment template
cp infra/env/dev.tfvars.example infra/env/dev.tfvars

# Edit infra/env/dev.tfvars:
#   project_id = "myproject"
#   project_name = "myproject"
#   github_repo = "your-username/CloudOpsHub"
#   db_password, grafana_password = generated secrets
#   create_artifact_registry = true  # First environment only
```

### 3. Deploy First Environment (Dev)

```bash
cd infra
terraform init
terraform workspace new dev
terraform apply -var-file=env/dev.tfvars
```

Terraform creates 28 resources (VPC, VM, secrets, WIF, etc.). Wait 3-5 minutes for VM to boot and containers to start.

### 4. Get Outputs & Configure GitHub Secrets

```bash
terraform output -raw service_account_email  # Save this
terraform output -raw wif_provider          # Save this
```

Set GitHub secrets (needed for CI/CD):
```bash
gh secret set GCP_PROJECT_ID -b "myproject"
gh secret set GCP_REGION -b "us-central1"
gh secret set GCP_SA_EMAIL -b "$(terraform output -raw service_account_email)"
gh secret set GCP_WIF_PROVIDER -b "$(terraform output -raw wif_provider)"
# Optional (for full security scanning):
# gh secret set SNYK_TOKEN -b "..."
# gh secret set SONAR_TOKEN -b "..."
# gh secret set SONAR_HOST_URL -b "https://sonarcloud.io"
```

### 5. Deploy Additional Environments (Staging, Production)

```bash
# Staging
terraform workspace new staging
cp infra/env/dev.tfvars infra/env/staging.tfvars
# Edit staging.tfvars: change environment = "staging", create_artifact_registry = false
terraform apply -var-file=env/staging.tfvars

# Production
terraform workspace new production
cp infra/env/dev.tfvars infra/env/production.tfvars
# Edit production.tfvars: environment = "production", create_artifact_registry = false
terraform apply -var-file=env/production.tfvars
```

Each environment gets its own VPC, VM, static IP, secrets, and WIF pool. Update `GCP_SA_EMAIL` and `GCP_WIF_PROVIDER` GitHub secrets after each apply if you want CI/CD to target that environment.

### 6. Verify Deployment

```bash
# Check Terraform outputs
terraform output

# Test the app (replace YOUR_VM_IP with output.vm_ip)
curl http://YOUR_VM_IP

# SSH into VM (replace ENV and ZONE)
gcloud compute ssh myproject-app-ENV --zone=us-central1-a --tunnel-through-iap \
  --command="sudo docker ps"
```

You should see 7 containers: frontend, backend, database, prometheus, grafana, alertmanager, node-exporter.

---

## Results & Lessons

| What | Value |
|------|-------|
| Terraform modules | 5 clean, focused modules (~200 lines total) |
| Resources per env | 28 GCP resources |
| Containers per env | 7 |
| Terraform apply time | ~3 minutes |
| Code-to-live time | 4-5 minutes (CI + CD + GitOps sync) |
| Security scanners | 5 (Gitleaks, Trivy, tfsec, Snyk, SonarCloud) |
| Monitoring | Prometheus + Grafana (3 dashboards) |
| Alerting | Slack via Alertmanager |
| GitOps agent | 80-line systemd service |

**Key takeaway**: Modular Terraform doesn't have to be complex. Keep modules small and focused. Use workspaces for environment isolation. Use WIF for secure, keyless CI/CD. A custom GitOps agent can be simpler than ArgoCD for single-VM setups.

---

## Next Steps

- Add SSL/TLS (Let's Encrypt or load balancer)
- Implement database backups (snapshots or mysqldump)
- Set up cost monitoring (GCP billing budgets)
- Customize Grafana dashboards for your metrics
- Add more alert rules ( latency, error rate thresholds )

---

## Conclusion

This architecture demonstrates that a production-grade platform can be built with a small, focused codebase. No sprawling microservices, no complex CI/CD orchestration, no overwhelming vendor lock-in. Just Terraform, Docker, GitHub Actions, and a few proven open-source tools.

The entire system is defined in code, version-controlled, and automatically deployed. Push to main, and minutes later the changes are running in production with metrics, alerts, and security scans.

That's the power of good DevOps: automate everything, observe everything, simplify relentlessly.

---

## References

- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Google WIF](https://cloud.google.com/iam/docs/workload-identity-federation)
- [Docker Compose](https://docs.docker.com/compose/)
- [Prometheus](https://prometheus.io/docs/)
- [Grafana](https://grafana.com/docs/)
- [Alertmanager](https://prometheus.io/docs/alerting/latest/configuration/)
- [Gitleaks](https://github.com/gitleaks/gitleaks)
- [Trivy](https://aquasecurity.github.io/trivy/)
- [tfsec](https://aquasecurity.github.io/tfsec/)
