# CloudOpsHub Project Progress

> Last updated: 2026-03-22
> Reference: Project.md for full requirements

## ✅ Completed

### A. Environment Setup (Terraform)
- [x] Terraform modules: network, compute, storage, secrets, monitoring, load_balancer, wif
- [x] GCP APIs enabled (compute, storage, secretmanager, iam, iamcredentials, sts, etc.)
- [x] VPC, subnet, firewall rules, NAT, router
- [x] GCE VM instance (e2-small, COS image) with startup script
- [x] Load balancer (global HTTP LB with health check)
- [x] Artifact Registry (Docker) for container images
- [x] Static assets GCS bucket
- [x] Secret Manager (database_url, grafana_password)
- [x] Monitoring: alert policies (CPU, DB, uptime), notification channel, uptime check, logging metric
- [x] Workload Identity Federation (WIF) module for keyless GitHub Actions auth
- [x] Terraform state bucket (GCS)
- [x] **Infrastructure LIVE** — `terraform apply` completed successfully
- [x] **Load Balancer IP:** `34.54.161.113` (updated after rebuild)

### B. Dockerization
- [x] Backend Dockerfile: `theepicbook/Dockerfile`
- [x] Frontend Dockerfile: `nginx/Dockerfile`
- [x] Database Dockerfile: `theepicbook/db/Dockerfile`

### C. CI/CD Pipeline
- [x] CI workflow: `.github/workflows/ci.yml`
  - Snyk code scan, SonarQube scan, Gitleaks, ESLint, Hadolint
  - Docker build (backend, frontend, database)
  - Trivy image scanning
  - Push to Artifact Registry
- [x] CD workflow: `.github/workflows/cd.yml`
  - Checkov + TFSec Terraform scanning
  - WIF auth to GCP
  - Verify images in Artifact Registry
  - Vault secret fetching
  - GitOps manifest update + ArgoCD sync
- [x] Fixed cd.yml: added `id-token: write` permission for WIF

### D. Infrastructure as Code
- [x] Full Terraform config with modules
- [x] Multi-environment support (dev/staging/production tfvars)
- [x] Deterministic naming — GitHub secrets survive destroy/apply cycles
- [x] Migrated from expandox-project1 to expadox-lab (new GCP project)

### E. GitOps (Lightweight Sync Agent — ArgoCD alternative for Docker VMs)
- [x] Create `gitops/` directory structure (gitops/base/docker-compose.yml)
- [x] Built GitOps sync agent (`gitops/scripts/gitops-sync.sh`) — polls Git, detects changes, auto-deploys
- [x] Integrated sync agent into VM startup script (runs as Docker container)
- [x] Removed Kubernetes-native ArgoCD manifests (not applicable to Docker Compose setup)
- [x] Updated CD workflow — manifests commit triggers auto-sync within 60s

### F. Monitoring, Logging, and Alerts
- [x] Prometheus + Grafana in VM startup script
- [x] GCP Cloud Monitoring alert policies
- [x] Grafana dashboard JSON
- [ ] Verify monitoring stack runs on VM after `terraform apply`

### G. Dev Environment Fixes
- [x] Fixed volume paths in `gitops/base/docker-compose.yml` (relative to compose file, not repo root)
- [x] Bumped database memory 256M→512M, grafana 128M→256M
- [x] Fixed `GRAFANA_ADMIN_PASSWORD` env var in startup script
- [x] Replaced nohup token refresh with systemd service
- [x] Added retry logic to CI docker push steps (transient timeout fix)
- [ ] Verify all containers running on dev VM
- [ ] Verify app accessible via load balancer IP

## 🔲 Not Started / In Progress

### GitHub Secrets to Add
| Secret | Value | Added? |
|---|---|---|
| `GCP_PROJECT_ID` | `expadox-lab` | ✅ |
| `GCP_REGION` | `us-central1` | ✅ |
| `GCP_SA_EMAIL` | `cloudopshub-app-dev@expadox-lab.iam.gserviceaccount.com` | ✅ |
| `GCP_WIF_PROVIDER` | `projects/129303118923/locations/global/workloadIdentityPools/cloudopshub-github-dev/providers/github-provider` | ✅ |
| `SNYK_TOKEN` | *(added)* | ✅ |
| `SONAR_TOKEN` | *(added)* | ✅ |
| `SONAR_HOST_URL` | `https://sonarcloud.io` | ✅ |
| `VAULT_ADDR` | ~~removed — using GCP Secret Manager~~ | ✅ N/A |
| `VAULT_ROLE_ID` | ~~removed — using GCP Secret Manager~~ | ✅ N/A |
| `VAULT_SECRET_ID` | ~~removed — using GCP Secret Manager~~ | ✅ N/A |
| `ARGOCD_SERVER` | ~~removed — GitOps sync agent polls Git directly~~ | ✅ N/A |

### Remaining Tasks (in order)
1. ✅ Add 4 GCP secrets to GitHub
2. ✅ Set up Snyk account → add SNYK_TOKEN
3. ✅ Set up SonarCloud/SonarQube → add SONAR_TOKEN, SONAR_HOST_URL
4. ✅ Create `gitops/` directory structure (already existed)
5. ✅ Replaced Vault with GCP Secret Manager (already provisioned) — removed Vault from startup script, updated cd.yml, added argocd_token secret to Terraform
6. ✅ Built GitOps sync agent (lightweight ArgoCD for Docker VMs) — runs on VM, polls Git, auto-deploys
7. ✅ Restructured: Terraform = infra only, Git = single source of truth, GitOps agent deploys from Git
8. ✅ Push to main → CI builds images → CD updates manifests → GitOps agent auto-deploys
9. ⬜ Set up staging environment

## 📝 Key Values (deterministic, survive destroy/apply)
- **Project ID:** expadox-lab
- **Project Number:** 129303118923
- **Region:** us-central1
- **SA Email:** cloudopshub-app-dev@expadox-lab.iam.gserviceaccount.com
- **WIF Provider:** projects/129303118923/locations/global/workloadIdentityPools/cloudopshub-github-dev/providers/github-provider
- **Artifact Registry:** us-central1-docker.pkg.dev/expadox-lab/cloudopshub-docker
- **Load Balancer IP:** 35.244.135.223
- **VM External IP:** 136.112.128.101
- **VM Internal IP:** 10.0.1.2
- **GitHub Repo:** lakunzy7/CloudOpsHub
