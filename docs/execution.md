# Execution Guide — Step-by-Step Commands

This document lists every command you need to run, in order, to execute the full project from scratch.

---

## Phase 1: Install Prerequisites (on your host machine)

### 1.1 Install VirtualBox

Download and install from: https://www.virtualbox.org/wiki/Downloads

```bash
# Verify installation
VBoxManage --version
```

### 1.2 Install Vagrant

Download and install from: https://developer.hashicorp.com/vagrant/downloads

```bash
# Verify installation
vagrant --version
```

### 1.3 Install AWS CLI v2

Download and install from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

```bash
# macOS
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Verify installation
aws --version
```

### 1.4 Configure AWS Credentials

```bash
aws configure
```

When prompted, enter:
```
AWS Access Key ID: <your-access-key>
AWS Secret Access Key: <your-secret-key>
Default region name: us-east-1
Default output format: json
```

### 1.5 Verify AWS Authentication

```bash
aws sts get-caller-identity
```

You should see output with your account ID, user ARN, etc.

---

## Phase 2: Create the Local VM

### 2.1 Clone the Repository

```bash
git clone <repository-url>
cd vcc_assignment_3
```

### 2.2 Start the VM

```bash
vagrant up
```

This will take 5-10 minutes on first run. It will:
- Download the Ubuntu 22.04 base image
- Create a VirtualBox VM (2 CPU, 2 GB RAM)
- Run the provisioning script to install all tools inside the VM

### 2.3 SSH into the VM

```bash
vagrant ssh
```

You are now inside the VM. All subsequent commands run here.

### 2.4 Verify Everything Installed Correctly

```bash
docker --version
```

Expected output: `Docker version 24.x.x` or higher

```bash
terraform --version
```

Expected output: `Terraform v1.x.x`

```bash
aws --version
```

Expected output: `aws-cli/2.x.x ...`

```bash
python3 --version
```

Expected output: `Python 3.10.x` or higher

```bash
systemctl status node_exporter
```

Expected output: `active (running)`

---

## Phase 3: Deploy the Sample Flask Application

### 3.1 Activate the Python Virtual Environment

```bash
cd /vagrant
source venv/bin/activate
```

### 3.2 Start the Flask Application

```bash
cd /vagrant/app
python app.py
```

Expected output:
```
* Running on http://0.0.0.0:5000
```

### 3.3 Verify the Application (open a new terminal)

Open a second terminal on your host machine:

```bash
curl http://localhost:5000/health
```

Expected output:
```json
{"status": "healthy"}
```

```bash
curl http://localhost:5000/api/status
```

Expected output: JSON with cpu, memory, disk percentages.

### 3.4 Open the Dashboard in Your Browser

Navigate to: **http://localhost:5000**

You should see the Auto-Scaling Demo dashboard with CPU, Memory, Disk gauges and load test buttons.

---

## Phase 4: Set Up Resource Monitoring (Prometheus + Grafana)

### 4.1 Start the Monitoring Stack

Inside the VM:

```bash
cd /vagrant
sudo docker-compose -f docker-compose.monitoring.yml up -d
```

Expected output:
```
Creating prometheus ... done
Creating grafana ... done
```

### 4.2 Verify Prometheus Is Running

```bash
curl -s http://localhost:9090/-/healthy
```

Expected output: `Prometheus Server is Healthy.`

### 4.3 Verify Grafana Is Running

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/login
```

Expected output: `200`

### 4.4 Open Grafana in Your Browser

Navigate to: **http://localhost:3000**

- Username: `admin`
- Password: `admin`
- Skip the password change prompt (or set a new password)

### 4.5 View the Pre-Configured Dashboard

1. Click the hamburger menu (top-left)
2. Click **Dashboards**
3. Click **VCC Auto-Scaling Monitor**

You should see:
- CPU Usage gauge (green/yellow/red zones)
- Memory Usage gauge
- Disk Usage gauge
- CPU and Memory time-series graphs
- Auto-Scale Threshold status indicator

### 4.6 Verify Node Exporter Metrics

```bash
curl -s http://localhost:9100/metrics | head -20
```

Expected output: Lines starting with `node_` showing system metrics.

### 4.7 Verify Prometheus Is Scraping Targets

Navigate to: **http://localhost:9090/targets**

You should see three targets, all with State = `UP`:
- `prometheus` (localhost:9090)
- `node_exporter` (host.docker.internal:9100)
- `flask_app` (host.docker.internal:5000)

---

## Phase 5: Start the Resource Monitor

### 5.1 Start the Monitor Daemon

Open a new terminal inside the VM (`vagrant ssh` from host):

```bash
cd /vagrant
source venv/bin/activate
sudo python monitoring/scripts/monitor.py
```

Expected output:
```
============================================================
Resource Monitor Started
CPU threshold: 75.0%
Memory threshold: 75.0%
Disk threshold: 75.0%
Check interval: 10s
Sustained checks: 3
Cooldown: 300s
============================================================
[OK] CPU=2.5% | MEM=34.2% | DISK=18.7%
[OK] CPU=1.8% | MEM=34.1% | DISK=18.7%
...
```

The monitor is now checking resources every 10 seconds. Keep this terminal open.

---

## Phase 6: Configure AWS Auto-Scaling

### 6.1 Configure AWS Credentials Inside the VM

```bash
aws configure
```

Enter the same credentials you used on the host:
```
AWS Access Key ID: <your-access-key>
AWS Secret Access Key: <your-secret-key>
Default region name: us-east-1
Default output format: json
```

### 6.2 Verify AWS Credentials

```bash