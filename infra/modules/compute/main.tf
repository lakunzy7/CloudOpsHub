resource "google_compute_address" "app" {
  name   = "${var.project_name}-ip-${var.environment}"
  region = var.region
}

resource "google_compute_instance" "app" {
  name         = "${var.project_name}-app-${var.environment}"
  machine_type = var.instance_type
  zone         = var.zone
  tags         = ["web"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
      size  = 30
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = var.subnet_id
    access_config {
      nat_ip = google_compute_address.app.address
    }
  }

  metadata_startup_script = var.startup_script

  metadata = {
    enable-oslogin = "TRUE"
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  allow_stopping_for_update = true
}
