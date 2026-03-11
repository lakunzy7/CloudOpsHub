# CloudOpsHub Architecture Diagram

> This document describes the full architecture of the CloudOpsHub platform — from code commit to production deployment.

Diagram images are available in `docs/diagrams/` in both **SVG** and **PNG** formats.

---

## High-Level Overview

![High-Level Overview](diagrams/01-high-level-overview.png)

<details>
<summary>Mermaid source (click to expand)</summary>

```mermaid
flowchart TB
    subgraph Developer["👤 Developer"]
        Code[Push Code to GitHub]
    end

    subgraph CICD["🔄 CI/CD Pipeline — GitHub Actions"]
        direction TB
        CI[CI Pipeline]
        CD[CD Pipeline]
        CI -->|on success| CD
    end

    subgraph Security["🛡️ Security Gates"]
        Snyk[Snyk - Code Scan]
        Sonar[SonarQube - Quality]
        Gitleaks[Gitleaks - Secret Scan]
        Trivy[Trivy - Image Scan]
        Checkov[Checkov - IaC Scan]
        TFSec[TFSec - IaC Scan]
    end

    subgraph Registry["📦 AWS ECR"]
        BackendImg[theepicbook-backend]
        FrontendImg[theepicbook-frontend]
    end

    subgraph GitOps["📂 GitOps Repository"]
        Manifests[Deployment Manifests]
    end

    subgraph ArgoCD["🔄 ArgoCD"]
        Sync[Sync & Deploy]
    end

    subgraph GCP["☁️ Google Cloud Platform"]
        LB[Cloud Load Balancer + Cloud Armor WAF]
        VM[Compute Engine VM - Docker Host]
        CloudSQL[Cloud SQL - MySQL 8.0]
        SecretMgr[Secret Manager]
        Monitoring[Cloud Monitoring]
    end

    subgraph Vault["🔐 HashiCorp Vault"]
        Secrets[Database URL + Tokens]
    end

    Code --> CI
    CI --> Security
    CI -->|Build & Push| Registry
    CD -->|Update manifests| GitOps
    CD -->|Trigger sync| ArgoCD
    ArgoCD -->|Deploy to| VM
    VM -->|Pull images| Registry
    VM -->|Read secrets| SecretMgr
    VM -->|Connect| CloudSQL
    LB -->|Route traffic| VM
    CD -->|Fetch secrets| Vault
```

</details>

---

## Application Architecture (3-Service Microservices)

![Application Architecture](diagrams/02-application-architecture.png)

<details>
<summary>Mermaid source (click to expand)</summary>

```mermaid
flowchart LR
    User["🌐 User Browser"]

    subgraph GCP["Google Cloud Platform"]
        subgraph LB["Cloud Load Balancer"]
            Armor["Cloud Armor WAF"]
            SSL["Managed SSL"]
        end

        subgraph VM["Compute Engine VM"]
            subgraph Docker["Docker Containers"]
                Frontend["Frontend\n(Nginx)\nPort 80"]
                Backend["Backend\n(Node.js/Express)\nPort 8080"]
            end
        end

        CloudSQL["Cloud SQL\nMySQL 8.0\nPrivate IP"]
    end

    User -->|HTTPS| SSL
    SSL --> Armor
    Armor --> Frontend
    Frontend -->|/api/* requests\nReverse Proxy| Backend
    Frontend -->|/assets/*\nStatic Files| Frontend
    Backend -->|Sequelize ORM| CloudSQL
```

</details>

### Service Details

| Service | Technology | Port | Role |
|---------|-----------|------|------|
| **Frontend** | Nginx 1.25 | 80 | Serves static assets (CSS, JS, images), reverse proxies API and page requests to backend |
| **Backend** | Node.js 16 + Express | 8080 | Handlebars SSR, REST API for cart operations, Sequelize ORM for database |
| **Database** | Cloud SQL (MySQL 8.0) | 3306 | Stores books, authors, cart, and checkout data. Private IP only. |

---

## CI/CD Pipeline Flow

![CI/CD Pipeline](diagrams/03-cicd-pipeline.png)

<details>
<summary>Mermaid source (click to expand)</summary>

```mermaid
flowchart TD
    Push["Developer pushes to main"]

    subgraph CI["CI Pipeline (ci.yml)"]
        direction TB
        Lint["Lint\n(ESLint)"]
        SnykScan["Snyk\nCode Scan"]
        SonarScan["SonarQube\nQuality Gate"]
        GitleaksScan["Gitleaks\nSecret Detection"]
        DockerLint["Hadolint\nDockerfile Lint"]

        Lint & SnykScan & SonarScan & GitleaksScan & DockerLint -->|All pass| Build

        Build["Build Docker Images\n• theepicbook-backend\n• theepicbook-frontend"]
        Build --> TrivyScan["Trivy\nVulnerability Scan"]
        TrivyScan --> ECRPush["Push to AWS ECR\nTagged with commit SHA"]
    end

    subgraph CD["CD Pipeline (cd.yml)"]
        direction TB
        CheckovScan["Checkov\nTerraform Scan"]
        TFSecScan["TFSec\nTerraform Scan"]
        CheckovScan & TFSecScan --> VerifyECR["Verify Images\nExist in ECR"]
        VerifyECR --> FetchVault["Fetch Secrets\nfrom Vault"]
        FetchVault --> UpdateManifests["Update GitOps\nManifests"]
        UpdateManifests --> CommitPush["Commit & Push\nManifest Changes"]
        CommitPush --> ArgoSync["Trigger\nArgoCD Sync"]
    end

    Push --> CI
    CI -->|workflow_run\non success| CD
```

</details>

### DevSecOps Security Gates

| Stage | Tool | What It Checks |
|-------|------|---------------|
| **Code** | Snyk | Known vulnerabilities in dependencies |
| **Code** | SonarQube | Code quality, bugs, code smells, security hotspots |
| **Commit** | Gitleaks | Hardcoded secrets, API keys, passwords in code |
| **Build** | Hadolint | Dockerfile best practices |
| **Build** | Trivy | Container image vulnerabilities (OS + app packages) |
| **Deploy** | Checkov | Terraform misconfigurations and security issues |
| **Deploy** | TFSec | Terraform security best practices |
| **Operate** | HashiCorp Vault | Runtime secret injection (no secrets in code/env files) |

---

## GCP Infrastructure (Terraform-managed)

![GCP Infrastructure](diagrams/04-gcp-infrastructure.png)

<details>
<summary>Mermaid source (click to expand)</summary>

```mermaid
flowchart TB
    subgraph GCP["GCP Project: expandox-project1"]
        subgraph VPC["VPC Network"]
            subgraph PublicSubnet["Public Subnet"]
                LB["Cloud Load Balancer\n+ Managed SSL\n+ Cloud Armor WAF"]
            end

            subgraph PrivateSubnet["Private Subnet"]
                NAT["Cloud NAT"]
                VM["Compute Engine\n(Container-Optimized OS)\nNo External IP"]
                CloudSQL["Cloud SQL MySQL 8.0\nPrivate IP Only\nAutomated Backups"]
            end
        end

        SecretMgr["Secret Manager\n• DATABASE_URL\n• ECR Credentials"]
        CloudMon["Cloud Monitoring\n• Uptime Checks\n• CPU/Memory Alerts\n• Error Log Metrics"]
        DNS["Cloud DNS\n(Optional)"]
    end

    subgraph AWS["AWS Account"]
        ECR["ECR\n• theepicbook-backend\n• theepicbook-frontend"]
    end

    Internet["🌐 Internet"] --> DNS
    DNS --> LB
    LB --> VM
    VM --> CloudSQL
    VM --> SecretMgr
    VM -->|Pull images| ECR
    VM -->|Outbound via| NAT
```

</details>

### Terraform Module Structure

```
terraform/
├── main.tf                    # Root — wires all modules together
├── variables.tf               # Input variables
├── outputs.tf                 # Output values
├── envs/
│   ├── dev.tfvars             # Dev environment values
│   ├── staging.tfvars         # Staging environment values
│   └── production.tfvars      # Production environment values
└── modules/
    ├── network/               # VPC, subnets, NAT, firewall rules
    ├── compute/               # GCE instance, service account, IAM
    ├── database/              # Cloud SQL, private IP, backups
    ├── load_balancer/         # Global LB, Cloud Armor, SSL, DNS
    ├── storage/               # GCS buckets, Artifact Registry
    ├── secrets/               # Secret Manager entries
    ├── monitoring/            # Uptime checks, alert policies
    └── registry/              # AWS ECR repositories
```

---

## GitOps & Environment Management

![GitOps & Environments](diagrams/05-gitops-environments.png)

<details>
<summary>Mermaid source (click to expand)</summary>

```mermaid
flowchart LR
    subgraph Repo["GitHub Repository"]
        subgraph GitOpsDir["gitops/"]
            Base["base/\ndocker-compose.yml"]
            Dev["overlays/dev/\ndocker-compose.override.yml"]
            Staging["overlays/staging/\ndocker-compose.override.yml"]
            Prod["overlays/production/\ndocker-compose.override.yml"]
        end
        ArgoApp["argocd/\napplication.yaml\nproject.yaml"]
    end

    subgraph ArgoCD["ArgoCD"]
        Watcher["Watches gitops/ for changes"]
    end

    subgraph Envs["Environments"]
        DevVM["Dev VM"]
        StagingVM["Staging VM"]
        ProdVM["Production VM"]
    end

    Base --> Dev & Staging & Prod
    ArgoApp --> Watcher
    Watcher -->|deploy.sh| DevVM & StagingVM & ProdVM
```

</details>

### Environment Differences

| Setting | Dev | Staging | Production |
|---------|-----|---------|------------|
| `NODE_ENV` | development | staging | production |
| Memory limit | 256MB | 512MB | 1GB |
| Database | Cloud SQL (small) | Cloud SQL (medium) | Cloud SQL HA (high availability) |
| Terraform workspace | `dev` | `staging` | `production` |

---

## Monitoring Stack

![Monitoring Stack](diagrams/06-monitoring-stack.png)

<details>
<summary>Mermaid source (click to expand)</summary>

```mermaid
flowchart LR
    subgraph App["Application Containers"]
        Backend["Backend\n:8080"]
        NodeExp["Node Exporter\n:9100"]
    end

    subgraph Mon["Monitoring Stack"]
        Prometheus["Prometheus\n:9090\nScrapes metrics"]
        Grafana["Grafana\n:3000\nDashboards"]
        Alertmanager["Alertmanager\n:9093\nAlert routing"]
    end

    subgraph Notify["Notifications"]
        Email["Email"]
        Slack["Slack"]
    end

    Backend -->|app metrics| Prometheus
    NodeExp -->|system metrics| Prometheus
    Prometheus -->|data source| Grafana
    Prometheus -->|fire alerts| Alertmanager
    Alertmanager --> Email & Slack
```

</details>

### Alert Rules

| Alert | Condition | Severity |
|-------|-----------|----------|
| Container Down | Container unreachable for > 1 min | Critical |
| High CPU | CPU > 80% for > 5 min | Warning |
| High Memory | Memory > 80% for > 5 min | Warning |
| Low Disk Space | Disk < 10% free | Critical |

---

## Network & Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        INTERNET                              │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTPS (443)
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  Cloud Load Balancer                                         │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Cloud Armor WAF                                       │  │
│  │  • Rate limiting (1000 req/min)                        │  │
│  │  • SQL injection blocking                              │  │
│  │  • XSS attack blocking                                 │  │
│  └────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Managed SSL Certificate                               │  │
│  │  • Automatic renewal                                   │  │
│  │  • HTTP → HTTPS redirect                               │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTP (80)
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  GCP VPC (Private Network)                                   │
│                                                              │
│  ┌──────────────────────────────────────────────────┐       │
│  │  Compute Engine VM (No External IP)              │       │
│  │                                                  │       │
│  │  ┌──────────┐    ┌───────────┐                  │       │
│  │  │ Frontend │───▶│  Backend  │                  │       │
│  │  │ (Nginx)  │    │ (Node.js) │                  │       │
│  │  │  :80     │    │  :8080    │                  │       │
│  │  └──────────┘    └─────┬─────┘                  │       │
│  │                        │                         │       │
│  └────────────────────────┼─────────────────────────┘       │
│                           │ Private IP (3306)                │
│                           ▼                                  │
│  ┌──────────────────────────────────────────────────┐       │
│  │  Cloud SQL (MySQL 8.0)                           │       │
│  │  • Private IP only (no public access)            │       │
│  │  • Automated daily backups                       │       │
│  │  • High Availability (production only)           │       │
│  │  • Query insights enabled                        │       │
│  └──────────────────────────────────────────────────┘       │
│                                                              │
│  Cloud NAT ──────────▶ Internet (outbound only)             │
│  (VM uses this for ECR pulls, package installs)              │
│                                                              │
│  Firewall Rules:                                             │
│  • Allow HTTP from Load Balancer health checks only          │
│  • Allow SSH via IAP (Identity-Aware Proxy) only            │
│  • Allow internal traffic between VM and Cloud SQL           │
│  • Deny all other inbound traffic                            │
└──────────────────────────────────────────────────────────────┘
```

---

## Data Flow Summary

```
User Request Flow:
User → DNS → Load Balancer → Cloud Armor → Nginx → Node.js → Cloud SQL

Deployment Flow:
Git Push → CI (lint + security) → Build → ECR → CD → GitOps → ArgoCD → VM

Secret Flow:
Vault → CD Pipeline → GitOps Manifests
Secret Manager → VM Startup Script → Docker Environment

Monitoring Flow:
Backend → Prometheus → Grafana (dashboards)
                    → Alertmanager → Email/Slack
```

---

## Regenerating Diagram Images

Pre-rendered PNG and SVG images are in `docs/diagrams/`. To regenerate them after editing the Mermaid source blocks above:

```bash
# Extract a mermaid block to a .mmd file, then render it:
npx @mermaid-js/mermaid-cli@10.6.1 -i diagram.mmd -o diagram.png -b white

# Or use the Kroki API (no local install needed):
curl -sf -X POST https://kroki.io/mermaid/png --data-binary @diagram.mmd -o diagram.png
curl -sf -X POST https://kroki.io/mermaid/svg --data-binary @diagram.mmd -o diagram.svg
```

Other viewing options:
- **GitHub** renders Mermaid blocks natively when viewing this file
- **Mermaid Live Editor**: Paste any block into [mermaid.live](https://mermaid.live)
- **VS Code**: Install the "Markdown Preview Mermaid Support" extension
