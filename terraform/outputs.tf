# ── Compute ──
output "vm_name" {
  description = "App compute instance name"
  value       = module.compute.instance_name
}

output "vm_internal_ip" {
  description = "App compute instance internal IP"
  value       = module.compute.internal_ip
}

output "vm_external_ip" {
  description = "App compute instance external IP (for SSH/access)"
  value       = module.compute.external_ip
}

output "service_account_email" {
  description = "App VM service account"
  value       = module.compute.service_account_email
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

# ── Workload Identity Federation ──
output "wif_provider" {
  description = "WIF provider for GitHub Actions (use as GCP_WIF_PROVIDER secret)"
  value       = module.wif.workload_identity_provider
}

output "artifact_registry_url" {
  description = "GCP Artifact Registry URL"
  value       = module.storage.artifact_registry_url
}
