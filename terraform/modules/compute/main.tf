# ── Service Account ──
resource "google_service_account" "app" {
  account_id   = "${var.project_id}-app-${var.environment}"
  display_name = "${var.project_name} App VM - ${var.environment}"
}

resource "google_project_iam_member" "roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/storage.objectViewer",
    "roles/secretmanager.secretAccessor",
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.app.email}"
}

# ── GCE Instance ──
resource "google_compute_instance" "app_server" {
  name         = "${var.project_id}-app-${var.environment}"
  machine_type = var.instance_type
  zone         = var.zone
  tags         = ["web", "ssh", "monitoring"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
      size  = 30
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = var.subnet_id
    access_config {
      # Ephemeral external IP for Vault/ArgoCD access
    }
  }

  metadata_startup_script = templatefile("${path.module}/../../templates/startup.sh", {
    project_id     = var.project_id
    environment    = var.environment
    registry_url   = var.artifact_registry_url
    registry_host  = split("/", var.artifact_registry_url)[0]
    db_secret_name      = var.db_secret_name
    grafana_secret_name = var.grafana_secret_name
    slack_secret_name   = var.slack_secret_name
    github_repo         = var.github_repo
    db_password         = var.db_password
  })

  metadata = {
    environment                = var.environment
    enable-oslogin             = "TRUE"
    google-logging-enabled     = "true"
    google-monitoring-enabled  = "true"
  }

  service_account {
    email  = google_service_account.app.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  allow_stopping_for_update = true
}
