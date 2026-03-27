variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "expandox-cloudehub"
}

variable "project_name" {
  description = "Short name for resource naming (lowercase, no spaces)"
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
  description = "Environment: dev, staging, or production"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "GCE machine type"
  type        = string
  default     = "e2-medium"
}

variable "db_password" {
  description = "MySQL password for appuser"
  type        = string
  sensitive   = true
}

variable "grafana_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alerts"
  type        = string
  sensitive   = true
  default     = "https://hooks.slack.com/services/placeholder"
}

variable "github_repo" {
  description = "GitHub repo (owner/repo format)"
  type        = string
  default     = "lakunzy7/CloudOpsHub"
}

variable "create_artifact_registry" {
  description = "Whether to create the Artifact Registry repo (set true for first environment only)"
  type        = bool
  default     = true
}
