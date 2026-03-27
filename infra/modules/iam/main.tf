resource "google_service_account" "app" {
  account_id   = "${var.project_name}-app-${var.environment}"
  display_name = "CloudOpsHub App VM - ${var.environment}"
}

resource "google_project_iam_member" "roles" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/secretmanager.secretAccessor",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.app.email}"
}

resource "google_project_iam_member" "cicd_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.app.email}"
}
