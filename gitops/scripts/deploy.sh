#!/bin/bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
DEPLOY_DIR="/opt/theepicbook"
COMPOSE_BASE="gitops/base/docker-compose.yml"
COMPOSE_OVERRIDE="gitops/overlays/${ENVIRONMENT}/docker-compose.override.yml"

echo "Deploying TheEpicBook to ${ENVIRONMENT}..."

cd "${DEPLOY_DIR}"

# Pull latest images
docker-compose -f "${COMPOSE_BASE}" -f "${COMPOSE_OVERRIDE}" pull

# Stop and restart with new images
docker-compose -f "${COMPOSE_BASE}" -f "${COMPOSE_OVERRIDE}" up -d --remove-orphans

# Wait for health check
echo "Waiting for application to be healthy..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:80/ > /dev/null 2>&1; then
    echo "Application is healthy!"
    exit 0
  fi
  sleep 2
done

echo "ERROR: Application failed to become healthy"
exit 1
