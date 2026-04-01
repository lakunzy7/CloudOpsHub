# CloudOpsHub

CloudOpsHub is an automated Docker-based infrastructure platform with GitOps and continuous delivery. It provisions multi-environment platforms (dev, staging, production) on Google Cloud, containerizes microservices with Docker, and uses a GitOps pipeline for continuous deployment with monitoring.

## How It Works

1. Developer pushes code to `main` branch
2. **CI** pipeline (GitHub Actions): lints code, runs 5 security scanners, builds Docker images, pushes to Artifact Registry
3. **CD** pipeline: updates image tags in `gitops/docker-compose.yml`, commits and pushes the updated manifest
4. **GitOps sync** (systemd service on VM): detects manifest change within 60s, pulls new images, redeploys containers

## Project Structure

```
CloudOpsHub/
  .github/workflows/ci.yml    — CI: lint, security scan, build & push
  .github/workflows/cd.yml    — CD: update GitOps manifest
  infra/                       — Terraform modules (5 modules)
  scripts/                     — VM bootstrap & GitOps sync
  gitops/                      — Docker Compose + monitoring configs
  theepicbook/                 — Node.js/MySQL application
  nginx/                       — Nginx reverse proxy + static files
  docs/                        — Documentation
```

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture Blog](docs/blog-post.md) | Deep-dive walkthrough of every code file: CI/CD pipeline, Dockerfiles, Terraform modules, GitOps sync, monitoring, and how everything connects |
| [Deployment Guide](docs/DEPLOYMENT_GUIDE.md) | Step-by-step instructions for setting up GCP, configuring GitHub secrets, deploying environments, and troubleshooting |
| [Project Overview](docs/project.md) | High-level overview: components, workflow, environments, required secrets |

## Quick Start

```bash
# 1. Clone repo
git clone https://github.com/your-username/CloudOpsHub.git
cd CloudOpsHub

# 2. Configure Terraform
cp infra/env/dev.tfvars.example infra/env/dev.tfvars
# Edit infra/env/dev.tfvars with your project details

# 3. Deploy (requires gcloud authenticated)
cd infra
terraform init
terraform workspace new dev
terraform apply -var-file=env/dev.tfvars

# 4. Configure GitHub secrets (GCP_WIF_PROVIDER, GCP_SA_EMAIL, etc.)
# 5. Push to main — CI/CD + GitOps handles the rest
```

## Environments

| Environment | Status | Description |
|-------------|--------|-------------|
| Dev | Template | Development/testing environment |
| Staging | Live | Pre-production validation |
| Production | Live | Full resource limits, production config |

Each environment gets isolated: separate VM, VPC, secrets, and WIF pool.

## Tech Stack

| Layer | Technology | Description |
|-------|-----------|-------------|
| Infrastructure as Code | Terraform (modular) | 5 focused modules: networking, iam, secrets, compute, wif |
| Containerization | Docker + Docker Compose | 3 images: backend, frontend, database |
| CI/CD | GitHub Actions | Lint → 5 scanners → build → push to Artifact Registry |
| GitOps | Bash systemd service | Polls Git every 60s, deploys on manifest change |
| Monitoring | Prometheus + Grafana | Metrics, dashboards, alerts |
| Alerting | Alertmanager + Slack | Incident notification and routing |
| Application | Node.js/Express + MySQL | Full-stack reference implementation (The EpicBook) |
