output "service_account_email" {
  description = "Service account email"
  value       = google_service_account.app.email
}

output "service_account_name" {
  description = "Service account fully qualified name"
  value       = google_service_account.app.name
}
