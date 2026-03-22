variable "project_name" { type = string }
variable "environment" { type = string }
variable "db_user" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}
variable "db_private_ip" { type = string }
variable "db_name" { type = string }
variable "grafana_password" {
  type      = string
  sensitive = true
}
variable "slack_webhook_url" {
  type      = string
  sensitive = true
}
