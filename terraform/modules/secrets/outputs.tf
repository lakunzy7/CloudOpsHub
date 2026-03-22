output "database_url_secret_id" {
  value = google_secret_manager_secret.database_url.secret_id
}

output "argocd_token_secret_id" {
  value = google_secret_manager_secret.argocd_token.secret_id
}

output "grafana_password_secret_id" {
  value = google_secret_manager_secret.grafana_password.secret_id
}

output "slack_webhook_url_secret_id" {
  value = google_secret_manager_secret.slack_webhook_url.secret_id
}
