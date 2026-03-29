# Implementation Plan — One Command Execution

## Run Everything With a Single Command

```bash
cd vcc_assignment_3
./run.sh YOUR_AWS_ACCESS_KEY YOUR_AWS_SECRET_KEY us-east-1
```

That's it. This single command will automatically execute all 10 steps below without any manual intervention.

---

## What It Does (automatically)

| Step | Action | Time |
|------|--------|------|
| Phase 1 | Initialize git repository | ~2s |
| Phase 2 | Create & provision VirtualBox VM (`vagrant up`) | ~5-10 min |
| Step 1 | Verify all installations inside VM | ~2s |
| Step 2 | Configure AWS credentials (non-interactive) | ~3s |
| Step 3 | Create EC2 key pair (`vcc-key`) | ~3s |
| Step 4 | Configure Terraform variables | ~1s |
| Step 5 | Initialize Terraform + preview plan | ~15s |
| Step 6 | Start Flask application on port 5000 | ~3s |
| Step 7 | Start Prometheus + Grafana via Docker Compose | ~10s |
| Step 8 | Start resource monitor daemon | ~5s |
| Step 9 | Generate heavy CPU load (stress-ng 60s) + wait for breach | ~2 min |
| Step 10 | Verify auto-scaling — check EC2 instance + cloud app | ~30s |

**Total estimated time: ~15-20 minutes** (mostly VM provisioning on first run)

---

## Prerequisites (install these first)

1. **VirtualBox** — https://www.virtualbox.org/wiki/Downloads
2. **Vagrant** — https://developer.hashicorp.com/vagrant/downloads
3. **Git** — `xcode-select --install` (macOS) or https://git-scm.com
4. **AWS Account** with:
- IAM user with **AmazonEC2FullAccess** policy
- Access Key ID and Secret Access Key

---

## Example

```bash
./run.sh AKIAIOSFODNN7EXAMPLE wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY us-east-1
```

The third argument (region) is optional — defaults to `us-east-1`.

---

## After Execution — What You'll See

```
============================================
ALL DONE — Everything is running!
============================================

Open in your browser:
Dashboard: http://localhost:5000
Grafana: http://localhost:3000 (admin/admin)
Prometheus: http://localhost:9090

Logs (inside VM via 'vagrant ssh'):
tail -f /tmp/flask_app.log
tail -f /tmp/resource_monitor.log
============================================
```

---

## Flow of Execution

```
./run.sh AWS_KEY AWS_SECRET REGION
│
├── git init + git commit
│
├── vagrant up
│ └── provision.sh installs: Docker, AWS CLI, Terraform, Node Exporter, Python
│
└── vagrant ssh -c "..." (runs everything inside VM automatically)
│
├── Step 1: Verify Docker, Terraform, AWS CLI, Python, Node Exporter
├── Step 2: Write AWS credentials to ~/.aws/credentials (no prompts)
├── Step 3: aws ec2 create-key-pair --key-name vcc-key
├── Step 4: cp terraform.tfvars.example terraform.tfvars + sed
├── Step 5: terraform init + terraform plan
├── Step 6: python app/app.py (background) + health check
├── Step 7: docker-compose up -d (Prometheus + Grafana) + verify
├── Step 8: python monitor.py (background) + verify logs
├── Step 9: curl POST /api/load/heavy + stress-ng --cpu 2 --timeout 60s
│ └── monitor.py detects breach > 75% for 3 checks
│ └── triggers scale_up.sh automatically
│ └── terraform apply (creates EC2 instance)
│ └── scp app to EC2 + start gunicorn
└── Step 10: terraform output instance_ip + curl health check on EC2
```

---

## Services After Completion

| Service | URL | Credentials |
|---------|-----|-------------|
| Flask App Dashboard | http://localhost:5000 | — |
| Grafana Monitoring | http://localhost:3000 | admin / admin |
| Prometheus | http://localhost:9090 | — |
| Node Exporter | http://localhost:9100/metrics | — |
| Cloud App (EC2) | http://EC2_IP:5000 | — |

---