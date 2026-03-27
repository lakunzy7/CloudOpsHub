# CloudOpsHub: Absolute Beginner Deployment Guide

*Deploy a complete Docker-based infrastructure platform on Google Cloud with GitOps, CI/CD, and security scanning.*

---

## Prerequisites

You need these installed locally:

| Tool | Why | Install |
|------|-----|--------|
| **Git** | Clone repo & manage code | https://git-scm.com/downloads |
| **Terraform** | Provision cloud infrastructure | https://developer.hashicorp.com/terraform/downloads |
| **gcloud CLI** | Interact with Google Cloud | https://cloud.google.com/sdk/docs/install |
| **Docker** (optional, for local testing) | Run app locally | https://docs.docker.com/get-docker/ |

Verify installations:
```bash
git --version
terraform version
gcloud version
docker --version   # optional
```

---

## Architecture Overview

```
GitHub (main branch)
   |
   +--> CI Pipeline (GitHub Actions)
   |      |-- lint (Node.js)
   |      |-- security-scan (Gitleaks, Trivy, tfsec, Snyk, SonarCloud)
   |      +-- build-and-push (Docker images -> Artifact Registry)
   |
   +--> CD Pipeline (triggered by CI success)
   |      +-- Updates image tags in gitops/docker-compose.yml -> commits
   |
   +--> GitOps Sync (systemd service on VM, polls every 60s)
          +-- Detects changes -> pulls new images -> redeploys
```

**What gets deployed (per environment):**

| Component | Description |
|-----------|-------------|
| **VM** | Single e2-medium instance (Container-Optimized OS) |
| **App** | Node.js backend + Nginx frontend + MySQL |
| **Monitoring** | Prometheus + Grafana (3 dashboards) + Alertmanager |
| **Registry** | Google Artifact Registry (Docker images) |
| **Secrets** | Google Secret Manager (DB password, Grafana password, Slack webhook) |
| **Security** | 5 CI scanners: Gitleaks, Trivy, tfsec, Snyk, SonarCloud |
| **WIF** | Workload Identity Federation (GitHub -> GCP auth, no keys) |

---

## Step 1: Prepare GCP Project

### 1.1 Create or select a GCP project

Go to [Google Cloud Console](https://console.cloud.google.com), create a new project or use existing. Note your **Project ID** (e.g., `my-cloudopshub`).

You'll need:
- **Project ID**: `YOUR_PROJECT_ID`
- **Project Number**: Found in the project dashboard (needed for WIF)
- **Billing**: Must be enabled on the project

### 1.2 Authenticate gcloud

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
gcloud auth application-default login
```

### 1.3 Create Terraform State Bucket

Terraform stores its state remotely in GCS so it persists across machines:

```bash
gsutil mb -p YOUR_PROJECT_ID -l us-central1 gs://YOUR_PROJECT_ID-cloudopshub-tf-state
```

---

## Step 2: Prepare GitHub Repository

### 2.1 Fork or Clone This Repository

```bash
git clone https://github.com/your-username/CloudOpsHub.git
cd CloudOpsHub
```

### 2.2 Authenticate GitHub CLI

```bash
gh auth login
```

### 2.3 Set GitHub Secrets

The CI/CD pipeline needs these secrets:

| Secret Name | Value | How to get |
|-------------|-------|------------|
| `GCP_PROJECT_ID` | Your GCP project ID | From Step 1.1 |
| `GCP_REGION` | GCP region (e.g., `us-central1`) | Your choice |
| `GCP_WIF_PROVIDER` | Workload Identity Provider path | After `terraform apply` (Step 3.3) |
| `GCP_SA_EMAIL` | Service account email | After `terraform apply` (Step 3.3) |
| `SNYK_TOKEN` | Snyk API token (optional) | https://app.snyk.io/account |
| `SONAR_TOKEN` | SonarCloud token (optional) | https://sonarcloud.io/account/security |
| `SONAR_HOST_URL` | `https://sonarcloud.io` (optional) | Fixed value |

Set the ones you have now:
```bash
gh secret set GCP_PROJECT_ID -b "YOUR_PROJECT_ID"
gh secret set GCP_REGION -b "us-central1"
```

**Note**: `GCP_WIF_PROVIDER` and `GCP_SA_EMAIL` will be set after Terraform apply (Step 3.3). Security scan tokens are optional — those scans will gracefully fail without them.

---

## Step 3: Deploy Infrastructure with Terraform

### 3.1 Prepare Terraform Variables

```bash
cd infra
cp dev.tfvars.example YOUR_ENV.tfvars
```

Edit the tfvars file (replace `YOUR_ENV` with `dev`, `staging`, or `production`):

```hcl
project_id    = "YOUR_PROJECT_ID"
project_name  = "cloudopshub"
environment   = "staging"               # dev, staging, or production
region        = "us-central1"
zone          = "us-central1-a"
instance_type = "e2-medium"
github_repo   = "your-username/CloudOpsHub"

# Generate secure passwords:
#   openssl rand -base64 15
db_password       = "YOUR_DB_PASSWORD_HERE"
grafana_password  = "YOUR_GRAFANA_PASSWORD_HERE"
slack_webhook_url = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

### 3.2 Initialize and Apply Terraform

For your first environment (dev):
```bash
terraform init
terraform apply -var-file=dev.tfvars
```

For additional environments (staging, production), use workspaces:
```bash
terraform workspace new staging
terraform apply -var-file=staging.tfvars
```

You'll see a plan summary:
```
Plan: 28 to add, 0 to change, 0 to destroy.
```

Type `yes` to confirm. **Wait 2-3 minutes** — Terraform creates:
- VPC network, subnet & firewall rules
- Service Account & IAM roles
- Artifact Registry repository
- 3 Secrets in Secret Manager (DB password, Grafana password, Slack webhook)
- VM instance with static IP
- Workload Identity Federation pool & provider

### 3.3 Get Terraform Outputs & Update GitHub Secrets

```bash
terraform output
```

You'll see:
```
app_url               = "http://YOUR_VM_IP"
artifact_registry_url = "us-central1-docker.pkg.dev/YOUR_PROJECT_ID/cloudopshub-docker"
grafana_url           = "http://YOUR_VM_IP:3000"
prometheus_url        = "http://YOUR_VM_IP:9090"
service_account_email = "cloudopshub-app-ENV@YOUR_PROJECT_ID.iam.gserviceaccount.com"
vm_ip                 = "YOUR_VM_IP"
vm_name               = "cloudopshub-app-ENV"
wif_provider          = "projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/cloudopshub-github-ENV/providers/github-provider"
```

Now update the GitHub secrets you couldn't set earlier:
```bash
gh secret set GCP_WIF_PROVIDER -b "$(terraform output -raw wif_provider)"
gh secret set GCP_SA_EMAIL -b "$(terraform output -raw service_account_email)"
```

---

## Step 4: Wait for Initial Deployment

The VM automatically boots and runs a startup script that:
1. Installs Docker Compose
2. Authenticates to Artifact Registry
3. Fetches secrets from Secret Manager
4. Writes `.env` file with all config
5. Clones this GitHub repository
6. Creates and starts the **GitOps sync** systemd service
7. Deploys the full app stack using `docker-compose`

**This takes 3-5 minutes** after Terraform apply.

Watch the VM boot progress:
```bash
gcloud compute ssh cloudopshub-app-ENV --zone=us-central1-a --tunnel-through-iap \
  --ssh-flag="-o StrictHostKeyChecking=no" \
  --command="sudo journalctl -u google-startup-scripts -f"
```

(Replace `ENV` with your environment name: `dev`, `staging`, etc.)

---

## Step 5: Verify Deployment

### 5.1 Check VM is Running

```bash
gcloud compute instances list
```

Or in **GCP Console**: Compute Engine > VM instances

### 5.2 Check Containers

```bash
gcloud compute ssh cloudopshub-app-ENV --zone=us-central1-a --tunnel-through-iap \
  --ssh-flag="-o StrictHostKeyChecking=no" \
  --command="sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

You should see 7 containers all running:

| Container | Port | Purpose |
|-----------|------|---------|
| `gitops-frontend-1` | 80 | Nginx reverse proxy + static files |
| `gitops-backend-1` | 8080 | Node.js Express API |
| `gitops-database-1` | 3306 | MySQL database |
| `gitops-prometheus-1` | 9090 | Metrics collection |
| `gitops-grafana-1` | 3000 | Dashboards & visualization |
| `gitops-alertmanager-1` | 9093 | Alert routing (Slack) |
| `gitops-node-exporter-1` | 9100 | Host metrics exporter |

### 5.3 Access the App

| Service | URL | Auth |
|---------|-----|------|
| **App** | `http://YOUR_VM_IP` | None |
| **Grafana** | `http://YOUR_VM_IP:3000` | `admin` / your grafana_password |
| **Prometheus** | `http://YOUR_VM_IP:9090` | None |
| **Alertmanager** | `http://YOUR_VM_IP:9093` | None |

Grafana comes with 3 pre-configured dashboards:
- **Infrastructure Overview** — CPU, memory, disk, network, system load
- **Application & Monitoring Health** — Container up/down, active alerts, scrape metrics
- **Epicbook** — App-specific dashboard

### 5.4 Check from GCP Console

1. Go to https://console.cloud.google.com
2. Select your project from the top dropdown
3. Navigate to:

| Resource | Console Path |
|----------|-------------|
| **VM** | Compute Engine > VM instances |
| **VM Logs** | Click VM name > Serial port 1 (console) |
| **SSH** | Click VM name > SSH button > Open in browser window |
| **VPC/Firewall** | VPC Network > VPC networks |
| **Static IP** | VPC Network > IP addresses |
| **Artifact Registry** | Artifact Registry > Repositories |
| **Secrets** | Security > Secret Manager |
| **Service Accounts** | IAM & Admin > Service Accounts |
| **WIF** | IAM & Admin > Workload Identity Federation |

---

## Step 6: Test CI/CD Pipeline

### 6.1 Make a Code Change

```bash
# Edit any file, e.g.:
echo "<!-- test -->" >> theepicbook/views/layouts/main.handlebars
git add theepicbook/views/layouts/main.handlebars
git commit -m "test: verify CI/CD pipeline"
git push
```

### 6.2 Watch GitHub Actions

Go to your GitHub repo > **Actions** tab, or use CLI:

```bash
gh run list --limit 3
gh run watch    # watch the latest run live
```

You should see the CI pipeline with 3 jobs:

1. **lint** — Runs `npm ci` + `npm run lint`
2. **security-scan** — Runs 5 security scanners (all `continue-on-error`)
3. **build-and-push** — Builds 3 Docker images, pushes to Artifact Registry

Then the **CD** pipeline triggers automatically:
- Updates image tags in `gitops/docker-compose.yml`
- Commits with `[skip ci]` to avoid infinite loop

### 6.3 Watch GitOps Sync Redeploy

```bash
gcloud compute ssh cloudopshub-app-ENV --zone=us-central1-a --tunnel-through-iap \
  --ssh-flag="-o StrictHostKeyChecking=no" \
  --command="sudo journalctl -u gitops-sync -f"
```

Within 60 seconds of CD completing, you should see:
```
Change detected: <old-sha> -> <new-sha>
Files changed — redeploying...
Sync successful
```

---

## Step 7: Configure Slack Alerts (Optional)

### 7.1 Create Slack Webhook

1. Go to https://api.slack.com/apps
2. Create a new app > **Incoming Webhooks**
3. Activate Incoming Webhooks
4. Add new webhook > select a channel (e.g., `#devops`)
5. Copy the webhook URL

### 7.2 Update the Webhook

**Option A: Via Terraform (recommended)**
```bash
# Edit your .tfvars file, update slack_webhook_url, then:
terraform apply -var-file=staging.tfvars
```

**Option B: Manual (temporary, overwritten on next apply)**
```bash
gcloud secrets versions add cloudopshub-slack-webhook-ENV \
  --project=YOUR_PROJECT_ID \
  --data-file=<(echo "YOUR_SLACK_WEBHOOK_URL")
```

### 7.3 Change Alert Channel

The alertmanager config defaults to `#devops`. To change:

```bash
# Edit the config for your environment:
sed -i 's|channel: "#devops"|channel: "#your-channel"|' gitops/ENV/monitoring/alertmanager.yml
git add gitops/ENV/monitoring/alertmanager.yml
git commit -m "chore: update alertmanager channel"
git push
```

GitOps sync will redeploy alertmanager automatically.

**Important**: The alertmanager config uses `SLACK_WEBHOOK_PLACEHOLDER` as the webhook URL. The GitOps sync script replaces this with the real webhook from Secret Manager at deploy time. Do NOT change this placeholder manually.

---

## Step 8: Security Scanning

The CI pipeline includes 5 security scanners that run on every push:

| Scanner | What it does | Needs secret? |
|---------|-------------|---------------|
| **Gitleaks** | Detects hardcoded secrets/credentials in git history | `GITLEAKS_LICENSE` (optional, works without) |
| **Trivy FS** | Scans source code for vulnerabilities | No |
| **tfsec (Trivy)** | Scans Terraform files for misconfigurations | No |
| **Snyk Code** | SAST — static application security testing | `SNYK_TOKEN` (required) |
| **SonarCloud** | Code quality + security analysis | `SONAR_TOKEN` (required) |

All scanners use `continue-on-error: true` — the pipeline **continues regardless** of scan results. Only `lint` must pass for images to build.

### Setting up optional tokens

**Snyk:**
1. Sign up at https://snyk.io
2. Go to Account Settings > API Token
3. `gh secret set SNYK_TOKEN -b "YOUR_TOKEN"`

**SonarCloud:**
1. Sign up at https://sonarcloud.io (link your GitHub)
2. Create a new project for your repo
3. Go to Account > Security > Generate token
4. `gh secret set SONAR_TOKEN -b "YOUR_TOKEN"`
5. `gh secret set SONAR_HOST_URL -b "https://sonarcloud.io"`

---

## Step 9: Multi-Environment Deployment

Terraform workspaces isolate state per environment. Each environment gets its own VM, VPC, secrets, and WIF pool.

### Switch between workspaces

```bash
cd infra
terraform workspace list              # see all workspaces
terraform workspace select staging    # switch to staging
terraform workspace select default    # switch to dev
terraform output                      # see outputs for current workspace
```

### Deploy a new environment

```bash
cd infra

# Create workspace
terraform workspace new production

# Create tfvars (use new passwords!)
cp dev.tfvars.example production.tfvars
# Edit production.tfvars with environment = "production"

# Apply
terraform apply -var-file=production.tfvars

# Update GitHub secrets with new WIF/SA values
gh secret set GCP_WIF_PROVIDER -b "$(terraform output -raw wif_provider)"
gh secret set GCP_SA_EMAIL -b "$(terraform output -raw service_account_email)"
```

### Destroy an environment

```bash
terraform workspace select staging
terraform destroy -var-file=staging.tfvars
```

**Note**: When switching the active environment for CI/CD, update `GCP_WIF_PROVIDER` and `GCP_SA_EMAIL` secrets to point to the target environment's values.

---

## Step 10: Common Commands & Troubleshooting

### Useful Commands

| Task | Command |
|------|---------|
| **SSH into VM** | `gcloud compute ssh cloudopshub-app-ENV --zone=us-central1-a --tunnel-through-iap` |
| **Check all containers** | `... --command="sudo docker ps"` |
| **View container logs** | `... --command="sudo docker logs gitops-backend-1 --tail 50"` |
| **View GitOps sync logs** | `... --command="sudo journalctl -u gitops-sync -f"` |
| **View startup script logs** | `... --command="sudo journalctl -u google-startup-scripts"` |
| **Restart all containers** | `... --command="cd /var/lib/gitops/repo && sudo docker compose -f gitops/docker-compose.yml up -d"` |
| **Restart GitOps sync** | `... --command="sudo systemctl restart gitops-sync"` |
| **Check .env file** | `... --command="sudo cat /var/lib/cloudopshub/.env"` |
| **Terraform outputs** | `terraform output` |
| **Terraform state** | `terraform state list` |
| **CI/CD status** | `gh run list --limit 5` |
| **Watch a CI run** | `gh run watch` |

### Troubleshooting

| Issue | Solution |
|-------|----------|
| SSH times out | Use `--tunnel-through-iap` flag (required on COS with OS Login) |
| App returns 502/503 | Check backend: `sudo docker logs gitops-backend-1` |
| Backend crashes with `Cannot read properties of undefined (reading 'use_env_variable')` | Add missing environment to `theepicbook/config/config.json` (must have entry for dev, staging, production) |
| Images not pulling | Verify CI workflow succeeded and images exist in Artifact Registry |
| Alertmanager not sending to Slack | Check that config uses `SLACK_WEBHOOK_PLACEHOLDER` (not `${SLACK_WEBHOOK_URL}`), and that the secret is set in Secret Manager |
| Alertmanager not reloading config | GitOps sync force-recreates it; manually: `sudo docker compose stop alertmanager && sudo docker compose rm -f alertmanager && sudo docker compose up -d alertmanager` |
| Ports not accessible | Check firewall rule: Compute Engine > VM > Network tags should include `web` |
| Git push rejected | Remote has newer commits from CD: `git pull --rebase && git push` |
| `build-and-push` fails on auth | Verify `GCP_WIF_PROVIDER` and `GCP_SA_EMAIL` secrets match current Terraform outputs |
| Security scans fail | Expected if tokens not set. Pipeline continues regardless (`continue-on-error: true`) |

---

## You're Done!

Your CloudOpsHub platform is now:
- Running on a single GCP VM per environment
- Auto-deploying via GitOps on every code push
- Fully containerized with Docker Compose (7 services)
- Security-scanned on every CI run (5 tools)
- Monitorable via Grafana (3 dashboards) + Prometheus
- Alerting to Slack via Alertmanager (if configured)

---

## Next Steps

- Add SSL/TLS (use certbot with nginx or a GCP load balancer)
- Set up database backups (volume snapshots or mysqldump cron)
- Add more alert rules (`gitops/*/monitoring/alert.rules.yml`)
- Customize Grafana dashboards (`gitops/*/monitoring/dashboards/`)
- Scale horizontally (add load balancer + multiple VMs)
- Monitor costs in GCP Billing Console

---

## Need Help?

1. **Check logs** — VM: `journalctl -u gitops-sync`; Containers: `docker logs <container>`
2. **Verify Terraform state** — `terraform plan -var-file=ENV.tfvars`
3. **Check GCP Console** — Compute Engine, Artifact Registry, Secret Manager
4. **Open an Issue** on GitHub with:
   - What you were trying
   - Error messages
   - `terraform output` (redact secrets)
   - `sudo docker ps` output
