# CI/CD Pipeline Setup Guide - CloudOpsHub

This guide walks you through setting up every secret, service, and configuration needed for the CI/CD pipelines to work. Follow each section in order.

---

## Table of Contents

1. [Overview - What Needs to Be Set Up](#1-overview---what-needs-to-be-set-up)
2. [GCP Service Account (GCP_SA_KEY, GCP_PROJECT_ID, GCP_REGION)](#2-gcp-service-account)
3. [Snyk (SNYK_TOKEN)](#3-snyk)
4. [SonarQube (SONAR_TOKEN, SONAR_HOST_URL)](#4-sonarqube)
5. [HashiCorp Vault (VAULT_ADDR, VAULT_ROLE_ID, VAULT_SECRET_ID)](#5-hashicorp-vault)
6. [ArgoCD (ARGOCD_SERVER)](#6-argocd)
7. [GitHub Environment Setup](#7-github-environment-setup)
8. [Adding Secrets to GitHub](#8-adding-secrets-to-github)
9. [Testing the Pipeline](#9-testing-the-pipeline)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Overview - What Needs to Be Set Up

The CI/CD pipeline has two workflows:

**CI Pipeline** (`.github/workflows/ci.yml`) - Triggered on every push/PR to `main`:
- Snyk vulnerability scan
- SonarQube code quality scan
- Gitleaks secret detection
- ESLint + Hadolint linting
- Docker build + Trivy scan + push to Artifact Registry

**CD Pipeline** (`.github/workflows/cd.yml`) - Triggered after CI succeeds on `main`:
- Checkov + TFSec terraform security scan
- Verify images exist in Artifact Registry
- Fetch secrets from HashiCorp Vault
- Update GitOps manifests
- Trigger ArgoCD sync

### Complete Secret List

| Secret Name | Used In | Required |
|---|---|---|
| `GCP_PROJECT_ID` | CI + CD | Yes |
| `GCP_REGION` | CI + CD | Yes |
| `GCP_SA_KEY` | CI + CD | Yes |
| `SNYK_TOKEN` | CI | Yes |
| `SONAR_TOKEN` | CI | Yes |
| `SONAR_HOST_URL` | CI | Yes |
| `VAULT_ADDR` | CD | Yes |
| `VAULT_ROLE_ID` | CD | Yes |
| `VAULT_SECRET_ID` | CD | Yes |
| `ARGOCD_SERVER` | CD | Yes |

`GITHUB_TOKEN` is automatically provided by GitHub Actions - you do NOT need to create it.

---

## 2. GCP Service Account

This service account lets GitHub Actions push Docker images to Artifact Registry and verify deployments.

### Step 1: Open Google Cloud Console

1. Go to https://console.cloud.google.com
2. Make sure you're in your project (top-left dropdown). Your project is `expadox-lab`.

### Step 2: Create a Service Account

1. In the left sidebar, go to **IAM & Admin > Service Accounts**
   - Direct URL: https://console.cloud.google.com/iam-admin/serviceaccounts?project=expadox-lab
2. Click **+ CREATE SERVICE ACCOUNT** at the top
3. Fill in the details:
   - **Service account name**: `github-actions-cicd`
   - **Service account ID**: will auto-fill as `github-actions-cicd`
   - **Description**: `Service account for GitHub Actions CI/CD pipeline`
4. Click **CREATE AND CONTINUE**

### Step 3: Assign Roles

On the "Grant this service account access to project" screen, add these roles one at a time by clicking **+ ADD ANOTHER ROLE** after each:

1. **Artifact Registry Writer** - Push/pull Docker images
   - Search for: `Artifact Registry Writer`
2. **Artifact Registry Reader** - Verify images exist
   - Search for: `Artifact Registry Reader`
3. **Storage Object Viewer** - Read from GCS buckets
   - Search for: `Storage Object Viewer`

Click **CONTINUE**, then **DONE**.

### Step 4: Create a JSON Key

1. Find your new service account `github-actions-cicd@expadox-lab.iam.gserviceaccount.com` in the list
2. Click on it to open its details
3. Go to the **KEYS** tab
4. Click **ADD KEY > Create new key**
5. Select **JSON** format
6. Click **CREATE**
7. A `.json` file will download to your computer. **Keep this file safe** - you'll paste its contents into GitHub.

### Alternative: Use gcloud CLI

If you prefer the command line:

```bash
# Create the service account
gcloud iam service-accounts create github-actions-cicd \
  --display-name="GitHub Actions CI/CD" \
  --project=expadox-lab

# Assign roles
gcloud projects add-iam-policy-binding expadox-lab \
  --member="serviceAccount:github-actions-cicd@expadox-lab.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

gcloud projects add-iam-policy-binding expadox-lab \
  --member="serviceAccount:github-actions-cicd@expadox-lab.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"

gcloud projects add-iam-policy-binding expadox-lab \
  --member="serviceAccount:github-actions-cicd@expadox-lab.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

# Generate the JSON key file
gcloud iam service-accounts keys create ~/gcp-sa-key.json \
  --iam-account=github-actions-cicd@expadox-lab.iam.gserviceaccount.com

# View the key (you'll copy this into GitHub)
cat ~/gcp-sa-key.json
```

### Values for GitHub Secrets

| Secret | Value |
|---|---|
| `GCP_PROJECT_ID` | `expadox-lab` |
| `GCP_REGION` | `us-central1` |
| `GCP_SA_KEY` | Entire contents of the downloaded `.json` key file |

---

## 3. Snyk

Snyk scans your Node.js dependencies for known vulnerabilities.

### Step 1: Create a Snyk Account

1. Go to https://app.snyk.io/login
2. Click **Sign up with GitHub** (easiest - links directly to your repos)
3. Authorize Snyk to access your GitHub account

### Step 2: Get Your API Token

1. After logging in, click your **avatar** (bottom-left corner)
2. Click **Account settings**
   - Direct URL: https://app.snyk.io/account
3. In the **General** section, find **Auth Token**
4. Click **click to show** to reveal your token
5. Copy the token

### Values for GitHub Secrets

| Secret | Value |
|---|---|
| `SNYK_TOKEN` | The API token you copied (looks like `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) |

---

## 4. SonarQube

SonarQube performs static code analysis for bugs, code smells, and security vulnerabilities.

### Option A: Use SonarCloud (Free for open-source - Recommended)

SonarCloud is the hosted version of SonarQube. Free for public repos.

#### Step 1: Create Account

1. Go to https://sonarcloud.io
2. Click **Log in** > **GitHub**
3. Authorize SonarCloud

#### Step 2: Set Up Your Project

1. Click **+** (top-right) > **Analyze new project**
2. Select your GitHub organization/account
3. Select the `CloudOpsHub` repository
4. Click **Set Up**
5. Choose **With GitHub Actions** as the analysis method

#### Step 3: Get Your Token

1. Go to https://sonarcloud.io/account/security
2. Under **Generate Tokens**, enter a name: `cloudopshub-ci`
3. Click **Generate**
4. Copy the token immediately (it won't be shown again)

#### Step 4: Get Your Project Details

1. Go to your project on SonarCloud
2. The URL will look like: `https://sonarcloud.io/project/overview?id=cloudopshub-theepicbook`
3. Note the project key: `cloudopshub-theepicbook` (already configured in ci.yml)

### Option B: Self-Hosted SonarQube

If you want to run your own SonarQube server:

```bash
# Quick start with Docker (for testing)
docker run -d --name sonarqube \
  -p 9000:9000 \
  sonarqube:community

# Wait ~2 minutes for it to start, then open http://localhost:9000
# Default login: admin / admin (you'll be prompted to change it)
```

1. Log in to your SonarQube instance
2. Go to **My Account** (top-right avatar) > **Security**
3. Generate a token with name `cloudopshub-ci`, type **Project Analysis Token**
4. Copy the token

### Values for GitHub Secrets

| Secret | Value |
|---|---|
| `SONAR_TOKEN` | The token you generated |
| `SONAR_HOST_URL` | `https://sonarcloud.io` (for SonarCloud) OR `http://your-server:9000` (for self-hosted) |

---

## 5. HashiCorp Vault

Vault securely stores and manages secrets used during deployment (DATABASE_URL, ArgoCD token).

### Option A: HashiCorp Cloud Platform (HCP) Vault - Managed (Recommended)

#### Step 1: Create HCP Account

1. Go to https://portal.cloud.hashicorp.com/sign-up
2. Create an account (free tier available)

#### Step 2: Create a Vault Cluster

1. In the HCP dashboard, click **Vault** in the left sidebar
2. Click **Create cluster**
3. Choose:
   - **Tier**: Development (free)
   - **Cloud provider**: AWS or Azure
   - **Region**: closest to you
4. Click **Create cluster**
5. Wait ~5 minutes for provisioning

#### Step 3: Get Connection Details

1. Once the cluster is ready, click on it
2. Note the **Public Cluster URL** - this is your `VAULT_ADDR`
   - Looks like: `https://vault-cluster-xxxxx.vault.xxxxxxx.aws.hashicorp.cloud:8200`
3. Click **Generate admin token** to get a root token for initial setup

#### Step 4: Configure Vault

Open a terminal and set up Vault:

```bash
# Set your Vault address and token
export VAULT_ADDR="https://vault-cluster-xxxxx.vault.xxxxxxx.aws.hashicorp.cloud:8200"
export VAULT_TOKEN="hvs.your-admin-token"
# If you don't have the vault CLI, install it:
# https://developer.hashicorp.com/vault/install

# Enable KV secrets engine
vault secrets enable -path=secret kv-v2

# Store the database URL secret
vault kv put secret/cloudopshub/database \
  DATABASE_URL="mysql://appuser:YOUR_DB_PASSWORD@database:3306/bookstore"

# Store the ArgoCD auth token (set this after ArgoCD setup in Section 6)
vault kv put secret/cloudopshub/argocd \
  ARGOCD_AUTH_TOKEN="YOUR_ARGOCD_TOKEN"

# Store DB passwords
vault kv put secret/cloudopshub/db \
  DB_PASSWORD="YOUR_DB_PASSWORD" \
  DB_ROOT_PASSWORD="YOUR_ROOT_PASSWORD"

# Store Grafana password
vault kv put secret/cloudopshub/grafana \
  GRAFANA_PASSWORD="YOUR_GRAFANA_PASSWORD"
```

#### Step 5: Set Up AppRole Auth for CI/CD

```bash
# Create a policy that allows reading secrets
vault policy write cloudopshub-app - <<EOF
path "secret/data/cloudopshub/*" {
  capabilities = ["read"]
}
path "secret/metadata/cloudopshub/*" {
  capabilities = ["list"]
}
EOF

# Enable AppRole authentication
vault auth enable approle

# Create a role for CI/CD
vault write auth/approle/role/cloudopshub-ci \
  token_policies="cloudopshub-app" \
  token_ttl=1h \
  token_max_ttl=4h

# Get the Role ID (save this!)
vault read auth/approle/role/cloudopshub-ci/role-id
# Output: role_id    xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# Generate a Secret ID (save this!)
vault write -f auth/approle/role/cloudopshub-ci/secret-id
# Output: secret_id    xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### Option B: Self-Hosted Vault (Docker)

```bash
# Run Vault in dev mode (for testing only - data is NOT persisted)
docker run -d --name vault \
  -p 8200:8200 \
  -e 'VAULT_DEV_ROOT_TOKEN_ID=my-root-token' \
  hashicorp/vault:1.15

# Set env vars
export VAULT_ADDR="http://YOUR_SERVER_IP:8200"
export VAULT_TOKEN="my-root-token"

# Then follow the same steps as Step 4 and Step 5 above
```

**Important**: For production, use a proper Vault deployment with TLS, storage backend, and auto-unseal. The dev mode server is for testing only.

### Values for GitHub Secrets

| Secret | Value |
|---|---|
| `VAULT_ADDR` | Your Vault URL (e.g., `https://vault-cluster-xxxxx.vault.xxxxxxx.aws.hashicorp.cloud:8200`) |
| `VAULT_ROLE_ID` | The Role ID from `vault read auth/approle/role/cloudopshub-ci/role-id` |
| `VAULT_SECRET_ID` | The Secret ID from `vault write -f auth/approle/role/cloudopshub-ci/secret-id` |

---

## 6. ArgoCD

ArgoCD watches your Git repository and automatically deploys changes to your infrastructure.

### Step 1: Install ArgoCD on Your GCE VM

SSH into your VM:

```bash
# SSH via gcloud
gcloud compute ssh cloudopshub-app-dev --zone=us-central1-a --project=expadox-lab
```

Install ArgoCD as a Docker container:

```bash
# Create ArgoCD directory
sudo mkdir -p /opt/argocd

# Run ArgoCD server
sudo docker run -d \
  --name argocd-server \
  --restart unless-stopped \
  -p 8443:8443 \
  -v /opt/argocd:/home/argocd/data \
  quay.io/argoproj/argocd:v2.9.3 \
  argocd-server --insecure --port 8443

# Get the initial admin password
sudo docker exec argocd-server argocd admin initial-password
# Save the password that's printed!
```

### Step 2: Access ArgoCD UI

1. Open `http://YOUR_VM_EXTERNAL_IP:8443` in your browser
   - Your load balancer IP is `34.149.190.75`, but ArgoCD runs on port 8443
   - You may need to add a firewall rule for port 8443 or use SSH tunnel:
     ```bash
     gcloud compute ssh cloudopshub-app-dev --zone=us-central1-a \
       --tunnel-through-iap -- -L 8443:localhost:8443
     ```
   - Then open: `http://localhost:8443`
2. Login with:
   - Username: `admin`
   - Password: the password from Step 1

### Step 3: Change the Admin Password

1. In ArgoCD UI: click **User Info** (left sidebar) > **Update Password**
2. Or via CLI:
   ```bash
   sudo docker exec -it argocd-server argocd account update-password \
     --current-password INITIAL_PASSWORD \
     --new-password YOUR_NEW_PASSWORD
   ```

### Step 4: Generate an API Token

The CD pipeline needs a token to trigger syncs:

```bash
# Login to ArgoCD CLI
sudo docker exec -it argocd-server argocd login localhost:8443 \
  --username admin \
  --password YOUR_PASSWORD \
  --insecure

# Generate an API token for CI/CD
sudo docker exec -it argocd-server argocd account generate-token \
  --account admin
# Save the token that's printed!
```

### Step 5: Configure ArgoCD Application

Add your Git repository and application:

```bash
# Add the repository
sudo docker exec -it argocd-server argocd repo add \
  https://github.com/lakunzy7/CloudOpsHub.git

# Create the application (this matches gitops/argocd/application.yaml)
sudo docker exec -it argocd-server argocd app create theepicbook \
  --repo https://github.com/lakunzy7/CloudOpsHub.git \
  --path gitops/base \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace theepicbook \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

### Step 6: Update Vault with ArgoCD Token

Now go back to Vault and store the ArgoCD token:

```bash
vault kv put secret/cloudopshub/argocd \
  ARGOCD_AUTH_TOKEN="THE_TOKEN_FROM_STEP_4"
```

### Values for GitHub Secrets

| Secret | Value |
|---|---|
| `ARGOCD_SERVER` | `http://YOUR_VM_IP:8443` or `https://argocd.yourdomain.com` |

---

## 7. GitHub Environment Setup

The CD pipeline requires a GitHub Environment named `production`.

### Step 1: Create the Environment

1. Go to your GitHub repo: https://github.com/lakunzy7/CloudOpsHub
2. Click **Settings** (tab at the top)
3. In the left sidebar, click **Environments**
4. Click **New environment**
5. Name: `production`
6. Click **Configure environment**

### Step 2: Optional Protection Rules

You can add protection rules for safety:

- **Required reviewers**: Add yourself - you'll need to approve each deployment
- **Wait timer**: Add a delay (e.g., 5 minutes) before deployment starts
- **Deployment branches**: Restrict to `main` only

Click **Save protection rules**.

---

## 8. Adding Secrets to GitHub

Now add all the secrets you've collected.

### Step 1: Navigate to Secrets

1. Go to https://github.com/lakunzy7/CloudOpsHub
2. Click **Settings** > **Secrets and variables** > **Actions**
3. Click **New repository secret**

### Step 2: Add Each Secret

Add these one at a time. For each, enter the **Name** and **Secret** value, then click **Add secret**:

| # | Name | Value |
|---|---|---|
| 1 | `GCP_PROJECT_ID` | `expadox-lab` |
| 2 | `GCP_REGION` | `us-central1` |
| 3 | `GCP_SA_KEY` | Paste the entire JSON key file contents |
| 4 | `SNYK_TOKEN` | Your Snyk API token |
| 5 | `SONAR_TOKEN` | Your SonarQube/SonarCloud token |
| 6 | `SONAR_HOST_URL` | `https://sonarcloud.io` or your self-hosted URL |
| 7 | `VAULT_ADDR` | Your Vault server URL |
| 8 | `VAULT_ROLE_ID` | Vault AppRole Role ID |
| 9 | `VAULT_SECRET_ID` | Vault AppRole Secret ID |
| 10 | `ARGOCD_SERVER` | Your ArgoCD server URL |

### Using gh CLI (Alternative)

If you have the GitHub CLI installed:

```bash
# Login first
gh auth login

# Set each secret
gh secret set GCP_PROJECT_ID --body "expadox-lab"
gh secret set GCP_REGION --body "us-central1"
gh secret set GCP_SA_KEY < ~/gcp-sa-key.json
gh secret set SNYK_TOKEN --body "your-snyk-token"
gh secret set SONAR_TOKEN --body "your-sonar-token"
gh secret set SONAR_HOST_URL --body "https://sonarcloud.io"
gh secret set VAULT_ADDR --body "https://your-vault-url:8200"
gh secret set VAULT_ROLE_ID --body "your-role-id"
gh secret set VAULT_SECRET_ID --body "your-secret-id"
gh secret set ARGOCD_SERVER --body "http://your-argocd-url:8443"
```

---

## 9. Testing the Pipeline

### Test CI Pipeline

1. Make a small change (e.g., add a comment to any file)
2. Commit and push to `main`:
   ```bash
   git add -A
   git commit -m "test: trigger CI pipeline"
   git push origin main
   ```
3. Go to https://github.com/lakunzy7/CloudOpsHub/actions
4. You should see the **CI** workflow running
5. Watch each job:
   - `snyk-code-scan` - should pass (scans dependencies)
   - `sonarqube-scan` - should pass (analyzes code quality)
   - `gitleaks` - should pass (no secrets in code)
   - `lint` - should pass (ESLint)
   - `docker-lint` - should pass (Hadolint)
   - `build-and-push` - runs after all above pass (builds + pushes images)

### Test CD Pipeline

The CD pipeline triggers automatically after CI completes successfully on `main`:

1. After CI succeeds, go to **Actions** tab
2. You should see a **CD** workflow start
3. Watch each job:
   - `terraform-security` - Checkov + TFSec scan
   - `deploy` - Verifies images, fetches Vault secrets, updates manifests, triggers ArgoCD

### Verify Images Were Pushed

```bash
# List images in Artifact Registry
gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/expadox-lab/cloudopshub-docker
```

---

## 10. Troubleshooting

### "Resource not found" or "Permission denied" on Artifact Registry

- Verify the service account has `Artifact Registry Writer` role
- Verify `GCP_PROJECT_ID` and `GCP_REGION` are correct
- Check the Artifact Registry repo exists:
  ```bash
  gcloud artifacts repositories list --project=expadox-lab --location=us-central1
  ```

### Snyk fails with "Authentication failed"

- Verify `SNYK_TOKEN` is correct
- Go to https://app.snyk.io/account and regenerate token if needed

### SonarQube fails with "Not authorized"

- Verify `SONAR_TOKEN` and `SONAR_HOST_URL` are correct
- For SonarCloud: ensure the project exists and the token has analyze permission
- For self-hosted: ensure the server is accessible from GitHub Actions runners

### Gitleaks detects false positives

- If Gitleaks flags files that don't actually contain secrets, create a `.gitleaks.toml` in the repo root:
  ```toml
  [allowlist]
  paths = [
    '''\.env\.example''',
    '''terraform\.tfvars\.example'''
  ]
  ```

### Vault "permission denied"

- Verify the AppRole credentials are correct
- Check that the policy grants read access:
  ```bash
  vault policy read cloudopshub-app
  ```
- Regenerate the Secret ID if it expired:
  ```bash
  vault write -f auth/approle/role/cloudopshub-ci/secret-id
  ```

### CD pipeline says "images not found"

- CI must complete successfully first (images are pushed during CI)
- Check that the image tag (git SHA) matches between CI and CD
- Verify with:
  ```bash
  gcloud artifacts docker images list \
    us-central1-docker.pkg.dev/expadox-lab/cloudopshub-docker \
    --include-tags
  ```

### ArgoCD sync fails

- Verify ArgoCD can access the Git repository
- Check ArgoCD logs:
  ```bash
  sudo docker logs argocd-server
  ```
- Ensure the ArgoCD token hasn't expired

### Build fails with "docker: command not found"

- This shouldn't happen on `ubuntu-latest` runners. If it does, add this step before builds:
  ```yaml
  - name: Set up Docker Buildx
    uses: docker/setup-buildx-action@v3
  ```

---

## Quick Reference - All URLs

| Service | URL |
|---|---|
| GitHub Actions | https://github.com/lakunzy7/CloudOpsHub/actions |
| GitHub Secrets | https://github.com/lakunzy7/CloudOpsHub/settings/secrets/actions |
| GCP Console | https://console.cloud.google.com/?project=expadox-lab |
| GCP Service Accounts | https://console.cloud.google.com/iam-admin/serviceaccounts?project=expadox-lab |
| Artifact Registry | https://console.cloud.google.com/artifacts?project=expadox-lab |
| Snyk Dashboard | https://app.snyk.io |
| SonarCloud | https://sonarcloud.io |
| HCP Vault | https://portal.cloud.hashicorp.com |
