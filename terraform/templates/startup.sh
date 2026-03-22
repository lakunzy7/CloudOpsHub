#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# CloudOpsHub VM Bootstrap — ${environment}
# ═══════════════════════════════════════════════════════════════════
# This script ONLY bootstraps the VM. It does NOT deploy the app,
# configure monitoring, or manage services. That's the GitOps
# agent's job — Git is our single source of truth.
#
# Responsibilities:
#   1. Install Docker Compose
#   2. Authenticate to Artifact Registry
#   3. Fetch secrets from GCP Secret Manager
#   4. Write .env file for Docker Compose
#   5. Clone repo & start GitOps sync agent
#
# Everything else (app, monitoring, config) is managed via Git
# in gitops/base/docker-compose.yml and monitoring/ configs.
# ═══════════════════════════════════════════════════════════════════

echo "=== CloudOpsHub VM Bootstrap - ${environment} ==="

# ── 1. Install Docker Compose (COS: /usr is read-only) ──
COMPOSE_BIN="/var/lib/toolbox/docker-compose"
if [ ! -f "$COMPOSE_BIN" ]; then
  echo "Installing Docker Compose..."
  DOCKER_COMPOSE_VERSION="v2.24.0"
  mkdir -p /var/lib/toolbox
  curl -SL "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    -o "$COMPOSE_BIN"
  chmod +x "$COMPOSE_BIN"
fi
export PATH="/var/lib/toolbox:$PATH"

# ── Helper: parse JSON field (COS has no jq) ──
json_field() {
  python3 -c "import sys,json;print(json.load(sys.stdin)['$1'])"
}

# ── 2. Authenticate to Artifact Registry ──
echo "Authenticating to Artifact Registry..."
ACCESS_TOKEN=$(curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | json_field access_token)

export HOME=/var/lib
mkdir -p /var/lib/.docker
echo "$ACCESS_TOKEN" | docker login -u oauth2accesstoken --password-stdin https://${registry_host}

# ── 3. Fetch secrets from GCP Secret Manager ──
echo "Fetching secrets from GCP Secret Manager..."
DATABASE_URL=$(curl -sf \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://secretmanager.googleapis.com/v1/projects/${project_id}/secrets/${db_secret_name}/versions/latest:access" | \
  python3 -c "import sys,json,base64;print(base64.b64decode(json.load(sys.stdin)['payload']['data']).decode())")

GRAFANA_PASSWORD=$(curl -sf \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://secretmanager.googleapis.com/v1/projects/${project_id}/secrets/${grafana_secret_name}/versions/latest:access" | \
  python3 -c "import sys,json,base64;print(base64.b64decode(json.load(sys.stdin)['payload']['data']).decode())")

SLACK_WEBHOOK_URL=$(curl -sf \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://secretmanager.googleapis.com/v1/projects/${project_id}/secrets/${slack_secret_name}/versions/latest:access" | \
  python3 -c "import sys,json,base64;print(base64.b64decode(json.load(sys.stdin)['payload']['data']).decode())")

# ── 4. Write .env file (consumed by docker-compose from Git) ──
echo "Writing environment file..."
ENV_DIR="/var/lib/cloudopshub"
mkdir -p "$ENV_DIR"

cat > "$ENV_DIR/.env" <<ENVEOF
DATABASE_URL=$DATABASE_URL
REGISTRY=${registry_url}
NODE_ENV=${environment}
PORT=8080
GRAFANA_ADMIN_PASSWORD=$GRAFANA_PASSWORD
DB_ROOT_PASSWORD=${db_password}
DB_PASSWORD=${db_password}
SLACK_WEBHOOK_URL=$SLACK_WEBHOOK_URL
ENVEOF
chmod 600 "$ENV_DIR/.env"

# ── 5. Clone repo & start GitOps sync agent ──
echo "Setting up GitOps sync agent..."
GITOPS_DIR="/var/lib/gitops"
mkdir -p "$GITOPS_DIR"

cat > "$GITOPS_DIR/gitops-sync.sh" <<'GSEOF'
#!/bin/bash
set -euo pipefail

REPO_URL="$${GITOPS_REPO_URL}"
BRANCH="$${GITOPS_BRANCH:-main}"
ENVIRONMENT="$${GITOPS_ENVIRONMENT:-dev}"
SYNC_INTERVAL="$${GITOPS_SYNC_INTERVAL:-60}"
REPO_DIR="/var/lib/gitops/repo"
STATE_FILE="/var/lib/gitops/last-synced-sha"
COMPOSE_BIN="$${COMPOSE_BIN:-/var/lib/toolbox/docker-compose}"
ENV_FILE="/var/lib/cloudopshub/.env"
LOG_PREFIX="[gitops-sync]"

log() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $LOG_PREFIX $*"; }

# Initial clone
if [ ! -d "$REPO_DIR/.git" ]; then
  log "Cloning $REPO_URL (branch: $BRANCH)..."
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

mkdir -p "$(dirname "$STATE_FILE")"
log "GitOps sync started (interval: $${SYNC_INTERVAL}s, env: $ENVIRONMENT)"
log "Source of truth: $REPO_URL (branch: $BRANCH)"

deploy() {
  cd "$REPO_DIR"

  # Inject secrets into monitoring configs (git working tree only, reset on next pull)
  WEBHOOK_URL=$(grep '^SLACK_WEBHOOK_URL=' "$$ENV_FILE" | cut -d= -f2- | tr -d '\n')
  if [ -n "$$WEBHOOK_URL" ]; then
    for f in gitops/*/monitoring/alertmanager.yml; do
      [ -f "$f" ] && sed "s|\${SLACK_WEBHOOK_URL}|$$WEBHOOK_URL|g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    done
  fi

  # App stack from gitops/
  COMPOSE_BASE="gitops/base/docker-compose.yml"
  COMPOSE_OVERRIDE="gitops/overlays/$ENVIRONMENT/docker-compose.override.yml"
  COMPOSE_CMD="$COMPOSE_BIN --env-file $ENV_FILE -f $COMPOSE_BASE"
  [ -f "$COMPOSE_OVERRIDE" ] && COMPOSE_CMD="$COMPOSE_CMD -f $COMPOSE_OVERRIDE"

  log "Pulling app images..."
  if ! $COMPOSE_CMD pull 2>&1; then
    log "WARNING: App image pull failed (may not be in registry yet)"
    return 1
  fi

  log "Deploying full stack (app + monitoring)..."
  $COMPOSE_CMD up -d --remove-orphans 2>&1

  return 0
}

# First deploy attempt
log "Running initial deployment..."
deploy || log "Initial deploy incomplete — will retry on next cycle"

# Sync loop
while true; do
  cd "$REPO_DIR"

  if ! git fetch origin "$BRANCH" --depth 1 2>/dev/null; then
    log "WARNING: git fetch failed, retrying next cycle"
    sleep "$SYNC_INTERVAL"
    continue
  fi

  REMOTE_SHA=$(git rev-parse "origin/$BRANCH")
  LOCAL_SHA=$(cat "$STATE_FILE" 2>/dev/null || echo "none")

  if [ "$REMOTE_SHA" = "$LOCAL_SHA" ]; then
    sleep "$SYNC_INTERVAL"
    continue
  fi

  log "Change detected: $${LOCAL_SHA:0:8} -> $${REMOTE_SHA:0:8}"

  # Check if relevant files changed
  if [ "$LOCAL_SHA" != "none" ]; then
    CHANGED=$(git diff --name-only "$LOCAL_SHA" "$REMOTE_SHA" -- gitops/ monitoring/ 2>/dev/null || echo "gitops/")
  else
    CHANGED="gitops/"
  fi

  if [ -z "$CHANGED" ]; then
    log "No gitops/monitoring changes, updating SHA only"
    echo "$REMOTE_SHA" > "$STATE_FILE"
    sleep "$SYNC_INTERVAL"
    continue
  fi

  log "Files changed — redeploying..."
  git reset --hard "origin/$BRANCH"

  if deploy; then
    log "Sync successful ($REMOTE_SHA)"
    echo "$REMOTE_SHA" > "$STATE_FILE"
  else
    log "Deploy failed, will retry next cycle"
  fi

  sleep "$SYNC_INTERVAL"
done
GSEOF
chmod +x "$GITOPS_DIR/gitops-sync.sh"

# Start GitOps sync agent as a Docker container
echo "Starting GitOps sync agent..."
docker run -d \
  --name gitops-sync \
  --restart unless-stopped \
  --entrypoint "" \
  -e GITOPS_REPO_URL="https://github.com/${github_repo}.git" \
  -e GITOPS_BRANCH="main" \
  -e GITOPS_ENVIRONMENT="${environment}" \
  -e GITOPS_SYNC_INTERVAL="60" \
  -e COMPOSE_BIN="/var/lib/toolbox/docker-compose" \
  -v "$GITOPS_DIR:/var/lib/gitops" \
  -v "$ENV_DIR/.env:/var/lib/cloudopshub/.env:ro" \
  -v /var/lib/toolbox/docker-compose:/var/lib/toolbox/docker-compose:ro \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/lib/.docker/config.json:/root/.docker/config.json:ro \
  alpine/git:latest \
  sh -c 'apk add --no-cache bash curl docker-cli >/dev/null 2>&1 && bash /var/lib/gitops/gitops-sync.sh'

# ── 6. Token refresh loop (systemd service for persistence) ──
echo "Setting up Artifact Registry token refresh service..."
cat > /etc/systemd/system/ar-token-refresh.service <<'SVCEOF'
[Unit]
Description=Artifact Registry Token Refresh
After=docker.service

[Service]
Type=simple
Restart=always
RestartSec=30
ExecStart=/bin/bash -c 'while true; do sleep 2700; TOKEN=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | python3 -c "import sys,json;print(json.load(sys.stdin)[\"access_token\"])"); if [ -n "$TOKEN" ]; then echo "$TOKEN" | docker login -u oauth2accesstoken --password-stdin https://us-central1-docker.pkg.dev >/dev/null 2>&1; fi; done'

[Install]
WantedBy=multi-user.target
SVCEOF
systemctl daemon-reload
systemctl enable --now ar-token-refresh.service

echo "=== Bootstrap complete ==="
echo "The GitOps agent will now manage all deployments from Git."
echo "Git is the single source of truth."
