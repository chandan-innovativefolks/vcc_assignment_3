#!/bin/bash
#
# Lightweight resource checker — runs as a cron job or standalone.
# Triggers scale_up.sh if any resource metric exceeds 75%.

THRESHOLD=75
SCALE_SCRIPT="$(dirname "$0")/../../cloud/scripts/scale_up.sh"
LOG_FILE="/var/log/resource_check.log"
LOCK_FILE="/tmp/autoscale.lock"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" | tee -a "$LOG_FILE"
}

CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2 + $4)}')
MEM_USAGE=$(free | awk '/Mem:/ {printf "%d", ($3/$2)*100}')
DISK_USAGE=$(df / | awk 'NR==2 {print int($5)}')

log "INFO" "CPU=${CPU_USAGE}% | MEM=${MEM_USAGE}% | DISK=${DISK_USAGE}%"

BREACH=false
REASONS=""

if [ "$CPU_USAGE" -gt "$THRESHOLD" ]; then
    BREACH=true
    REASONS="${REASONS}CPU=${CPU_USAGE}% "
fi

if [ "$MEM_USAGE" -gt "$THRESHOLD" ]; then
    BREACH=true
    REASONS="${REASONS}MEM=${MEM_USAGE}% "
fi

if [ "$DISK_USAGE" -gt "$THRESHOLD" ]; then
    BREACH=true
    REASONS="${REASONS}DISK=${DISK_USAGE}% "
fi

if [ "$BREACH" = true ]; then
    log "WARN" "Threshold exceeded: $REASONS"

    if [ -f "$LOCK_FILE" ]; then
        LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
        if [ "$LOCK_AGE" -lt 300 ]; then
            log "INFO" "Scale-up already triggered recently (${LOCK_AGE}s ago), skipping"
            exit 0
        fi
    fi

    log "WARN" "Triggering cloud auto-scale..."
    touch "$LOCK_FILE"

    if bash "$SCALE_SCRIPT" >> "$LOG_FILE" 2>&1; then
        log "INFO" "Scale-up completed successfully"
    else
        log "ERROR" "Scale-up failed"
        rm -f "$LOCK_FILE"
        exit 1
    fi
else
    log "INFO" "All resources within normal limits"
fi
