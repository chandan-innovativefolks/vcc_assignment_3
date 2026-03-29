# VCC Assignment 3 — Local VM Resource Monitoring & Cloud Auto-Scaling

## Objective

Create a local virtual machine, implement real-time resource monitoring, and configure automatic scaling to Amazon Web Services (AWS) when resource usage exceeds **75%**.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Step-by-Step Implementation](#step-by-step-implementation)
- [Step 1: Create the Local VM](#step-1-create-the-local-vm)
- [Step 2: Deploy the Sample Application](#step-2-deploy-the-sample-application)
- [Step 3: Set Up Resource Monitoring](#step-3-set-up-resource-monitoring)
- [Step 4: Configure Cloud Auto-Scaling](#step-4-configure-cloud-auto-scaling)
- [Step 5: Test the Auto-Scaling Flow](#step-5-test-the-auto-scaling-flow)
4. [Project Structure](#project-structure)
5. [Configuration Reference](#configuration-reference)
6. [Plagiarism Declaration](#plagiarism-declaration)

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────┐
│ LOCAL VM (VirtualBox / Vagrant) │
│ │
│ ┌────────────┐ ┌────────────┐ ┌─────────────────────────────┐ │
│ │ Flask App │ │ Node │ │ Resource Monitor │ │
│ │ (Port 5000) │ │ Exporter │ │ (monitor.py) │ │
│ │ │ │ (Port 9100)│ │ │ │
│ │ /metrics ───┼──┤ │ │ • Polls CPU / MEM / DISK │ │
│ │ /api/status │ │ Prometheus│ │ • Threshold: 75% │ │
│ │ /api/load │ │ (Port 9090)│ │ • Sustained breach → scale │ │
│ └────────────┘ │ │ │ • 5-min cooldown │ │
│ │ Grafana │ └────────────┬────────────────┘ │
│ │ (Port 3000)│ │ │
│ └────────────┘ │ │
└────────────────────────────────────────────────┼───────────────────┘
│
┌─────────▼─────────┐
│ Usage > 75% ? │
└────────┬──────────┘
│ YES
┌────────▼──────────┐
│ scale_up.sh │
│ Terraform + SSH │
└────────┬──────────┘
│
┌───────────────────────────────────────────────┼────────────────────┐
│ AMAZON WEB SERVICES (AWS) │ │
│ ┌────────────┐ ┌────────────┐ ┌────────────▼────────────────┐ │
│ │ Security │ │ EC2 │ │ Flask App (deployed) │ │
│ │ Group │──│ Instance │──│ gunicorn + 4 workers │ │
│ └────────────┘ └────────────┘ └─────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

**Flow Summary:**
1. A Flask application runs on the local VM with Prometheus metrics enabled.
2. Prometheus + Grafana continuously monitor CPU, memory, and disk usage.
3. A Python-based resource monitor checks metrics every 10 seconds.
4. When any metric exceeds **75% for 3 consecutive checks** (30 seconds), the monitor triggers `scale_up.sh`.
5. The scale-up script uses **Terraform** to provision an AWS EC2 instance.
6. The Flask application is deployed to the cloud instance via SSH/SCP.
7. Traffic can then be directed to the cloud instance.
8. When load normalizes, `scale_down.sh` destroys the cloud resources.

For detailed architecture diagrams (Mermaid format), see [`diagrams/architecture.md`](diagrams/architecture.md).

---

## Prerequisites

| Tool | Version | Purpose |
|-----------------|-----------|----------------------------------|
| VirtualBox | >= 7.0 | VM hypervisor |
| Vagrant | >= 2.4 | VM provisioning & management |
| Terraform | >= 1.0 | Infrastructure as Code (AWS) |
| AWS CLI | v2 | AWS command-line interface |
| Docker | >= 24.0 | Monitoring stack containers |
| Python | >= 3.10 | Application & monitoring scripts |
| Git | >= 2.0 | Version control |

### AWS Setup

1. Create an AWS account at [aws.amazon.com](https://aws.amazon.com)
2. Create an **IAM user** with programmatic access and the **AmazonEC2FullAccess** policy
3. Create an **EC2 Key Pair** in your target region (e.g., `us-east-1`) and download the `.pem` file
4. Configure the AWS CLI:
```bash
aws configure
# Enter your Access Key ID, Secret Access Key, region (us-east-1), and output format (json)
```
5. Set up the SSH key:
```bash
chmod 400 ~/your-key-pair.pem
```

---

## Step-by-Step Implementation

### Step 1: Create the Local VM

We use **Vagrant** with the **VirtualBox** provider to create an Ubuntu 22.04 VM.

#### 1.1 Clone the Repository

```bash
git clone <repository-url>
cd vcc_assignment_3
```

#### 1.2 Start the VM

```bash
vagrant up
```

This command will:
- Download the `ubuntu/jammy64` box (if not cached)
- Create a VirtualBox VM with **2 GB RAM** and **2 CPUs**
- Configure a private network at `192.168.56.10`
- Set up port forwarding (5000, 9090, 3000, 9100)
- Run `provision.sh` to install all dependencies

**What `provision.sh` installs:**
- Python 3, pip, venv
- Docker and Docker Compose
- Node Exporter (Prometheus system metrics)
- AWS CLI v2
- Terraform
- stress-ng (for load testing)

#### 1.3 Access the VM

```bash
vagrant ssh
```

#### 1.4 Verify Installation

```bash
docker --version
terraform --version
aws --version
python3 --version
```

---

### Step 2: Deploy the Sample Application

The sample application is a **Flask** web app that:
- Serves a real-time monitoring dashboard
- Exposes Prometheus metrics at `/metrics`
- Provides API endpoints to simulate CPU load
- Reports system resource usage

#### 2.1 Start the Application

```bash
cd /vagrant
source venv/bin/activate
cd app
python app.py
```

Or with Gunicorn (production):

```bash
gunicorn --bind 0.0.0.0:5000 --workers 2 --threads 4 app:app
```

#### 2.2 Application Endpoints

| Endpoint | Method | Description |
|--------------------|--------|---------------------------------|
| `/` | GET | Dashboard UI |
| `/api/status` | GET | JSON resource metrics |
| `/api/load/light` | POST | Light CPU load (10s, 1 worker) |
| `/api/load/heavy` | POST | Heavy CPU load (30s, 4 workers) |
| `/metrics` | GET | Prometheus metrics |
| `/health` | GET | Health check |

#### 2.3 Access the Dashboard

Open **http://localhost:5000** in your browser.

---

### Step 3: Set Up Resource Monitoring

We use a three-layer monitoring approach:

1. **Node Exporter** — collects system-level metrics (CPU, memory, disk, network)
2. **Prometheus** — scrapes and stores metrics, evaluates alert rules
3. **Grafana** — visualizes metrics with dashboards and gauges

#### 3.1 Start the Monitoring Stack

```bash
cd /vagrant
sudo docker-compose -f docker-compose.monitoring.yml up -d
```

#### 3.2 Verify Services

| Service | URL | Credentials |
|----------------|----------------------------|-----------------|
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3000 | admin / admin |
| Node Exporter | http://localhost:9100/metrics | — |

#### 3.3 Grafana Dashboard

A pre-configured dashboard is automatically provisioned showing:
- **CPU Usage** — gauge + time series (red zone above 75%)
- **Memory Usage** — gauge + time series (red zone above 75%)
- **Disk Usage** — gauge (red zone above 75%)
- **Auto-Scale Trigger** — status indicator (NORMAL / ALERT)

#### 3.4 Prometheus Alert Rules

Alert rules are defined in `monitoring/prometheus/alert_rules.yml`:

- **HighCPUUsage**: triggers when CPU > 75% for 1 minute
- **HighMemoryUsage**: triggers when memory > 75% for 1 minute
- **HighDiskUsage**: triggers when disk > 75% for 1 minute

#### 3.5 Start the Resource Monitor

The Python-based monitor continuously checks resource usage and triggers auto-scaling:

```bash
cd /vagrant
source venv/bin/activate
sudo python monitoring/scripts/monitor.py
```

**Alternatively**, use the lightweight bash script as a cron job:

```bash
# Run every minute via cron
echo "* * * * * /vagrant/monitoring/scripts/check_resources.sh" | crontab -
```

#### 3.6 Monitor Configuration

| Parameter | Default | Environment Variable |
|-------------------|---------|------------------------|
| CPU Threshold | 75% | `THRESHOLD_CPU` |
| Memory Threshold | 75% | `THRESHOLD_MEMORY` |
| Disk Threshold | 75% | `THRESHOLD_DISK` |
| Check Interval | 10s | `CHECK_INTERVAL` |
| Sustained Checks | 3 | `SUSTAINED_CHECKS` |
| Cooldown Period | 300s | `COOLDOWN_SECONDS` |

---

### Step 4: Configure Cloud Auto-Scaling

When resource usage exceeds 75%, the system provisions an AWS EC2 instance using Terraform.

#### 4.1 Configure AWS Credentials

```bash
aws configure
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region: us-east-1
# Default output format: json
```

Verify credentials:

```bash
aws sts get-caller-identity
```

#### 4.2 Create an EC2 Key Pair (if needed)

```bash
aws ec2 create-key-pair --key-name vcc-key --query 'KeyMaterial' --output text > ~/.ssh/vcc-key.pem
chmod 400 ~/.ssh/vcc-key.pem
```

#### 4.3 Configure Terraform Variables

```bash
cd /vagrant/cloud/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
aws_region = "us-east-1"
instance_name = "vcc-scaled-instance"
instance_type = "t2.medium"
key_pair_name = "vcc-key"
```

#### 4.4 Initialize Terraform

```bash
cd /vagrant/cloud/terraform
terraform init
terraform plan
```

#### 4.5 Auto-Scaling Flow

The `scale_up.sh` script performs these steps automatically:
1. **Validates prerequisites** — checks for AWS CLI, Terraform, and active credentials
2. **Runs `terraform apply`** — provisions an AWS EC2 `t2.medium` instance with a security group
3. **Waits for SSH readiness** — polls until the instance is reachable
4. **Deploys the application** — copies app files via SCP, installs dependencies
5. **Starts the application** — runs Gunicorn with 4 workers
6. **Verifies deployment** — performs a health check

#### 4.6 Scale Down

When load returns to normal:

```bash
export AWS_REGION="us-east-1"
export KEY_PAIR_NAME="vcc-key"
bash /vagrant/cloud/scripts/scale_down.sh
```

This runs `terraform destroy` to terminate all AWS resources.

---

### Step 5: Test the Auto-Scaling Flow

#### 5.1 Start All Services

```bash
vagrant ssh

# Terminal 1: Start the app
cd /vagrant && source venv/bin/activate
python app/app.py &

# Terminal 2: Start monitoring stack
cd /vagrant && sudo docker-compose -f docker-compose.monitoring.yml up -d

# Terminal 3: Start resource monitor
cd /vagrant && source venv/bin/activate
sudo python monitoring/scripts/monitor.py
```

#### 5.2 Generate Heavy Load

**Option A: Via the Dashboard UI**

Open http://localhost:5000 and click **"Heavy Load (triggers scale)"**.

**Option B: Via API**

```bash
curl -X POST http://localhost:5000/api/load/heavy
```

**Option C: Using stress-ng**

```bash
stress-ng --cpu 2 --vm 1 --vm-bytes 1G --timeout 60s
```

#### 5.3 Observe the Flow

1. Open **Grafana** at http://localhost:3000 — watch CPU/memory gauges turn red
2. Watch the **resource monitor logs** — see breach counts incrementing
3. After 3 consecutive breaches, the **scale-up script triggers**
4. An EC2 instance is provisioned and the app is deployed
5. Check the **AWS Console** (EC2 Dashboard) to verify the instance

#### 5.4 Verify Cloud Deployment

```bash
# Get the cloud instance IP from Terraform
cd /vagrant/cloud/terraform
terraform output instance_ip

# Test the cloud application
curl http://INSTANCE_IP:5000/health
curl http://INSTANCE_IP:5000/api/status
```

---

## Project Structure

```
vcc_assignment_3/
├── Vagrantfile # VM definition (VirtualBox)
├── run.sh # script to run create entire infra
├── provision.sh # VM setup script
├── docker-compose.monitoring.yml # Prometheus + Grafana stack
├── app/
│ ├── app.py # Flask application + metrics
│ ├── requirements.txt # Python dependencies
│ └── Dockerfile # Container image for app
├── monitoring/
│ ├── scripts/
│ │ ├── monitor.py # Python resource monitor + auto-scale trigger
│ │ └── check_resources.sh # Bash resource checker (cron-friendly)
│ ├── prometheus/
│ │ ├── prometheus.yml # Prometheus scrape configuration
│ │ └── alert_rules.yml # Alert rules (>75% thresholds)
│ └── grafana/
│ ├── dashboards/
│ │ └── vm-resources.json # Pre-built Grafana dashboard
│ └── provisioning/
│ ├── datasources/
│ │ └── prometheus.yml # Auto-configure Prometheus datasource
│ └── dashboards/
│ └── dashboard.yml # Dashboard provisioning config
├── cloud/
│ ├── terraform/
│ │ ├── main.tf # AWS EC2 instance + security group (IaC)
│ │ ├── variables.tf # Terraform variable definitions
│ │ └── terraform.tfvars.example # Example variable values
│ └── scripts/
│ ├── scale_up.sh # Automated scale-up workflow
│ └── scale_down.sh # Automated scale-down workflow
├── diagrams/
│ └── architecture.md # Architecture diagrams (Mermaid)
├── docs/
│ └── REPORT.md # Detailed implementation report
└── README.md # This file
```

---

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|--------------------|-------------------------------|--------------------------------------|
| `THRESHOLD_CPU` | `75` | CPU usage threshold (%) |
| `THRESHOLD_MEMORY` | `75` | Memory usage threshold (%) |
| `THRESHOLD_DISK` | `75` | Disk usage threshold (%) |
| `CHECK_INTERVAL` | `10` | Seconds between resource checks |
| `SUSTAINED_CHECKS` | `3` | Consecutive breaches before scaling |
| `COOLDOWN_SECONDS` | `300` | Cooldown after a scale event (s) |
| `AWS_REGION` | `us-east-1` | AWS region for EC2 instances |
| `INSTANCE_NAME` | `vcc-scaled-instance` | Name tag for the EC2 instance |
| `KEY_PAIR_NAME` | `your-aws-key-pair-name` | AWS key pair name for SSH access |
| `SSH_KEY_PATH` | `~/.ssh/id_rsa` | Path to SSH private key |

### Ports

| Port | Service |
|------|----------------|
| 5000 | Flask App |
| 9090 | Prometheus |
| 3000 | Grafana |
| 9100 | Node Exporter |

---