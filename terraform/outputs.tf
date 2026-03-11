# ── Compute ──
output "vm_name" {
  description = "App compute instance name"
  value       = module.compute.instance_name
}

output "vm_internal_ip" {
  description = "App compute instance internal IP"
  value       = module.compute.internal_ip
}

output "service_account_email" {
  description = "App VM service account"
  value       = module.compute.service_account_email
}

# ── Database ──
output "cloud_sql_private_ip" {
  description = "Cloud SQL private IP"
  value       = module.database.private_ip
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name"
  value       = module.database.connection_name
}

# ── Secrets ──
output "database_url_secret" {
  description = "Secret Manager secret ID for DATABASE_URL"
  value       = module.secrets.database_url_secret_id
}

# ── Load Balancer ──
output "load_balancer_ip" {
  description = "Load balancer external IP"
  value       = module.load_balancer.ip_address
}

output "dns_nameservers" {
  description = "DNS nameservers (if domain configured)"
  value       = module.load_balancer.dns_nameservers
}

# ── Storage ──
output "static_assets_bucket" {
  description = "GCS bucket URL for static assets"
  value       = module.storage.static_assets_url
}

output "artifact_registry_url" {
  description = "GCP Artifact Registry URL"
  value       = module.storage.artifact_registry_url
}

# ── ECR ──
output "ecr_backend_url" {
  description = "AWS ECR backend repository URL"
  value       = module.registry.backend_url
}

output "ecr_frontend_url" {
  description = "AWS ECR frontend repository URL"
  value       = module.registry.frontend_url
}
