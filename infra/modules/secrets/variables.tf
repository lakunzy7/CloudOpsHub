variable "project_name" {
  description = "Short name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment: dev, staging, or production"
  type        = string
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
}
