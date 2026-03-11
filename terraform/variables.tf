variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "cloudopshub"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "dev"
}

# ── AWS (ECR only) ──
variable "aws_region" {
  description = "AWS region for ECR"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID for ECR registry"
  type        = string
}

# ── Networking ──
variable "app_subnet_cidr" {
  description = "CIDR range for the application subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "db_subnet_cidr" {
  description = "CIDR range for the database subnet"
  type        = string
  default     = "10.0.2.0/24"
}

# ── Compute ──
variable "instance_type" {
  description = "GCE instance machine type"
  type        = string
  default     = "e2-medium"
}

# ── Database ──
variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-f1-micro"
}

variable "db_password" {
  description = "Cloud SQL app user password"
  type        = string
  sensitive   = true
}

# ── DNS / SSL (optional) ──
variable "domain_name" {
  description = "Domain name for the app (leave empty to skip DNS/SSL)"
  type        = string
  default     = ""
}

# ── Monitoring ──
variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
}

# ── Static assets CORS ──
variable "allowed_origins" {
  description = "Allowed CORS origins for static assets bucket"
  type        = list(string)
  default     = ["*"]
}
