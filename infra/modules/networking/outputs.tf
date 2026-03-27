output "vpc_id" {
  description = "VPC network ID"
  value       = google_compute_network.vpc.id
}

output "subnet_id" {
  description = "App subnet ID"
  value       = google_compute_subnetwork.app.id
}
