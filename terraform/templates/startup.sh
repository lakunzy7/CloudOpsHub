#!/bin/bash
set -euo pipefail

echo "=== CloudOpsHub VM Startup - ${environment} ==="

# ── Install Docker Compose ──
if ! command -v docker-compose &> /dev/null; then
  echo "Installing Docker Compose..."
  DOCKER_COMPOSE_VERSION="v2.24.0"
  mkdir -p /usr/local/bin
  curl -SL "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi

# ── Install AWS CLI (for ECR login) ──
if ! command -v aws &> /dev/null; then
  echo "Installing AWS CLI..."
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp/aws-install
  /tmp/aws-install/aws/install
  rm -rf /tmp/awscliv2.zip /tmp/aws-install
fi

# ── Fetch DATABASE_URL from Secret Manager ──
echo "Fetching secrets from GCP Secret Manager..."
DATABASE_URL=$(gcloud secrets versions access latest --secret="${db_secret_name}" --project="${project_id}")
export DATABASE_URL

# ── Login to ECR ──
echo "Logging into ECR..."
aws ecr get-login-password --region ${aws_region} | \
  docker login --username AWS --password-stdin ${ecr_registry}

# ── Set up application directory ──
APP_DIR="/opt/theepicbook"
mkdir -p "$APP_DIR"
cd "$APP_DIR"

# ── Write environment file ──
cat > .env <<ENVEOF
DATABASE_URL=$DATABASE_URL
ECR_REGISTRY=${ecr_registry}
NODE_ENV=${environment}
PORT=8080
ENVEOF
chmod 600 .env

# ── Write docker-compose for 3 microservices ──
cat > docker-compose.yml <<COMPOSEEOF
version: "3.8"

services:
  frontend:
    image: ${ecr_registry}/theepicbook-frontend:latest
    restart: unless-stopped
    ports:
      - "80:80"
    depends_on:
      - backend
    networks:
      - app-network

  backend:
    image: ${ecr_registry}/theepicbook-backend:latest
    restart: unless-stopped
    environment:
      - PORT=8080
      - DATABASE_URL=$${DATABASE_URL}
    networks:
      - app-network

networks:
  app-network:
    driver: bridge
COMPOSEEOF

# ── Pull and start ──
echo "Pulling latest images..."
docker-compose pull

echo "Starting microservices..."
docker-compose up -d --remove-orphans

# ── Health check ──
echo "Waiting for application to be healthy..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:80/ > /dev/null 2>&1; then
    echo "All services healthy!"
    exit 0
  fi
  sleep 5
done

echo "WARNING: Application did not become healthy within timeout"
