resource "google_secret_manager_secret" "database_url" {
  secret_id = "${var.project_name}-database-url-${var.environment}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = "mysql://${var.db_user}:${var.db_password}@${var.db_private_ip}:3306/${var.db_name}"
}

resource "google_secret_manager_secret" "argocd_token" {
  secret_id = "${var.project_name}-argocd-token-${var.environment}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "argocd_token" {
  secret      = google_secret_manager_secret.argocd_token.id
  secret_data = "placeholder-will-be-updated-after-argocd-install"
}

resource "google_secret_manager_secret" "slack_webhook_url" {
  secret_id = "${var.project_name}-slack-webhook-url-${var.environment}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "slack_webhook_url" {
  secret      = google_secret_manager_secret.slack_webhook_url.id
  secret_data = var.slack_webhook_url
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
