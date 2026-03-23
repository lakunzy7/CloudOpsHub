#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# GitOps Sync Agent — polls Git, deploys on change
# ═══════════════════════════════════════════════════════════════

REPO_URL="${GITOPS_REPO_URL}"
BRANCH="${GITOPS_BRANCH:-main}"
ENVIRONMENT="${GITOPS_ENVIRONMENT:-dev}"
SYNC_INTERVAL="${GITOPS_SYNC_INTERVAL:-60}"
REPO_DIR="/var/lib/gitops/repo"
STATE_FILE="/var/lib/gitops/last-synced-sha"
COMPOSE_BIN="${COMPOSE_BIN:-/var/lib/toolbox/docker-compose}"
ENV_FILE="/var/lib/cloudopshub/.env"

log() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') [gitops-sync] $*"; }

# Refresh Artifact Registry token before pulling images
refresh_token() {
  local token
  token=$(curl -sf -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | \
    python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])" 2>/dev/null) || return 1
  echo "$token" | docker login -u oauth2accesstoken --password-stdin \
    "https://${REGISTRY_HOST:-us-central1-docker.pkg.dev}" >/dev/null 2>&1
}

# Clone if first run
if [ ! -d "$REPO_DIR/.git" ]; then
  log "Cloning $REPO_URL (branch: $BRANCH)..."
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

mkdir -p "$(dirname "$STATE_FILE")"
log "GitOps sync started (interval: ${SYNC_INTERVAL}s, env: $ENVIRONMENT)"

deploy() {
  cd "$REPO_DIR"

  # Inject slack webhook into alertmanager config
  WEBHOOK_URL=$(grep '^SLACK_WEBHOOK_URL=' "$ENV_FILE" | cut -d= -f2- | tr -d '\n')
  if [ -n "$WEBHOOK_URL" ]; then
    for f in gitops/*/monitoring/alertmanager.yml; do
      [ -f "$f" ] && sed "s|SLACK_WEBHOOK_PLACEHOLDER|$WEBHOOK_URL|g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    done
  fi

  COMPOSE_CMD="$COMPOSE_BIN --env-file $ENV_FILE -f gitops/docker-compose.yml"
  [ -f "gitops/overlays/$ENVIRONMENT/docker-compose.override.yml" ] && \
    COMPOSE_CMD="$COMPOSE_CMD -f gitops/overlays/$ENVIRONMENT/docker-compose.override.yml"

  log "Refreshing registry token..."
  refresh_token || log "WARNING: Token refresh failed"

  log "Pulling images..."
  if ! $COMPOSE_CMD pull 2>&1; then
    log "WARNING: Image pull failed"
    return 1
  fi

  log "Deploying stack..."
  $COMPOSE_CMD up -d --remove-orphans 2>&1
  return 0
}

# Initial deploy
log "Running initial deployment..."
deploy || log "Initial deploy incomplete — will retry"

# Sync loop
while true; do
  sleep "$SYNC_INTERVAL"
  cd "$REPO_DIR"

  if ! git fetch origin "$BRANCH" --depth 1 2>/dev/null; then
    log "WARNING: git fetch failed"
    continue
  fi

  REMOTE_SHA=$(git rev-parse "origin/$BRANCH")
  LOCAL_SHA=$(cat "$STATE_FILE" 2>/dev/null || echo "none")

  [ "$REMOTE_SHA" = "$LOCAL_SHA" ] && continue

  log "Change detected: ${LOCAL_SHA:0:8} -> ${REMOTE_SHA:0:8}"

  # Only redeploy if gitops/ or monitoring/ changed
  if [ "$LOCAL_SHA" != "none" ]; then
    CHANGED=$(git diff --name-only "$LOCAL_SHA" "$REMOTE_SHA" -- gitops/ monitoring/ 2>/dev/null || echo "gitops/")
  else
    CHANGED="gitops/"
  fi

  if [ -z "$CHANGED" ]; then
    log "No gitops changes, updating SHA only"
    echo "$REMOTE_SHA" > "$STATE_FILE"
    continue
  fi

  log "Relevant files changed — redeploying..."
  git reset --hard "origin/$BRANCH"

  if deploy; then
    log "Sync successful ($REMOTE_SHA)"
    echo "$REMOTE_SHA" > "$STATE_FILE"
  else
    log "Deploy failed, will retry next cycle"
  fi
done
