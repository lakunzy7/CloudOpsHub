#!/bin/bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════
# GitOps Sync Agent — Git is the single source of truth
# ═══════════════════════════════════════════════════════════════════
# Polls the Git repo for changes to gitops/ or monitoring/ configs.
# When a change is detected, pulls new images and redeploys.
#
# Everything deployed on the VM comes from Git:
#   - gitops/base/docker-compose.yml  → app + monitoring services
#   - gitops/overlays/{env}/          → environment overrides
#   - monitoring/                     → Prometheus, Grafana, alerts config
# ═══════════════════════════════════════════════════════════════════

REPO_URL="${GITOPS_REPO_URL}"
BRANCH="${GITOPS_BRANCH:-main}"
ENVIRONMENT="${GITOPS_ENVIRONMENT:-dev}"
SYNC_INTERVAL="${GITOPS_SYNC_INTERVAL:-60}"
REPO_DIR="/var/lib/gitops/repo"
STATE_FILE="/var/lib/gitops/last-synced-sha"
COMPOSE_BIN="${COMPOSE_BIN:-/var/lib/toolbox/docker-compose}"
ENV_FILE="/var/lib/cloudopshub/.env"
LOG_PREFIX="[gitops-sync]"

log() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') ${LOG_PREFIX} $*"; }

# Initial clone
if [ ! -d "$REPO_DIR/.git" ]; then
  log "Cloning $REPO_URL (branch: $BRANCH)..."
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

mkdir -p "$(dirname "$STATE_FILE")"
log "GitOps sync started (interval: ${SYNC_INTERVAL}s, env: $ENVIRONMENT)"
log "Source of truth: $REPO_URL (branch: $BRANCH)"

deploy() {
  cd "$REPO_DIR"

  COMPOSE_BASE="gitops/base/docker-compose.yml"
  COMPOSE_OVERRIDE="gitops/overlays/$ENVIRONMENT/docker-compose.override.yml"
  COMPOSE_CMD="$COMPOSE_BIN --env-file $ENV_FILE -f $COMPOSE_BASE"
  [ -f "$COMPOSE_OVERRIDE" ] && COMPOSE_CMD="$COMPOSE_CMD -f $COMPOSE_OVERRIDE"

  log "Pulling images..."
  if ! $COMPOSE_CMD pull 2>&1; then
    log "WARNING: Image pull failed (may not be in registry yet)"
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

  log "Change detected: ${LOCAL_SHA:0:8} -> ${REMOTE_SHA:0:8}"

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
