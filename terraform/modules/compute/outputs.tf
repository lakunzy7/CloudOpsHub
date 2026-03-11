output "instance_id" {
  value = google_compute_instance.app_server.id
}

output "instance_name" {
  value = google_compute_instance.app_server.name
}

output "internal_ip" {
  value = google_compute_instance.app_server.network_interface[0].network_ip
}

output "service_account_email" {
  value = google_service_account.app.email
}
