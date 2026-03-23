# CloudOpsHub Project

## Overview

CloudOpsHub is an automated Docker-based infrastructure platform with GitOps and continuous delivery. It provisions multi-environment platforms (dev, staging, production) on Google Cloud, containerizes microservices with Docker, and uses a GitOps pipeline for continuous deployment with monitoring.

## Components

| Component | Technology | Purpose |
|-----------|-----------|---------|
| App Frontend | Nginx | Reverse proxy, static assets, security headers |
| App Backend | Node.js/Express | REST API, server-side rendering |
| Database | MySQL 8.0 (Docker) | Application data with seed data |
| Infrastructure | Terraform | VPC, VM, service accounts, secrets, registry |
| CI/CD | GitHub Actions | Build images, update manifests |
| GitOps | Bash systemd service | Poll Git, deploy on change |
| Monitoring | Prometheus + Grafana | Metrics, dashboards, alerts |
| Alerting | Alertmanager | Slack notifications for incidents |

## How It Works

1. Developer pushes code to `main` branch
2. **CI** pipeline: lint code, build Docker images, push to Artifact Registry
3. **CD** pipeline: update image tags in `gitops/docker-compose.yml`, commit and push
4. **GitOps sync** on VM detects manifest change within 60s, pulls new images, redeploys

## Environments

Each environment (dev/staging/production) has:
- Its own GCP VM provisioned by Terraform
- Separate secrets in GCP Secret Manager
- Environment-specific resource limits in `gitops/overlays/{env}/`
- Environment-specific monitoring configs in `gitops/{env}/monitoring/`

Deploy a new environment:
```bash
cd infra
terraform workspace new staging
terraform apply -var-file=staging.tfvars
```

## GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `GCP_PROJECT_ID` | GCP project ID |
| `GCP_REGION` | GCP region (e.g., `us-central1`) |
| `GCP_WIF_PROVIDER` | Workload Identity provider (from `terraform output wif_provider`) |
| `GCP_SA_EMAIL` | Service account email (from `terraform output service_account_email`) |
