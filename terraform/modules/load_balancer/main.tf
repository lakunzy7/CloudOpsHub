# ── Global Static IP ──
resource "google_compute_global_address" "lb_ip" {
  name = "${var.project_name}-lb-ip-${var.environment}"
}

# ── Health Check ──
resource "google_compute_health_check" "app" {
  name                = "${var.project_name}-health-${var.environment}"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 80
    request_path = "/"
  }
}

# ── Instance Group ──
resource "google_compute_instance_group" "app" {
  name = "${var.project_name}-group-${var.environment}"
  zone = var.zone

  instances = [var.instance_id]

  named_port {
    name = "http"
    port = 80
  }
}

# ── Cloud Armor ──
resource "google_compute_security_policy" "app" {
  name = "${var.project_name}-armor-${var.environment}"

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config { src_ip_ranges = ["*"] }
    }
    description = "Default allow"
  }

  rule {
    action   = "rate_based_ban"
    priority = 1000
    match {
      versioned_expr = "SRC_IPS_V1"
      config { src_ip_ranges = ["*"] }
    }
    rate_limit_options {
      conform_action   = "allow"
      exceed_action    = "deny(429)"
      ban_duration_sec = 120
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
    }
    description = "Rate limit: 100 req/min per IP"
  }

  rule {
    action   = "deny(403)"
    priority = 900
    match {
      expr { expression = "evaluatePreconfiguredExpr('sqli-v33-stable')" }
    }
    description = "Block SQL injection"
  }

  rule {
    action   = "deny(403)"
    priority = 901
    match {
      expr { expression = "evaluatePreconfiguredExpr('xss-v33-stable')" }
    }
    description = "Block XSS attacks"
  }
}

# ── Backend Service ──
resource "google_compute_backend_service" "app" {
  name                  = "${var.project_name}-backend-${var.environment}"
  protocol              = "HTTP"
  port_name             = "http"
  health_checks         = [google_compute_health_check.app.id]
  load_balancing_scheme = "EXTERNAL"
  security_policy       = google_compute_security_policy.app.id
  timeout_sec           = 30

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  backend {
    group = google_compute_instance_group.app.id
  }
}

# ── URL Map ──
resource "google_compute_url_map" "app" {
  name            = "${var.project_name}-urlmap-${var.environment}"
  default_service = google_compute_backend_service.app.id
}

# ── SSL Certificate (managed, optional) ──
resource "google_compute_managed_ssl_certificate" "app" {
  count = var.domain_name != "" ? 1 : 0
  name  = "${var.project_name}-cert-${var.environment}"
  managed { domains = [var.domain_name] }
}

# ── HTTPS Proxy ──
resource "google_compute_target_https_proxy" "app" {
  count            = var.domain_name != "" ? 1 : 0
  name             = "${var.project_name}-https-proxy-${var.environment}"
  url_map          = google_compute_url_map.app.id
  ssl_certificates = [google_compute_managed_ssl_certificate.app[0].id]
}

resource "google_compute_global_forwarding_rule" "https" {
  count                 = var.domain_name != "" ? 1 : 0
  name                  = "${var.project_name}-https-fwd-${var.environment}"
  target                = google_compute_target_https_proxy.app[0].id
  port_range            = "443"
  ip_address            = google_compute_global_address.lb_ip.address
  load_balancing_scheme = "EXTERNAL"
}

# ── HTTP Proxy ──
resource "google_compute_target_http_proxy" "app" {
  name    = "${var.project_name}-http-proxy-${var.environment}"
  url_map = var.domain_name != "" ? google_compute_url_map.http_redirect[0].id : google_compute_url_map.app.id
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.project_name}-http-fwd-${var.environment}"
  target                = google_compute_target_http_proxy.app.id
  port_range            = "80"
  ip_address            = google_compute_global_address.lb_ip.address
  load_balancing_scheme = "EXTERNAL"
}

# ── HTTP-to-HTTPS Redirect ──
resource "google_compute_url_map" "http_redirect" {
  count = var.domain_name != "" ? 1 : 0
  name  = "${var.project_name}-http-redirect-${var.environment}"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# ── DNS (optional) ──
resource "google_dns_managed_zone" "app" {
  count       = var.domain_name != "" ? 1 : 0
  name        = "${var.project_name}-zone-${var.environment}"
  dns_name    = "${var.domain_name}."
  description = "DNS zone for CloudOpsHub ${var.environment}"
}

resource "google_dns_record_set" "a" {
  count        = var.domain_name != "" ? 1 : 0
  name         = "${var.domain_name}."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.app[0].name
  rrdatas      = [google_compute_global_address.lb_ip.address]
}
