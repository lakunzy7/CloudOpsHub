output "vm_ip" {
  description = "Static external IP of the VM"
  value       = google_compute_address.app.address
}

output "vm_name" {
  description = "VM instance name"
  value       = google_compute_instance.app.name
}

output "service_account_email" {
  description = "VM service account email"
  value       = google_service_account.app.email
}

output "artifact_registry_url" {
  description = "Docker registry URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}

output "wif_provider" {
  description = "Workload Identity provider (set as GCP_WIF_PROVIDER GitHub secret)"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "app_url" {
  description = "Application URL"
  value       = "http://${google_compute_address.app.address}"
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "http://${google_compute_address.app.address}:3000"
}

output "prometheus_url" {
  description = "Prometheus URL"
  value       = "http://${google_compute_address.app.address}:9090"
}
