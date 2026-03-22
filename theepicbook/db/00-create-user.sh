#!/bin/bash
# Create appuser with remote access from any Docker container.
# Shell script so env vars are expanded. Runs via /docker-entrypoint-initdb.d/
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<-EOSQL
  CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY '$MYSQL_PASSWORD';
  GRANT ALL PRIVILEGES ON bookstore.* TO 'appuser'@'%';
  FLUSH PRIVILEGES;
EOSQL
