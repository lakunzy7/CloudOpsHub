#!/bin/bash
set -euo pipefail

# Enable KV secrets engine v2
vault secrets enable -path=secret kv-v2 2>/dev/null || true

# Store application secrets
vault kv put secret/cloudopshub/database \
  DATABASE_URL="mysql://appuser:CHANGE_ME@<cloud-sql-ip>:3306/bookstore"

vault kv put secret/cloudopshub/argocd \
  ARGOCD_AUTH_TOKEN="CHANGE_ME"

vault kv put secret/cloudopshub/ecr \
  AWS_ACCESS_KEY_ID="CHANGE_ME" \
  AWS_SECRET_ACCESS_KEY="CHANGE_ME"

vault kv put secret/cloudopshub/grafana \
  GRAFANA_PASSWORD="CHANGE_ME"

# Create policy
vault policy write cloudopshub-app vault/policy.hcl

# Enable AppRole auth for CI/CD
vault auth enable approle 2>/dev/null || true
vault write auth/approle/role/cloudopshub-ci \
  token_policies="cloudopshub-app" \
  token_ttl=1h \
  token_max_ttl=4h

echo "Vault setup complete."
echo "Retrieve Role ID:   vault read auth/approle/role/cloudopshub-ci/role-id"
echo "Generate Secret ID: vault write -f auth/approle/role/cloudopshub-ci/secret-id"
