variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "project_name" {
  description = "Short name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment: dev, staging, or production"
  type        = string
}
