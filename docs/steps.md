# All Execution Steps

## 2a. Alternative: Docker Compose (Apple Silicon / no VirtualBox)

If `vagrant up` fails (for example **Apple Silicon** with an **amd64-only** VirtualBox box, or **Vagrant** blocked on the **Downloads** folder), run the same services with Docker:

```bash
cd vcc_assignment_3
docker compose up -d
```

- Flask: [http://localhost:5000](http://localhost:5000)  
- Prometheus: [http://localhost:9090](http://localhost:9090)  
- Grafana: [http://localhost:3000](http://localhost:3000) (admin/admin)  
- Node exporter metrics: [http://localhost:9100/metrics](http://localhost:9100/metrics)

Stop with: `docker compose down`.

On macOS, if port **5000** is used by **AirPlay Receiver**, change the app port mapping in `docker-compose.yml` (e.g. `5001:5000`) or turn off AirPlay in **System Settings → AirDrop & Handoff**.

AWS CLI, Terraform, and `terraform.tfvars` can be configured on your **host**; you do not need the VM for those steps.

---

## 1. Initialize Git Repository
```bash
cd vcc_assignment_3
git init && git add -A && git commit -m "Initial commit: VCC Assignment 3"
```

## 2. Start the Local VM
```bash
vagrant up
```

## 3. SSH into the VM
```bash
vagrant ssh
```

## 4. Verify Installations (inside VM)
```bash
docker --version
terraform --version
aws --version
python3 --version
systemctl status node_exporter
```

## 5. Configure AWS Credentials (inside VM)
```bash
aws configure
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region name: us-east-1
# Default output format: json
```

## 6. Verify AWS Authentication
```bash
aws sts get-caller-identity
```

## 7. Create EC2 Key Pair
```bash
aws ec2 create-key-pair --key-name vcc-key --query 'KeyMaterial' --output text > ~/.ssh/vcc-key.pem
chmod 400 ~/.ssh/vcc-key.pem
```

## 8. Configure Terraform Variables
```bash
cd /vagrant/cloud/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values:
nano terraform.tfvars
```

Set these values in the file:
```hcl
aws_region = "us-east-1"
instance_name = "vcc-scaled-instance"
instance_type = "t2.medium"
key_pair_name = "vcc-key"
```

## 9. Initialize Terraform
```bash
cd /vagrant/cloud/terraform
terraform init
terraform plan
```

## 10. Start the Flask Application
```bash
cd /vagrant
source venv/bin/activate
python app/app.py &
```

## 11. Start the Monitoring Stack (Prometheus + Grafana)
```bash
cd /vagrant
sudo docker-compose -f docker-compose.monitoring.yml up -d
```

## 12. Verify Monitoring Services
```bash
curl -s http://localhost:9090/-/healthy
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/login
curl -s http://localhost:9100/metrics | head -5
```

Open in browser:
- Flask App Dashboard: http://localhost:5000
- Grafana Dashboard: http://localhost:3000 (admin/admin)
- Prometheus: http://localhost:9090

## 13. Start the Resource Monitor
```bash
cd /vagrant
source venv/bin/activate
sudo python monitoring/scripts/monitor.py
```

## 14. Generate Heavy Load (trigger auto-scaling)

Option A — From Dashboard UI:
Open http://localhost:5000 and click "Heavy Load (triggers scale)"

Option B — From command line:
```bash
curl -X POST http://localhost:5000/api/load/heavy
```

Option C — Using stress-ng:
```bash
stress-ng --cpu 2 --vm 1 --vm-bytes 1G --timeout 60s
```

## 15. Observe Auto-Scaling in Action
- Watch monitor.py logs: breach count goes from 1/3 → 2/3 → 3/3 → SCALE UP
- Watch Grafana at http://localhost:3000: gauges turn red above 75%
- Watch AWS Console at https://console.aws.amazon.com/ec2/: new instance appears

## 16. Verify Cloud Deployment
```bash
cd /vagrant/cloud/terraform
terraform output instance_ip
curl http://INSTANCE_IP:5000/health
curl http://INSTANCE_IP:5000/api/status
```

## 17. Scale Down (destroy AWS resources)
```bash
export AWS_REGION="us-east-1"
export KEY_PAIR_NAME="vcc-key"
bash /vagrant/cloud/scripts/scale_down.sh
```

## 18. Verify Resources Are Destroyed
```bash
cd /vagrant/cloud/terraform
terraform show
```

## 19. Stop All Services
```bash
# Stop resource monitor: Ctrl+C in its terminal

# Stop Flask app
kill %1

# Stop monitoring stack
cd /vagrant
sudo docker-compose -f docker-compose.monitoring.yml down
```

## 20. Exit and Stop the VM
```bash
exit
vagrant halt
```