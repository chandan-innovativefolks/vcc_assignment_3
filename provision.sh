#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Updating package index ==="
sudo apt-get update -y

echo "=== Installing core dependencies ==="
sudo -E apt-get install -y \
    python3 python3-pip python3-venv python3-setuptools \
    curl wget git jq stress-ng unzip \
    apt-transport-https ca-certificates gnupg lsb-release

echo "=== Installing Docker ==="
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker vagrant

echo "=== Installing Docker Compose ==="
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

echo "=== Setting up Python environment ==="
rm -rf /home/vagrant/venv
python3 -m venv /home/vagrant/venv
source /home/vagrant/venv/bin/activate
cd /vagrant
pip install --upgrade pip
pip install -r app/requirements.txt

echo "=== Installing Node Exporter ==="
NODE_EXPORTER_VERSION="1.7.0"
ARCH="$(uname -m)"

if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    NODE_EXPORTER_ARCH="arm64"
else
    NODE_EXPORTER_ARCH="amd64"
fi

wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${NODE_EXPORTER_ARCH}.tar.gz"
tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-${NODE_EXPORTER_ARCH}.tar.gz"
sudo cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-${NODE_EXPORTER_ARCH}/node_exporter" /usr/local/bin/
rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-${NODE_EXPORTER_ARCH}"*

sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'UNIT'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=vagrant
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter

echo "=== Installing AWS CLI v2 ==="
ARCH="$(uname -m)"
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    AWSCLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
else
    AWSCLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
fi

curl -fsSL "$AWSCLI_URL" -o "/tmp/awscliv2.zip"
unzip -qo /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install --update
rm -rf /tmp/aws /tmp/awscliv2.zip

echo "=== Installing Terraform ==="
wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update -y
sudo -E apt-get install -y terraform

echo "=== Setting up monitoring stack via Docker Compose ==="
cd /vagrant
if docker compose version >/dev/null 2>&1; then
    sudo docker compose -f docker-compose.monitoring.yml up -d
else
    sudo docker-compose -f docker-compose.monitoring.yml up -d
fi

echo "=== Provisioning complete ==="
echo "Flask App:     http://localhost:5000"
echo "Prometheus:    http://localhost:9090"
echo "Grafana:       http://localhost:3000 (admin/admin)"
echo "Node Exporter: http://localhost:9100/metrics"