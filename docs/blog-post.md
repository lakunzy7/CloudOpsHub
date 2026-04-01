# Building a Modular Terraform Infrastructure with GitOps and CI/CD — A Complete Walkthrough

---

## Background

A growing SaaS company needed to modernize its infrastructure: automate multi-environment deployments, containerize microservices, and build a GitOps pipeline for reliable, continuous delivery.

This blog documents **every piece of code** — what each file does, how the pieces connect, and why the design decisions were made. It's written for beginners who want to understand how a real-world DevOps platform ticks from the inside.

---

## Project Goals

- **Simplicity over complexity** — Clean module organization without over-engineering
- **Full automation** — Push code to GitHub → builds happen automatically → deployment runs itself
- **Observability** — Metrics, dashboards, and alerts for every component
- **Security** — No long-lived credentials, no secrets in Git, scanning on every push
- **Multi-environment** — Isolated dev/staging/production with minimal duplicate configuration

---

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| **Infrastructure as Code** | Terraform (modular) | Declarative — you describe the desired state, Terraform figures out how to get there |
| **Containerization** | Docker + Docker Compose | Packages apps + dependencies into identical, reproducible containers |
| **CI/CD** | GitHub Actions | Native GitHub integration — runs automatically on every push |
| **GitOps** | Custom systemd service | 80-line bash script replaces ArgoCD/Flux for single-VM setups |
| **Monitoring** | Prometheus + Grafana | Industry-standard open-source observability stack |
| **Alerting** | Alertmanager + Slack | Routes alerts to your team's Slack channels |
| **Security Scanning** | Gitleaks, Trivy, tfsec, Snyk, SonarCloud | Five independent layers checking on every push |
| **Application** | Node.js + MySQL + Nginx | Full-stack bookstore app (The EpicBook) |

---

## Architecture Overview — The "Code to Live" Journey

Before diving into individual files, it helps to understand what happens when you push a one-line code change:

```
You push code to GitHub
  │
  ▼
┌──────────────────── CI Pipeline (.github/workflows/ci.yml) ───────────────┐
│  Step 1: LINT      — checks code style                                    │
│  Step 2: SECURITY  — scans for secrets, vulnerabilities, misconfigurations │
│  Step 3: BUILD     — packs app into Docker containers                     │
│  Step 4: PUSH      — uploads containers to GCP Artifact Registry          │
└───────────────────────────────────────────────────────────────────────────┘
  │
  ▼
┌──────────────────── CD Pipeline (.github/workflows/cd.yml) ───────────────┐
│  Reads the image SHA → writes it into gitops/docker-compose.yml           │
│  Commits the updated manifest back to the same branch                     │
│  Uses [skip ci] so this commit doesn't trigger another CI run             │
└───────────────────────────────────────────────────────────────────────────┘
  │
  ▼
┌────────── GitOps Sync on the VM (scripts/gitops-sync.sh + systemd) ──────┐
│  Polls Git every 60 seconds → detects the new commit                    │
│  Pulls fresh containers from Artifact Registry                          │
│  Restarts containers with new code — zero manual intervention            │
└───────────────────────────────────────────────────────────────────────────┘
  │
  ▼
Your app is live. Prometheus is already scraping metrics.
Any anomalies trigger Slack alerts via Alertmanager.
```

Every section below breaks down one piece of this pipeline from the very first line to the last.

---

## Table of Contents

1. [The Application — What We Are Deploying](#part-1-the-application)
2. [Containerizing the App — Three Dockerfiles](#part-2-dockerfiles)
3. [Terraform Infrastructure — Provisioning the Cloud](#part-3-terraform)
4. [CI Pipeline — Build, Test, Push](#part-4-ci)
5. [CD Pipeline — The GitOps Trigger](#part-5-cd)
6. [GitOps Sync — The On-VM Deployment Agent](#part-6-gitops)
7. [Monitoring & Alerting](#part-7-monitoring)
8. [Security Scanning](#part-8-security)
9. [How Everything Fits Together — The Big Picture](#part-9-big-picture)
10. [Challenges & Solutions](#part-10-challenges)

---

<a name="part-1-the-application"></a>
## Part 1: The Application — What We Are Deploying

The app is called **The EpicBook** — a Node.js bookstore. Before understanding the deployment pipeline, you need to understand what gets deployed.

### Application Structure

```
theepicbook/
  server.js              ← Express app (the program that runs on port 8080)
  package.json           ← Dependencies (Express, Sequelize, prom-client, etc.)
  Dockerfile             ← How to build the container
  config/
    config.json          ← Database config for each environment (dev, staging, prod)
  models/                ← Database tables (Sequelize ORM)
    author.js            ← Author table: id, firstName, lastName
    book.js              ← Book table: id, title, genre, price, inventory
    cart.js              ← Cart table: links books to shopping carts
    checkout.js          ← Checkout table: shipping address
    index.js             ← Sequelize bootstrap: reads config.json by NODE_ENV
  routes/
    html-routes.js       ← Renders HTML pages (home, cart, gallery)
    cart-api-routes.js   ← REST API (/api/cart — add, list, clear)
  views/                 ← Handlebars HTML templates
  public/                ← Static CSS/JS (copied into the Nginx container by CI)
  db/
    Dockerfile           ← How to build the MySQL container
    00-create-user.sh    ← Creates appuser in MySQL
    BuyTheBook_Schema.sql← CREATE DATABASE & tables
    author_seed.sql      ← Sample authors
    books_seed.sql       ← Sample books
```

### How the Works (Two-Minute Code Walkthrough)

**`server.js`** — This is the main file. It:
1. Creates an Express (Node.js web framework) app
2. Connects to a MySQL database using the `DATABASE_URL` environment variable
3. Sets up routes for HTML pages and API endpoints
4. Exports a `/metrics` endpoint for Prometheus to scrape
5. Listens on port 8080 (configurable via `PORT` env variable)

**`config/config.json`** — Sequelize (the ORM) reads this file to find the database. Each key (`development`, `staging`, `production`) maps to a `NODE_ENV` value. The value `use_env_variable: "DATABASE_URL"` means "read the connection string from the `DATABASE_URL` environment variable" — which is set by Docker Compose. **This is critical**: if the file doesn't have an entry for the current `NODE_ENV`, the app crashes on startup.

**`models/index.js`** — Reads `NODE_ENV`, looks up the matching section in `config.json`, then loads all model files (`author.js`, `book.js`, `cart.js`, `checkout.js`) and tells Sequelize to sync the database tables.

**`routes/html-routes.js`** — Handles GET requests for pages:
- `/` → Fetch 9 random books, render the homepage
- `/cart` → Show the shopping cart
- `/gallery` → Show a gallery page

**`routes/cart-api-routes.js`** — Handles API calls:
- `POST /api/cart` → Add a book to cart
- `GET /api/cart` → List cart contents
- `DELETE /api/cart/delete` → Empty the cart

---

<a name="part-2-dockerfiles"></a>
## Part 2: Containerizing the App — Three Dockerfiles

Docker packages an app and all its dependencies into a **container image** — a single file that runs identically on any Linux machine. This project builds **three** container images.

### 1. Backend — `theepicbook/Dockerfile`

```dockerfile
# Stage 1: Install dependencies in a clean layer
FROM node:18-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --production

# Stage 2: Build the final lightweight image
FROM node:18-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=deps /app/node_modules ./
COPY server.js config/ models/ routes/ views/ public/ ./
RUN chown -R appuser:appgroup /app
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/ || exit 1
CMD ["node", "server.js"]
```

**What each line does:**

| Line(s) | What It Does | Why |
|---------|-------------|-----|
| `FROM node:18-alpine AS deps` | Start with Node.js 18 on Alpine Linux (tiny 5MB base) | Alpine makes the final image small |
| `COPY package*.json` + `RUN npm ci` | Install only production dependencies | `npm ci` is faster and more reproducible than `npm install` |
| `FROM node:18-alpine` (again) | Start fresh — don't include build tools in final image | Multi-stage build: the first stage is discarded, keeping only the `node_modules/` we copied out |
| `addgroup` + `adduser` | Create a non-root user | Security best practice — the app doesn't run as root |
| `COPY --from=deps ...` | Bring node_modules from the build stage | We only copy what we need, not the entire first stage |
| `COPY server.js config/ models/ routes/ views/ public/ ./` | Copy application code | All the files the app needs to run |
| `USER appuser` | Switch to the unprivileged user | Even if someone compromises the app, they can't do root-level damage |
| `HEALTHCHECK` | Docker pings the app every 30 seconds | Allows Docker Compose to know if the app is healthy or stuck |

### 2. Frontend — `nginx/Dockerfile`

```dockerfile
FROM nginx:1.25-alpine
RUN apk add --no-cache wget=1.21.4-r0 && rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/
COPY public/ /usr/share/nginx/html/
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:80/ || exit 1
```

**What this does:**

Nginx acts as a **reverse proxy** — it's a web server that forwards requests to the Node.js backend. This container:
1. Takes a pre-built Nginx image
2. Removes the default config
3. Drops in our custom `nginx.conf` (routes `/api/` to the backend, serves static files from `/assets/`)
4. Copies the app's `public/` directory (CSS, JS, images) into Nginx's static file directory
5. Adds a health check

**The Nginx config** (`nginx.conf`) defines three routes:
- `/` → Proxies to the Node.js backend at `http://backend:8080`
- `/api/` → Proxies to the Node.js backend (the API endpoints)
- `/assets/` → Serves static files directly from Nginx's local disk (faster, no backend needed)

### 3. Database — `theepicbook/db/Dockerfile`

```dockerfile
FROM mysql:8.0
COPY 00-create-user.sh /docker-entrypoint-initdb.d/00-create-user.sh
COPY BuyTheBook_Schema.sql /docker-entrypoint-initdb.d/01-schema.sql
COPY author_seed.sql /docker-entrypoint-initdb.d/02-authors.sql
COPY books_seed.sql /docker-entrypoint-initdb.d/03-books.sql
```

**What this does:**

MySQL's Docker image has a special feature: any file in `/docker-entrypoint-initdb.d/` runs **once** when the container first starts. The files run in alphabetical order:
1. `00-create-user.sh` → Creates the `appuser` database user with a password
2. `01-schema.sql` → Creates the `bookstore` database and all tables
3. `02-authors.sql` → Seeds sample authors
4. `03-books.sql` → Seeds sample books

This means the database container is **self-initializing** — no manual SQL setup needed.

---

<a name="part-3-terraform"></a>
## Part 3: Terraform Infrastructure — Provisioning the Cloud

Terraform reads `.tf` files and creates cloud resources. Think of it as a blueprint — you describe what you want, and Terraform creates or updates resources to match.

### The Module Structure

Instead of one giant file, the Terraform code is split into **5 modules** + a root orchestrator:

```
infra/
  main.tf              ← Root: calls all 5 modules, enables APIs, creates AR
  variables.tf         ← Input values (project_id, region, passwords, etc.)
  outputs.tf           ← Values printed after apply (VM IP, URLs, etc.)
  modules/
    networking/        ← VPC, subnet, firewall rules
    iam/               ← Service account, permissions
    secrets/           ← GCP Secret Manager (DB password, Grafana, Slack)
    compute/           ← VM instance, static IP
    wif/               ← Workload Identity Federation (for CI/CD auth)
  env/
    dev.tfvars.example ← Template (checked into Git)
    staging.tfvars     ← Real values (gitignored — contains secrets)
    production.tfvars  ← Real values (gitignored — contains secrets)
```

### The Root Orchestrator — `infra/main.tf`

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
  backend "gcs" {
    bucket = "expandox-cloudehub-cloudopshub-tf-state"
    prefix = "terraform/state"
  }
}
```

**Why a GCS backend?** Terraform stores its **state** (a record of what resources exist) in a Google Cloud Storage bucket. This is essential for team collaboration and disaster recovery — the state isn't tied to a single developer's laptop.

```hcl
# Enable APIs first
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])
  project = var.project_id
  ...
}
```

Before creating any resources, these 6 Google APIs must be enabled. Every other module depends on this step implicitly.

```hcl
# Shared artifact registry (created once, first environment only)
resource "google_artifact_registry_repository" "docker" {
  count         = var.create_artifact_registry ? 1 : 0
  location      = var.region
  repository_id = "${var.project_name}-docker"
  format        = "DOCKER"
}
```

**Why `count`?** The Docker registry is shared — no environment suffix. The first deployment sets `create_artifact_registry = true` to create it. Subsequent deployments set it to `false` because it already exists. This avoids the complexity of `terraform import`.

**The 5 module calls** each pass specific variables and reference outputs from sibling modules:

```hcl
module "networking" { ... }                              # VPC + subnet + firewalls
module "iam"        { ... }                              # Service account + permissions
module "secrets"    { ... }                              # DB password, Grafana, Slack in Secret Manager
module "compute"   { ... startup_script = templatefile() } # VM instance
module "wif"       { ... }                              # OIDC federation for CI/CD
```

The **compute** module receives a `startup_script` generated by `templatefile()` — this injects environment-specific values (project ID, region, secret names) into the bootstrap script (`scripts/startup.sh`) **at provisioning time**.

### What Each Module Creates

#### Module 1: Networking (`infra/modules/networking/main.tf`)

| Resource | Name Pattern | Purpose |
|----------|-------------|---------|
| VPC | `{name}-vpc-{env}` | Private network — all VMs connect to it |
| Subnet | `{name}-subnet-{env}` | `10.0.1.0/24` — the IP range for VMs |
| Firewall (HTTP) | Allows 80, 3000, 9090, 9093 from 0.0.0.0/0 | Lets internet reach the app, Grafana, Prometheus, Alertmanager |
| Firewall (SSH) | Allows 22 from 35.235.240.0/20 | SSH only via IAP (Google's secure tunnel) |

#### Module 2: IAM (`infra/modules/iam/main.tf`)

Creates a **service account** — the VM's identity in GCP:

```
cloudopshub-app-{env}@{project-id}.iam.gserviceaccount.com
```

Then grants it 4 roles:
| Role | What It Does |
|------|-------------|
| `roles/artifactregistry.reader` | Pulls Docker images from the registry |
| `roles/secretmanager.secretAccessor` | Reads secrets from Secret Manager |
| `roles/logging.logWriter` | Writes logs to Cloud Logging |
| `roles/monitoring.metricWriter` | Writes metrics to Cloud Monitoring |

Plus a separate binding: `roles/artifactregistry.writer` — lets the CI pipeline **push** images.

#### Module 3: Secrets (`infra/modules/secrets/main.tf`)

Stores 3 secrets in GCP Secret Manager:
| Secret | ID | Used By |
|--------|---|---------|
| DB Password | `{name}-db-password-{env}` | MySQL container + Sequelize config |
| Grafana Password | `{name}-grafana-password-{env}` | Grafana admin login |
| Slack Webhook | `{name}-slack-webhook-{env}` | Alertmanager → Slack notifications |

#### Module 4: Compute (`infra/modules/compute/main.tf`)

Creates:
1. **Static IP** — A fixed public IP address (e.g., `34.135.154.250`)
2. **VM Instance** — e2-medium, Container-Optimized OS (cos-cloud), 30 GB disk

The VM gets the `startup-script` metadata (rendered by `templatefile`), which runs on first boot.

#### Module 5: WIF (`infra/modules/wif/main.tf`)

**Workload Identity Federation** — this is how GitHub Actions authenticates to GCP **without any passwords**.

```hcl
# Pool: a grouping for GitHub runners
google_iam_workload_identity_pool.github

# Provider: says "trust tokens from GitHub Actions OIDC"
google_iam_workload_identity_pool_provider.github

# Binding: "This pool is allowed to act as this service account"
google_service_account_iam_member.wif_binding
```

The flow works like this:
1. GitHub Actions gets an OIDC token from GitHub (built-in, automatic)
2. GCP verifies the token is from your repository
3. If the token matches (`assertion.repository == 'your-repo'`), GCP grants temporary credentials
4. These credentials expire in 1 hour — no keys to store or rotate

**This is why there's no GCP service account key** (no JSON file) anywhere in the project.

---

<a name="part-4-ci"></a>
## Part 4: CI Pipeline — Build, Test, Push

**File:** `.github/workflows/ci.yml`

### What is CI?

**Continuous Integration (CI)** is the practice of automatically building and testing every code push. In this project, when you push to the `main` branch, GitHub Actions runs a pipeline that does three things:

1. Checks the code quality
2. Scans for security issues
3. Builds Docker containers and uploads them

### The Pipeline Structure

A GitHub Actions workflow is organized into **jobs** that can run in parallel or sequence. Each job contains **steps**.

```yaml
name: CI

on:
  push:
    branches: [main]          # Triggers on push to main
  pull_request:
    branches: [main]          # Also triggers on PRs to main (just lint + scan, no build)

permissions:
  contents: read              # Can read the repo
  security-events: write      # Can upload security scan results to GitHub

env:                          # Global variables, available in ALL jobs
  REGISTRY: ${{ secrets.GCP_REGION }}-docker.pkg.dev/${{ secrets.GCP_PROJECT_ID }}/cloudopshub-docker
  IMAGE_TAG: ${{ github.sha }}  # The commit SHA, e.g. "a1b2c3d4e5f6..."
```

### Job 1: lint (Code Quality Check)

```yaml
lint:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4           # Clones the repo
    - uses: actions/setup-node@v4         # Installs Node.js 18
      with:
        node-version: 18
        cache: npm                        # Speeds up by caching node_modules
        cache-dependency-path: theepicbook/package-lock.json
    - run: cd theepicbook && npm ci       # Installs exact deps from lock file
    - run: cd theepicbook && npm run lint # Runs ESLint
```

**What `npm ci` does vs `npm install`:** `npm ci` reads `package-lock.json` and installs **exactly** those versions. `npm install` might update versions, leading to inconsistent builds.

**What ESLint checks:** Code style, unused variables, unreachable code, common JavaScript bugs.

**This job MUST pass** for the pipeline to proceed.

### Job 2: security-scan (5 Independent Scanners)

```yaml
security-scan:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0                    # Gets full git history (needed for gitleaks)
```

**Step 1: Gitleaks — Finds Hardcoded Secrets**
```yaml
    - name: Gitleaks — Scan for hardcoded secrets
      uses: gitleaks/gitleaks-action@v2
      continue-on-error: true
      env:
        GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}
```

Gitleaks scans every commit in the repo's entire history looking for API keys, passwords, tokens, private keys, etc. It knows patterns like AWS keys, GitHub tokens, private keys, and more.

**`continue-on-error: true`** means: if this scanner finds something, don't stop the pipeline — just report it and move on. This is intentional for a team project where you might want to build while investigating a potential leak.

**Step 2: Trivy FS — Filesystem Vulnerability Scan**
```yaml
    - name: Trivy — Filesystem vulnerability scan
      uses: aquasecurity/trivy-action@master
      continue-on-error: true
      with:
        scan-type: 'fs'     # Filesystem mode (not Docker image scanning)
        scan-ref: '.'        # Scan the entire repo
```

Trivy looks at `package.json`, `package-lock.json`, and other dependency files to find known vulnerabilities in npm packages, Python packages, Go modules, etc.

**Step 3: tfsec — Terraform Misconfiguration Scan**
```yaml
    - name: tfsec — Terraform security scan
      uses: aquasecurity/trivy-action@master
      continue-on-error: true
      with:
        scan-type: 'config'  # IaC configuration audit mode
        scan-ref: 'infra'    # Only scan the infra/ directory
```

Checks if Terraform config has security issues — overly permissive firewalls, missing encryption, public storage buckets, etc. Uses Trivy's config scanning engine.

**Steps 4 & 5: Snyk Code + SonarCloud (Require Authentication)**
```yaml
    - name: Snyk Code — SAST scan
      uses: snyk/actions/node@master
      continue-on-error: true
      env:
        SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
```

Snyk Code performs **Static Application Security Testing (SAST)** — it parses JavaScript code looking for SQL injection, cross-site scripting (XSS), insecure random number generation, and similar vulnerabilities.

```yaml
    - name: SonarCloud — Code quality scan
      uses: SonarSource/sonarqube-scan-action@master
      continue-on-error: true
      env:
        SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

SonarCloud checks code quality: bugs, code smells, test coverage, and security hotspots. It uploads results to sonarcloud.io where you can track quality trends over time.

Both scanners are optional — the pipeline builds and deploys even without `SNYK_TOKEN` or `SONAR_TOKEN`.

### Job 3: build-and-push (The Main Event)

```yaml
build-and-push:
  needs: [lint, security-scan]     # Waits for these to finish
  runs-on: ubuntu-latest
  if: ${{ always() && needs.lint.result == 'success' && github.ref == 'refs/heads/main' }}
  permissions:
    id-token: write                # REQUIRED for WIF (OIDC token generation)
    contents: read
```

**The `if` condition explained:**

| Condition | What It Does |
|-----------|-------------|
| `always()` | Run even if security-scan failed (because of continue-on-error) |
| `needs.lint.result == 'success'` | BUT only if lint actually passed |
| `github.ref == 'refs/heads/main'` | Only on main branch — skip for PRs |

**Step 1: Authenticate to GCP (Using WIF)**
```yaml
    - uses: actions/checkout@v4

    - name: Authenticate to Google Cloud
      uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: ${{ secrets.GCP_WIF_PROVIDER }}
        service_account: ${{ secrets.GCP_SA_EMAIL }}
```

This is where WIF (Workload Identity Federation) comes in:

1. GitHub provides an OIDC token to this runner
2. The `google-github-actions/auth` action sends this token to GCP
3. GCP verifies: "Yes, this token is from repo `lakunzy7/CloudOpsHub`"
4. GCP grants temporary credentials for the service account
5. All subsequent `gcloud` commands run as that service account

**No password, no API key, no JSON file.**

**Step 2: Configure Docker to Talk to Artifact Registry**
```yaml
    - run: gcloud auth configure-docker ${{ secrets.GCP_REGION }}-docker.pkg.dev --quiet
```

This configures Docker to authenticate with GCP Artifact Registry. Docker will now use GCP credentials when pushing/pulling to that registry.

**Step 3: Build & Push Backend**
```yaml
    - name: Build and push Backend image
      run: |
        docker build -t $REGISTRY/theepicbook-backend:$IMAGE_TAG \
                     -t $REGISTRY/theepicbook-backend:latest \
                     theepicbook/
        docker push $REGISTRY/theepicbook-backend:$IMAGE_TAG
        docker push $REGISTRY/theepicbook-backend:latest
```

**What `-t` means:** Tag the image. Two tags are applied:
- **Commit SHA** (e.g., `theepicbook-backend:a1b2c3d...`) — this is the exact version deployed
- **`latest`** — a pointer that always moves to the most recent build

**Why two tags?** The `latest` tag is for convenience (e.g., `docker pull :latest`). The commit SHA tag is for precision (e.g., "exactly this version, no surprises").

**Step 4: Build & Push Frontend**
```yaml
    - name: Build and push Frontend image
      run: |
        cp -r theepicbook/public nginx/public
        docker build -t $REGISTRY/theepicbook-frontend:$IMAGE_TAG ... nginx/
        docker push $REGISTRY/theepicbook-frontend:$IMAGE_TAG
        docker push $REGISTRY/theepicbook-frontend:latest
```

Note the `cp` command first — the Nginx container needs the static files from `theepicbook/public/`. CI copies them into the `nginx/` directory before building the frontend image.

**Step 5: Build & Push Database**
```yaml
    - name: Build and push Database image
      run: |
        docker build -t $REGISTRY/theepicbook-database:$IMAGE_TAG ... theepicbook/db/
        docker push $REGISTRY/theepicbook-database:$IMAGE_TAG
        docker push $REGISTRY/theepicbook-database:latest
```

---

<a name="part-5-cd"></a>
## Part 5: CD Pipeline — The GitOps Trigger

**File:** `.github/workflows/cd.yml`

### What is CD?

**Continuous Deployment (CD)** takes the freshly built containers and deploys them. In this project, CD works by **updating the Docker Compose manifest** — it's not deploying directly to the server. It's changing a file in Git and committing it. The GitOps agent on the server then picks up the change.

```yaml
name: CD

on:
  workflow_run:
    workflows: [CI]               # Triggered when the CI workflow...
    types: [completed]            # ...finishes
    branches: [main]              # ...on the main branch

permissions:
  contents: write                 # Can commit and push to the repo

env:
  REGISTRY: ${{ secrets.GCP_REGION }}-docker.pkg.dev/${{ secrets.GCP_PROJECT_ID }}/cloudopshub-docker
```

**Why `workflow_run` instead of `push`?** This job should only run after CI **succeeds**. If CI fails (lint fails), there's no new code to deploy — skip CD entirely.

### The Deploy Job

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    #     ^ Only run if CI was successful. If CI failed, this job doesn't start.
```

**Step 1: Get the Code**
```yaml
    - uses: actions/checkout@v4
```

**Step 2: Read What CI Produced**
```yaml
    IMAGE_TAG=${{ github.event.workflow_run.head_sha }}
```

`github.event.workflow_run.head_sha` is the commit SHA from the CI run that just succeeded. For example: `a1b2c3d4e5f6...`.

**Step 3: Rewrite the Manifest**
```yaml
    sed -i "s|image:.*theepicbook-backend.*|image: $REGISTRY/theepicbook-backend:$IMAGE_TAG|" \
      gitops/docker-compose.yml
    sed -i "s|image:.*theepicbook-frontend.*|image: $REGISTRY/theepicbook-frontend:$IMAGE_TAG|" \
      gitops/docker-compose.yml
    sed -i "s|image:.*theepicbook-database.*|image: $REGISTRY/theepicbook-database:$IMAGE_TAG|" \
      gitops/docker-compose.yml
```

**What this does:** Every image line in `gitops/docker-compose.yml` gets rewritten. For example:

Before (old SHA):
```yaml
  backend:
    image: us-central1-docker.pkg.dev/expandox-cloudehub/cloudopshub-docker/theepicbook-backend:abc123
```

After (new SHA):
```yaml
  backend:
    image: us-central1-docker.pkg.dev/expandox-cloudehub/cloudopshub-docker/theepicbook-backend:def456
```

The `sed` command finds the line containing `theepicbook-backend` and replaces the entire image line with the new SHA-tagged image.

**Why `|` instead of `/` as the sed delimiter?** Because the image URL contains `/` characters. Using `|` avoids having to escape every slash.

**Step 4: Commit the Change**
```yaml
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add gitops/docker-compose.yml
    git commit -m "chore: update image to ${IMAGE_TAG} [skip ci]" || exit 0
    git push
```

**The `[skip ci]` tag is critical.** GitHub Actions skips workflow runs for commits containing `[skip ci]` in the message. Without it, this commit would trigger CI again, which would trigger CD again, which would commit again — creating an infinite loop.

### What CD Does NOT Do

CD does **not**:
- SSH into a server
- Run `docker compose up`
- Deploy to Kubernetes
- Execute any code on your infrastructure

It's purely a **manifest update**. This is the GitOps pattern: the server's state is defined by what's in Git, and the server itself pulls updates.

---

<a name="part-6-gitops"></a>
## Part 6: GitOps Sync — The Server-Side Deployment Agent

If you want a detailed section, it starts here.

### What is GitOps?

**GitOps** means: "The desired state of my infrastructure is stored in Git. The live environment should automatically match what's in Git."

In this project, `gitops/docker-compose.yml` is the **source of truth** — it says which Docker image versions should be running. The GitOps agent on the VM reads that file and makes it happen.

### The Two-Part System

GitOps has two parts that work together:

1. **`scripts/startup.sh`** — runs once when the VM first boots (set by Terraform)
2. **`scripts/gitops-sync.sh`** — runs continuously as a systemd service

---

### Part A: Bootstrap — `scripts/startup.sh`

When Terraform creates the VM, it passes a **startup script** via `templatefile()`. This script runs once on first boot. Let's trace what happens step by step.

**Step 1: Install Docker Compose**

```bash
curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64" \
  -o /var/lib/toolbox/docker-compose
chmod +x /var/lib/toolbox/docker-compose
```

Downloads Docker Compose v2.24.0 to a custom location (`/var/lib/toolbox`). This version is pinned so deployments are reproducible.

**Step 2: Authenticate to Artifact Registry**

```bash
gcloud auth configure-docker $REGISTRY_HOST --quiet
```

Authenticates Docker to pull private images. The VM already has `gcloud` pre-installed because it's a Google Cloud VM.

**Step 3: Fetch Secrets from Secret Manager**

```bash
DB_PASS=$(gcloud secrets versions access latest --secret=$DB_PASSWORD_SECRET_NAME)
GRAFANA_PASS=$(gcloud secrets versions access latest --secret=$GRAFANA_SECRET_NAME)
SLACK_WEBHOOK=$(gcloud secrets versions access latest --secret=$SLACK_SECRET_NAME)
```

These are the actual secret values stored in GCP Secret Manager. They're loaded into shell variables **in memory only** — never written to a file (except the `.env` file, which is on-disk but gitignored).

**Step 4: Write `.env` File for Docker Compose**

```bash
cat > /var/lib/cloudopshub/.env <<EOF
DATABASE_URL=mysql://appuser:${DB_PASS}@database:3306/bookstore
DB_ROOT_PASSWORD=${DB_PASS}
DB_PASSWORD=${DB_PASS}
NODE_ENV=$ENVIRONMENT
PORT=8080
REGISTRY=${REGISTRY_HOST}
GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASS}
SLACK_WEBHOOK_URL=${SLACK_WEBHOOK}
EOF
```

This `.env` file is passed to `docker compose` via `--env-file`. Docker Compose reads it to fill in variables like `${SLACK_WEBHOOK_URL}` in `docker-compose.yml`.

**Step 5: Create the Systemd Service Unit**

```bash
cat > /etc/systemd/system/gitops-sync.service <<'EOF'
[Unit]
Description=GitOps Sync Agent for CloudOpsHub
After=network-online.target

[Service]
Type=simple
...
ExecStart=/usr/local/bin/gitops-sync.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gitops-sync
systemctl start gitops-sync
```

Systemd creates a background service that:
- Starts after networking is up
- Runs `gitops-sync.sh`
- Auto-restarts if it crashes (after 5 seconds)
- Starts automatically on boot

---

### Part B: The GitOps Agent — `scripts/gitops-sync.sh`

This script runs forever. Every 60 seconds it checks: "Has the Git commit changed in the `gitops/` directory?" If yes, it redeploys.

Here's the full flow:

**Step 1: Clone the Repo**

```bash
REPO_DIR="/var/lib/gitops/repo"
if [ ! -d "$REPO_DIR/.git" ]; then
  git clone --depth 1 --branch $GITOPS_BRANCH $GITOPS_REPO_URL $REPO_DIR
fi
cd $REPO_DIR
```

`--depth 1` means "only fetch the latest commit" — a shallow clone. We don't need git history, we just need the latest version of `gitops/docker-compose.yml`. This keeps the clone fast and small.

**Step 2: Initial Deploy**

```bash
deploy() {
  # 2a. Write environment variables to .env file (for Docker Compose)
  export $(cat "$GITOPS_ENV_FILE" | xargs)

  # 2b. Start/refresh containers with the new manifest
  docker compose -f $COMPOSE_FILE -f $OVERLAY_FILE \
    --env-file $GITOPS_ENV_FILE up -d --pull always --remove-orphans
}

deploy || echo "$(date): Initial deploy failed, will retry" >&2
```

The first run starts the 7 containers (frontend, backend, database, prometheus, grafana, node-exporter, alertmanager) from the versions specified in `docker-compose.yml`.

**Step 4: The Sync Loop**

```bash
while true; do
  sleep $GITOPS_SYNC_INTERVAL

  git fetch origin $GITOPS_BRANCH --depth 1
  LOCAL_SHA=$(git rev-parse HEAD)
  REMOTE_SHA=$(git rev-parse FETCH_HEAD)

  if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
    echo "$(date): New commit detected. Local: $LOCAL_SHA Remote: $REMOTE_SHA"

    git reset --hard origin/$GITOPS_BRANCH

    # Check if the change affects docker compose or monitoring
    if git diff --name-only $LOCAL_SHA $REMOTE_SHA | grep -qE '(gitops/|monitoring/)'; then
      deploy || echo "$(date): Deploy failed" >&2
    else
      echo "$(date): No changes in gitops/, skipping deploy"
    fi
  fi
done
```

**How it works, line by line:**

| Code | Explanation |
|------|-------------|
| `sleep 60` | Wait 60 seconds between checks |
| `git fetch` | Download latest changes without modifying local files |
| `LOCAL_SHA=$(git rev-parse HEAD)` | Get the commit hash of what's currently running |
| `REMOTE_SHA=$(git rev-parse FETCH_HEAD)` | Get the commit hash of what's in the remote |
| `if LOCAL != REMOTE` | If they differ, there's a new commit |
| `git reset --hard` | Force-update local repo to match remote |
| `grep -qE '(gitops/|monitoring/)'` | Only redeploy if the changed files are in `gitops/` or `monitoring/` — ignore doc-only commits |
| `deploy` | Run docker-compose up with the new manifest |

The loop is tolerant — if `deploy()` fails (network issue, bad config), it just tries again next cycle.

### What `deploy()` Actually Does

**1. Pull Fresh Images**
```bash
docker compose -f docker-compose.yml -f overlays/production/docker-compose.override.yml \
  --env-file /var/lib/cloudopshub/.env up -d --pull always
```

`--pull always` forces Docker to check if a newer image exists in Artifact Registry and download it. This is how the new code actually gets onto the server.

**2. Remove Orphaned Containers**
`--remove-orphans` cleans up any containers that are no longer defined in the compose file.

**3. Apply Environment Override**
The overlay file (`gitops/overlays/production/docker-compose.override.yml`) adds resource limits on top of the base `docker-compose.yml`:

```yaml
# Base (from docker-compose.yml)
services:
  backend:
    image: theepicbook-backend:def456
    ports:
      - "8080:8080"

# Overlay (adds resource limits for production)
services:
  backend:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 1G
        reservations:
          cpus: '1.0'
          memory: 512M
    restart_policy:
      condition: on-failure
      delay: 5s
      max_attempts: 3
```

Docker Compose merges both files — the base provides the image and ports, the overlay adds resource constraints.

**4. Force Alertmanager Recreate if Webhook Changed**
```bash
if grep -q "SLACK_WEBHOOK_PLACEHOLDER" monitoring/alertmanager.yml; then
  docker compose stop alertmanager
  docker compose rm -f alertmanager
  docker compose up -d alertmanager
fi
```

If the alertmanager config still has the placeholder, the webhook hasn't been injected yet. Alertmanager can't just be restarted — Docker caches the mount, so a `restart` doesn't reload the file. The container must be removed and recreated with the correct file.

---

<a name="part-7-monitoring"></a>
## Part 7: Monitoring & Alerting — The Observability Stack

Monitoring is critical — you can't fix what you can't see. This project deploys a full observability stack:

| Component | Purpose | Port |
|-----------|---------|------|
| Prometheus | Scrapes metrics from all targets | 9090 |
| Grafana | Visualizes metrics in dashboards | 3000 |
| Alertmanager | Routes alerts to Slack | 9093 |
| Node Exporter | Exposes VM-level metrics | 9100 |

### Prometheus — The Metrics Collector

**What Prometheus Does:**
Prometheus is a time-series database (TSDB). Every 15 seconds, it "scrapes" (HTTP GETs) from each target's `/metrics` endpoint, collecting numeric measurements like CPU usage, request count, response latency.

**Scrape Targets** (from `gitops/{env}/monitoring/prometheus.yml`):

| Target | Metrics | What They Measure |
|--------|---------|-------------------|
| `prometheus:9090` | `prometheus_engine_query_duration_seconds`, `prometheus_tsdb_compactions_total` | How healthy Prometheus itself is (storage, ingestion rate) |
| `node-exporter:9100` | `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes`, `node_disk_read_bytes_total` | VM health (CPU, memory, disk, network I/O, load average) |
| `backend:8080/metrics` | `http_request_duration_seconds`, `http_requests_total`, `nodejs_eventloop_lag_seconds` | App health (request rate, error rate, latency) |

The backend's `/metrics` endpoint is provided by the `prom-client` npm package, which automatically collects Node.js process metrics. The Express middleware in `server.js` adds a custom histogram for HTTP request duration.

### Alert Rules — When to Notify

Prometheus evaluates alert rules every 15 seconds. Rules are defined in `gitops/{env}/monitoring/alert.rules.yml`:

```yaml
groups:
  - name: vm-alerts
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
```

**How to read this:** If CPU usage exceeds 80% for 5 consecutive minutes, fire a "warning" alert. The `for: 5m` prevents "flapping" — a brief spike doesn't trigger an alert.

| Alert Group | Alerts | Description |
|-------------|--------|-------------|
| vm-alerts | HighCPUUsage, HighMemoryUsage, HighDiskUsage | VM-level thresholds (80% CPU, 85% memory, 85% disk) for 5m |
| container-alerts | ContainerDown, ContainerRestarting | A Docker container is absent for 1m, or restarting 3+ times in 15m |
| app-alerts | AppDown, HighErrorRate | Backend is unreachable for 2m, or 5xx error rate exceeds 5% |
| prometheus-alerts | TargetDown | A scrape target has been unreachable for 5m |

### Grafana — The Dashboard UI

Grafana reads Prometheus data and displays it visually. Three dashboards are auto-provisioned on startup:

1. **Infrastructure Dashboard** — CPU, memory, disk usage gauges, network I/O graphs
2. **Application Dashboard** — Request rate, error rate, latency percentiles (p50, p95, p99)
3. **Epicbook Dashboard** — Bookstore-specific metrics (active carts, category views)

Dashboards are loaded from `gitops/{env}/monitoring/dashboards/` via provisioning configs:
- `datasource.yml` → Point Grafana at Prometheus at `http://prometheus:9090`
- `dashboards.yml` → Tell Grafana to load JSON files from `/var/lib/grafana/dashboards/`

### Alertmanager — The Notification Router

Alertmanager receives alerts from Prometheus and routes them to the right place:

```yaml
receivers:
  - name: slack-notifications
    slack_configs:
      - channel: '#devops'
        title: '{{ .GroupLabels.alertname }} — Warning'
        send_resolved: true
  - name: slack-critical
    slack_configs:
      - channel: '#devops'
        title: '{{ .GroupLabels.alertname }} — CRITICAL'
        send_resolved: true

route:
  receiver: slack-notifications
  group_by: [alertname, environment]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - match:
        severity: critical
      receiver: slack-critical
    - match:
        severity: warning
      receiver: slack-notifications
```

**How routing works:**

1. Similar alerts are grouped together (by `alertname` and `environment`)
2. Alerts wait 30 seconds (`group_wait`) before being sent — this batches similar alerts
3. If the same alert fires again within 5 minutes (`group_interval`), it's included in an update
4. If no change for 4 hours (`repeat_interval`), the alert is sent again to remind the team
5. Critical alerts go to the `slack-critical` receiver, warnings go to `slack-notifications`

---

<a name="part-8-security"></a>
## Part 8: Security Scanning — Five Layers of Defense

The CI pipeline runs five independent security scanners, each checking different aspects:

| Scanner | What It Checks | Example Findings | Required? |
|---------|---------------|-----------------|-----------|
| **Gitleaks** | Entire git history for committed secrets | AWS keys, GitHub tokens, private keys, API credentials | No |
| **Trivy FS** | Source files for dependency vulnerabilities | npm packages with known CVEs | No |
| **Trivy Config (tfsec)** | Terraform config for infrastructure misconfigurations | Overly permissive firewalls, public storage, missing encryption | No |
| **Snyk Code** | Application code (Node.js) for vulnerabilities | SQL injection, XSS, prototype pollution, insecure crypto | Yes (for results) |
| **SonarCloud** | Entire repo for code quality + hotspots | Bugs, code smells, security vulnerabilities, test coverage | Yes (for results) |

**Why not make them blocking?**

A failed scan could block a critical security fix. The team chose `continue-on-error: true` so deployments aren't blocked, but all results are visible in GitHub Actions logs and SonarCloud.

---

<a name="part-9-big-picture"></a>
## Part 9: The Big Picture — How Everything Links Together

Let's trace the entire data flow from Terraform to the user's browser:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  TERRAFORM (infra/main.tf)                                             │
│                                                                        │
│  Provisions a GCP VM, VPC, service account, and WIF.                  │
│  Passes startup.sh as a template to the VM's bootstrap.               │
│                                                                        │
│  startup.sh does:                                                     │
│    1. Install Docker Compose                                           │
│    2. Auth to Artifact Registry                                        │
│    3. Write .env with secrets                                          │
│    4. Clone repo                                                       │
│    5. Start gitops-sync service                                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  THE VM (7 Docker containers)                                          │
│                                                                        │
│  Nginx (:80) ────proxies───> Node.js (:8080) ────connects───> MySQL   │
│  │                                │                                   │
│  │                                ▼                                   │
│  │                           /metrics (prom-client)                   │
│  │                                                                   │
│  Prometheus (:9090) ← scrapes ← Node.js + Node Exporter + Self       │
│        │                                                                │
│        ▼                                                                │
│    Alertmanager (:9093) ← evaluates rules ← alerts to Slack          │
│        │                                                                │
│        ▼                                                                │
│    Grafana (:3000) ← reads ← Prometheus data → dashboards             │
└─────────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │
┌─────────────────────────────────────────────────────────────────────────┐
│  DEVELOPER PUSH ────────────────────────────────────────────────────────┐
│                                                                        │
│  1. Code pushed to GitHub                                              │
│  2. CI builds new images, pushes to Artifact Registry                 │
│  3. CD writes new SHA into docker-compose.yml                          │
│  4. gitops-sync detects change → pulls new images → restarts          │
└─────────────────────────────────────────────────────────────────────────┘
```

### What Happens When a User Visits the App

1. User opens `http://your-vm-ip/` in a browser
2. Request hits Nginx on port 80
3. For `/` (homepage), Nginx proxies to Node.js backend
4. Node.js queries MySQL for random books
5. Node.js renders the Handlebars template
6. Page loads with books, CSS, and JS
7. Every request adds a metric to `/metrics`
8. Every 15s Prometheus scrapes those metrics
9. Every 15s Prometheus evaluates alert rules
10. If an alert fires → Alertmanager → Slack notification

---

<a name="part-10-challenges"></a>
## Part 10: Challenges & Solutions

### 1. Terraform Template Escaping (`$$` vs `$`)

**Problem:** `templatefile()` replaces `${VAR}` with a value, but bash also uses `${VAR}` for variables.

**Solution:** Use `$${VAR}` in the template. Terraform sees `$${}` and renders it as literal `${}`. Shell variables work normally.

```hcl
# In startup.sh template:
# Terraform variable: ${project_id} → becomes "expandox-cloudehub"
# Shell variable:     $${HOME_DIR} → becomes "${HOME_DIR}" (literal, for shell to interpret)
```

### 2. Docker Compose Bind Mount Doesn't Reload on Restart

**Problem:** If you change alertmanager.yml and just `docker compose restart alertmanager`, Docker uses the old cached bind mount. The new file isn't picked up.

**Solution:** Stop, remove the container, then recreate:
```bash
docker compose stop alertmanager
docker compose rm -f alertmanager
docker compose up -d alertmanager
```

### 3. Systemd HOME Mismatch

**Problem:** Docker stores credentials at `$HOME/.docker/config.json`. The startup script sets `HOME=/var/lib`, but systemd uses `HOME=/root` by default.

**Solution:** Add `Environment=HOME=/var/lib` to the systemd unit file.

### 4. Sequelize NODE_ENV Mismatch

**Problem:** `config.json` only had `development` and `test` entries. Deploying with `NODE_ENV=staging` crashed because Sequelize couldn't find the staging config.

**Solution:** Add entries for all environments (`development`, `staging`, `production`) to `config/config.json`. All use `DATABASE_URL` from the environment.

### 5. Secret Placeholder Pattern

**Problem:** Can't commit real Slack webhook URLs to Git, but the config file needs a valid URL for the YAML structure.

**Solution:** Use a unique sentinel string `SLACK_WEBHOOK_PLACEHOLDER` in Git. At deploy time, `gitops-sync.sh` reads the real secret from GCP Secret Manager and uses `sed` to replace it. The container is then recreated with the correct file.

---

## Results

| Metric | Value |
|--------|-------|
| Terraform modules | 5 focused modules (~200 lines) |
| Resources per env | 28 GCP resources |
| Containers per env | 7 (with monitoring stack) |
| `terraform apply` time | ~3 minutes |
| Code-to-live time | 4-5 minutes (CI + CD + GitOps sync) |
| Security scanners | 5 running on every push |
| Monitoring | Prometheus + Grafana (3 dashboards) |
| GitOps agent | 80 lines of bash |

---

## Next Steps

- SSL/TLS (Let's Encrypt + certbot)
- Database backups (automated snapshots)
- Load balancer in front of Nginx
- Multi-region for higher availability

---

## References

- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Google Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [GitHub Actions CI/CD](https://docs.github.com/en/actions)
- [Docker Compose](https://docs.docker.com/compose/)
- [Prometheus](https://prometheus.io/docs/)
- [Grafana](https://grafana.com/docs/)
- [Alertmanager](https://prometheus.io/docs/alerting/latest/configuration/)
- [Gitleaks](https://github.com/gitleaks/gitleaks)
- [Trivy](https://aquasecurity.github.io/trivy/)
