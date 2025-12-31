# Dockerfile
# Multi-stage build for Python Flask App

# Stage 1: Builder
FROM python:3.9-slim as builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Stage 2: Runtime
FROM python:3.9-slim

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /root/.local /root/.local
COPY app.py .

# Make sure scripts in .local are usable:
ENV PATH=/root/.local/bin:$PATH

EXPOSE 8080

# Run with Gunicorn for production performance
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]
