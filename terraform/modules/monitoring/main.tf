# ── Uptime Check ──
resource "google_monitoring_uptime_check_config" "app" {
  display_name = "TheEpicBook ${var.environment} uptime"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/"
    port         = 80
    use_ssl      = var.domain_name != ""
    validate_ssl = var.domain_name != ""
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.domain_name != "" ? var.domain_name : var.lb_ip
    }
  }
}

# ── Notification Channel ──
resource "google_monitoring_notification_channel" "email" {
  display_name = "CloudOpsHub ${var.environment} alerts"
  type         = "email"
  labels       = { email_address = var.alert_email }
}

# ── Alert: Uptime failure ──
resource "google_monitoring_alert_policy" "uptime" {
  display_name = "TheEpicBook ${var.environment} - uptime failure"
  combiner     = "OR"

  conditions {
    display_name = "Uptime check failed"
    condition_threshold {
      filter          = "resource.type = \"uptime_url\" AND metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_NEXT_OLDER"
      }
      trigger { count = 1 }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]
  alert_strategy { auto_close = "1800s" }
}

# ── Alert: VM high CPU ──
resource "google_monitoring_alert_policy" "high_cpu" {
  display_name = "TheEpicBook ${var.environment} - high CPU"
  combiner     = "OR"

  conditions {
    display_name = "CPU utilization > 80%"
    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
      trigger { count = 1 }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]
}

# ── Alert: Cloud SQL high CPU ──
resource "google_monitoring_alert_policy" "db_high_cpu" {
  display_name = "TheEpicBook ${var.environment} - DB high CPU"
  combiner     = "OR"

  conditions {
    display_name = "Cloud SQL CPU > 80%"
    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND metric.type = \"cloudsql.googleapis.com/database/cpu/utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
      trigger { count = 1 }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]
}

# ── Log-based metric ──
resource "google_logging_metric" "app_errors" {
  name   = "${var.project_name}-app-errors-${var.environment}"
  filter = "resource.type=\"gce_instance\" AND severity>=ERROR"
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}
