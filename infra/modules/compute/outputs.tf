output "static_ip" {
  description = "Static external IP address"
  value       = google_compute_address.app.address
}

output "instance_name" {
  description = "VM instance name"
  value       = google_compute_instance.app.name
}
