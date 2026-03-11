variable "project_name" { type = string }
variable "environment" { type = string }
variable "zone" { type = string }
variable "instance_id" { type = string }
variable "domain_name" {
  type    = string
  default = ""
}
