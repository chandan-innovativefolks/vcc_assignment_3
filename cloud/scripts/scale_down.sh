#!/bin/bash
#
# Scale Down — Destroy the AWS EC2 instance when load returns to normal.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
LOG_FILE="/var/log/scale_down.log"

AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_NAME="${INSTANCE_NAME:-vcc-scaled-instance}"
KEY_PAIR_NAME="${KEY_PAIR_NAME:-your-aws-key-pair-name}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SCALE-DOWN] $1" | tee -a "$LOG_FILE"
}

log "========================================="
log "Starting cloud scale-down process"
log "========================================="

cd "$TERRAFORM_DIR"

terraform destroy -auto-approve -input=false -no-color \
    -var="aws_region=$AWS_REGION" \
    -var="instance_name=$INSTANCE_NAME" \
    -var="key_pair_name=$KEY_PAIR_NAME" \
    2>&1 | tee -a "$LOG_FILE"

rm -f /tmp/autoscale.lock

log "========================================="
log "Scale-down complete. AWS resources destroyed."
log "========================================="
