# CloudOpsHub: Build an Automated Docker-Based Infrastructure Platform with GitOps and Continuous Delivery

---

## Background

CloudOpsHub is a growing SaaS company that provides real-time analytics to a diverse customer base across multiple regions. As their user base scales, they face challenges with manual infrastructure provisioning, inconsistent environment setups, and delayed deployments due to their reliance on traditional, non-automated processes.

The company is looking to modernize its infrastructure management and deployment pipelines. Specifically, they need to automate the creation of multi-environment platforms (development, staging, production), containerize their microservices using Docker, and build a GitOps pipeline for continuous deployment and reliable monitoring.

This blog documents the actual implementation — from initial single-file Terraform through modular refactor to production deployment with multiple live environments.

---

## Project Goals

Starting this project, I defined clear goals that would guide every decision:

- **Simplicity over complexity** — Clean 5-module Terraform, zero unnecessary abstraction
- **Full automation** — Push code to GitHub, everything else happens automatically
- **Observability** — Know what's happening at all times (metrics, dashboards, alerts)
- **Security** — Scan every commit for vulnerabilities, secrets, and misconfigurations
- **Multi-environment support** — Easily spin up dev, staging, and production environments

---

## Tech Stack

| Layer | Technology | Why I Chose It |
|-------|-----------|----------------|
| **Cloud Provider** | Google Cloud Platform | Free tier, strong IAM, Workload Identity Federation |
| **Infrastructure as Code** | Terraform (5 modules) | Industry standard, declarative, clean separation |
| **Containerization** | Docker + Docker Compose | Simple multi-container orchestration |
| **CI/CD** | GitHub Actions | Native GitHub integration, free for public repos |
| **GitOps** | Custom systemd service | Lightweight, polls Git every 60s, auto-redeploys |
| **Monitoring** | Prometheus + Grafana | Open source, powerful, industry standard |
| **Alerting** | Alertmanager + Slack | Real-time incident notifications |
| **Security Scanning** | Gitleaks, Trivy, tfsec, Snyk, SonarCloud | Multi-layered security coverage |
| **Application** | Node.js + Express + MySQL + Nginx | Full-stack web application (TheEpicBook) |

---

## Phase 1: Infrastructure Design — The Modular Journey

### Initial Implementation: Single File

The project started with a single `infra/main.tf` file (~200 lines) containing all 28 resources. It worked, but as the infrastructure grew, I wanted better organization without the complexity of 8+ modules.

### Refactor: 5 Clean Modules

I refactored into 5 focused modules, each ~30-40 lines:

```
infra/
  main.tf              — Root orchestrator (APIs + AR + module calls, ~50 lines)
  variables.tf         — 10 input variables
  outputs.tf           — References module outputs
  modules/
    networking/        — VPC, subnet, 2 firewalls (4 resources)
    iam/               — Service account, 4 IAM bindings, cicd_writer (6 resources)
    secrets/           — 3 secrets + 3 versions (6 resources)
    compute/           — Static IP, VM instance, startup script (2 resources)
    wif/               — Workload Identity Pool, provider, SA binding (3 resources)
  env/
    dev.tfvars.example
    staging.tfvars
    production.tfvars
```

**Zero-downtime migration**: Used Terraform `moved` blocks to relocate all 21 resources from root to modules without destroying/recreating anything. Staging remained live throughout the refactor.

**Shared Artifact Registry**: The Docker registry (`cloudopshub-docker`) has no environment suffix and is shared across all environments. Introduced `create_artifact_registry` variable — first environment creates it, others skip creation to avoid conflicts.

**Professional layout**: Environment-specific configurations live in `infra/env/`:

```
infra/env/
  dev.tfvars.example       (create_artifact_registry = true)
  staging.tfvars           (gitignored, contains real passwords)
  production.tfvars        (gitignored, contains real passwords)
```

Users copy `.tfvars.example` to create their local config files which are gitignored for security.

### What Terraform Creates (28 Resources)

A single `terraform apply -var-file=env/<env>.tfvars` provisions everything:

- **Networking** (`modules/networking`): VPC, subnet, firewall rules (ports 80, 3000, 9090, 9093, 22)
- **Compute** (`modules/compute`): VM instance with Container-Optimized OS, static IP
- **IAM** (`modules/iam`): Service account, role bindings (Artifact Registry reader, Secret Manager accessor, Log Writer, Metric Writer)
- **Secrets** (`modules/secrets`): 3 secrets + versions (DB password, Grafana password, Slack webhook)
- **WIF** (`modules/wif`): Workload Identity Pool, OIDC provider, SA binding
- **APIs** (root): Auto-enables required GCP services
- **Artifact Registry** (root): Shared Docker registry (created once)

---

## Live Environments (Deployed 2026-03-27)

### Staging Environment

- **VM**: `cloudopshub-app-staging` (us-central1-a)
- **Static IP**: 136.116.110.195
- **App**: http://136.116.110.195
- **Grafana**: http://136.116.110.195:3000 (admin/Fpq1tb4au5g//wjm4Vow)
- **Prometheus**: http://136.116.110.195:9090
- **Alertmanager**: http://136.116.110.195:9093
- **Service Account**: `cloudopshub-app-staging@expandox-cloudehub.iam.gserviceaccount.com`
- **WIF Provider**: `projects/828485768677/locations/global/workloadIdentityPools/cloudopshub-github-staging/providers/github-provider`
- **Terraform workspace**: `staging`

### Production Environment

- **VM**: `cloudopshub-app-production` (us-central1-a)
- **Static IP**: 34.135.154.250
- **App**: http://34.135.154.250
- **Grafana**: http://34.135.154.250:3000 (admin/aFvcADkgiOifhkyjIo6C)
- **Prometheus**: http://34.135.154.250:9090
- **Alertmanager**: http://34.135.154.250:9093
- **Service Account**: `cloudopshub-app-production@expandox-cloudehub.iam.gserviceaccount.com`
- **WIF Provider**: `projects/828485768677/locations/global/workloadIdentityPools/cloudopshub-github-production/providers/github-provider`
- **Terraform workspace**: `production`

Both environments are isolated via Terraform workspaces, each with its own VPC, VM, secrets, and monitoring stack. The modular design means adding environments (dev, qa, etc.) is straightforward.

---

## Workload Identity Federation (No Service Account Keys)

Authentication for CI/CD uses **Workload Identity Federation (WIF)** instead of service account keys — a major security win.

Traditional approach: Generate a JSON key file, store it as a GitHub secret. Keys don't expire, need rotation, and are high-value targets if leaked.

WIF approach: GitHub Actions gets an OIDC token from the GitHub OIDC provider. This token is exchanged for a GCP access token via the Workload Identity Pool. No long-lived keys, no rotation headaches.

```
GitHub Actions (OIDC token from actions.githubusercontent.com)
    → GCP Workload Identity Pool (cloudopshub-github-<env>)
    → Maps to Service Account (cloudopshub-app-<env>)
    → Temporary credentials (1 hour)
```

The CI/CD pipeline uses these credentials to push Docker images to Artifact Registry.

---

## Phase 2: CI/CD Pipeline

### Continuous Integration (CI)

Every push to `main` triggers the CI pipeline with 3 parallel jobs:

**Job 1: Lint**
```yaml
- Uses Node.js 20
- Runs: npm ci, npm run lint
- Required for build-and-push to proceed
```

**Job 2: Security Scan** (runs even if lint fails)
```yaml
- Gitleaks: Scans git history for hardcoded secrets
- Trivy (FS): Scans source for vulnerabilities
- tfsec (via Trivy): Scans Terraform configs
- Snyk Code: SAST on application code
- SonarCloud: Code quality + security hotspots
- All use continue-on-error: true (don't block deployments)
```

**Job 3: Build & Push**
```yaml
- Builds 3 Docker images (backend, frontend, database)
- Tags: <commit-sha> and latest
- Pushes to us-central1-docker.pkg.dev/expandox-cloudehub/cloudopshub-docker
- Requires: Lint passed, security scan completed
```

### Continuous Delivery (CD)

The CD workflow triggers after CI succeeds:

1. Updates `gitops/docker-compose.yml` with new image SHA tags
2. Commits with `[skip ci]` to avoid infinite loop
3. Pushes to `main`

That's it — no complex promotion logic. The GitOps sync picks up the commit and redeploys automatically.

---

## Phase 3: GitOps Deployment

### The GitOps Sync Agent

Instead of ArgoCD or Flux (overkill for one VM), I built an 80-line bash systemd service:

**What it does every 60 seconds:**
1. Refresh Artifact Registry auth token (2 hours expiry)
2. `git fetch` and check for new commits
3. If changes detected:
   - `git pull` the latest code
   - `sed` inject Slack webhook into `alertmanager.yml` (pulled from Secret Manager)
   - `docker compose pull` (fetch new images)
   - `docker compose up -d` (redeploy changed containers)
   - Force-recreate alertmanager to pick up webhook

The service logs to journalctl:
```bash
journalctl -u gitops-sync -f
# Output: "Change detected: abc123 -> def456" "Sync successful"
```

### Docker Compose Stack (7 Services)

```yaml
services:
  frontend:
    image: ...frontend:latest
    ports: ["80:80"]
    depends_on: [backend]

  backend:
    image: ...backend:latest
    environment:
      NODE_ENV: production
      DATABASE_URL: mysql://appuser:${DB_PASSWORD}@database:3306/epicbook
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]

  database:
    image: mysql:8.0
    volumes: ["db_data:/var/lib/mysql"]
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}
      MYSQL_DATABASE: epicbook
      MYSQL_USER: appuser

  prometheus:
    image: prom/prometheus:latest
    volumes: ["./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml"]
    ports: ["9090:9090"]

  grafana:
    image: grafana/grafana:latest
    volumes: ["./monitoring/dashboards:/etc/grafana/provisioning/dashboards"]
    ports: ["3000:3000"]

  alertmanager:
    image: prom/alertmanager:latest
    volumes: ["./monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml"]
    ports: ["9093:9093"]

  node-exporter:
    image: prom/node-exporter:latest
    volumes: ["/:/host:ro,rslave"]
    ports: ["9100:9100"]
```

All configs (Prometheus, Grafana dashboards, Alertmanager rules) live in `gitops/<env>/monitoring/` and are environment-specific.

---

## Phase 4: Monitoring & Alerting

### Prometheus

Prometheus scrapes targets every 15s:

| Target | Port | Metrics |
|--------|------|---------|
| Node Exporter | 9100 | CPU, memory, disk, network, processes |
| Backend app | 8080 | Request rate, latency, errors (Express) |
| Prometheus | 9090 | Self-monitoring |

**Alert rules** (in `gitops/*/monitoring/alert.rules.yml`):
- `ServiceDown` — Target or job down for > 1 minute (severity: critical)
- `HighCPU` — CPU usage > 80% for 5 minutes (warning)
- `HighMemory` — Memory usage > 85% for 5 minutes (warning)
- `HighDisk` — Disk usage > 80% (warning)

### Grafana Dashboards (3 Pre-provisioned)

**Infrastructure Overview**
- CPU/Memory/Disk gauges
- Network I/O time series
- System load, uptime

**Application & Monitoring Health**
- Service status (up/down indicators)
- Active alerts count
- Prometheus TSDB size, scrape duration

**Epicbook Dashboard** (app-specific)
- Request rate, error rate
- Response time percentiles
- Database connection pool metrics

All dashboards auto-import from JSON in `gitops/<env>/monitoring/dashboards/`.

### Alertmanager → Slack

Alerts route to `#devops` channel:

```yaml
route:
  receiver: 'slack-notifications'
  group_wait: 30s
  group_interval: 5m

receivers:
- name: 'slack-notifications'
  slack_configs:
  - api_url: 'https://hooks.slack.com/services/...'  # injected by GitOps sync
    channel: '#devops'
    send_resolved: true
```

The Slack webhook URL lives in Secret Manager (not in Git). The `gitops-sync` script replaces `SLACK_WEBHOOK_PLACEHOLDER` with the real URL at deploy time.

---

## Phase 5: Security Scanning

Security is integrated into every CI run, not bolted on at the end.

| Scanner | Target | What it catches | Secret required? |
|---------|--------|----------------|------------------|
| **Gitleaks** | Git history | Hardcoded passwords, API keys, tokens | No (works without) |
| **Trivy FS** | Source files | Dependency vulnerabilities (package-lock.json) | No |
| **tfsec (Trivy)** | Terraform configs | Overly permissive IAM, missing encryption, public access | No |
| **Snyk Code** | App code (Node.js) | SAST: SQL injection, XSS, insecure crypto | Yes (SNYK_TOKEN) |
| **SonarCloud** | Entire repo | Code quality, bugs, hotspots, test coverage | Yes (SONAR_TOKEN) |

All scanners use `continue-on-error: true`. The pipeline continues regardless of scan results — only `lint` must pass for images to build. This ensures security visibility without blocking deployments if tokens aren't configured.

---

## Challenges & Lessons Learned

### 1. Terraform Template Escaping

The VM startup script uses Terraform's `templatefile()`. Terraform interprets `${VAR}` as interpolation, conflicting with bash `${VAR}` syntax. Solution: use `$${VAR}` to emit a literal `${VAR}` in the rendered script. Cost me hours to figure out.

### 2. Docker Config Reloads

`docker compose restart` doesn't reload bind-mounted config files — containers restart with cached filesystem state. Must remove and recreate:

```bash
docker compose stop alertmanager
docker compose rm -f alertmanager
docker compose up -d alertmanager
```

The GitOps sync handles this automatically when it detects config changes.

### 3. Systemd HOME Environment

Docker looks for auth at `$HOME/.docker/config.json`. Startup script ran `docker login` with `HOME=/var/lib`, storing config at `/var/lib/.docker/config.json`. But systemd service ran as root with `HOME=/root`, so Docker couldn't find auth. Fix: `Environment=HOME=/var/lib` in the systemd unit.

### 4. Sequelize Environment Config

Node.js app uses Sequelize ORM with config keyed by `NODE_ENV`. Deploying with `NODE_ENV=staging` crashed because `config/config.json` had no `staging` key — only `development` and `production`. Error: `Cannot read properties of undefined (reading 'use_env_variable')`. Fixed by adding entries for all environments (dev, staging, production).

### 5. Secret Injection Without Committing Secrets

Alertmanager config needs a Slack webhook URL but can't store it in Git. Solution: store placeholder `SLACK_WEBHOOK_PLACEHOLDER` in git-tracked config, and have GitOps sync `sed`-replace it with the real URL from Secret Manager at deploy time. Keeps secrets out of Git while maintaining config-as-code.

---

## Multi-Environment Strategy

Terraform workspaces + `infra/env/` tfvars provide clean isolation:

### Deploy First Environment (creates shared Docker registry)

```bash
cd infra
terraform init
terraform workspace new dev
terraform apply -var-file=env/dev.tfvars   # create_artifact_registry = true
```

### Deploy Additional Environments (reuse existing registry)

```bash
terraform workspace new staging
terraform apply -var-file=env/staging.tfvars   # create_artifact_registry = false

terraform workspace new production
terraform apply -var-file=env/production.tfvars  # create_artifact_registry = false
```

Each environment gets:
- Isolated VPC, subnet, firewall
- Separate VM with unique static IP
- Independent secrets in Secret Manager
- Dedicated WIF pool for CI/CD
- Environment-specific monitoring configs in `gitops/<env>/monitoring/`

Workspace command cheat sheet:
```bash
terraform workspace list              # see all workspaces
terraform workspace select staging    # switch to staging
terraform output                      # show outputs for current workspace
terraform destroy -var-file=env/dev.tfvars  # destroy an environment
```

---

## Project Structure

```
CloudOpsHub/
  infra/
    main.tf              — Root orchestrator (calls 5 modules, ~50 lines)
    variables.tf         — 10 input variables
    outputs.tf           — References module outputs
    modules/
      networking/        — VPC, subnet, 2 firewalls (4 resources)
      iam/               — Service account, IAM bindings (6 resources)
      secrets/           — 3 secrets + 3 versions (6 resources)
      compute/           — Static IP, VM instance (2 resources)
      wif/               — WIF pool, provider, SA binding (3 resources)
    env/
      dev.tfvars.example         — Copy to dev.tfvars, fill passwords
      staging.tfvars             # Local only (gitignored, contains secrets)
      production.tfvars          # Local only (gitignored, contains secrets)

  scripts/
    startup.sh           — VM bootstrap (installs Docker, Docker Compose, writes .env)
    gitops-sync.sh       — GitOps agent (systemd, polls every 60s)

  gitops/
    docker-compose.yml   — 7 services (frontend, backend, database, prometheus, grafana, alertmanager, node-exporter)
    dev/monitoring/      — Dev Prometheus rules, Alertmanager config, Grafana dashboards
    staging/monitoring/  — Staging monitoring configs
    production/monitoring/ — Production monitoring configs
    overlays/            — docker-compose.override.yml per env (resource limits)

  .github/workflows/
    ci.yml   — Lint + 5 security scanners + build/push to Artifact Registry
    cd.yml   — Update docker-compose.yml image tags → commit
    (Secrets: GCP_PROJECT_ID, GCP_REGION, GCP_WIF_PROVIDER, GCP_SA_EMAIL, SNYK_TOKEN, SONAR_TOKEN, SONAR_HOST_URL)

  theepicbook/           — Node.js application (Express + Sequelize + MySQL)
  nginx/                 — Nginx reverse proxy config (listens on :80 → backend:8080)
  docs/                  — Documentation (DEPLOYMENT_GUIDE.md, blog-post.md)
  sonar-project.properties — SonarCloud configuration
```

---

## Results

| Metric | Value |
|--------|-------|
| **Infrastructure code** | 5 modules + root (~200 lines total) |
| **Terraform modules** | 5 (networking, iam, secrets, compute, wif) |
| **CI pipeline** | ~120 lines (3 jobs, 5 security scanners) |
| **CD pipeline** | ~35 lines |
| **GitOps sync** | ~80 lines (bash systemd service) |
| **Resources per environment** | 28 GCP resources |
| **Containers per environment** | 7 |
| **Deploy time (Terraform)** | ~3 minutes |
| **Deploy time (code change to live)** | ~4-5 minutes (CI + CD + sync) |
| **Security scanners** | 5 (Gitleaks, Trivy, tfsec, Snyk, SonarCloud) |
| **Monitoring dashboards** | 3 (Infrastructure, Application, Epicbook) |
| **Alert channels** | Slack (#devops) |
| **Environments deployed** | 3 (dev ready, staging live, production live) |
| **State migration** | Zero downtime via Terraform `moved` blocks |
| **GitHub stars** | — (PRs welcome!) |

---

## What's Next

- **SSL/TLS** — Add HTTPS with Let's Encrypt certificates (certbot in Docker or GCP load balancer)
- **Database backups** — Automated mysqldump or persistent disk snapshots
- **Load balancer** — GCP HTTP(S) Load Balancer for production HA and SSL termination
- **Dev environment deployment** — Run `terraform apply -var-file=env/dev.tfvars` to spin up dev
- **Custom domain** — Point a domain to the static IP with DNS A record
- **Log aggregation** — Add Loki or ELK stack for centralized container logs
- **Cost monitoring** — Set up GCP billing budget alerts

---

## Conclusion

Building CloudOpsHub taught me that good DevOps isn't about using every tool available — it's about picking the right tools, organizing them cleanly, and keeping complexity low.

The modular Terraform approach gives us separation without over-engineering. Each module is focused and testable. The root `main.tf` reads like a recipe: "create APIs, create AR, call networking module, call IAM module..." Easy to understand.

The GitOps pattern with a tiny 80-line systemd service proves you don't need heavyweight tools for simple deployments. Just poll Git, pull changes, and run `docker compose up -d`. Works beautifully.

Security is visible at every stage: 5 scanners on every commit, WIF instead of keys, secrets in Secret Manager, no passwords in Git. Yet none of it blocks the developer workflow — scans run, results are logged, but deployments proceed.

The entire platform — infrastructure, monitoring, deployment automation — is defined in code, version controlled, and reproducible. Push to main, and within minutes the changes are live in staging with full observability.

That's the goal. That's CloudOpsHub.

---

## References

- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Google Cloud Container-Optimized OS](https://cloud.google.com/container-optimized-os/docs)
- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [GitHub Actions](https://docs.github.com/en/actions)
- [Docker Compose](https://docs.docker.com/compose/)
- [Prometheus](https://prometheus.io/docs/)
- [Grafana](https://grafana.com/docs/)
- [Alertmanager](https://prometheus.io/docs/alerting/latest/configuration/)
- [Gitleaks](https://github.com/gitleaks/gitleaks)
- [Trivy](https://aquasecurity.github.io/trivy/)
- [tfsec](https://aquasecurity.github.io/tfsec/)
- [Snyk](https://docs.snyk.io/)
- [SonarCloud](https://docs.sonarcloud.io/)
- [Google Secret Manager](https://cloud.google.com/secret-manager/docs)
- [Google Artifact Registry](https://cloud.google.com/artifact-registry/docs)
- [Sequelize ORM](https://sequelize.org/docs/v6/)
- [Express.js](https://expressjs.com/)
