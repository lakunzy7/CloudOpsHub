# ── VPC ──
resource "google_compute_network" "vpc" {
  name                    = "${var.project_id}-vpc-${var.environment}"
  auto_create_subnetworks = false
}

# ── Subnets ──
resource "google_compute_subnetwork" "app" {
  name                     = "${var.project_id}-app-subnet-${var.environment}"
  ip_cidr_range            = var.app_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# ── Cloud Router + NAT ──
resource "google_compute_router" "router" {
  name    = "${var.project_id}-router-${var.environment}"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.project_id}-nat-${var.environment}"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ── Firewall Rules ──
resource "google_compute_firewall" "allow_http" {
  name    = "${var.project_id}-allow-http-${var.environment}"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "${var.project_id}-allow-ssh-iap-${var.environment}"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["ssh"]
}

resource "google_compute_firewall" "allow_internal" {
  name    = "${var.project_id}-allow-internal-${var.environment}"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.app_subnet_cidr]
}

resource "google_compute_firewall" "allow_health_check" {
  name    = "${var.project_id}-allow-hc-${var.environment}"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["web"]
}

resource "google_compute_firewall" "allow_monitoring" {
  name    = "${var.project_id}-allow-monitoring-${var.environment}"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["9090", "9093", "9100", "3000"]
  }

  source_ranges = [var.app_subnet_cidr]
  target_tags   = ["monitoring"]
}
