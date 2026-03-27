variable "project_name" {
  description = "Short name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment: dev, staging, or production"
  type        = string
}

variable "github_repo" {
  description = "GitHub repo (owner/repo format)"
  type        = string
}

variable "service_account_name" {
  description = "Service account fully qualified name for WIF binding"
  type        = string
}
