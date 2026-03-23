# CLAUDE.md

## Project Overview

CloudOpsHub is a Docker-based infrastructure platform with GitOps continuous delivery. The app is **TheEpicBook**, an online bookstore (Node.js/Express) in `theepicbook/`.

## Architecture

```
GitHub push → CI (build images) → CD (update manifest) → GitOps sync (deploy on VM)
```

**Services** (Docker Compose):
- Frontend: nginx reverse proxy + static assets (`nginx/`)
- Backend: Node.js/Express API + Handlebars SSR (`theepicbook/`)
- Database: MySQL 8.0 with seed data (`theepicbook/db/`)
- Monitoring: Prometheus, Grafana, Alertmanager, Node Exporter

**Infrastructure** (GCP via Terraform in `infra/`):
- Single `main.tf` — no modules. VPC, VM, Service Account, Firewall, Secrets, Artifact Registry, WIF.
- VM runs Container-Optimized OS with Docker Compose.

**GitOps**: systemd service on VM polls Git every 60s. On change → `docker-compose pull && up -d`.

## Common Commands

```bash
# Local dev
docker compose up --build          # Start full stack locally
cd theepicbook && npm run lint     # ESLint check

# Infrastructure
cd infra && terraform init && terraform apply -var-file=dev.tfvars

# Check VM
gcloud compute ssh <vm-name> --zone us-central1-a
journalctl -u gitops-sync -f      # GitOps sync logs on VM
docker ps                          # Container status on VM
```

## Key Paths

- `infra/main.tf` — All Terraform (no modules)
- `gitops/docker-compose.yml` — Production deployment manifest
- `gitops/overlays/{env}/` — Per-environment resource overrides
- `gitops/{env}/monitoring/` — Prometheus, Grafana, Alertmanager configs per env
- `scripts/startup.sh` — VM bootstrap (Terraform template)
- `scripts/gitops-sync.sh` — GitOps sync loop
- `.github/workflows/ci.yml` — Build & push images
- `.github/workflows/cd.yml` — Update manifest tags

## Code Style

ESLint: 2-space indent, double quotes, semicolons required, camelCase, `===`, curly braces. See `theepicbook/.eslintrc.json`.

## Environments

Dev, Staging, Production — each gets its own VM, secrets, and overlay config. Deploy with different `.tfvars` files.
