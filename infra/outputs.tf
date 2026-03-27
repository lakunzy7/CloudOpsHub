output "vm_ip" {
  description = "Static external IP of the VM"
  value       = module.compute.static_ip
}

output "vm_name" {
  description = "VM instance name"
  value       = module.compute.instance_name
}

output "service_account_email" {
  description = "VM service account email"
  value       = module.iam.service_account_email
}

output "artifact_registry_url" {
  description = "Docker registry URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.project_name}-docker"
}

output "wif_provider" {
  description = "Workload Identity provider (set as GCP_WIF_PROVIDER GitHub secret)"
  value       = module.wif.provider_name
}

output "app_url" {
  description = "Application URL"
  value       = "http://${module.compute.static_ip}"
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "http://${module.compute.static_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus URL"
  value       = "http://${module.compute.static_ip}:9090"
}
