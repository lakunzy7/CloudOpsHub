#!/bin/bash
set -euo pipefail

# Seed Cloud SQL database for TheEpicBook
# Usage: ./scripts/seed-database.sh <DATABASE_URL>
# Example: ./scripts/seed-database.sh "mysql://appuser:pass@10.0.2.5:3306/bookstore"
#
# Prerequisites: mysql client installed
# This script is idempotent — it checks if data exists before inserting.

DATABASE_URL="${1:?Usage: $0 <DATABASE_URL>}"

# Parse DATABASE_URL: mysql://user:password@host:port/database
PROTO="$(echo "$DATABASE_URL" | cut -d: -f1)"
USER="$(echo "$DATABASE_URL" | cut -d/ -f3 | cut -d: -f1)"
PASS="$(echo "$DATABASE_URL" | cut -d: -f3 | cut -d@ -f1)"
HOST="$(echo "$DATABASE_URL" | cut -d@ -f2 | cut -d: -f1)"
PORT="$(echo "$DATABASE_URL" | cut -d@ -f2 | cut -d: -f2 | cut -d/ -f1)"
DB="$(echo "$DATABASE_URL" | cut -d/ -f4)"

MYSQL_CMD="mysql -h $HOST -P $PORT -u $USER -p$PASS $DB"

echo "Connecting to Cloud SQL at $HOST:$PORT/$DB..."

# Check connectivity
if ! $MYSQL_CMD -e "SELECT 1" > /dev/null 2>&1; then
  echo "ERROR: Cannot connect to database"
  exit 1
fi

# Let Sequelize create tables via app sync, then seed data
# Check if Author table has data
AUTHOR_COUNT=$($MYSQL_CMD -N -e "SELECT COUNT(*) FROM Author;" 2>/dev/null || echo "0")

if [ "$AUTHOR_COUNT" -eq "0" ]; then
  echo "Seeding authors..."
  # Strip USE statements since we already selected the DB
  sed '/^USE /d' theepicbook/db/author_seed.sql | $MYSQL_CMD
  echo "Authors seeded."
else
  echo "Authors already exist ($AUTHOR_COUNT rows), skipping."
fi

BOOK_COUNT=$($MYSQL_CMD -N -e "SELECT COUNT(*) FROM Book;" 2>/dev/null || echo "0")

if [ "$BOOK_COUNT" -eq "0" ]; then
  echo "Seeding books..."
  sed '/^USE /d' theepicbook/db/books_seed.sql | $MYSQL_CMD
  echo "Books seeded."
else
  echo "Books already exist ($BOOK_COUNT rows), skipping."
fi

echo "Database seed complete."
