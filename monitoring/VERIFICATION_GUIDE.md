# Monitoring Stack Verification Guide

This guide walks you through verifying that the monitoring stack is deployed and working correctly.

---

## Prerequisites

- Dev environment is running (VM is live)
- Secrets are added to GitHub (GRAFANA_ADMIN_PASSWORD, SLACK_WEBHOOK_URL)
- CD pipeline has completed successfully
- You have SSH access to the VM via Cloud IAP

---

## Step 1: SSH into the VM

From your local machine:

```bash
gcloud compute ssh dev-app-vm \
  --zone=us-central1-a \
  --project=expadox-lab \
  --tunnel-through-iap
```

This connects you to the VM through Cloud IAP (no public IP needed).

---

## Step 2: Verify All Containers are Running

```bash
docker ps
```

You should see **7 containers**:

```
CONTAINER ID   IMAGE                                                    STATUS              NAMES
xxx            prom/prometheus:latest                                   Up X minutes        theepicbook-prometheus
xxx            grafana/grafana:latest                                   Up X minutes        theepicbook-grafana
xxx            prom/alertmanager:latest                                 Up X minutes        theepicbook-alertmanager
xxx            prom/node-exporter:latest                                Up X minutes        theepicbook-node-exporter
xxx            us-central1-docker.pkg.dev/.../theepicbook-backend      Up X minutes        backend
xxx            us-central1-docker.pkg.dev/.../theepicbook-frontend     Up X minutes        frontend
xxx            us-central1-docker.pkg.dev/.../theepicbook-database     Up X minutes        database
```

### If a container is missing or failing:

```bash
# Check logs
docker logs theepicbook-prometheus
docker logs theepicbook-grafana
docker logs theepicbook-alertmanager
```

**Common issues:**

- `Port already in use` → Check if another process is using the port: `sudo lsof -i :9090`
- `Config file not found` → Check volume mounts in docker-compose.yml
- `Permission denied` → Check file permissions: `ls -la gitops/dev/monitoring/`

---

## Step 3: Verify Prometheus Targets

Prometheus should have 3 scrape targets healthy.

### Option A: Check via HTTP API

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | head -50
```

Look for this structure:

```json
{
  "status": "success",
  "data": {
    "activeTargets": [
      {
        "labels": {
          "job": "prometheus",
          "instance": "localhost:9090"
        },
        "lastError": "",
        "lastScrapeTime": "...",
        "health": "up"
      },
      {
        "labels": {
          "job": "node-exporter",
          "instance": "dev-app-vm"
        },
        "health": "up"
      },
      {
        "labels": {
          "job": "theepicbook-app",
          "instance": "theepicbook-app"
        },
        "health": "up"
      }
    ]
  }
}
```

**All targets should have `"health": "up"`**

### Option B: Check via Prometheus UI

From inside the VM:

```bash
# Get Prometheus status
curl -s http://localhost:9090/api/v1/status/tsdb | python3 -m json.tool
```

---

## Step 4: Verify Grafana is Healthy

```bash
curl -s http://localhost:3000/api/health
```

You should see:

```json
{
  "commit": "...",
  "database": "ok",
  "version": "..."
}
```

### Verify Datasource is Auto-Provisioned

```bash
curl -s http://localhost:3000/api/datasources \
  -H "Authorization: Bearer admin"
```

You should see a Prometheus datasource with `"type":"prometheus"`.

---

## Step 5: Verify Alertmanager is Running

```bash
curl -s http://localhost:9093/api/v1/status | python3 -m json.tool
```

You should see configuration details with your cluster name.

### Verify Slack Webhook Was Injected

```bash
docker exec theepicbook-alertmanager cat /etc/alertmanager/alertmanager.yml | grep slack_api_url
```

You should see:

```
slack_api_url: https://hooks.slack.com/services/T.../B.../xxx...
```

**NOT**:

```
slack_api_url: ${SLACK_WEBHOOK_URL}
```

If you see the placeholder, the `sed` injection in the CD pipeline failed. Check GitHub Actions logs.

---

## Step 6: Test Prometheus Scraping

### Check if Prometheus has collected metrics:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool
```

You should see metrics for `job="prometheus"`, `job="node-exporter"`, and `job="theepicbook-app"`.

Example:

```json
{
  "status": "success",
  "data": {
    "resultType": "vector",
    "result": [
      {
        "metric": {
          "__name__": "up",
          "job": "prometheus",
          "instance": "localhost:9090"
        },
        "value": [1234567890, "1"]
      },
      {
        "metric": {
          "__name__": "up",
          "job": "node-exporter",
          "instance": "dev-app-vm"
        },
        "value": [1234567890, "1"]
      }
    ]
  }
}
```

---

## Step 7: Test Slack Alerts

### Manually trigger an alert by stopping the app:

```bash
docker stop theepicbook-app
```

Wait **2-3 minutes** (the alert rule has a 2-minute threshold).

### Check your Slack workspace

Go to `#cloudopshub-alerts` channel. You should see:

```
[CRITICAL] AppDown

Environment: dev
Alert: TheEpicBook app is down
Description: Application has been unreachable for 2 minutes.
```

### If no Slack alert appears:

Check Alertmanager logs:

```bash
docker logs theepicbook-alertmanager
```

Check if the webhook URL is correct:

```bash
docker exec theepicbook-alertmanager cat /etc/alertmanager/alertmanager.yml | grep slack_api_url
```

### Restart the app and verify "RESOLVED" alert:

```bash
docker start theepicbook-app
```

Wait a few seconds. In Slack, you should see:

```
[RESOLVED] AppDown

Environment: dev
Alert: TheEpicBook app is down
Description: Application has been unreachable for 2 minutes.
```

---

## Step 8: Full Health Check Script

Run this script to verify everything in one go:

```bash
#!/bin/bash

echo "=== Checking running containers ==="
docker ps | grep -E "prometheus|grafana|alertmanager|node-exporter|backend|frontend|database"

echo ""
echo "=== Checking Prometheus targets ==="
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -A 2 '"health"'

echo ""
echo "=== Checking Grafana health ==="
curl -s http://localhost:3000/api/health | python3 -m json.tool | grep -E 'database|version'

echo ""
echo "=== Checking Alertmanager status ==="
curl -s http://localhost:9093/api/v1/status | python3 -m json.tool | grep -E 'cluster|config'

echo ""
echo "=== Checking Slack webhook injection ==="
docker exec theepicbook-alertmanager cat /etc/alertmanager/alertmanager.yml | grep slack_api_url

echo ""
echo "=== Checking for collected metrics ==="
curl -s 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool | grep -A 2 '"job"'
```

Save as `verify.sh` and run:

```bash
bash verify.sh
```

---

## Monitoring URLs

Once verified, you can access services from inside the VM:

| Service | URL | Access |
|---------|-----|--------|
| Grafana | `http://localhost:3000` | Login with admin / `GRAFANA_ADMIN_PASSWORD` |
| Prometheus | `http://localhost:9090` | No auth |
| Alertmanager | `http://localhost:9093` | No auth |

**Note:** These are only accessible from inside the VM (firewall blocks external access). Use SSH via Cloud IAP to reach them.

---

## Troubleshooting Checklist

| Issue | Solution |
|-------|----------|
| Prometheus targets DOWN | Check container logs: `docker logs theepicbook-prometheus` |
| No Prometheus metrics | Verify app is running and exposes `/metrics` |
| Grafana won't start | Check `.env` file has GRAFANA_ADMIN_PASSWORD: `cat .env` |
| Grafana datasource missing | Check volume mount for datasource.yml in docker-compose.yml |
| Alertmanager not sending alerts | Check Slack webhook URL was injected: `docker exec theepicbook-alertmanager cat /etc/alertmanager/alertmanager.yml` |
| Slack shows `${SLACK_WEBHOOK_URL}` | The `sed` injection in CD pipeline failed — check GitHub Actions logs |
| Container port conflicts | List port usage: `sudo lsof -i :9090` (or :3000, :9093, :9100) |

---

## Next Steps

After verification:

1. **Create Grafana dashboards** to visualize metrics
2. **Test each alert** by triggering conditions (stop containers, high CPU)
3. **Document alert runbooks** — what to do when each alert fires
4. **Replicate to staging** by copying `gitops/dev/monitoring/` to `gitops/staging/monitoring/`

---
