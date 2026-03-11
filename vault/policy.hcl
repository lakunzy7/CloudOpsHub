# CloudOpsHub application policy for Vault
# Grant read access to application secrets

path "secret/data/cloudopshub/*" {
  capabilities = ["read"]
}

path "secret/metadata/cloudopshub/*" {
  capabilities = ["list"]
}
