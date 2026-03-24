# CloudOpsHub: Absolute Beginner Deployment Guide

*Deploy a complete Docker-based infrastructure platform on Google Cloud with GitOps and CI/CD in under 30 minutes.*

---

## 📋 Prerequisites

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

## 🗺️ Architecture Overview (Simple)

```
GitHub (main branch)
   ↓ push
CI Pipeline (GitHub Actions)
   ↓ build & push images
GitOps Sync (runs on VM)
   ↓ every 60s checks Git changes
   ↓ pulls new images, redeploys
```

**What gets deployed:**

| Component | Description |
|-----------|-------------|
| **VM** | Single e2-medium instance (Ubuntu/COS) |
| **App** | Node.js backend + Nginx frontend + MySQL |
| **Monitoring** | Prometheus + Grafana + Alertmanager |
| **Registry** | Google Artifact Registry (Docker images) |
| **Secrets** | Google Secret Manager (passwords, webhook) |

---

## Step 1: Prepare GCP Project

### 1.1 Create or select a GCP project

Go to [Google Cloud Console](https://console.cloud.google.com), create a new project or use existing. Note your **Project ID** (e.g., `my-cloudopshub`).

You'll need:
- **Project ID**: `YOUR_PROJECT_ID`
- **Billing**: Must be enabled on the project
- **APIs to enable**: Compute Engine, Secret Manager, Artifact Registry, IAM

### 1.2 Enable Required APIs (One-time)

In Cloud Console → **APIs & Services** → **Enable APIs** → search and enable:

- Compute Engine API
- Secret Manager API
- Artifact Registry API
- IAM API

Or run:
```bash
gcloud services enable compute.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com
```

### 1.3 Create Service Account for GitHub Actions

GitHub Actions needs permission to push Docker images.

```bash
gcloud iam service-accounts create cloudopshub-ci \
  --display-name "CloudOpsHub CI/CD Service Account"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member "serviceAccount:cloudopshub-ci@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role "roles/artifactregistry.writer"
```

**Note**: You'll configure Workload Identity Federation later in the GitHub secrets step — this allows GitHub to act as this service account.

---

## Step 2: Prepare GitHub Repository

### 2.1 Fork or Clone This Repository

```bash
git clone https://github.com/your-username/CloudOpsHub.git
cd CloudOpsHub
```

If you want to use a different repository name, you'll need to update `infra/variables.tf` accordingly.

### 2.2 Set GitHub Secrets

The CI/CD and Terraform need these secrets stored in GitHub (Repository → Settings → Secrets and variables → Actions):

| Secret Name | Value | How to get |
|-------------|-------|------------|
| `GCP_PROJECT_ID` | Your GCP project ID | From Step 1.1 |
| `GCP_REGION` | GCP region (e.g., `us-central1`) | Your choice |
| `GCP_WIF_PROVIDER` | Workload Identity Provider | After `terraform apply` (see below) |
| `GCP_SA_EMAIL` | Service account email | `cloudopshub-ci@YOUR_PROJECT_ID.iam.gserviceaccount.com` |

Set them with GitHub CLI:
```bash
cd /path/to/CloudOpsHub
gh repo clone your-username/CloudOpsHub
cd CloudOpsHub

gh secret set GCP_PROJECT_ID -b "YOUR_PROJECT_ID"
gh secret set GCP_REGION -b "us-central1"
gh secret set GCP_WIF_PROVIDER -b "will-get-after-first-terraform-apply"
gh secret set GCP_SA_EMAIL -b "cloudopshub-ci@YOUR_PROJECT_ID.iam.gserviceaccount.com"
```

**Note**: `GCP_WIF_PROVIDER` will be filled in after you run Terraform the first time (we'll copy the output).

---

## Step 3: Deploy Infrastructure with Terraform

### 3.1 Prepare Terraform Variables

Copy the example tfvars file and edit with your values:

```bash
cd infra
cp dev.tfvars.example dev.tfvars
```

Edit `dev.tfvars` (use `nano`/`vim`/VS Code):

```hcl
project_id    = "YOUR_PROJECT_ID"        # GCP project ID
project_name  = "cloudopshub"            # can be anything lowercase
environment   = "dev"                    # dev, staging, production
region        = "us-central1"            # or your preferred region
zone          = "us-central1-a"          # must match region
instance_type = "e2-medium"              # VM size
github_repo   = "your-username/CloudOpsHub"

# Generate secure passwords (run in terminal):
# openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 20
db_password       = "YOUR_DB_PASSWORD_HERE"
grafana_password  = "YOUR_GRAFANA_PASSWORD_HERE"
slack_webhook_url = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"  # optional, placeholder works
```

### 3.2 Initialize and Apply Terraform

```bash
terraform init
terraform apply -var-file=dev.tfvars
```

You'll see a plan summary:
```
Plan: 28 to add, 0 to change, 0 to destroy.
```

Type `yes` to confirm.

**Wait 2-3 minutes** — Terraform creates:
- VPC network & firewall
- Service Account & IAM roles
- Artifact Registry repository
- Secrets in Secret Manager (you'll see them in Cloud Console)
- VM instance with static IP
- Workload Identity Federation (for GitHub Actions)

### 3.3 Get Terraform Outputs

After apply completes, run:

```bash
terraform output
```

Copy these values — you'll need them:

| Output | What it is |
|--------|------------|
| `vm_ip` | Static IP of your VM (e.g., `35.188.65.76`) |
| `wif_provider` | Workload Identity Provider path |
| `service_account_email` | CI service account email |
| `app_url` | Your app URL |
| `grafana_url` | Grafana dashboard URL |
| `prometheus_url` | Prometheus metrics URL |

---

## Step 4: Update GitHub Secrets with Terraform Outputs

Now set the `GCP_WIF_PROVIDER` secret (Step 2.2) with the value from `terraform output wif_provider`:

```bash
gh secret set GCP_WIF_PROVIDER -b "projects/YOUR_PROJECT_NUMBER/locations/global/workloadIdentityPools/cloudopshub-github-dev/providers/github-provider"
```

Replace with your actual output from `terraform output wif_provider`.

---

## Step 5: Wait for Initial Deployment

The VM automatically boots and runs a startup script that:
- Installs Docker & Docker Compose
- Clones this GitHub repository
- Starts the **GitOps sync agent** (systemd service)
- Fetches secrets from Secret Manager
- Deploys the full app stack using `docker-compose`

**This takes 2-5 minutes** after Terraform apply.

You can watch the VM boot:
```bash
gcloud compute ssh cloudopshub-app-dev --zone=us-central1-a --tunnel-through-iap \
  --ssh-flag="-o StrictHostKeyChecking=no" \
  --command="sudo journalctl -u google-startup-scripts -f"
```

---

## Step 6: Verify Deployment

### 6.1 Check VM is Running

```bash
gcloud compute instances list
```

Find `cloudopshub-app-dev` — status should be `RUNNING`.

### 6.2 Check Containers

```bash
gcloud compute ssh cloudopshub-app-dev --zone=us-central1-a --tunnel-through-iap \
  --ssh-flag="-o StrictHostKeyChecking=no" \
  --command="sudo docker ps"
```

You should see 7 containers:
- `gitops-frontend-1`
- `gitops-backend-1`
- `gitops-database-1`
- `gitops-prometheus-1`
- `gitops-grafana-1`
- `gitops-alertmanager-1`
- `gitops-node-exporter-1`

### 6.3 Access the App

Open browser to `http://YOUR_VM_IP` (from `terraform output vm_ip`).

You should see **TheEpicBook** homepage.

### 6.4 Access Monitoring

| Tool | URL | Login |
|------|-----|-------|
| Grafana | `http://YOUR_VM_IP:3000` | `admin` / `YOUR_GRAFANA_PASSWORD` |
| Prometheus | `http://YOUR_VM_IP:9090` | no auth |

Grafana should show 3 dashboards:
- Infrastructure Overview
- Application & Monitoring Health
- Epicbook (pre-seeded)

---

## Step 7: Test CI/CD Pipeline

### 7.1 Make a Code Change

Edit any file in the repository, for example change the app title:

```bash
cd theepicbook/views/layouts/main.handlebars
# Find and change the title, save
```

### 7.2 Commit & Push

```bash
git add .
git commit -m "test: update homepage title"
git push
```

### 7.3 Watch GitHub Actions

Go to your GitHub repo → **Actions** → you should see:
1. **CI** workflow running → builds and pushes 3 Docker images to Artifact Registry
2. **CD** workflow triggers automatically after CI success → updates image tags in `gitops/docker-compose.yml` and pushes

### 7.4 Watch GitOps Sync Redeploy

On the VM, the `gitops-sync` systemd service polls Git every 60 seconds. When it detects changes, it pulls new images and restarts containers.

Check sync logs:
```bash
gcloud compute ssh cloudopshub-app-dev --zone=us-central1-a --tunnel-through-iap \
  --ssh-flag="-o StrictHostKeyChecking=no" \
  --command="sudo journalctl -u gitops-sync -f"
```

Within 60 seconds of GitHub Actions completing, you should see:
```
Change detected: <old-sha> -> <new-sha>
Files changed — redeploying...
Sync successful
```

Reload your app URL (`http://YOUR_VM_IP`) — the change should be live.

---

## Step 8: Configure Slack Alerts (Optional)

If you have a Slack workspace and want alerts:

### 8.1 Create Slack Webhook

1. Go to https://api.slack.com/apps
2. Create a new app → **Incoming Webhooks**
3. Activate Incoming Webhooks
4. Add a new webhook → select a channel (e.g., `#devops`)
5. Copy the webhook URL (looks like `https://hooks.slack.com/services/T0.../.../...`)

### 8.2 Update Secret Manager with Webhook

You may need to update the secret value (Terraform manages it, so you can either update `dev.tfvars` and reapply, or manually in Secret Manager):

```bash
# Option A: Update via Terraform (recommended)
# Edit dev.tfvars, change slack_webhook_url, then:
terraform apply -var-file=dev.tfvars

# Option B: Manual (temporary, will be overwritten by next apply)
gcloud secrets versions add cloudopshub-slack-webhook-dev \
  --project=YOUR_PROJECT_ID \
  --data-file=<(echo "YOUR_SLACK_WEBHOOK_URL")
```

### 8.3 Set Alertmanager Channel

The alertmanager config sends to `#devops` by default. To change it:

```bash
sed -i 's|channel: "#devops"|channel: "#your-channel"|' gitops/dev/monitoring/alertmanager.yml
git add gitops/dev/monitoring/alertmanager.yml
git commit -m "chore: update alertmanager channel"
git push
```

GitOps sync will redeploy alertmanager automatically.

---

## Step 9: Common Commands & Troubleshooting

### Useful Commands

| Task | Command |
|------|---------|
| **Check VM status** | `gcloud compute instances describe cloudopshub-app-dev --zone=us-central1-a` |
| **View VM logs** | `gcloud compute ssh ... --command="sudo journalctl -u google-startup-scripts"` |
| **View GitOps sync logs** | `gcloud compute ssh ... --command="sudo journalctl -u gitops-sync -f"` |
| **Docker logs for a container** | `gcloud compute ssh ... --command="sudo docker logs gitops-backend-1"` |
| **Restart all services** | `gcloud compute ssh ... --command="cd /var/lib/gitops/repo && sudo /var/lib/toolbox/docker-compose -f gitops/docker-compose.yml -f gitops/overlays/dev/docker-compose.override.yml restart"` |
| **SSH into VM** | `gcloud compute ssh cloudopshub-app-dev --zone=us-central1-a --tunnel-through-iap` |
| **Terraform state** | `terraform state list` |
| **Destroy everything** | `terraform destroy -var-file=dev.tfvars` |

### Troubleshooting

| Issue | Solution |
|-------|----------|
| `Permission denied` when SSH | Use `--tunnel-through-iap` flag (required on COS with OS Login) |
| App returns 502/503 | Check backend container: `sudo docker logs gitops-backend-1` |
| Images not pulling | Verify CI workflow succeeded and images exist in Artifact Registry |
| Alertmanager not reloading after config change | GitOps script now force-recreates; if not, manually: `docker-compose stop alertmanager && docker-compose rm -f alertmanager && docker-compose up -d alertmanager` |
| Ports not accessible | Check firewall rule includes the port (9093 for alertmanager) |
| GitOps sync stuck | Restart service: `sudo systemctl restart gitops-sync` |

---

## Step 10: Deploy Additional Environments (Staging/Production)

### 10.1 Prepare Staging

```bash
cd infra
terraform workspace new staging
cp dev.tfvars staging.tfvars
# Edit staging.tfvars:
# - environment = "staging"
# - change db_password, grafana_password to new values
# - change instance_type if needed (e.g., e2-standard-2)
terraform apply -var-file=staging.tfvars
```

Copy the outputs (`vm_ip`, `wif_provider`, etc.) and update GitHub secrets for staging (you can use same secrets or create new ones with naming convention like `GCP_WIF_PROVIDER_STAGING`).

**Note**: The GitOps sync will automatically use the `staging` environment based on the `GITOPS_ENVIRONMENT` environment variable passed by the startup script. You'll need a separate Terraform apply to provision a staging VM.

### 10.2 Deploy Production

Same as staging, but:
- Use larger instance type (e.g., `e2-standard-4`)
- Consider using a load balancer (not in this simplified setup)
- Use stronger, unique passwords
- Enable additional monitoring/alerts

---

## 🎉 You're Done!

Your CloudOpsHub platform is now:
- ✅ Running on a single VM
- ✅ Auto-deploying via GitOps on code changes
- ✅ Fully containerized with Docker Compose
- ✅ Monitorable via Grafana + Prometheus
- ✅ Alerting to Slack (if configured)

---

## 📚 Next Steps

- Customize Grafana dashboards (`gitops/*/monitoring/dashboards/`)
- Add more alert rules (`gitops/*/monitoring/alert.rules.yml`)
- Set up database backups (volume snapshots or export)
- Add SSL/TLS (use certbot with nginx)
- Scale horizontally (add more VMs behind load balancer — requires more Terraform)
- Monitor costs in GCP Billing Console

---

## 📞 Need Help?

1. **Check logs** — VM: `journalctl -u gitops-sync`; Containers: `docker logs <container>`
2. **Verify Terraform state** — `terraform plan -var-file=dev.tfvars`
3. **Read CLAUDE.md** in repo for architecture details
4. **Open an Issue** on GitHub with:
   - What you were trying
   - Error messages
   - `terraform output` (redact secrets)
   - `gcloud compute ssh ... --command="sudo docker ps"` output

Happy deploying! 🚀
