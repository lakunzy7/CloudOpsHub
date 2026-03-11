output "static_assets_url" {
  value = google_storage_bucket.static_assets.url
}

output "artifact_registry_url" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}
