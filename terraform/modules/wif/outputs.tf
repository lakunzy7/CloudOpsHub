output "workload_identity_provider" {
  description = "Full WIF provider resource name for GitHub Actions"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "workload_identity_pool_id" {
  description = "WIF pool ID"
  value       = google_iam_workload_identity_pool.github.workload_identity_pool_id
}
