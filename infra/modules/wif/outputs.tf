output "pool_name" {
  description = "Workload Identity Pool name"
  value       = google_iam_workload_identity_pool.github.name
}

output "provider_name" {
  description = "Workload Identity Provider name (set as GCP_WIF_PROVIDER GitHub secret)"
  value       = google_iam_workload_identity_pool_provider.github.name
}
