variable "project_name" { type = string }
variable "environment" { type = string }
variable "region" { type = string }
variable "db_tier" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}
variable "vpc_id" { type = string }
variable "private_vpc_connection" {
  description = "Dependency on private VPC connection"
  type        = string
}
