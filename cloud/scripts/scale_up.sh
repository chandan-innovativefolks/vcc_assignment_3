#!/bin/bash
#
# Scale Up — Provision an AWS EC2 instance and deploy the application.
# Called automatically when local VM resource usage exceeds 75%.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
APP_DIR="${SCRIPT_DIR}/../../app"
mkdir -p "${SCRIPT_DIR}/../logs"
LOG_FILE="${SCALE_UP_LOG:-${SCRIPT_DIR}/../logs/scale_up.log}"

AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_NAME="${INSTANCE_NAME:-vcc-scaled-instance}"
KEY_PAIR_NAME="${KEY_PAIR_NAME:-vcc-key}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SCALE-UP] $1" | tee -a "$LOG_FILE"
}

log "========================================="
log "Starting cloud scale-up process"
log "Region: $AWS_REGION"
log "Instance Type: t2.medium"
log "========================================="

log "Step 1: Validating prerequisites..."

if ! command -v aws &>/dev/null; then
    log "ERROR: AWS CLI not found"
    exit 1
fi

if ! command -v terraform &>/dev/null; then
    log "ERROR: terraform not found"
    exit 1
fi

if ! aws sts get-caller-identity &>/dev/null; then
    log "ERROR: No active AWS credentials. Run 'aws configure'"
    exit 1
fi

log "Prerequisites validated"

log "Step 2: Deploying cloud infrastructure (terraform apply)..."

cd "$TERRAFORM_DIR"

terraform init -input=false -no-color 2>&1 | tee -a "$LOG_FILE"

terraform apply -auto-approve -input=false -no-color 2>&1 | tee -a "$LOG_FILE"

log "Terraform apply finished."
terraform output -no-color 2>&1 | tee -a "$LOG_FILE"

log "========================================="
log "Scale-up complete."
log "========================================="
