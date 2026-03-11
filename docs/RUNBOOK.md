# CloudOpsHub Deployment Runbook

> A step-by-step guide to deploy TheEpicBook application from scratch. Follow the steps in order — each section builds on the previous one.

---

## Table of Contents

1. [What You Need Before Starting](#1-what-you-need-before-starting)
2. [Set Up HashiCorp Vault (Secrets Manager)](#2-set-up-hashicorp-vault-secrets-manager)
3. [Add Secrets to GitHub](#3-add-secrets-to-github)
4. [Create Cloud Infrastructure with Terraform](#4-create-cloud-infrastructure-with-terraform)
5. [Seed the Database](#5-seed-the-database)
6. [Deploy the Application](#6-deploy-the-application)
7. [Set Up Monitoring](#7-set-up-monitoring)
8. [Useful Commands Reference](#8-useful-commands-reference)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. What You Need Before Starting

Install the following tools on your machine. Click each link for installation instructions.

| Tool | What It Does | Install Link |
|------|-------------|-------------|
| **Terraform** >= 1.5 | Creates cloud infrastructure (servers, databases, etc.) from code | [Install Terraform](https://www.terraform.io/downloads) |
| **Docker** & Docker Compose | Packages the app into containers so it runs the same everywhere | [Install Docker](https://docs.docker.com/get-docker/) |
| **gcloud CLI** | Lets you interact with Google Cloud from the terminal | [Install gcloud](https://cloud.google.com/sdk/docs/install) |
| **AWS CLI** | Lets you interact with AWS (we use it for the container registry) | [Install AWS CLI](https://aws.amazon.com/cli/) |
| **Vault CLI** (optional) | Manages secrets like passwords and API keys securely | [Install Vault](https://developer.hashicorp.com/vault/install) |
| **MySQL client** | Needed to seed the database with initial data | Included with most MySQL installations |

### Verify your installations

Run these commands to make sure everything is installed:

```bash
terraform --version    # Should show v1.5 or higher
docker --version       # Should show Docker version
docker compose version # Should show Docker Compose version
gcloud --version       # Should show Google Cloud SDK version
aws --version          # Should show aws-cli version
```

### Accounts you need

- **Google Cloud** account with a project (ours is `expandox-project1`)
- **AWS** account (for ECR container registry)
- **GitHub** account with access to this repo
- **Snyk** account (free tier works) for security scanning
- **SonarQube** instance for code quality scanning

---

## 2. Set Up HashiCorp Vault (Secrets Manager)

> **What is Vault?** HashiCorp Vault stores sensitive data (passwords, API keys, tokens) securely. Instead of putting secrets in code, our app fetches them from Vault at deploy time.

### Step 1: Connect to your Vault server

```bash
# Replace with your actual Vault server address
export VAULT_ADDR="https://vault.example.com"

# Use your admin token to authenticate
export VAULT_TOKEN="<your-vault-admin-token>"
```

### Step 2: Run the setup script

This script creates all the secrets, access policies, and authentication methods our app needs:

```bash
./vault/vault-setup.sh
```

**What this script does behind the scenes:**
- Enables a secrets engine (a place to store secrets)
- Stores your database URL and ArgoCD token
- Creates a read-only policy (so the app can read secrets but not modify them)
- Creates an AppRole (a machine-friendly login method for CI/CD)

### Step 3: Get the credentials for CI/CD

```bash
# Get the Role ID (like a username for machines)
vault read auth/approle/role/cloudopshub-ci/role-id

# Generate a Secret ID (like a password for machines)
vault write -f auth/approle/role/cloudopshub-ci/secret-id
```

**Save both values** — you'll add them to GitHub in the next step.

---

## 3. Add Secrets to GitHub

GitHub Actions (our CI/CD pipeline) needs access to various services. We store credentials as GitHub Secrets so they're never exposed in code.

### Step 1: Navigate to your repo's secrets page

1. Go to your GitHub repository
2. Click **Settings** (top tab)
3. Click **Secrets and variables** in the left sidebar
4. Click **Actions**
5. Click **New repository secret** for each one below

### Step 2: Add these secrets

| Secret Name | Where to Get It | Example Value |
|-------------|----------------|---------------|
| `AWS_ACCOUNT_ID` | AWS Console > top-right corner > Account ID | `123456789012` |
| `AWS_ACCESS_KEY_ID` | AWS IAM > Users > Security credentials > Create access key | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | Given when you create the access key above | `wJalrXUtnFEMI/K7MDENG/...` |
| `AWS_REGION` | The AWS region where your ECR registry lives | `us-east-1` |
| `SNYK_TOKEN` | [Snyk Account Settings](https://app.snyk.io/account) > API Token | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `SONAR_TOKEN` | SonarQube > My Account > Security > Generate Token | `sqp_xxxxxxxxxxxxxxxxx` |
| `SONAR_HOST_URL` | Your SonarQube server address | `https://sonarqube.example.com` |
| `VAULT_ADDR` | Your Vault server address (same as Step 2) | `https://vault.example.com` |
| `VAULT_ROLE_ID` | From Step 2, Step 3 above | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `VAULT_SECRET_ID` | From Step 2, Step 3 above | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `ARGOCD_SERVER` | Your ArgoCD server address | `https://argocd.example.com` |

### Step 3: Create a production environment

1. In the same Settings page, click **Environments**
2. Click **New environment**, name it `production`
3. Check **Required reviewers** and add yourself (this means someone must approve production deployments)

---

## 4. Create Cloud Infrastructure with Terraform

> **What is Terraform?** Terraform lets you define cloud infrastructure (servers, databases, networks) in code files. You run a command, and it creates everything for you on Google Cloud.

### Step 1: Navigate to the Terraform directory

```bash
cd terraform
```

### Step 2: Initialize Terraform

This downloads the required plugins for Google Cloud and AWS:

```bash
terraform init
```

You should see: `Terraform has been successfully initialized!`

### Step 3: Deploy the dev environment

```bash
# Create (or switch to) the "dev" workspace
# Workspaces let you manage separate environments (dev/staging/production) with the same code
terraform workspace new dev 2>/dev/null || terraform workspace select dev

# Preview what Terraform will create (no changes made yet)
terraform plan -var-file=envs/dev.tfvars -var="db_password=YOUR_DB_PASSWORD"

# If the plan looks good, apply it (type "yes" when prompted)
terraform apply -var-file=envs/dev.tfvars -var="db_password=YOUR_DB_PASSWORD"
```

> **Tip:** Replace `YOUR_DB_PASSWORD` with a strong password. In production, fetch this from Vault instead of typing it directly.

### Step 4: Deploy staging and production (when ready)

```bash
# Staging
terraform workspace new staging 2>/dev/null || terraform workspace select staging
terraform apply -var-file=envs/staging.tfvars -var="db_password=YOUR_DB_PASSWORD"

# Production
terraform workspace new production 2>/dev/null || terraform workspace select production
terraform apply -var-file=envs/production.tfvars -var="db_password=YOUR_DB_PASSWORD"
```

### Step 5: Save the output values

After each `terraform apply`, check the outputs — you'll need these later:

```bash
terraform output vm_ips              # IP addresses of your servers
terraform output db_connection_string # Database connection URL
terraform output load_balancer_ip    # Public IP for your website
terraform output ecr_repository_url  # Where Docker images are stored
```

### What Terraform creates for you

- **VPC & Network** — A private network with subnets, NAT gateway, and firewall rules
- **Compute Engine VM** — A server running Container-Optimized OS (pre-installed Docker)
- **Cloud SQL** — A managed MySQL database (private IP, automated backups)
- **Load Balancer** — HTTPS traffic routing with Cloud Armor WAF protection
- **Secret Manager** — Stores database credentials securely on GCP
- **ECR Repositories** — Two container registries on AWS (one for frontend, one for backend)
- **Monitoring** — Uptime checks and alert policies on GCP

---

## 5. Seed the Database

> **What is seeding?** Seeding means inserting initial data (books, authors) into the database so the app has something to display.

Sequelize (our ORM) automatically creates the database tables when the app starts for the first time. But we need to add the actual book and author data separately.

### Step 1: Get your database URL

```bash
# From Terraform output:
terraform output db_connection_string

# Or from Vault:
vault kv get -field=DATABASE_URL secret/cloudopshub/database
```

The URL format is: `mysql://appuser:PASSWORD@CLOUD_SQL_IP:3306/bookstore`

### Step 2: Run the seed script

```bash
./scripts/seed-database.sh "mysql://appuser:PASSWORD@CLOUD_SQL_IP:3306/bookstore"
```

This script is **idempotent** — meaning it's safe to run multiple times. It won't create duplicate data.

---

## 6. Deploy the Application

There are three ways to deploy, depending on your situation.

### Option A: Local Development (quickest way to test)

Use this to run the app on your own machine:

```bash
# 1. Copy the example environment file and fill in your values
cp .env.example .env

# 2. Edit .env with your DATABASE_URL and other settings
#    (open .env in your text editor)

# 3. Build the Docker images
./scripts/build.sh

# 4. Start the app
docker compose up

# 5. Open http://localhost in your browser
```

To stop the app: press `Ctrl+C` or run `docker compose down`

To also run a local MySQL database (instead of Cloud SQL):

```bash
docker compose --profile local up
```

### Option B: Manual Deploy to GCP

Use this for first-time setup or debugging:

```bash
# 1. SSH into your GCP server
gcloud compute ssh <instance-name> --zone=<zone> --project=expandox-project1

# 2. On the server, set your environment variables
export DATABASE_URL="mysql://appuser:PASSWORD@CLOUD_SQL_IP:3306/bookstore"
export ECR_REGISTRY="<aws-account-id>.dkr.ecr.<region>.amazonaws.com"

# 3. Log in to ECR (so Docker can pull your images)
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin $ECR_REGISTRY

# 4. Start the application
cd /opt/theepicbook
docker compose up -d
```

> **Tip:** The `-d` flag runs containers in the background (detached mode).

### Option C: GitOps Deploy (standard production flow)

This is the automated flow — no manual steps needed after initial setup:

1. **You push code** to the `main` branch
2. **CI pipeline runs automatically:**
   - Lints your code (checks code style)
   - Runs security scans (Snyk, SonarQube, Gitleaks)
   - Builds Docker images for frontend and backend
   - Scans images for vulnerabilities (Trivy)
   - Pushes images to ECR
3. **CD pipeline runs automatically:**
   - Scans Terraform configs (Checkov, TFSec)
   - Updates the image tags in GitOps manifests
   - Triggers ArgoCD to deploy the new version
4. **ArgoCD deploys** the new version to your GCP server

You can monitor the pipeline in your GitHub repo under the **Actions** tab.

---

## 7. Set Up Monitoring

> **What are these tools?**
> - **Prometheus** collects metrics (CPU usage, request counts, etc.)
> - **Grafana** displays those metrics as visual dashboards
> - **Alertmanager** sends alerts (email/Slack) when something goes wrong

### Start the monitoring stack

```bash
cd monitoring
docker compose up -d
```

### Access the dashboards

| Tool | URL | Login |
|------|-----|-------|
| **Prometheus** | http://localhost:9090 | No login required |
| **Grafana** | http://localhost:3000 | Username: `admin`, Password: value of `$GRAFANA_PASSWORD` (default: `admin`) |
| **Alertmanager** | http://localhost:9093 | No login required |

### What you get out of the box

- A pre-built **Grafana dashboard** showing app and server metrics
- **Alert rules** that notify you when:
  - A container goes down
  - CPU usage exceeds 80%
  - Memory usage exceeds 80%
  - Disk space drops below 10%

### Customize alerts

Edit `monitoring/alertmanager/alertmanager.yml` to configure where alerts are sent (email, Slack, PagerDuty, etc.).

---

## 8. Useful Commands Reference

### Docker

```bash
# See running containers and their status
docker compose ps

# View live logs from all services
docker compose logs -f

# View logs from a specific service (e.g., backend)
docker compose logs -f backend

# Restart a specific service
docker compose restart backend

# Stop everything
docker compose down

# Stop everything AND delete all data (careful!)
docker compose down -v
```

### Terraform

```bash
# See which workspace (environment) you're in
terraform workspace show

# Switch to a different environment
terraform workspace select dev

# Preview changes before applying
terraform plan -var-file=envs/dev.tfvars

# Apply changes
terraform apply -var-file=envs/dev.tfvars

# Destroy all infrastructure (CAREFUL — this deletes everything!)
terraform destroy -var-file=envs/dev.tfvars
```

### GCP

```bash
# List your VMs
gcloud compute instances list --project=expandox-project1

# SSH into a VM
gcloud compute ssh <instance-name> --zone=<zone> --project=expandox-project1

# View Cloud SQL instances
gcloud sql instances list --project=expandox-project1
```

### GitOps (environment-specific deploys)

```bash
# Deploy with dev settings
docker compose -f gitops/base/docker-compose.yml \
  -f gitops/overlays/dev/docker-compose.override.yml up -d

# Deploy with staging settings
docker compose -f gitops/base/docker-compose.yml \
  -f gitops/overlays/staging/docker-compose.override.yml up -d

# Deploy with production settings
docker compose -f gitops/base/docker-compose.yml \
  -f gitops/overlays/production/docker-compose.override.yml up -d
```

---

## 9. Troubleshooting

### "Cannot connect to the Docker daemon"

Docker isn't running. Start it:

```bash
sudo systemctl start docker
```

### "Error: No such container"

The container may have crashed. Check the logs:

```bash
docker compose logs backend
```

### "Access Denied" on Cloud SQL

- Verify your `DATABASE_URL` has the correct username, password, and IP
- Make sure the VM's service account has `roles/cloudsql.client` permission
- Check that Cloud SQL has private IP enabled and is on the same VPC

### "Unauthorized" on ECR push/pull

Your AWS credentials may have expired:

```bash
# Re-authenticate with ECR
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <ecr-registry-url>
```

### Terraform "Error acquiring state lock"

Someone else (or a previous run) is currently applying changes. If you're sure no one else is running Terraform:

```bash
terraform force-unlock <LOCK_ID>
```

### ArgoCD sync failed

1. Check the ArgoCD UI for error details
2. Verify the GitOps manifests in `gitops/base/docker-compose.yml` have valid image tags
3. Check that the VM can reach ECR (network/firewall rules)

### App starts but shows "502 Bad Gateway"

The frontend (nginx) is running but can't reach the backend. Check:

```bash
# Is the backend container running?
docker compose ps

# Check backend logs for errors
docker compose logs backend

# Common cause: backend hasn't finished starting yet — wait 10-20 seconds and refresh
```
