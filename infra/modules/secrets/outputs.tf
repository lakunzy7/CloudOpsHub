output "db_password_secret_id" {
  description = "DB password secret ID"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "grafana_password_secret_id" {
  description = "Grafana password secret ID"
  value       = google_secret_manager_secret.grafana_password.secret_id
}

output "slack_webhook_secret_id" {
  description = "Slack webhook secret ID"
  value       = google_secret_manager_secret.slack_webhook.secret_id
}
