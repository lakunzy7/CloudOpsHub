#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# CloudOpsHub VM Bootstrap — ${environment}
# ═══════════════════════════════════════════════════════════════
# 1. Install Docker Compose
# 2. Authenticate to Artifact Registry
# 3. Fetch secrets → write .env
# 4. Clone repo & start GitOps sync (systemd)
# ═══════════════════════════════════════════════════════════════

echo "=== CloudOpsHub Bootstrap - ${environment} ==="

# ── 1. Install Docker Compose ──
COMPOSE_BIN="/var/lib/toolbox/docker-compose"
if [ ! -f "$COMPOSE_BIN" ]; then
  echo "Installing Docker Compose..."
  mkdir -p /var/lib/toolbox
  curl -SL "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64" \
    -o "$COMPOSE_BIN"
  chmod +x "$COMPOSE_BIN"
fi
export PATH="/var/lib/toolbox:$PATH"

# ── Helper: get metadata access token ──
get_token() {
  curl -sf -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | \
    python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])"
}

# ── Helper: fetch secret from Secret Manager ──
get_secret() {
  local token="$1" secret_id="$2"
  curl -sf \
    -H "Authorization: Bearer $token" \
    "https://secretmanager.googleapis.com/v1/projects/${project_id}/secrets/$secret_id/versions/latest:access" | \
    python3 -c "import sys,json,base64;print(base64.b64decode(json.load(sys.stdin)['payload']['data']).decode())"
}

# ── 2. Authenticate to Artifact Registry ──
echo "Authenticating to Artifact Registry..."
ACCESS_TOKEN=$(get_token)
export HOME=/var/lib
mkdir -p /var/lib/.docker
echo "$ACCESS_TOKEN" | docker login -u oauth2accesstoken --password-stdin https://${registry_host}

# ── 3. Fetch secrets and write .env ──
echo "Fetching secrets..."
DB_PASSWORD=$(get_secret "$ACCESS_TOKEN" "${db_password_secret}")
GRAFANA_PASSWORD=$(get_secret "$ACCESS_TOKEN" "${grafana_secret}")
SLACK_WEBHOOK=$(get_secret "$ACCESS_TOKEN" "${slack_secret}")

ENV_DIR="/var/lib/cloudopshub"
mkdir -p "$ENV_DIR"

cat > "$ENV_DIR/.env" <<ENVEOF
DATABASE_URL=mysql://appuser:$DB_PASSWORD@database:3306/bookstore
DB_ROOT_PASSWORD=${db_password}
DB_PASSWORD=${db_password}
NODE_ENV=${environment}
PORT=8080
REGISTRY=${region}-docker.pkg.dev/${project_id}/${project_name}-docker
GRAFANA_ADMIN_PASSWORD=$GRAFANA_PASSWORD
SLACK_WEBHOOK_URL=$SLACK_WEBHOOK
GITOPS_ENV=${environment}
ENVEOF
chmod 600 "$ENV_DIR/.env"

# ── 4. Clone repo & set up GitOps sync as systemd service ──
echo "Setting up GitOps sync..."
GITOPS_DIR="/var/lib/gitops"
REPO_DIR="$GITOPS_DIR/repo"
mkdir -p "$GITOPS_DIR"

if [ ! -d "$REPO_DIR/.git" ]; then
  git clone --depth 1 --branch main "https://github.com/${github_repo}.git" "$REPO_DIR"
fi

cp "$REPO_DIR/scripts/gitops-sync.sh" "$GITOPS_DIR/gitops-sync.sh"
chmod +x "$GITOPS_DIR/gitops-sync.sh"

cat > /etc/systemd/system/gitops-sync.service <<'SVCEOF'
[Unit]
Description=GitOps Sync Agent
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=10
Environment=GITOPS_REPO_URL=https://github.com/${github_repo}.git
Environment=GITOPS_BRANCH=main
Environment=GITOPS_ENVIRONMENT=${environment}
Environment=GITOPS_SYNC_INTERVAL=60
Environment=COMPOSE_BIN=/var/lib/toolbox/docker-compose
Environment=REGISTRY_HOST=${registry_host}
Environment=GCP_PROJECT_ID=${project_id}
Environment=PATH=/var/lib/toolbox:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/bin/bash /var/lib/gitops/gitops-sync.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable --now gitops-sync.service

echo "=== Bootstrap complete ==="
