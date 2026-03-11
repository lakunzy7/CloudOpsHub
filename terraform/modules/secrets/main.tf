resource "google_secret_manager_secret" "database_url" {
  secret_id = "${var.project_name}-database-url-${var.environment}"
  replication { auto {} }
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = "mysql://${var.db_user}:${var.db_password}@${var.db_private_ip}:3306/${var.db_name}"
}

resource "google_secret_manager_secret" "ecr_credentials" {
  secret_id = "${var.project_name}-ecr-creds-${var.environment}"
  replication { auto {} }
}
