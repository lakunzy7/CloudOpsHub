terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "expandox-cloudehub-cloudopshub-tf-state"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ── Enable Required GCP APIs ──
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}

# ── Network ──
resource "google_compute_network" "vpc" {
  name                    = "${var.project_name}-vpc-${var.environment}"
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "app" {
  name          = "${var.project_name}-subnet-${var.environment}"
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
}

resource "google_compute_firewall" "allow_http" {
  name    = "${var.project_name}-allow-http-${var.environment}"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80", "3000", "9090"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.project_name}-allow-ssh-${var.environment}"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["web"]
}

# ── Service Account ──
resource "google_service_account" "app" {
  account_id   = "${var.project_name}-app-${var.environment}"
  display_name = "CloudOpsHub App VM - ${var.environment}"

  depends_on = [google_project_service.apis]
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

# ── Static IP ──
resource "google_compute_address" "app" {
  name   = "${var.project_name}-ip-${var.environment}"
  region = var.region

  depends_on = [google_project_service.apis]
}

# ── Secrets ──
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.project_name}-db-password-${var.environment}"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
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
  depends_on = [google_project_service.apis]
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
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "slack_webhook" {
  secret      = google_secret_manager_secret.slack_webhook.id
  secret_data = var.slack_webhook_url
}

# ── Artifact Registry ──
resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  repository_id = "${var.project_name}-docker"
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}

# ── Compute Instance ──
resource "google_compute_instance" "app" {
  name         = "${var.project_name}-app-${var.environment}"
  machine_type = var.instance_type
  zone         = var.zone
  tags         = ["web"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
      size  = 30
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.app.id
    access_config {
      nat_ip = google_compute_address.app.address
    }
  }

  metadata_startup_script = templatefile("${path.module}/../scripts/startup.sh", {
    project_id          = var.project_id
    project_name        = var.project_name
    environment         = var.environment
    region              = var.region
    registry_host       = "${var.region}-docker.pkg.dev"
    github_repo         = var.github_repo
    db_password_secret  = google_secret_manager_secret.db_password.secret_id
    grafana_secret      = google_secret_manager_secret.grafana_password.secret_id
    slack_secret        = google_secret_manager_secret.slack_webhook.secret_id
    db_password         = var.db_password
  })

  metadata = {
    enable-oslogin = "TRUE"
  }

  service_account {
    email  = google_service_account.app.email
    scopes = ["cloud-platform"]
  }

  allow_stopping_for_update = true

  depends_on = [google_project_service.apis]
}

# ── Workload Identity Federation (for GitHub Actions CI/CD) ──
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "${var.project_name}-github-${var.environment}"
  display_name              = "GitHub Actions - ${var.environment}"

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == '${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

resource "google_project_iam_member" "cicd_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.app.email}"
}
