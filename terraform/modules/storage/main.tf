# ── Static Assets Bucket ──
resource "google_storage_bucket" "static_assets" {
  name          = "${var.project_id}-${var.project_name}-static-${var.environment}"
  location      = var.region
  force_destroy = var.environment != "production"

  uniform_bucket_level_access = true

  versioning {
    enabled = var.environment == "production"
  }

  lifecycle_rule {
    condition { age = 90 }
    action { type = "Delete" }
  }

  cors {
    origin          = var.allowed_origins
    method          = ["GET", "HEAD"]
    response_header = ["Content-Type", "Cache-Control"]
    max_age_seconds = 3600
  }
}

resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.static_assets.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# ── Terraform State Bucket ──
resource "google_storage_bucket" "terraform_state" {
  name          = "cloudopshub-terraform-state"
  location      = var.region
  force_destroy = false

  uniform_bucket_level_access = true

  versioning { enabled = true }

  lifecycle_rule {
    condition { num_newer_versions = 5 }
    action { type = "Delete" }
  }
}

# ── Artifact Registry ──
resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  repository_id = "${var.project_name}-docker"
  format        = "DOCKER"
  description   = "Docker images for CloudOpsHub"

  cleanup_policies {
    id     = "keep-latest-10"
    action = "KEEP"
    most_recent_versions { keep_count = 10 }
  }
}
