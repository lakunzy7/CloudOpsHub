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

variable "zone" {
  description = "GCP zone"
  type        = string
}

variable "instance_type" {
  description = "GCE machine type"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the VM"
  type        = string
}

variable "service_account_email" {
  description = "Service account email for the VM"
  type        = string
}

variable "startup_script" {
  description = "Rendered startup script content"
  type        = string
}
