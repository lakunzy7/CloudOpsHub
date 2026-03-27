# State migration: move flat resources into modules.
# These blocks make `terraform plan` show moves (not destroy/create).
# Safe to remove after one successful apply per workspace.

# ── Networking (4 resources) ──
moved {
  from = google_compute_network.vpc
  to   = module.networking.google_compute_network.vpc
}

moved {
  from = google_compute_subnetwork.app
  to   = module.networking.google_compute_subnetwork.app
}

moved {
  from = google_compute_firewall.allow_http
  to   = module.networking.google_compute_firewall.allow_http
}

moved {
  from = google_compute_firewall.allow_ssh
  to   = module.networking.google_compute_firewall.allow_ssh
}

# ── IAM (6 resources: SA + 4 role bindings + cicd_writer) ──
moved {
  from = google_service_account.app
  to   = module.iam.google_service_account.app
}

moved {
  from = google_project_iam_member.roles["roles/artifactregistry.reader"]
  to   = module.iam.google_project_iam_member.roles["roles/artifactregistry.reader"]
}

moved {
  from = google_project_iam_member.roles["roles/secretmanager.secretAccessor"]
  to   = module.iam.google_project_iam_member.roles["roles/secretmanager.secretAccessor"]
}

moved {
  from = google_project_iam_member.roles["roles/logging.logWriter"]
  to   = module.iam.google_project_iam_member.roles["roles/logging.logWriter"]
}

moved {
  from = google_project_iam_member.roles["roles/monitoring.metricWriter"]
  to   = module.iam.google_project_iam_member.roles["roles/monitoring.metricWriter"]
}

moved {
  from = google_project_iam_member.cicd_writer
  to   = module.iam.google_project_iam_member.cicd_writer
}

# ── Secrets (6 resources: 3 secrets + 3 versions) ──
moved {
  from = google_secret_manager_secret.db_password
  to   = module.secrets.google_secret_manager_secret.db_password
}

moved {
  from = google_secret_manager_secret_version.db_password
  to   = module.secrets.google_secret_manager_secret_version.db_password
}

moved {
  from = google_secret_manager_secret.grafana_password
  to   = module.secrets.google_secret_manager_secret.grafana_password
}

moved {
  from = google_secret_manager_secret_version.grafana_password
  to   = module.secrets.google_secret_manager_secret_version.grafana_password
}

moved {
  from = google_secret_manager_secret.slack_webhook
  to   = module.secrets.google_secret_manager_secret.slack_webhook
}

moved {
  from = google_secret_manager_secret_version.slack_webhook
  to   = module.secrets.google_secret_manager_secret_version.slack_webhook
}

# ── Compute (2 resources: static IP + VM) ──
moved {
  from = google_compute_address.app
  to   = module.compute.google_compute_address.app
}

moved {
  from = google_compute_instance.app
  to   = module.compute.google_compute_instance.app
}

# ── WIF (3 resources: pool, provider, SA binding) ──
moved {
  from = google_iam_workload_identity_pool.github
  to   = module.wif.google_iam_workload_identity_pool.github
}

moved {
  from = google_iam_workload_identity_pool_provider.github
  to   = module.wif.google_iam_workload_identity_pool_provider.github
}

moved {
  from = google_service_account_iam_member.wif_binding
  to   = module.wif.google_service_account_iam_member.wif_binding
}
