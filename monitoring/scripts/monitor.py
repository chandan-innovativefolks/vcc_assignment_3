#!/usr/bin/env python3
"""
Resource Monitor & Auto-Scaling Trigger

Continuously monitors local VM resource usage (CPU, memory, disk).
When any metric exceeds the 75% threshold for a sustained period,
it triggers cloud auto-scaling by provisioning an AWS EC2 instance.
"""

import os
import sys
import json
import time
import logging
import subprocess
from datetime import datetime

import psutil

THRESHOLD_CPU = float(os.environ.get("THRESHOLD_CPU", 75.0))
THRESHOLD_MEMORY = float(os.environ.get("THRESHOLD_MEMORY", 75.0))
THRESHOLD_DISK = float(os.environ.get("THRESHOLD_DISK", 75.0))
CHECK_INTERVAL = int(os.environ.get("CHECK_INTERVAL", 10))
SUSTAINED_CHECKS = int(os.environ.get("SUSTAINED_CHECKS", 3))
COOLDOWN_SECONDS = int(os.environ.get("COOLDOWN_SECONDS", 300))

_PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_DEFAULT_LOG = os.path.join(_PROJECT_ROOT, "logs", "resource_monitor.log")
LOG_FILE = os.environ.get("LOG_FILE", _DEFAULT_LOG)
SCALE_SCRIPT = os.path.join(_PROJECT_ROOT, "cloud", "scripts", "scale_up.sh")

os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

_handlers = [logging.StreamHandler(sys.stdout)]
try:
    _handlers.append(logging.FileHandler(LOG_FILE, mode="a"))
except OSError:
    pass

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=_handlers,
)
logger = logging.getLogger("resource_monitor")


class ResourceMonitor:
    def __init__(self):
        self.breach_count = 0
        self.last_scale_time = 0
        self.scaled_up = False
        self.history = []

    def collect_metrics(self):
        cpu = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory().percent
        disk = psutil.disk_usage("/").percent

        metrics = {
            "timestamp": datetime.utcnow().isoformat(),
            "cpu_percent": cpu,
            "memory_percent": memory,
            "disk_percent": disk,
        }
        self.history.append(metrics)
        if len(self.history) > 360:
            self.history = self.history[-360:]

        return metrics

    def check_thresholds(self, metrics):
        breaches = []
        if metrics["cpu_percent"] > THRESHOLD_CPU:
            breaches.append(f"CPU={metrics['cpu_percent']:.1f}%")
        if metrics["memory_percent"] > THRESHOLD_MEMORY:
            breaches.append(f"Memory={metrics['memory_percent']:.1f}%")
        if metrics["disk_percent"] > THRESHOLD_DISK:
            breaches.append(f"Disk={metrics['disk_percent']:.1f}%")
        return breaches

    def trigger_scale_up(self, breaches):
        now = time.time()
        if now - self.last_scale_time < COOLDOWN_SECONDS:
            remaining = int(COOLDOWN_SECONDS - (now - self.last_scale_time))
            logger.info(f"Scale-up in cooldown, {remaining}s remaining")
            return False

        logger.warning(f"THRESHOLD BREACHED: {', '.join(breaches)}")
        logger.warning("Initiating AWS auto-scale...")

        try:
            result = subprocess.run(
                ["bash", SCALE_SCRIPT],
                capture_output=True,
                text=True,
                timeout=600,
            )
            if result.returncode == 0:
                logger.info(f"Scale-up succeeded:\n{result.stdout}")
                self.scaled_up = True
                self.last_scale_time = now
                return True
            else:
                logger.error(f"Scale-up failed (exit {result.returncode}):\n{result.stderr}")
                return False
        except FileNotFoundError:
            logger.error(f"Scale script not found: {SCALE_SCRIPT}")
            return False
        except subprocess.TimeoutExpired:
            logger.error("Scale-up script timed out after 600s")
            return False

    def run(self):
        logger.info("=" * 60)
        logger.info("Resource Monitor Started")
        logger.info(f" CPU threshold: {THRESHOLD_CPU}%")
        logger.info(f" Memory threshold: {THRESHOLD_MEMORY}%")
        logger.info(f" Disk threshold: {THRESHOLD_DISK}%")
        logger.info(f" Check interval: {CHECK_INTERVAL}s")
        logger.info(f" Sustained checks: {SUSTAINED_CHECKS}")
        logger.info(f" Cooldown: {COOLDOWN_SECONDS}s")
        logger.info("=" * 60)

        while True:
            try:
                metrics = self.collect_metrics()
                breaches = self.check_thresholds(metrics)

                status = "OK"
                if breaches:
                    self.breach_count += 1
                    status = f"WARN ({self.breach_count}/{SUSTAINED_CHECKS})"
                else:
                    self.breach_count = 0

                logger.info(
                    f"[{status}] CPU={metrics['cpu_percent']:.1f}% | "
                    f"MEM={metrics['memory_percent']:.1f}% | "
                    f"DISK={metrics['disk_percent']:.1f}%"
                )

                if self.breach_count >= SUSTAINED_CHECKS:
                    self.trigger_scale_up(breaches)
                    self.breach_count = 0

                time.sleep(CHECK_INTERVAL)

            except KeyboardInterrupt:
                logger.info("Monitor stopped by user")
                break
            except Exception as e:
                logger.error(f"Unexpected error: {e}")
                time.sleep(CHECK_INTERVAL)


if __name__ == "__main__":
    monitor = ResourceMonitor()
    monitor.run()
