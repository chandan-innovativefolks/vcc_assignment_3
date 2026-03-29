"""
Sample Flask application with Prometheus metrics integration.
Simulates a CPU/memory-intensive workload to demonstrate auto-scaling.
"""

import os
import time
import hashlib
import threading

from flask import Flask, jsonify, render_template_string
from prometheus_client import (
Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST
)
import psutil

app = Flask(__name__)

REQUEST_COUNT = Counter("app_requests_total", "Total requests", ["method", "endpoint"])
REQUEST_LATENCY = Histogram("app_request_latency_seconds", "Request latency", ["endpoint"])
CPU_USAGE = Gauge("app_cpu_usage_percent", "Current CPU usage percentage")
MEMORY_USAGE = Gauge("app_memory_usage_percent", "Current memory usage percentage")
ACTIVE_THREADS = Gauge("app_active_threads", "Number of active worker threads")

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>VCC Assignment 3 - Auto-Scaling Demo</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #0f172a; color: #e2e8f0; }
.container { max-width: 960px; margin: 0 auto; padding: 2rem; }
h1 { color: #38bdf8; margin-bottom: 0.5rem; }
.subtitle { color: #94a3b8; margin-bottom: 2rem; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1.5rem; margin-bottom: 2rem; }
.card { background: #1e293b; border-radius: 12px; padding: 1.5rem; border: 1px solid #334155; }
.card h3 { color: #94a3b8; font-size: 0.85rem; text-transform: uppercase; margin-bottom: 0.5rem; }
.card .value { font-size: 2rem; font-weight: 700; }
.green { color: #4ade80; } .yellow { color: #facc15; } .red { color: #f87171; }
.btn-group { display: flex; gap: 1rem; flex-wrap: wrap; margin-bottom: 2rem; }
.btn { padding: 0.75rem 1.5rem; border: none; border-radius: 8px; cursor: pointer; font-size: 1rem; font-weight: 600; transition: transform 0.1s; }
.btn:hover { transform: scale(1.03); }
.btn-blue { background: #3b82f6; color: white; }
.btn-red { background: #ef4444; color: white; }
.btn-green { background: #22c55e; color: white; }
.log { background: #0f172a; border: 1px solid #334155; border-radius: 8px; padding: 1rem; font-family: monospace; font-size: 0.85rem; max-height: 250px; overflow-y: auto; color: #94a3b8; }
</style>
</head>
<body>
<div class="container">
<h1>Cloud Auto-Scaling Demo</h1>
<p class="subtitle">VCC Assignment 3 &mdash; Local VM &rarr; AWS Scaling</p>
<div class="grid">
<div class="card"><h3>CPU Usage</h3><div class="value" id="cpu">--</div></div>
<div class="card"><h3>Memory Usage</h3><div class="value" id="mem">--</div></div>
<div class="card"><h3>Disk Usage</h3><div class="value" id="disk">--</div></div>
<div class="card"><h3>Status</h3><div class="value green" id="status">Normal</div></div>
</div>
<div class="btn-group">
<button class="btn btn-blue" onclick="loadTest('light')">Light Load</button>
<button class="btn btn-red" onclick="loadTest('heavy')">Heavy Load (triggers scale)</button>
<button class="btn btn-green" onclick="getStatus()">Refresh Stats</button>
</div>
<div class="log" id="log">Ready...</div>
</div>
<script>
function log(msg) {
const el = document.getElementById('log');
el.innerHTML += '\\n' + new Date().toLocaleTimeString() + ' &gt; ' + msg;
el.scrollTop = el.scrollHeight;
}
function colorize(val) { return val > 75 ? 'red' : val > 50 ? 'yellow' : 'green'; }
function getStatus() {
fetch('/api/status').then(r => r.json()).then(d => {
document.getElementById('cpu').className = 'value ' + colorize(d.cpu);
document.getElementById('cpu').textContent = d.cpu.toFixed(1) + '%';
document.getElementById('mem').className = 'value ' + colorize(d.memory);
document.getElementById('mem').textContent = d.memory.toFixed(1) + '%';
document.getElementById('disk').className = 'value ' + colorize(d.disk);
document.getElementById('disk').textContent = d.disk.toFixed(1) + '%';
document.getElementById('status').textContent = d.scaling_status;
document.getElementById('status').className = 'value ' + (d.scaling_status === 'Normal' ? 'green' : 'red');
log('Status updated — CPU: ' + d.cpu.toFixed(1) + '%, MEM: ' + d.memory.toFixed(1) + '%');
});
}
function loadTest(level) {
log('Starting ' + level + ' load test...');
fetch('/api/load/' + level, {method: 'POST'}).then(r => r.json()).then(d => {
log(d.message);
setTimeout(getStatus, 3000);
});
}
getStatus();
setInterval(getStatus, 10000);
</script>
</body>
</html>
"""

scaling_status = "Normal"


def update_metrics():
"""Background thread to continuously update Prometheus gauges."""
while True:
CPU_USAGE.set(psutil.cpu_percent(interval=1))
MEMORY_USAGE.set(psutil.virtual_memory().percent)
time.sleep(5)


metrics_thread = threading.Thread(target=update_metrics, daemon=True)
metrics_thread.start()


@app.route("/")
def index():
REQUEST_COUNT.labels(method="GET", endpoint="/").inc()
return render_template_string(HTML_TEMPLATE)


@app.route("/api/status")
def status():
REQUEST_COUNT.labels(method="GET", endpoint="/api/status").inc()
cpu = psutil.cpu_percent(interval=0.5)
mem = psutil.virtual_memory().percent
disk = psutil.disk_usage("/").percent
return jsonify({
"cpu": cpu,
"memory": mem,
"disk": disk,
"scaling_status": scaling_status,
"threshold": 75.0,
"hostname": os.uname().nodename,
})


@app.route("/api/load/<level>", methods=["POST"])
def generate_load(level):
"""Generate artificial CPU load to trigger auto-scaling."""
REQUEST_COUNT.labels(method="POST", endpoint="/api/load").inc()

if level == "light":
duration, workers = 10, 1
elif level == "heavy":
duration, workers = 30, 4
else:
return jsonify({"error": "Invalid level. Use 'light' or 'heavy'."}), 400

def cpu_burn(seconds):
end = time.time() + seconds
while time.time() < end:
hashlib.sha256(os.urandom(128)).hexdigest()

ACTIVE_THREADS.set(workers)
for _ in range(workers):
t = threading.Thread(target=cpu_burn, args=(duration,))
t.daemon = True
t.start()

return jsonify({
"message": f"Started {level} load: {workers} workers for {duration}s",
"workers": workers,
"duration_seconds": duration,
})


@app.route("/metrics")
def metrics():
return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.route("/health")
def health():
return jsonify({"status": "healthy"})


if __name__ == "__main__":
app.run(host="0.0.0.0", port=5000, debug=True)