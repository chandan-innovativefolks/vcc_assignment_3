# VCC Assignment 3 — Detailed Implementation Report

## 1. Introduction

This report documents the design and implementation of a local virtual machine (VM) with real-time resource monitoring that automatically scales workloads to Amazon Web Services (AWS) when resource utilization exceeds a 75% threshold. The system demonstrates a hybrid cloud architecture where a local environment handles normal workloads and seamlessly offloads to cloud infrastructure during peak demand.

---

## 2. System Design

### 2.1 Design Goals

- **Automated Monitoring**: Continuously track CPU, memory, and disk usage on the local VM.
- **Threshold-Based Scaling**: Automatically provision cloud resources when any metric exceeds 75%.
- **Infrastructure as Code**: Use Terraform for repeatable, version-controlled cloud provisioning.
- **Observability**: Provide real-time dashboards via Grafana for visual monitoring.
- **Graceful Scaling**: Include cooldown periods and sustained-check requirements to prevent thrashing.

### 2.2 Technology Stack

| Layer | Technology | Justification |
|--------------------|---------------------------------|--------------------------------------------------------------|
| Virtualization | VirtualBox + Vagrant | Free, cross-platform, scriptable VM management |
| Application | Python Flask + Gunicorn | Lightweight, easy to deploy, built-in metrics support |
| Metrics Collection | Prometheus + Node Exporter | Industry standard for infrastructure monitoring |
| Visualization | Grafana | Rich dashboarding, Prometheus integration, alerting support |
| Monitoring Agent | Custom Python script (psutil) | Fine-grained control over threshold logic and scaling actions|
| Cloud Provider | Amazon Web Services (AWS) | Free tier available, Terraform support, EC2 API |
| IaC | Terraform | Declarative, multi-cloud, state management, plan/apply cycle |
| Containerization | Docker + Docker Compose | Consistent monitoring stack deployment |

### 2.3 Architecture

The system consists of three logical layers:

**Layer 1 — Local VM (VirtualBox)**
- Runs the Flask application serving user traffic.
- Runs Node Exporter for system-level metric collection.
- Hosts the monitoring stack (Prometheus + Grafana) in Docker containers.
- Runs the resource monitor daemon that evaluates scaling decisions.

**Layer 2 — Decision Engine (Resource Monitor)**
- Polls system metrics every 10 seconds using the `psutil` library.
- Maintains a breach counter; requires 3 consecutive threshold breaches (30 seconds of sustained overload) before triggering a scale-up.
- Enforces a 5-minute cooldown between scaling events to prevent rapid oscillation.
- Executes the scale-up shell script when scaling criteria are met.

**Layer 3 — Cloud Infrastructure (AWS)**
- Terraform provisions an EC2 `t2.medium` instance with Ubuntu 22.04 AMI.
- Creates a security group allowing traffic on ports 22, 80, 443, and 5000.
- The scale-up script deploys the application via SSH/SCP using the EC2 key pair.
- The scale-down script destroys all AWS resources when no longer needed.

---

## 3. Implementation Details

### 3.1 Local VM Creation

The VM is defined in a `Vagrantfile` with the following specifications:

- **Base Image**: Ubuntu 22.04 LTS (Jammy Jellyfish)
- **Resources**: 2 vCPUs, 2 GB RAM
- **Network**: Private network (192.168.56.10) + port forwarding
- **Provisioning**: Automated via `provision.sh`

The provisioning script installs all dependencies including Docker, the monitoring tools, AWS CLI v2, and Terraform — making the VM self-contained.

### 3.2 Resource Monitoring Implementation

Three monitoring mechanisms operate at different levels:

**a) Node Exporter (System Metrics)**
- Runs as a systemd service on the VM.
- Exposes hardware and OS metrics at port 9100.
- Prometheus scrapes these metrics every 15 seconds.

**b) Prometheus (Metrics Storage & Alerting)**
- Configured with three scrape targets: itself, Node Exporter, and the Flask app.
- Alert rules fire when CPU, memory, or disk usage exceeds 75% for 1+ minutes.
- Stores 7 days of time-series data.

**c) Custom Resource Monitor (monitor.py)**
- Independent Python daemon using `psutil` for direct system metric access.
- Implements a state machine: NORMAL → WARN → SCALE_UP → COOLDOWN → NORMAL.
- Configurable via environment variables for all thresholds and timing parameters.
- Logs all events to both stdout and a log file for audit trails.

### 3.3 Auto-Scaling Configuration

The scaling pipeline is implemented as a shell script (`scale_up.sh`) that orchestrates:

1. **Prerequisite validation** — Ensures AWS CLI and Terraform are available and authenticated.
2. **Infrastructure provisioning** — Runs `terraform apply` to create the EC2 instance and security group.
3. **SSH readiness polling** — Waits up to 5 minutes for the instance to accept SSH connections.
4. **Application deployment** — Copies the Flask app via SCP and installs dependencies remotely.
5. **Service startup** — Launches Gunicorn with 4 workers for production-grade serving.
6. **Health verification** — Confirms the application responds to health check requests.

### 3.4 Sample Application

The Flask application serves as both the workload and the monitoring interface:

- **Dashboard**: A single-page UI showing real-time CPU, memory, and disk gauges with color-coded thresholds.
- **Load Generation**: API endpoints to simulate light (1 worker, 10s) and heavy (4 workers, 30s) CPU load via SHA-256 hash computation.
- **Prometheus Metrics**: Exposes request counts, latency histograms, and resource gauges at `/metrics`.
- **Health Endpoint**: Returns a simple JSON response for deployment verification.

---

## 4. Testing Procedure

### 4.1 Normal Operation Test

1. Start the VM: `vagrant up && vagrant ssh`
2. Launch all services (app, monitoring stack, resource monitor)
3. Verify all dashboards are accessible and showing green/normal status
4. Confirm metrics are being collected in Prometheus

### 4.2 Threshold Breach Test

1. Generate heavy CPU load via the dashboard button or `stress-ng --cpu 2 --timeout 60s`
2. Observe Grafana gauges transitioning from green → yellow → red
3. Watch resource monitor logs showing breach count incrementing
4. After 3 consecutive checks (30s), verify scale-up script execution

### 4.3 Cloud Scaling Test

1. Ensure AWS credentials are configured (`aws sts get-caller-identity`)
2. Trigger heavy load and wait for auto-scale
3. Verify EC2 instance creation in the **AWS Console → EC2 Dashboard**
4. Access the cloud application at the instance's public IP
5. Confirm the health endpoint responds correctly

### 4.4 Scale-Down Test

1. Stop the load generation
2. Execute `scale_down.sh` manually (or wait for automated cooldown)
3. Verify the EC2 instance is terminated in the AWS Console
4. Confirm Terraform state shows no resources

---

## 5. Challenges and Solutions

| Challenge | Solution |
|--------------------------------------------------|----------------------------------------------------------------|
| Preventing scaling thrashing (rapid up/down) | Implemented 5-minute cooldown and 3-check sustained breach |
| Docker networking between containers and host | Used `host.docker.internal` for Prometheus to reach host ports |
| SSH key management for EC2 deployment | Terraform uses AWS EC2 key pairs; private key passed via env |
| Monitoring stack persistence across VM restarts | Docker volumes for Prometheus and Grafana data |
| Load generation without external tools | Built-in Flask endpoints using hashlib for CPU-intensive work |
| EC2 instance readiness delay | Retry loop with 30 attempts at 10s intervals for SSH readiness |

---

## 6. Future Enhancements

- **Load Balancer Integration**: Use an AWS Application Load Balancer (ALB) to route traffic between local and cloud instances.
- **Auto Scaling Groups**: Use AWS Auto Scaling Groups with launch templates for more robust scaling.
- **Multi-Cloud Support**: Extend Terraform configs to support GCP and Azure as alternative scale targets.
- **Predictive Scaling**: Use time-series analysis on historical metrics to anticipate load spikes before they breach thresholds.
- **Container Orchestration**: Deploy with Amazon ECS or EKS for container-based auto-scaling.
- **Webhook Alerts**: Integrate with SNS/Slack/email notifications when scaling events occur.

---

## 7. Conclusion

This project demonstrates a complete hybrid cloud auto-scaling solution that bridges local infrastructure with AWS cloud resources. The implementation uses industry-standard tools (Prometheus, Grafana, Terraform) combined with custom monitoring logic to create a responsive, threshold-based scaling system. The 75% threshold with sustained-check requirements ensures scaling decisions are deliberate and cost-effective, while the Infrastructure as Code approach ensures cloud provisioning is repeatable and auditable.

---
