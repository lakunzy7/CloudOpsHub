terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # NOTE: Backend bucket name cannot use variables. Update this to match
  # your project: "<YOUR_PROJECT_ID>-cloudopshub-tf-state"
  # Or use: terraform init -backend-config="bucket=<YOUR_PROJECT_ID>-cloudopshub-tf-state"
  backend "gcs" {
    bucket = "expadox-lab-cloudopshub-tf-state"
    prefix = "terraform/state"
  }
}

# ── Providers ──
provider "google" {
  project = var.project_id
  region  = var.region
}

# ── Enable Required GCP APIs ──
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "dns.googleapis.com",
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

# ── Module: Network ──
module "network" {
  source = "./modules/network"

  project_name    = var.project_name
  environment     = var.environment
  region          = var.region
  app_subnet_cidr = var.app_subnet_cidr

  depends_on = [google_project_service.apis]
}

# ── Module: Secrets ──
module "secrets" {
  source = "./modules/secrets"

  project_name  = var.project_name
  environment   = var.environment
  db_user          = "appuser"
  db_password      = var.db_password
  db_private_ip    = "database"
  db_name          = "bookstore"
  grafana_password = var.grafana_password

  depends_on = [google_project_service.apis]
}

# ── Module: Compute ──
module "compute" {
  source = "./modules/compute"

  project_id             = var.project_id
  project_name           = var.project_name
  environment            = var.environment
  zone                   = var.zone
  instance_type          = var.instance_type
  subnet_id              = module.network.app_subnet_id
  db_secret_name            = module.secrets.database_url_secret_id
  grafana_secret_name       = module.secrets.grafana_password_secret_id
  artifact_registry_url     = module.storage.artifact_registry_url
  github_repo               = var.github_repo

  depends_on = [google_project_service.apis]
}

# ── Module: Load Balancer ──
module "load_balancer" {
  source = "./modules/load_balancer"

  project_name = var.project_name
  environment  = var.environment
  zone         = var.zone
  instance_id  = module.compute.instance_id
  domain_name  = var.domain_name

  depends_on = [google_project_service.apis]
}

# ── Module: Storage ──
module "storage" {
  source = "./modules/storage"

  project_id      = var.project_id
  project_name    = var.project_name
  environment     = var.environment
  region          = var.region
  allowed_origins = var.allowed_origins

  depends_on = [google_project_service.apis]
}

# ── Module: Workload Identity Federation ──
module "wif" {
  source = "./modules/wif"

  project_id            = var.project_id
  project_number        = var.project_number
  project_name          = var.project_name
  environment           = var.environment
  github_repo           = var.github_repo
  service_account_email = module.compute.service_account_email

  depends_on = [google_project_service.apis]
}

# ── Module: Monitoring ──
module "monitoring" {
  source = "./modules/monitoring"

  project_id   = var.project_id
  project_name = var.project_name
  environment  = var.environment
  alert_email  = var.alert_email
  lb_ip        = module.load_balancer.ip_address
  domain_name  = var.domain_name

  depends_on = [google_project_service.apis]
}
