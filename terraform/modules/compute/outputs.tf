output "instance_id" {
  value = google_compute_instance.app_server.self_link
}

output "instance_name" {
  value = google_compute_instance.app_server.name
}

output "internal_ip" {
  value = google_compute_instance.app_server.network_interface[0].network_ip
}

output "external_ip" {
  description = "App compute instance external IP (for SSH/access)"
  value       = google_compute_instance.app_server.network_interface[0].access_config[0].nat_ip
}

output "service_account_email" {
  value = google_service_account.app.email
}
