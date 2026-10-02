FROM python:3.12-slim

# Patch the vulnerable Debian package detected by Trivy (CVE-2026-103111)
RUN apt-get update && apt-get install -y --only-upgrade libpcre2-8-0 \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
RUN useradd --create-home --uid 10002 worker
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY worker.py .

# Switch to non-root user after OS dependencies are installed
USER 10002
CMD ["python","worker.py"]