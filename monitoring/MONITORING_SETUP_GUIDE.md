# CloudOpsHub Monitoring Stack — Complete Setup Guide

A beginner-friendly guide to setting up a monitoring stack for a Docker-based application deployed on Google Cloud Platform (GCP).

---

## What You're Building

A monitoring system that watches your application and alerts you on Slack when something goes wrong. Here's what each tool does:

| Tool | What it does |
|------|-------------|
| **Prometheus** | Collects metrics (CPU, memory, request count) from your app and VM every 15 seconds |
| **Grafana** | Displays metrics as graphs and dashboards so you can visualize what's happening |
| **Alertmanager** | Sends Slack notifications when Prometheus detects a problem |
| **Node Exporter** | Exposes VM-level metrics (CPU, memory, disk) so Prometheus can collect them |

### How They Connect

```
Your App + VM
    ↓ (exposes metrics)
Prometheus (collects every 15s)
    ↓                    ↓
Grafana (dashboards)   Alertmanager (notifications)
                            ↓
                      Slack #cloudopshub-alerts
```

---

## Prerequisites

Before you start, make sure you have:

- [ ] A GCP project with Terraform already applied (VPC, VM, firewall rules)
- [ ] A GitHub repository with CI/CD pipelines set up
- [ ] A Slack workspace where you can create apps
- [ ] Docker and docker-compose installed on your GCE VM (Container-Optimised OS has Docker pre-installed)

---

## Step 1: Understand the Infrastructure

Your Terraform setup has already created:

- **A GCE VM** (`dev-app-vm`) with no public IP — accessed only via Cloud IAP
- **Firewall rules** that allow monitoring ports (9090, 9093, 9100, 3000) **internally only**
- **Cloud NAT** so the VM can pull Docker images without a public IP
- **Secret Manager** with a `dev-grafana-admin-password` secret

You don't need to change any Terraform. It's already set up for monitoring.

---

## Step 2: Create the Monitoring Config Files

Create a `monitoring/` folder inside your `gitops/dev/` directory with 4 files:

```
gitops/dev/
├── docker-compose.yml          ← already exists
└── monitoring/
    ├── prometheus.yml           ← you create this
    ├── alert.rules.yml          ← you create this
    ├── alertmanager.yml         ← you create this
    └── datasource.yml           ← you create this
```

### 2.1 — prometheus.yml

This tells Prometheus what to monitor and how often.

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

  # Change "dev" to "staging" or "prod" for other environments
  external_labels:
    monitor:     cloudopshub
    environment: dev

rule_files:
  - "alert.rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

scrape_configs:

  # Prometheus monitors itself
  - job_name: prometheus
    static_configs:
      - targets:
          - localhost:9090

  # VM metrics (CPU, memory, disk)
  - job_name: node-exporter
    static_configs:
      - targets:
          - node-exporter:9100
    relabel_configs:
      - source_labels: [__address__]
        target_label:  instance
        replacement:   dev-app-vm

  # Your application metrics
  - job_name: theepicbook-app
    static_configs:
      - targets:
          - app:8080
    metrics_path: /metrics
    relabel_configs:
      - source_labels: [__address__]
        target_label:  instance
        replacement:   theepicbook-app
```

**Key points:**
- `scrape_interval: 15s` — Prometheus checks every 15 seconds
- `node-exporter:9100` — uses Docker container name (not IP address)
- `app:8080` — your Node.js app must expose a `/metrics` endpoint
- `alertmanager:9093` — where to send alerts

### 2.2 — alert.rules.yml

This defines **when** to fire alerts. Think of these as "if this happens, tell me."

```yaml
groups:

  # VM Alerts — monitors the server itself
  - name: vm-alerts
    rules:

      - alert: HighCPUUsage
        expr: 100 - (avg by(instance)
          (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
          environment: dev
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is {{ $value }}% — above 80% for 5 minutes."

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes /
          node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
          environment: dev
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is {{ $value }}% — above 85% for 5 minutes."

      - alert: HighDiskUsage
        expr: (1 - (node_filesystem_avail_bytes{mountpoint="/"} /
          node_filesystem_size_bytes{mountpoint="/"})) * 100 > 85
        for: 5m
        labels:
          severity: warning
          environment: dev
        annotations:
          summary: "High disk usage on {{ $labels.instance }}"
          description: "Disk usage is {{ $value }}%."

  # Container Alerts — monitors Docker containers
  - name: container-alerts
    rules:

      - alert: ContainerDown
        expr: absent(container_last_seen{name=~"theepicbook.*"})
        for: 1m
        labels:
          severity: critical
          environment: dev
        annotations:
          summary: "Container {{ $labels.name }} is down"
          description: "Container has been down for 1 minute. Immediate action required."

      - alert: ContainerRestarting
        expr: rate(container_restart_count{name=~"theepicbook.*"}[15m]) > 0
        for: 5m
        labels:
          severity: warning
          environment: dev
        annotations:
          summary: "Container {{ $labels.name }} is restarting"
          description: "Container has been restarting frequently in the last 15 minutes."

  # Application Alerts — monitors your app
  - name: app-alerts
    rules:

      - alert: AppDown
        expr: up{job="theepicbook-app"} == 0
        for: 2m
        labels:
          severity: critical
          environment: dev
        annotations:
          summary: "TheEpicBook app is down"
          description: "Application has been unreachable for 2 minutes."

      - alert: HighErrorRate
        expr: |
          (sum(rate(http_requests_total{job="theepicbook-app",status=~"5.."}[5m]))
           /
           sum(rate(http_requests_total{job="theepicbook-app"}[5m]))) * 100 > 5
        for: 5m
        labels:
          severity: warning
          environment: dev
        annotations:
          summary: "High error rate on TheEpicBook"
          description: "HTTP 5xx error rate is {{ $value }}% — above 5% for 5 minutes."

  # Prometheus Health — monitors Prometheus itself
  - name: prometheus-alerts
    rules:

      - alert: TargetDown
        expr: up == 0
        for: 5m
        labels:
          severity: warning
          environment: dev
        annotations:
          summary: "Scrape target down: {{ $labels.job }}"
          description: "Prometheus cannot reach {{ $labels.job }} at {{ $labels.instance }}."
```

**Key points:**
- `severity: critical` — serious problems (app down, container crashed)
- `severity: warning` — things to watch (high CPU, high memory)
- `for: 5m` — the problem must last 5 minutes before alerting (avoids false alarms)
- `expr:` — the PromQL query that checks the condition

### 2.3 — alertmanager.yml

This defines **where** to send alerts (Slack).

```yaml
global:
  resolve_timeout: 5m
  slack_api_url: "${SLACK_WEBHOOK_URL}"

route:
  receiver: slack-notifications
  group_by:
    - alertname
    - environment
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

receivers:

  - name: slack-notifications
    slack_configs:
      - channel: "#cloudopshub-alerts"
        send_resolved: true
        title: >
          [{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}
        text: >
          *Environment:* {{ .GroupLabels.environment }}
          *Alert:* {{ range .Alerts }}{{ .Annotations.summary }}{{ end }}
          *Description:* {{ range .Alerts }}{{ .Annotations.description }}{{ end }}
        color: >
          {{ if eq .Status "firing" }}danger{{ else }}good{{ end }}

  - name: slack-critical
    slack_configs:
      - channel: "#cloudopshub-alerts"
        send_resolved: true
        title: >
          [CRITICAL] {{ .GroupLabels.alertname }}
        text: >
          *Environment:* {{ .GroupLabels.environment }}
          *Alert:* {{ range .Alerts }}{{ .Annotations.summary }}{{ end }}
          *Description:* {{ range .Alerts }}{{ .Annotations.description }}{{ end }}
        color: danger

inhibit_rules:
  - source_match:
      severity: critical
    target_match:
      severity: warning
    equal:
      - alertname
      - environment
```

**Key points:**
- `${SLACK_WEBHOOK_URL}` — placeholder. The CD pipeline replaces this with the real URL at deploy time
- `group_wait: 30s` — waits 30 seconds to group similar alerts together
- `repeat_interval: 4h` — re-sends unresolved alerts every 4 hours
- `send_resolved: true` — notifies you when a problem is fixed too
- `inhibit_rules` — if a critical alert fires, it suppresses the matching warning (no spam)

### 2.4 — datasource.yml

This tells Grafana where to get data from.

```yaml
apiVersion: 1

datasources:
  - name:      Prometheus
    type:      prometheus
    access:    proxy
    url:       http://prometheus:9090
    isDefault: true
    editable:  true
    jsonData:
      timeInterval: "15s"
```

**Key points:**
- Grafana connects to Prometheus at `http://prometheus:9090` (Docker internal network)
- `isDefault: true` — this is the main data source
- Auto-provisioned on Grafana startup — no manual clicking needed

---

## Step 3: Add Monitoring Services to docker-compose.yml

Your `gitops/dev/docker-compose.yml` should include these monitoring services alongside your app services:

```yaml
  # ── Prometheus ──────────────────────────────────────────────────
  prometheus:
    image: prom/prometheus:latest
    container_name: theepicbook-prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./monitoring/alert.rules.yml:/etc/prometheus/alert.rules.yml
      - prometheus_data:/prometheus
    networks:
      - theepicbook-network

  # ── Grafana ─────────────────────────────────────────────────────
  grafana:
    image: grafana/grafana:latest
    container_name: theepicbook-grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/datasource.yml:/etc/grafana/provisioning/datasources/datasource.yml
    networks:
      - theepicbook-network

  # ── Node Exporter ───────────────────────────────────────────────
  node-exporter:
    image: prom/node-exporter:latest
    container_name: theepicbook-node-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    networks:
      - theepicbook-network

  # ── Alertmanager ────────────────────────────────────────────────
  alertmanager:
    image: prom/alertmanager:latest
    container_name: theepicbook-alertmanager
    restart: unless-stopped
    ports:
      - "9093:9093"
    volumes:
      - ./monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml
    networks:
      - theepicbook-network
```

**Key points:**
- `${GRAFANA_ADMIN_PASSWORD}` — docker-compose reads this from the `.env` file
- All services are on the same `theepicbook-network` so they can find each other by name
- Config files are mounted as read-only volumes from `./monitoring/`
- No Alpine images needed — these are already minimal (static Go binaries)

Don't forget to add the volumes:

```yaml
volumes:
  prometheus_data:
    driver: local
  grafana_data:
    driver: local
```

---

## Step 4: Set Up Slack Alerts

### 4.1 — Create a Slack Webhook

1. Go to https://api.slack.com/apps
2. Click **Create New App** → **From scratch**
3. Name it `CloudOpsHub Alerts`, pick your workspace
4. In the left menu click **Incoming Webhooks**
5. Toggle **Activate Incoming Webhooks** to ON
6. Click **Add New Webhook to Workspace**
7. Select the channel `#cloudopshub-alerts`
8. Copy the webhook URL (looks like `https://hooks.slack.com/services/T.../B.../xxx...`)

**IMPORTANT: Never share this URL publicly. Treat it like a password.**

### 4.2 — Add GitHub Secrets

Go to your GitHub repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add these 2 secrets:

| Secret name | Value |
|---|---|
| `GRAFANA_ADMIN_PASSWORD` | A strong password you choose (e.g. `MyGrafana2026!`) |
| `SLACK_WEBHOOK_URL` | The webhook URL from step 4.1 |

---

## Step 5: Update the CD Pipeline

Your CD pipeline (`.github/workflows/cd.yml`) needs to do two things before running `docker-compose up`:

1. **Write the Grafana password** to a `.env` file on the VM
2. **Inject the Slack webhook URL** into `alertmanager.yml` (because Alertmanager can't read environment variables)

Add this step in the `argocd-sync` job, before the deploy step:

```yaml
      - name: Write secrets and deploy
        run: |
          gcloud compute ssh ${{ env.VM_NAME }} \
            --zone=${{ env.VM_ZONE }} \
            --project=${{ env.PROJECT_ID }} \
            --tunnel-through-iap \
            --command="
              cd /opt/cloudopshub && \
              git pull origin main && \

              # Write Grafana password to .env
              echo 'GRAFANA_ADMIN_PASSWORD=${{ secrets.GRAFANA_ADMIN_PASSWORD }}' > .env && \
              chmod 600 .env && \

              # Inject Slack webhook into alertmanager config
              sed -i 's|\${SLACK_WEBHOOK_URL}|${{ secrets.SLACK_WEBHOOK_URL }}|g' gitops/dev/monitoring/alertmanager.yml && \

              docker-compose --env-file .env -f gitops/dev/docker-compose.yml pull && \
              docker-compose --env-file .env -f gitops/dev/docker-compose.yml up -d && \
              echo 'Deployment complete'
            "
```

**What this does:**
1. SSHs into the VM through Cloud IAP (the only way in — no public IP)
2. Pulls the latest code from git
3. Creates a `.env` file with the Grafana password (only readable by root)
4. Uses `sed` to replace `${SLACK_WEBHOOK_URL}` in alertmanager.yml with the real URL
5. Pulls new Docker images and starts all containers

---

## Step 6: Deploy

Once everything is committed and merged to `main`:

1. Push your code → CI pipeline runs → CD pipeline triggers
2. CD pipeline deploys app + monitoring together
3. Everything starts automatically

That's it. You don't run anything manually.

---

## Step 7: Verify It Works

After the CD pipeline runs, SSH into the VM to check:

```bash
# SSH into VM via IAP
gcloud compute ssh dev-app-vm \
  --zone=us-central1-a \
  --project=expandox-project-2 \
  --tunnel-through-iap

# Check all containers are running
docker ps

# You should see:
# theepicbook-prometheus    (port 9090)
# theepicbook-grafana       (port 3000)
# theepicbook-alertmanager  (port 9093)
# theepicbook-node-exporter (port 9100)
# theepicbook-app           (port 8080)
# theepicbook-nginx         (port 80)
# theepicbook-mysql         (port 3306)
```

### Check Prometheus Targets

From the VM, run:

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool
```

All targets should show `"health": "up"`.

### Check Grafana

From the VM, run:

```bash
curl -s http://localhost:3000/api/health
```

Should return `{"commit":"...","database":"ok","version":"..."}`.

### Test a Slack Alert

Stop a container to trigger an alert:

```bash
docker stop theepicbook-app
```

Wait 2-3 minutes. You should see an alert in your `#cloudopshub-alerts` Slack channel:

```
[CRITICAL] AppDown

Environment: dev
Alert: TheEpicBook app is down
Description: Application has been unreachable for 2 minutes.
```

Start it back:

```bash
docker start theepicbook-app
```

You'll get a "RESOLVED" message in Slack.

---

## What Gets Monitored — Summary

### Alerts You'll Receive

| Alert | Condition | Severity | When |
|-------|-----------|----------|------|
| HighCPUUsage | CPU > 80% | warning | For 5 minutes |
| HighMemoryUsage | Memory > 85% | warning | For 5 minutes |
| HighDiskUsage | Disk > 85% | warning | For 5 minutes |
| ContainerDown | Container missing | critical | For 1 minute |
| ContainerRestarting | Frequent restarts | warning | For 5 minutes |
| AppDown | App unreachable | critical | For 2 minutes |
| HighErrorRate | 5xx errors > 5% | warning | For 5 minutes |
| TargetDown | Scrape target unreachable | warning | For 5 minutes |

### Service URLs (from inside the VM)

| Service | URL | Login |
|---------|-----|-------|
| Grafana | http://localhost:3000 | admin / your GRAFANA_ADMIN_PASSWORD |
| Prometheus | http://localhost:9090 | No login |
| Alertmanager | http://localhost:9093 | No login |

**Note:** These are only accessible from inside the VM (firewall blocks external access). Use SSH via IAP to reach them.

---

## Deploying to Staging or Production

To replicate this for staging or prod:

1. Copy `gitops/dev/monitoring/` to `gitops/staging/monitoring/` or `gitops/prod/monitoring/`
2. In `prometheus.yml`, change `environment: dev` to `environment: staging` or `environment: prod`
3. In `alert.rules.yml`, change all `environment: dev` labels to match
4. Add environment-specific GitHub Secrets if needed (or reuse the same ones)

---

## Troubleshooting

### "Prometheus target is DOWN"

```bash
# Check if the container is running
docker ps | grep <container-name>

# Check container logs
docker logs theepicbook-prometheus
```

Common causes:
- Container hasn't started yet (wait 30 seconds)
- Container name doesn't match the target in `prometheus.yml`
- App doesn't expose `/metrics` endpoint

### "No alerts in Slack"

```bash
# Check Alertmanager is running
docker logs theepicbook-alertmanager

# Check if webhook URL was injected
docker exec theepicbook-alertmanager cat /etc/alertmanager/alertmanager.yml | grep slack_api_url
```

If you see `${SLACK_WEBHOOK_URL}` instead of a real URL, the `sed` command in the CD pipeline didn't work. Check the pipeline logs.

### "Can't access Grafana"

```bash
# Check Grafana logs
docker logs theepicbook-grafana

# Check if .env was written
cat /opt/cloudopshub/.env
```

If `.env` is missing or empty, the CD pipeline didn't write the secrets. Check the pipeline logs.

---

## File Structure — Final

```
gitops/dev/
├── docker-compose.yml              ← App + monitoring containers
└── monitoring/
    ├── prometheus.yml               ← What to scrape
    ├── alert.rules.yml              ← When to alert
    ├── alertmanager.yml             ← Where to send alerts (Slack)
    └── datasource.yml               ← Connects Grafana to Prometheus

.github/workflows/
└── cd.yml                           ← Deploys everything + injects secrets

GitHub Secrets:
├── GRAFANA_ADMIN_PASSWORD           ← Grafana login password
└── SLACK_WEBHOOK_URL                ← Slack webhook for alerts
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────┐
│              GitHub Repository                   │
│                                                  │
│  Code Push → CI Pipeline → CD Pipeline           │
│                               ↓                  │
│                    SSH via Cloud IAP              │
└───────────────────────┬─────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────┐
│         GCE VM (dev-app-vm)                      │
│         Private IP only — no public access       │
│                                                  │
│  ┌─────────────┐  ┌──────────────┐              │
│  │   nginx:80   │  │  app:8080    │  ← Your App │
│  └─────────────┘  └──────┬───────┘              │
│                          │ /metrics              │
│  ┌───────────────────────▼──────────────────┐   │
│  │         Prometheus :9090                  │   │
│  │  Scrapes metrics every 15s                │   │
│  │  Evaluates alert rules                    │   │
│  └──────┬──────────────────┬────────────────┘   │
│         │                  │                     │
│  ┌──────▼──────┐   ┌──────▼──────────┐         │
│  │ Grafana     │   │ Alertmanager    │         │
│  │ :3000       │   │ :9093           │         │
│  │ Dashboards  │   │     ↓           │         │
│  └─────────────┘   │  Slack Webhook  │         │
│                     └────────────────┘         │
│  ┌─────────────┐                                │
│  │ Node        │                                │
│  │ Exporter    │ ← VM CPU/memory/disk metrics   │
│  │ :9100       │                                │
│  └─────────────┘                                │
└─────────────────────────────────────────────────┘
```
