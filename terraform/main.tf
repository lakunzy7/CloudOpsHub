terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "cloudopshub-terraform-state"
    prefix = "terraform/state"
  }
}

# ── Providers ──
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "aws" {
  region = var.aws_region
}

# ── Enable Required GCP APIs ──
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "dns.googleapis.com",
    "artifactregistry.googleapis.com",
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
  db_subnet_cidr  = var.db_subnet_cidr

  depends_on = [google_project_service.apis]
}

# ── Module: Database ──
module "database" {
  source = "./modules/database"

  project_name           = var.project_name
  environment            = var.environment
  region                 = var.region
  db_tier                = var.db_tier
  db_password            = var.db_password
  vpc_id                 = module.network.vpc_id
  private_vpc_connection = module.network.private_vpc_connection
}

# ── Module: Secrets ──
module "secrets" {
  source = "./modules/secrets"

  project_name  = var.project_name
  environment   = var.environment
  db_user       = module.database.user_name
  db_password   = var.db_password
  db_private_ip = module.database.private_ip
  db_name       = module.database.database_name

  depends_on = [google_project_service.apis]
}

# ── Module: Compute ──
module "compute" {
  source = "./modules/compute"

  project_id     = var.project_id
  project_name   = var.project_name
  environment    = var.environment
  zone           = var.zone
  instance_type  = var.instance_type
  subnet_id      = module.network.app_subnet_id
  db_secret_name = module.secrets.database_url_secret_id
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region

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

# ── Module: Registry (AWS ECR) ──
module "registry" {
  source = "./modules/registry"
}
