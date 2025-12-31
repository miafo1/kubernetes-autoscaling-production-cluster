# app/app.py
import time
import math
from flask import Flask, Response, request
from prometheus_client import generate_latest, Counter, Gauge

app = Flask(__name__)

# Prometheus Metrics
REQUEST_COUNT = Counter('app_request_count', 'Total application request count', ['method', 'endpoint', 'http_status'])
IN_PROGRESS = Gauge('app_inprogress_requests', 'Number of in-progress requests')

@app.before_request
def before_request():
    IN_PROGRESS.inc()

@app.after_request
def after_request(response):
    IN_PROGRESS.dec()
    REQUEST_COUNT.labels(request.method, request.path, response.status_code).inc()
    return response

@app.route('/')
def index():
    return "Kubernetes Auto-Scaling Demo App v1.0"

@app.route('/health')
def health():
    return "OK", 200

@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype='text/plain')

@app.route('/load')
def load():
    """Simulates CPU load for auto-scaling testing"""
    duration = request.args.get('duration', default=10, type=int)
    start_time = time.time()
    
    # Simple CPU busy loop
    while time.time() - start_time < duration:
        _ = math.sqrt(64 * 64 * 64 * 64 * 64)
    
    return f"Simulated load for {duration} seconds", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
