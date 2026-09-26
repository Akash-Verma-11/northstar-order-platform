#!/bin/sh
set -e
echo "Running database schema setup..."
python -c "from app import app, db; app.app_context().push(); db.create_all()"
echo "Starting gunicorn..."
exec gunicorn --bind 0.0.0.0:8080 --workers 2 --threads 4 --timeout 30 app:app