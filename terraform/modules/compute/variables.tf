variable "project_id" { type = string }
variable "project_name" { type = string }
variable "environment" { type = string }
variable "zone" { type = string }
variable "instance_type" { type = string }
variable "subnet_id" { type = string }
variable "db_secret_name" { type = string }
variable "grafana_secret_name" { type = string }
variable "artifact_registry_url" { type = string }

variable "github_repo" {
  description = "GitHub repository (owner/repo) for GitOps sync"
  type        = string
}

variable "slack_secret_name" { type = string }

variable "db_password" {
  description = "Database password for MySQL containers"
  type        = string
  sensitive   = true
}
