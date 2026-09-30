#!/bin/sh
set -e
echo "Waiting for database..."
until pg_isready -h postgres -p 5432 -U app > /dev/null 2>&1; do
  echo "Database not ready, waiting..."
  sleep 2
done
echo "Database is ready."
echo "Running database schema setup..."
python -c "from app import app, db; app.app_context().push(); db.create_all()"
echo "Starting gunicorn..."
exec gunicorn --bind 0.0.0.0:8080 --workers 2 --threads 4 --timeout 30 app:app