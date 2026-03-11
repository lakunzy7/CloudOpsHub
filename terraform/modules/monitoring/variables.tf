variable "project_id" { type = string }
variable "project_name" { type = string }
variable "environment" { type = string }
variable "alert_email" { type = string }
variable "lb_ip" { type = string }
variable "domain_name" {
  type    = string
  default = ""
}
