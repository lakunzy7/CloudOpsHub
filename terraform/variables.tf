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

# ── Networking ──
variable "app_subnet_cidr" {
  description = "CIDR range for the application subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# ── Compute ──
variable "instance_type" {
  description = "GCE instance machine type"
  type        = string
  default     = "e2-medium"
}

# ── Database ──
variable "db_password" {
  description = "MySQL app user password"
  type        = string
  sensitive   = true
}

variable "grafana_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = "CloudOps-Grafana-2026!"
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

# ── GitHub CI/CD ──
variable "github_repo" {
  description = "GitHub repository in owner/repo format for WIF"
  type        = string
  default     = "lakunzy7/CloudOpsHub"
}

variable "project_number" {
  description = "GCP project number"
  type        = string
}

# ── Static assets CORS ──
variable "allowed_origins" {
  description = "Allowed CORS origins for static assets bucket"
  type        = list(string)
  default     = ["*"]
}
