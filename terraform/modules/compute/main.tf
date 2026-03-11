# ── Service Account ──
resource "google_service_account" "app" {
  account_id   = "${var.project_name}-app-${var.environment}"
  display_name = "CloudOpsHub App VM - ${var.environment}"
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
  name         = "${var.project_name}-app-${var.environment}"
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
  }

  metadata_startup_script = templatefile("${path.module}/../../templates/startup.sh", {
    project_id     = var.project_id
    environment    = var.environment
    ecr_registry   = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
    ecr_repository = "theepicbook"
    db_secret_name = var.db_secret_name
    aws_region     = var.aws_region
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
