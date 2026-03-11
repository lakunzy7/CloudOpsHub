output "ip_address" {
  value = google_compute_global_address.lb_ip.address
}

output "dns_nameservers" {
  value = var.domain_name != "" ? google_dns_managed_zone.app[0].name_servers : []
}
