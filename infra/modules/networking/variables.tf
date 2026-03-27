variable "project_name" {
  description = "Short name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment: dev, staging, or production"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}
