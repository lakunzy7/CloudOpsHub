# GitHub Secrets Setup for Monitoring

This guide walks you through adding the required GitHub secrets to enable the monitoring stack (Prometheus, Grafana, Alertmanager with Slack notifications).

## Prerequisites

- Access to your GitHub repository: `lakunzy7/CloudOpsHub`
- A Slack workspace where you can create apps
- Administrative access to Slack workspace

---

## Step 1: Create a Slack App and Webhook

### 1.1 Go to Slack App Portal

Open https://api.slack.com/apps in your browser

### 1.2 Create a New App

1. Click **Create New App**
2. Select **From scratch**
3. **App Name:** `CloudOpsHub Alerts`
4. **Pick a workspace:** Select your workspace (e.g., `your-workspace`)
5. Click **Create App**

### 1.3 Enable Incoming Webhooks

1. In the left sidebar, click **Incoming Webhooks**
2. Toggle **Activate Incoming Webhooks** to **ON**
3. Click **Add New Webhook to Workspace**
4. Select channel: **#cloudopshub-alerts** (create this channel if it doesn't exist)
5. Click **Allow**

### 1.4 Copy the Webhook URL

After authorizing, you'll see a new webhook URL listed. It looks like:

```
https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX
```

**⚠️ Keep this URL secret** — it's like a password. Anyone with this URL can post to your Slack channel.

---

## Step 2: Add GitHub Secrets

### 2.1 Navigate to GitHub Secrets

1. Go to your repository: https://github.com/lakunzy7/CloudOpsHub
2. Click **Settings** (top menu)
3. In the left sidebar, click **Secrets and variables**
4. Click **Actions**

### 2.2 Add `GRAFANA_ADMIN_PASSWORD`

1. Click **New repository secret**
2. **Name:** `GRAFANA_ADMIN_PASSWORD`
3. **Value:** Choose a strong password (example: `MyGrafana2026!`)
   - Must contain uppercase, lowercase, numbers, and special characters
   - At least 16 characters recommended
4. Click **Add secret**

### 2.3 Add `SLACK_WEBHOOK_URL`

1. Click **New repository secret** again
2. **Name:** `SLACK_WEBHOOK_URL`
3. **Value:** Paste the webhook URL from Step 1.4 (the full HTTPS URL)
4. Click **Add secret**

---

## Step 3: Verify Secrets are Set

Go back to **Secrets and variables** → **Actions** and confirm you see:

- ✅ `GRAFANA_ADMIN_PASSWORD`
- ✅ `SLACK_WEBHOOK_URL`

(The values are masked for security)

---

## Step 4: Deploy and Test

Once secrets are added, the next code push will:

1. Trigger the CI pipeline
2. CI completes → CD pipeline starts
3. CD injects secrets into configs
4. Docker containers start with monitoring enabled
5. Alerts will post to `#cloudopshub-alerts` in Slack

### Test the Slack Alert

From the VM, stop the app container:

```bash
docker stop theepicbook-app
```

Wait 2-3 minutes. You should see a **[CRITICAL] AppDown** alert in Slack:

```
[CRITICAL] AppDown

Environment: dev
Alert: TheEpicBook app is down
Description: Application has been unreachable for 2 minutes.
```

Restart it:

```bash
docker start theepicbook-app
```

You'll see a **[RESOLVED]** message in Slack.

---

## Troubleshooting

### "I don't see the webhook URL after enabling Incoming Webhooks"

- Refresh the page
- Check that you toggled "Activate Incoming Webhooks" to ON
- Try creating a new webhook again

### "Secrets not working in CD pipeline"

- Verify both secrets are in **Settings** → **Secrets and variables** → **Actions**
- Check the secret names match exactly: `GRAFANA_ADMIN_PASSWORD` and `SLACK_WEBHOOK_URL`
- Check the CD pipeline logs for errors during the "Write secrets and deploy" step

### "No alerts in Slack even though app is down"

- Check Docker logs: `docker logs theepicbook-alertmanager`
- Verify the webhook URL was injected: `docker exec theepicbook-alertmanager cat /etc/alertmanager/alertmanager.yml | grep slack_api_url`
- If you see `${SLACK_WEBHOOK_URL}` instead of a real URL, the `sed` injection failed — check CD pipeline logs

---

## Reference

| Item | Where to Find |
|------|---------------|
| GitHub Secrets | Repo → Settings → Secrets and variables → Actions |
| Slack App Portal | https://api.slack.com/apps |
| Webhook URL | api.slack.com → Your App → Incoming Webhooks |
| Grafana | `http://vm-internal-ip:3000` (admin / your password) |
| Prometheus | `http://vm-internal-ip:9090` |
