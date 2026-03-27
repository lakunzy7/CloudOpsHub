resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.project_name}-db-password-${var.environment}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

resource "google_secret_manager_secret" "grafana_password" {
  secret_id = "${var.project_name}-grafana-password-${var.environment}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "grafana_password" {
  secret      = google_secret_manager_secret.grafana_password.id
  secret_data = var.grafana_password
}

resource "google_secret_manager_secret" "slack_webhook" {
  secret_id = "${var.project_name}-slack-webhook-${var.environment}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "slack_webhook" {
  secret      = google_secret_manager_secret.slack_webhook.id
  secret_data = var.slack_webhook_url
}
