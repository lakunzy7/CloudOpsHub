# Monitoring Stack Deployment Checklist

## ✅ Implementation Complete

All monitoring stack components have been configured and are ready to deploy. This checklist guides you through the final deployment steps.

---

## Files Created & Modified

### Configuration Files (12 new files)

```
gitops/dev/monitoring/
  ├── prometheus.yml          ✅ Created
  ├── alert.rules.yml         ✅ Created
  ├── alertmanager.yml        ✅ Created
  └── datasource.yml          ✅ Created

gitops/staging/monitoring/
  ├── prometheus.yml          ✅ Created
  ├── alert.rules.yml         ✅ Created
  ├── alertmanager.yml        ✅ Created
  └── datasource.yml          ✅ Created

gitops/production/monitoring/
  ├── prometheus.yml          ✅ Created
  ├── alert.rules.yml         ✅ Created
  ├── alertmanager.yml        ✅ Created
  └── datasource.yml          ✅ Created
```

### Modified Files (2 files)

```
gitops/base/docker-compose.yml
  ✅ Added 4 monitoring services (prometheus, grafana, alertmanager, node-exporter)
  ✅ Added volume definitions (prometheus_data, grafana_data)

.github/workflows/cd.yml
  ✅ Added secret injection step via SSH
  ✅ Writes GRAFANA_ADMIN_PASSWORD to .env
  ✅ Injects SLACK_WEBHOOK_URL into alertmanager.yml
  ✅ Runs docker-compose with --env-file flag
```

### Documentation Files (4 new files)

```
monitoring/GITHUB_SECRETS_SETUP.md       ✅ Created
monitoring/VERIFICATION_GUIDE.md         ✅ Created
monitoring/IMPLEMENTATION_SUMMARY.md     ✅ Created
MONITORING_DEPLOYMENT_CHECKLIST.md       ✅ Created (this file)
```

---

## Pre-Deployment Checklist

### Step 1: Review Implementation

- [ ] Read `monitoring/IMPLEMENTATION_SUMMARY.md` (5 min overview)
- [ ] Read `monitoring/GITHUB_SECRETS_SETUP.md` (understand Slack setup)
- [ ] Review docker-compose.yml changes (scroll to monitoring section)
- [ ] Review cd.yml changes (secret injection step)

### Step 2: Prepare Slack App

Follow `monitoring/GITHUB_SECRETS_SETUP.md` — Step 1:

- [ ] Go to https://api.slack.com/apps
- [ ] Create new app named "CloudOpsHub Alerts"
- [ ] Enable Incoming Webhooks
- [ ] Create webhook for #cloudopshub-alerts channel
- [ ] Copy webhook URL (starts with `https://hooks.slack.com/...`)
- [ ] Store in safe place (never commit to Git)

### Step 3: Add GitHub Secrets

Follow `monitoring/GITHUB_SECRETS_SETUP.md` — Step 2:

- [ ] Go to GitHub repo Settings → Secrets and variables → Actions
- [ ] Add secret `GRAFANA_ADMIN_PASSWORD` (strong password, e.g., `MyGrafana2026!`)
- [ ] Add secret `SLACK_WEBHOOK_URL` (paste webhook from Step 2)
- [ ] Verify both secrets appear in the list (values masked)

### Step 4: Commit Changes

```bash
# Review what will be committed
git status

# Stage all new monitoring files
git add gitops/*/monitoring/
git add .github/workflows/cd.yml
git add gitops/base/docker-compose.yml
git add monitoring/GITHUB_SECRETS_SETUP.md
git add monitoring/VERIFICATION_GUIDE.md
git add monitoring/IMPLEMENTATION_SUMMARY.md
git add MONITORING_DEPLOYMENT_CHECKLIST.md

# Create commit
git commit -m "feat: implement complete monitoring stack

- Add Prometheus for metrics collection
- Add Grafana for dashboards and visualization
- Add Alertmanager with Slack integration
- Configure for dev, staging, and production environments
- Update CD pipeline to inject secrets and deploy monitoring services
- Include comprehensive documentation and verification guides"

# Push to main (triggers CI/CD)
git push origin main
```

---

## Deployment Process (Automatic)

Once pushed, GitHub Actions will automatically:

```
1. CI Pipeline (2-3 min)
   ├─ Run Snyk security scan
   ├─ Run SonarQube code quality
   ├─ Build Docker images
   ├─ Scan images with Trivy
   └─ Push to Artifact Registry

2. CD Pipeline (3-5 min)
   ├─ Verify images in Artifact Registry
   ├─ SSH to dev VM via Cloud IAP
   ├─ Write secrets to .env
   ├─ Inject Slack webhook via sed
   ├─ Pull new images
   ├─ Start all containers (app + monitoring)
   └─ Deploy complete

3. GitOps Sync (within 60 seconds)
   ├─ GitOps agent detects manifest changes
   ├─ Auto-syncs if any manual updates needed
   └─ All containers running
```

---

## Post-Deployment Verification

After code is pushed and CD pipeline completes (5-10 minutes):

### Quick Check (3 minutes)

```bash
# SSH into VM
gcloud compute ssh dev-app-vm \
  --zone=us-central1-a \
  --project=expadox-lab \
  --tunnel-through-iap

# Check all containers running
docker ps | grep -E "prometheus|grafana|alertmanager|node-exporter|backend|frontend|database"

# Should show 7 containers
# Press Ctrl+C to exit
```

### Full Verification (5 minutes)

Follow `monitoring/VERIFICATION_GUIDE.md`:

```bash
# Step 1: Verify all containers
docker ps

# Step 2: Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep '"health"'

# Step 3: Check Grafana health
curl -s http://localhost:3000/api/health | python3 -m json.tool

# Step 4: Check Slack webhook injected
docker exec theepicbook-alertmanager cat /etc/alertmanager/alertmanager.yml | grep slack_api_url

# Step 5: Test Slack alert
docker stop theepicbook-app
# Wait 2-3 minutes
# Check #cloudopshub-alerts in Slack for [CRITICAL] AppDown alert
docker start theepicbook-app
# Wait a few seconds
# Check Slack for [RESOLVED] message
```

---

## Monitoring Dashboard Access

After deployment:

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | `http://localhost:3000` | admin / your GRAFANA_ADMIN_PASSWORD |
| Prometheus | `http://localhost:9090` | No auth required |
| Alertmanager | `http://localhost:9093` | No auth required |

**Note:** Only accessible from inside the VM (private IP). Use SSH via Cloud IAP to access.

---

## What Gets Monitored Automatically

### VM Metrics (Node Exporter)
- CPU usage
- Memory usage
- Disk usage
- Network I/O
- System load

### Container Health (Prometheus)
- Container startup/restart count
- Container uptime

### Application Metrics (Backend)
- HTTP request count
- HTTP response times
- HTTP error rates (5xx)

### System Health (Prometheus)
- Prometheus scrape success
- Alert rule evaluation
- Target connectivity

---

## Alerts You'll Receive on Slack

### Critical Alerts (Need Immediate Action)

- **[CRITICAL] AppDown** — TheEpicBook app unreachable for 2+ minutes
- **[CRITICAL] ContainerDown** — Container missing for 1+ minute

### Warning Alerts (Should Investigate)

- **[WARNING] HighCPUUsage** — CPU > 80% for 5 minutes
- **[WARNING] HighMemoryUsage** — Memory > 85% for 5 minutes
- **[WARNING] HighDiskUsage** — Disk > 85% for 5 minutes
- **[WARNING] ContainerRestarting** — Frequent container restarts
- **[WARNING] HighErrorRate** — 5xx errors > 5% for 5 minutes
- **[WARNING] TargetDown** — Scrape target unreachable

Each alert includes:
- Environment (dev/staging/production)
- Alert summary
- Detailed description
- Status (firing/resolved)

---

## Troubleshooting Quick Reference

### "Containers won't start"
1. Check CD pipeline logs for errors
2. SSH into VM and check docker logs: `docker logs theepicbook-*`
3. Ensure secrets were injected: `cat .env`

### "Prometheus targets showing DOWN"
1. Check container is running: `docker ps | grep prometheus`
2. Check container logs: `docker logs theepicbook-prometheus`
3. Check prometheus config: `docker exec theepicbook-prometheus cat /etc/prometheus/prometheus.yml`

### "No alerts in Slack"
1. Stop app to trigger alert: `docker stop theepicbook-app`
2. Wait 2-3 minutes
3. Check Slack #cloudopshub-alerts channel
4. Check webhook was injected: `docker exec theepicbook-alertmanager cat /etc/alertmanager/alertmanager.yml | grep slack_api_url`

For detailed troubleshooting, see `monitoring/VERIFICATION_GUIDE.md`.

---

## Next Steps (After Verification)

### Week 1
- [ ] Verify all alerts are working
- [ ] Create Grafana dashboards for visualization
- [ ] Test each alert condition (cpu, memory, errors)
- [ ] Share Grafana link with team

### Week 2
- [ ] Document alert runbooks (what to do when alert fires)
- [ ] Set up on-call rotation for critical alerts
- [ ] Customize alert thresholds based on actual usage

### Week 3
- [ ] Deploy monitoring to staging environment
- [ ] Repeat verification steps for staging
- [ ] Plan production monitoring deployment

---

## Important Reminders

⚠️ **Slack Webhook URL**
- This is sensitive like a password
- Never commit to Git
- Never share publicly
- Only store in GitHub Secrets

⚠️ **Grafana Password**
- Set a strong password (uppercase, lowercase, numbers, special chars)
- Store securely
- Consider rotating after initial setup

⚠️ **Alert Thresholds**
- Current thresholds tuned for small VMs (e2-small, e2-medium)
- May need adjustment as traffic increases
- Monitor false alarm rate and adjust accordingly

---

## Support

Questions or issues? Refer to:

1. **IMPLEMENTATION_SUMMARY.md** — Overview of what was built
2. **GITHUB_SECRETS_SETUP.md** — How to set up Slack integration
3. **VERIFICATION_GUIDE.md** — How to test everything works
4. **MONITORING_SETUP_GUIDE.md** — Original comprehensive guide

---

## Summary

✅ **All monitoring components are configured**
✅ **Docker-compose updated with services**
✅ **CD pipeline updated for secret injection**
✅ **All 3 environments ready to deploy**
✅ **Documentation complete and comprehensive**

**Next Action:** Add GitHub secrets and push to main branch.

Estimated time to full deployment: **10-15 minutes** (including manual Slack app setup)

---
