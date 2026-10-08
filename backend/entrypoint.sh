#!/bin/sh
set -e
DB_HOST="${DB_HOST:-postgres}"
DB_USER="${DB_USER:-app}"
echo "Waiting for database at ${DB_HOST}:5432..."
until pg_isready -h "$DB_HOST" -p 5432 -U "$DB_USER" > /dev/null 2>&1; do
  echo "Database not ready, waiting..."
  sleep 2
done
echo "Database is ready."
echo "Running database schema setup..."
python -c "from app import app, db; app.app_context().push(); db.create_all()"
echo "Starting gunicorn..."
exec gunicorn --bind 0.0.0.0:8080 --workers 2 --threads 4 --timeout 30 app:app
