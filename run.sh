#!/bin/bash
set -e

# =============================================
# VCC Assignment 3 — ONE COMMAND SETUP
# =============================================
#
# Usage:
# ./run.sh <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> [AWS_REGION]
#
# Example:
# ./run.sh AKIAIOSFODNN7EXAMPLE wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY us-east-1
#
# =============================================

if [ $# -lt 2 ]; then
  echo ""
  echo "Usage: ./run.sh <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> [AWS_REGION]"
  echo ""
  echo "Example:"
  echo "./run.sh AKIAIOSFODNN7EXAMPLE wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY us-east-1"
  echo ""
  exit 1
fi

AWS_KEY="$1"
AWS_SECRET="$2"
AWS_REGION="${3:-us-east-1}"

echo ""
echo "============================================"
echo " VCC Assignment 3 — Full Automated Setup"
echo "============================================"
echo " AWS Region: $AWS_REGION"
echo "============================================"
echo ""

# ---- PHASE 1: Git Init ----
echo "[Phase 1/4] Initializing git repository..."
if [ ! -d ".git" ]; then
  git init
  git add -A
  git commit -m "Initial commit: VCC Assignment 3" || true
  echo "Done."
else
  echo "Git repo already exists, skipping."
fi
echo ""

# ---- PHASE 2: Start VM ----
echo "[Phase 2/4] Starting the local VM (this may take a few minutes on first run)..."
vagrant up --provider=virtualbox
echo "VM is running."
echo ""

# ---- PHASE 3: Create setup script to run inside VM ----
echo "[Phase 3/4] Configuring and starting all services inside the VM..."
echo ""

cat > /tmp/vcc_vm_setup.sh <<EOF
#!/bin/bash
set -e

AWS_REGION="${AWS_REGION}"

echo "============================================"
echo " Inside VM — Automated Setup Running"
echo "============================================"

# --- Step 1: Verify Installations ---
echo ""
echo "[Step 1/10] Verifying installations..."
echo "Docker: \$(docker --version 2>&1 || echo 'Docker not found')"
echo "Terraform: \$(terraform --version 2>&1 | head -1 || echo 'Terraform not found')"
echo "AWS CLI: \$(aws --version 2>&1 || echo 'AWS CLI not found')"
echo "Python: \$(python3 --version 2>&1 || echo 'Python3 not found')"
echo "Node Exporter: \$(systemctl is-active node_exporter 2>/dev/null || echo 'unknown')"

# --- Step 2: Configure AWS (non-interactive) ---
echo ""
echo "[Step 2/10] Configuring AWS credentials..."
mkdir -p ~/.aws

cat > ~/.aws/credentials <<AWSCRED
[default]
aws_access_key_id = ${AWS_KEY}
aws_secret_access_key = ${AWS_SECRET}
AWSCRED

cat > ~/.aws/config <<AWSCONF
[default]
region = ${AWS_REGION}
output = json
AWSCONF

echo "Verifying AWS authentication..."
aws sts get-caller-identity
echo "AWS configured successfully."

# --- Step 3: Create EC2 Key Pair ---
echo ""
echo "[Step 3/10] Creating EC2 key pair..."
mkdir -p ~/.ssh

if aws ec2 describe-key-pairs --key-names vcc-key >/dev/null 2>&1; then
  echo "Key pair 'vcc-key' already exists, skipping."

  if [ ! -f ~/.ssh/vcc-key.pem ]; then
    echo "WARNING: AWS key pair exists, but ~/.ssh/vcc-key.pem is missing."
    echo "You will not be able to SSH into EC2 unless you recreate/download the PEM manually."
  fi
else
  aws ec2 create-key-pair \
    --key-name vcc-key \
    --query 'KeyMaterial' \
    --output text > ~/.ssh/vcc-key.pem

  chmod 400 ~/.ssh/vcc-key.pem
  echo "Key pair created at ~/.ssh/vcc-key.pem"
fi

# --- Step 4: Configure Terraform ---
echo ""
echo "[Step 4/10] Configuring Terraform variables..."
cd /vagrant/cloud/terraform

if [ -f terraform.tfvars.example ]; then
  cp -f terraform.tfvars.example terraform.tfvars
else
  echo "ERROR: terraform.tfvars.example not found in /vagrant/cloud/terraform"
  exit 1
fi

sed -i 's/your-aws-key-pair-name/vcc-key/g' terraform.tfvars
sed -i "s/us-east-1/${AWS_REGION}/g" terraform.tfvars || true

echo "terraform.tfvars:"
cat terraform.tfvars

# --- Step 5: Initialize and Apply Terraform ---
echo ""
echo "[Step 5/10] Initializing Terraform..."
terraform init -input=false
echo "Terraform initialized."

echo ""
echo "Running Terraform plan..."
terraform plan -input=false -out=tfplan
echo "Terraform plan complete."

echo ""
echo "Running Terraform apply..."
terraform apply -auto-approve -input=false tfplan
echo "Terraform apply complete."

# --- Step 6: Start Flask Application ---
echo ""
echo "[Step 6/10] Starting Flask application..."
cd /vagrant

if [ -f /home/vagrant/venv/bin/activate ]; then
  source /home/vagrant/venv/bin/activate
else
  echo "WARNING: /home/vagrant/venv not found. Trying system Python."
fi

nohup python3 app/app.py > /tmp/flask_app.log 2>&1 &
sleep 5

echo "Health check:"
curl -s http://localhost:5000/health || echo "Flask health endpoint not responding yet"
echo ""
echo "Flask app expected at http://localhost:5000"

# --- Step 7: Start Monitoring Stack ---
echo ""
echo "[Step 7/10] Starting Prometheus + Grafana..."
cd /vagrant

if docker compose version >/dev/null 2>&1; then
  sudo docker compose -f docker-compose.monitoring.yml up -d
elif docker-compose version >/dev/null 2>&1; then
  sudo docker-compose -f docker-compose.monitoring.yml up -d
else
  echo "ERROR: Neither 'docker compose' nor 'docker-compose' is installed."
  exit 1
fi

sleep 8
echo "Prometheus: \$(curl -s http://localhost:9090/-/healthy || echo 'not ready')"
echo "Grafana HTTP Code: \$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/login || echo 'not ready')"
echo "Monitoring stack is running."

# --- Step 8: Start Resource Monitor ---
echo ""
echo "[Step 8/10] Starting resource monitor..."
cd /vagrant

if [ -f /home/vagrant/venv/bin/activate ]; then
  source /home/vagrant/venv/bin/activate
fi

nohup python3 monitoring/scripts/monitor.py > /tmp/resource_monitor.log 2>&1 &
sleep 5

echo "Latest monitor output:"
tail -5 /tmp/resource_monitor.log || true

# --- Step 9: Generate Heavy Load ---
echo ""
echo "[Step 9/10] Generating heavy CPU load to trigger auto-scaling..."
curl -s -X POST http://localhost:5000/api/load/heavy || true
echo ""

if command -v stress-ng >/dev/null 2>&1; then
  stress-ng --cpu 2 --vm 1 --vm-bytes 1G --timeout 60s &
  STRESS_PID=\$!

  echo "Waiting for threshold breach detection..."
  for i in \$(seq 1 12); do
    sleep 10
    echo ""
    echo "--- Check \$i (\$((i * 10))s elapsed) ---"
    tail -3 /tmp/resource_monitor.log || true
  done

  wait \$STRESS_PID 2>/dev/null || true
else
  echo "stress-ng not installed, skipping load generation."
fi

# --- Step 10: Verify Auto-Scaling ---
echo ""
echo "[Step 10/10] Checking auto-scaling results..."
echo ""
echo "Resource monitor log (last 20 lines):"
tail -20 /tmp/resource_monitor.log || true

cd /vagrant/cloud/terraform

INSTANCE_IP=\$(terraform output -raw instance_ip 2>/dev/null || echo "")
if [ -n "\$INSTANCE_IP" ]; then
  echo ""
  echo "EC2 instance deployed at: \$INSTANCE_IP"
  echo "Verifying cloud app..."
  sleep 10
  curl -s "http://\$INSTANCE_IP:5000/health" || echo "Instance may still be starting or SG may block access"
  echo ""
else
  echo "No instance_ip Terraform output found."
fi

echo ""
echo "============================================"
echo " ALL DONE — Everything is running!"
echo "============================================"
echo ""
echo "Open in your browser:"
echo "Dashboard:  http://localhost:5000"
echo "Grafana:    http://localhost:3000  (admin/admin)"
echo "Prometheus: http://localhost:9090"
echo ""
echo "Logs inside VM:"
echo "tail -f /tmp/flask_app.log"
echo "tail -f /tmp/resource_monitor.log"
echo "============================================"
EOF

chmod +x /tmp/vcc_vm_setup.sh

echo "Waiting for SSH to become ready after provisioning..."
SSH_READY=0
for i in $(seq 1 18); do
  if vagrant ssh -c "echo SSH is ready" >/dev/null 2>&1; then
    echo "SSH is ready."
    SSH_READY=1
    break
  fi
  echo "Still waiting for SSH... ($i/18)"
  sleep 10
done

if [ "$SSH_READY" -ne 1 ]; then
  echo "SSH not ready after initial wait. Trying: vagrant reload"
  vagrant reload

  for i in $(seq 1 18); do
    if vagrant ssh -c "echo SSH is ready" >/dev/null 2>&1; then
      echo "SSH is ready after reload."
      SSH_READY=1
      break
    fi
    echo "Still waiting for SSH after reload... ($i/18)"
    sleep 10
  done
fi

if [ "$SSH_READY" -ne 1 ]; then
  echo "ERROR: SSH did not become ready even after reload."
  echo "Try manually:"
  echo "  vagrant status"
  echo "  vagrant reload"
  echo "  vagrant ssh"
  exit 1
fi

echo "Uploading setup script to VM..."
vagrant upload /tmp/vcc_vm_setup.sh /tmp/vcc_vm_setup.sh

echo "Running setup script inside VM..."
vagrant ssh -c "chmod +x /tmp/vcc_vm_setup.sh && bash /tmp/vcc_vm_setup.sh"

# ---- PHASE 4: Done ----
echo ""
echo "============================================"
echo " COMPLETE — One command, everything done!"
echo "============================================"
echo ""
echo "Open in your browser:"
echo "Dashboard:  http://localhost:5001"
echo "Grafana:    http://localhost:3000  (admin/admin)"
echo "Prometheus: http://localhost:9090"
echo ""
echo "To SSH into the VM: vagrant ssh"
echo "============================================"