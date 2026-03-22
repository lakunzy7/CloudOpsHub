variable "project_id" {
  description = "GCP project ID (lowercase, for resource naming)"
  type        = string
}

variable "project_number" {
  description = "GCP project number"
  type        = string
}

variable "project_name" {
  description = "Project name for display purposes"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository (owner/repo format)"
  type        = string
}

variable "github_owner" {
  description = "GitHub repository owner (user or org)"
  type        = string
}

variable "service_account_email" {
  description = "Service account email to allow impersonation"
  type        = string
}
