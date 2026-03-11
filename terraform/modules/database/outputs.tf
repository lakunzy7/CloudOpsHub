output "private_ip" {
  value = google_sql_database_instance.main.private_ip_address
}

output "connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "database_name" {
  value = google_sql_database.bookstore.name
}

output "user_name" {
  value = google_sql_user.app_user.name
}
