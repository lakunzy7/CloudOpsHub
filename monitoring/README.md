# CloudOpsHub Monitoring Stack

Complete monitoring solution for Docker-based infrastructure with Prometheus, Grafana, Alertmanager, and Slack notifications.

---

## 📋 Quick Start

**Status:** ✅ Implementation complete and ready to deploy

**Time to full deployment:** 15-30 minutes

### 1. Read This First
👉 **[MONITORING_DEPLOYMENT_CHECKLIST.md](../MONITORING_DEPLOYMENT_CHECKLIST.md)** (5 min)
- Overview of what's implemented
- Step-by-step deployment checklist
- Quick reference for troubleshooting

### 2. Set Up Slack (Manual - 5-10 min)
👉 **[GITHUB_SECRETS_SETUP.md](./GITHUB_SECRETS_SETUP.md)**
- Create Slack app at api.slack.com
- Generate webhook for #cloudopshub-alerts
- Add GitHub secrets

### 3. Deploy (Automatic - 5-10 min)
- Commit and push monitoring changes to main branch
- CI/CD pipeline automatically deploys to VM
- Secrets are injected at deploy time

### 4. Verify (Manual - 5 min)
👉 **[VERIFICATION_GUIDE.md](./VERIFICATION_GUIDE.md)**
- Run health check commands
- Test Slack alerts
- Confirm monitoring is working

---

## 📚 Documentation Files

| Document | Purpose |
|----------|---------|
| **MONITORING_DEPLOYMENT_CHECKLIST.md** | START HERE — deployment steps and checklist |
| **IMPLEMENTATION_SUMMARY.md** | Complete technical overview of implementation |
| **GITHUB_SECRETS_SETUP.md** | How to create Slack app and add GitHub secrets |
| **VERIFICATION_GUIDE.md** | How to test and verify deployment |
| **MONITORING_SETUP_GUIDE.md** | Original comprehensive technical guide |
| **README.md** | This file — index of all documentation |

---

## 🏗️ Architecture

```
GitHub Repo
    ↓
CI Pipeline (build, test, scan)
    ↓
CD Pipeline (secret injection + deploy)
    ↓
GCE VM (dev-app-vm)
    ├─ Prometheus :9090 (metrics collection)
    ├─ Grafana :3000 (dashboards)
    ├─ Alertmanager :9093 (alert routing)
    ├─ Node Exporter :9100 (VM metrics)
    ├─ Backend :8080 (/metrics endpoint)
    ├─ Frontend :80 (reverse proxy)
    └─ Database (MySQL)
         ↓
    Slack #cloudopshub-alerts (notifications)
```

---

## 📊 What Gets Monitored

### VM Health (via Node Exporter)
- CPU usage
- Memory usage
- Disk usage
- System load

### Application Health
- HTTP request count
- HTTP response times
- HTTP error rates (5xx)
- Uptime

### Container Health
- Container startup/restart counts
- Container uptime

### System Health
- Prometheus scrape success
- Alert rule evaluation
- Target connectivity

---

## 🎯 Alert Types

### Critical Alerts (Need Immediate Action)
- **AppDown** — App unreachable for 2+ minutes
- **ContainerDown** — Container missing for 1+ minute

### Warning Alerts (Should Investigate)
- **HighCPUUsage** — CPU > 80% for 5 minutes
- **HighMemoryUsage** — Memory > 85% for 5 minutes
- **HighDiskUsage** — Disk > 85% for 5 minutes
- **ContainerRestarting** — Frequent container restarts
- **HighErrorRate** — 5xx errors > 5% for 5 minutes
- **TargetDown** — Scrape target unreachable for 5 minutes

All alerts post to Slack with:
- Environment label (dev/staging/production)
- Alert summary
- Detailed description
- Status (firing/resolved)

---

## 🔧 Components

| Component | Port | Purpose |
|-----------|------|---------|
| **Prometheus** | 9090 | Metrics collection, alert evaluation |
| **Grafana** | 3000 | Dashboards, visualization |
| **Alertmanager** | 9093 | Alert routing to Slack |
| **Node Exporter** | 9100 | VM metrics (CPU, memory, disk) |

---

## 📁 Configuration Files

All monitoring configuration files are in `gitops/{env}/monitoring/`:

```
gitops/dev/monitoring/
├── prometheus.yml       — Scrape targets, alert rules
├── alert.rules.yml      — Alert conditions (8 rules)
├── alertmanager.yml     — Slack routing, grouping
└── datasource.yml       — Grafana Prometheus config

gitops/staging/monitoring/
├── prometheus.yml
├── alert.rules.yml
├── alertmanager.yml
└── datasource.yml

gitops/production/monitoring/
├── prometheus.yml
├── alert.rules.yml
├── alertmanager.yml
└── datasource.yml
```

---

## 🚀 Deployment

### Prerequisites
- Slack workspace (for creating app)
- GitHub repository access
- GCP project with VM already running

### Steps

1. **Create Slack app** (5-10 min)
   - Go to https://api.slack.com/apps
   - Create "CloudOpsHub Alerts" app
   - Enable Incoming Webhooks
   - Generate webhook for #cloudopshub-alerts channel

2. **Add GitHub secrets** (2-3 min)
   - `GRAFANA_ADMIN_PASSWORD` (strong password)
   - `SLACK_WEBHOOK_URL` (from Slack app)

3. **Deploy** (automatic, 5-10 min)
   - Commit and push to main branch
   - CI/CD pipeline runs automatically
   - Monitoring stack deployed to VM

4. **Verify** (5 min)
   - SSH to VM
   - Run health checks
   - Test Slack alerts

---

## 🧪 Testing

### Quick Test (1 minute)

```bash
# SSH to VM
gcloud compute ssh dev-app-vm \
  --zone=us-central1-a \
  --project=expadox-lab \
  --tunnel-through-iap

# Check all containers running
docker ps | wc -l
# Should show 7 containers
```

### Full Test (3-5 minutes)

```bash
# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep '"health"'

# Check Grafana
curl -s http://localhost:3000/api/health | python3 -m json.tool

# Test Slack alert
docker stop theepicbook-app
# Wait 2-3 minutes, check Slack #cloudopshub-alerts
docker start theepicbook-app
```

See **VERIFICATION_GUIDE.md** for detailed testing steps.

---

## 🔐 Security

✅ **Secrets Management**
- Passwords/webhooks stored in GitHub Secrets (masked)
- Secrets injected at deploy time
- Never stored in Git or container images

✅ **Network Security**
- Monitoring services on internal network only
- No public IP exposure
- Cloud IAP required for SSH access
- Firewall allows monitoring ports only internally

✅ **Data Protection**
- Metrics stored in Docker volumes (not Git)
- Alert history in Prometheus time-series DB
- No sensitive data in logs

---

## 📊 Environments

Monitoring configured for all 3 environments:

| Environment | Config Path | Instance | Database |
|-------------|------------|----------|----------|
| Dev | gitops/dev/monitoring/ | e2-small | db-f1-micro |
| Staging | gitops/staging/monitoring/ | e2-medium | db-g1-small |
| Production | gitops/production/monitoring/ | e2-standard | db-g1-small |

Each environment has:
- Separate Prometheus config (environment-specific labels)
- Separate alert rules (environment tag)
- Same alert conditions (tunable thresholds)
- Shared Slack channel (#cloudopshub-alerts)

---

## 🛠️ Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Containers won't start | Check CD pipeline logs for secret errors |
| Prometheus targets DOWN | Check container logs: `docker logs theepicbook-prometheus` |
| No Slack alerts | Verify webhook injected: `docker exec theepicbook-alertmanager cat /etc/alertmanager/alertmanager.yml` |
| Can't access Grafana | Check `.env` file: `cat .env` |

See **VERIFICATION_GUIDE.md** for detailed troubleshooting with example commands.

---

## 📈 Next Steps

### Week 1
- [ ] Deploy monitoring to dev environment
- [ ] Verify all alerts working
- [ ] Test each alert condition

### Week 2
- [ ] Create Grafana dashboards
- [ ] Document alert runbooks
- [ ] Set up on-call rotation

### Week 3
- [ ] Deploy to staging environment
- [ ] Customize alert thresholds
- [ ] Plan production deployment

---

## 📖 Full Documentation

- **monitoring/MONITORING_SETUP_GUIDE.md** — Original comprehensive technical guide (detailed explanations)
- **MONITORING_DEPLOYMENT_CHECKLIST.md** — Step-by-step deployment checklist (what to do)
- **monitoring/IMPLEMENTATION_SUMMARY.md** — Technical implementation details
- **monitoring/GITHUB_SECRETS_SETUP.md** — Slack integration setup
- **monitoring/VERIFICATION_GUIDE.md** — Testing and verification steps

---

## 🤝 Support

Questions? Check:

1. Relevant documentation file (above)
2. **VERIFICATION_GUIDE.md** troubleshooting section
3. Container logs: `docker logs theepicbook-*`
4. Alertmanager config: `docker exec theepicbook-alertmanager cat /etc/alertmanager/alertmanager.yml`

---

## Summary

✅ **Implementation:** Complete
✅ **Documentation:** Comprehensive
✅ **Ready to deploy:** Yes

**Next action:** Follow MONITORING_DEPLOYMENT_CHECKLIST.md

---

Last updated: 2026-03-21
