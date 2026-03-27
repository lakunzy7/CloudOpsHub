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

# ── Enable Required GCP APIs (project-level, all modules depend on this) ──
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

# ── Artifact Registry (shared across environments, no env suffix) ──
resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  repository_id = "${var.project_name}-docker"
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}

# ── Networking ──
module "networking" {
  source = "./modules/networking"

  project_name = var.project_name
  environment  = var.environment
  region       = var.region

  depends_on = [google_project_service.apis]
}

# ── IAM ──
module "iam" {
  source = "./modules/iam"

  project_id   = var.project_id
  project_name = var.project_name
  environment  = var.environment

  depends_on = [google_project_service.apis]
}

# ── Secrets ──
module "secrets" {
  source = "./modules/secrets"

  project_name      = var.project_name
  environment       = var.environment
  db_password       = var.db_password
  grafana_password  = var.grafana_password
  slack_webhook_url = var.slack_webhook_url

  depends_on = [google_project_service.apis]
}

# ── Compute ──
module "compute" {
  source = "./modules/compute"

  project_name          = var.project_name
  environment           = var.environment
  region                = var.region
  zone                  = var.zone
  instance_type         = var.instance_type
  subnet_id             = module.networking.subnet_id
  service_account_email = module.iam.service_account_email

  startup_script = templatefile("${path.module}/../scripts/startup.sh", {
    project_id         = var.project_id
    project_name       = var.project_name
    environment        = var.environment
    region             = var.region
    registry_host      = "${var.region}-docker.pkg.dev"
    github_repo        = var.github_repo
    db_password_secret = module.secrets.db_password_secret_id
    grafana_secret     = module.secrets.grafana_password_secret_id
    slack_secret       = module.secrets.slack_webhook_secret_id
    db_password        = var.db_password
  })

  depends_on = [google_project_service.apis]
}

# ── Workload Identity Federation ──
module "wif" {
  source = "./modules/wif"

  project_name         = var.project_name
  environment          = var.environment
  github_repo          = var.github_repo
  service_account_name = module.iam.service_account_name

  depends_on = [google_project_service.apis]
}
