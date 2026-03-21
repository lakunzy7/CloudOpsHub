# Terraform Deployment Guide

## Prerequisites

1. **GCP Project**: `expandox-cloudehub` (ID: `828485768677`)
2. **Billing**: Enabled with $300 credits
3. **gcloud CLI**: Installed and authenticated
4. **Terraform**: Version >= 1.5.0

---

## Step 1: Enable Required GCP APIs

```bash
gcloud services enable \
  iam.googleapis.com \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  storage.googleapis.com \
  secretmanager.googleapis.com \
  cloudresourcemanager.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  --project=expandox-cloudehub
```

---

## Step 2: Create Terraform State Backend Bucket

Run the provided script:

```bash
chmod +x scripts/setup-terraform-backend.sh
./scripts/setup-terraform-backend.sh expandox-cloudehub us-central1
```

This creates: `gs://expandox-cloudehub-cloudopshub-tf-state` with versioning enabled.

---

## Step 3: Initialize Terraform

```bash
cd terraform
terraform init
```

This will download providers and initialize the backend.

---

## Step 4: Prepare GitHub Secrets

Add these secrets to your GitHub repository (`Settings → Secrets and variables → Actions`):

| Secret Name | Value | Source |
|-------------|-------|--------|
| `GCP_PROJECT_ID` | `expandox-cloudehub` | Your project |
| `GCP_PROJECT_NUMBER` | `828485768677` | gcloud projects describe |
| `GCP_REGION` | `us-central1` | Terraform config |
| `GCP_WIF_PROVIDER` | Will be output after terraform apply | See below |
| `GCP_SA_EMAIL` | Will be output after terraform apply | See below |
| `GRAFANA_ADMIN_PASSWORD` | Generate a strong password | e.g., `openssl rand -base64 16` |
| `SLACK_WEBHOOK_URL` | Your Slack incoming webhook | Slack App setup |
| `DATABASE_URL` | Will be in Secret Manager after apply | Auto-created |

**Note**: `GCP_WIF_PROVIDER` and `GCP_SA_EMAIL` will be available in Terraform outputs after applying the dev environment.

---

## Step 5: Deploy Dev Environment

```bash
# From terraform directory
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

**Outputs to capture**:
- `dev_vm_external_ip` - SSH into this VM
- `wif_provider` - Value for `GCP_WIF_PROVIDER` secret
- `service_account_email` - Value for `GCP_SA_EMAIL` secret
- `artifact_registry_url` - Docker image repository
- `database_url_secret_id` - Secret name for DB connection

After successful apply, update GitHub secrets with:
- `GCP_WIF_PROVIDER` = `projects/828485768677/locations/global/workloadIdentityPools/Expandox-Cloudehub-github-dev/providers/github-provider`
- `GCP_SA_EMAIL` = `Expandox-Cloudehub-app-dev@expandox-cloudehub.iam.gserviceaccount.com`

---

## Step 6: Wait for VM to Initialize

SSH to the VM and verify GitOps agent is running:

```bash
gcloud compute ssh dev-app-vm --zone=us-central1-a --project=expandox-cloudehub
# Inside VM:
cd /opt/cloudopshub
git status  # Should show clean working tree
docker-compose --env-file .env -f gitops/base/docker-compose.yml ps
```

---

## Step 7: Test CI/CD Pipeline

1. Push a change to `main` branch
2. Watch GitHub Actions run:
   - CI: builds and scans Docker images
   - CD: deploys to dev environment
3. Verify deployment:
   ```bash
   curl http://<dev_vm_external_ip>:8080  # TheEpicBook app
   curl http://<dev_vm_external_ip>:3000  # Grafana
   curl http://<dev_vm_external_ip>:9090  # Prometheus
   curl http://<dev_vm_external_ip>:9093  # Alertmanager
   ```

---

## Deploy Staging & Production

After dev is stable, deploy staging:

```bash
terraform plan -var-file=environments/staging.tfvars
terraform apply -var-file=environments/staging.tfvars
```

Then production:

```bash
terraform plan -var-file=environments/production.tfvars
terraform apply -var-file=environments/production.tfvars
```

---

## Important Notes

- **Grafana Password**: You've already set this in GitHub secrets (`GRAFANA_ADMIN_PASSWORD`). Terraform variable is optional.
- **Secrets**: `db_password` is stored in GCP Secret Manager automatically by the `secrets` module.
- **Service Accounts**: Created automatically by the `compute` module.
- **WIF**: Workload Identity Federation pool is created by `wif` module; GitHub Actions uses it for auth.
- **Resource Naming**: All resources include `project_name` and `environment` to avoid conflicts.

---

## Destroying Environments

To tear down an environment:

```bash
terraform destroy -var-file=environments/dev.tfvars
```

**Warning**: This will delete all resources including VMs, databases, and buckets. Ensure you have backups.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `Bucket already exists` error | Use a unique bucket name or delete the existing bucket: `gsutil rm -r gs://expandox-cloudehub-cloudopshub-tf-state` |
| `Permission denied` | Ensure you're authenticated with `gcloud auth application-default login` |
| `Service account not found` | Apply Terraform twice - sometimes IAM propagation is delayed |
| `GitHub Actions auth fails` | Verify WIF provider and service account email in GitHub secrets match Terraform outputs |
