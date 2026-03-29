# Architecture Diagram

## System Architecture — Local VM to Cloud Auto-Scaling

```mermaid
flowchart TD
subgraph LOCAL["Local Environment (VirtualBox VM)"]
APP["Flask Application<br/>:5000"]
NE["Node Exporter<br/>:9100"]
MON["Resource Monitor<br/>(monitor.py)"]
subgraph MONITORING["Monitoring Stack (Docker)"]
PROM["Prometheus<br/>:9090"]
GRAF["Grafana<br/>:3000"]
end
APP -->|"/metrics"| PROM
NE -->|"system metrics"| PROM
PROM -->|"data source"| GRAF
PROM -->|"alerts"| MON
MON -->|"polls CPU/MEM/DISK"| APP
end

MON -->|"threshold > 75%"| DECIDE{{"Resource Usage<br/>> 75%?"}}
DECIDE -->|"No"| NORMAL["Continue Monitoring<br/>(check every 10s)"]
NORMAL -->|"loop"| MON
DECIDE -->|"Yes (sustained)"| SCALE["Trigger Scale-Up<br/>(scale_up.sh)"]

subgraph CLOUD["Amazon Web Services (AWS)"]
TF["Terraform<br/>Infrastructure as Code"]
EC2["AWS EC2<br/>(t2.medium)"]
CAPP["Flask App<br/>(Cloud Instance)"]
SG["Security Group<br/>(:5000, :22, :80)"]
TF -->|"provision"| EC2
TF -->|"configure"| SG
EC2 -->|"runs"| CAPP
end

SCALE -->|"terraform apply"| TF
SCALE -->|"deploy app via SSH"| CAPP
USER(("User")) -->|"HTTP requests"| APP
USER -->|"redirected when scaled"| CAPP
USER -->|"view dashboards"| GRAF

style LOCAL fill:#1e293b,stroke:#38bdf8,color:#e2e8f0
style MONITORING fill:#0f172a,stroke:#818cf8,color:#e2e8f0
style CLOUD fill:#1a2e05,stroke:#4ade80,color:#e2e8f0
style DECIDE fill:#78350f,stroke:#f59e0b,color:#fef3c7
style SCALE fill:#7f1d1d,stroke:#ef4444,color:#fecaca
style NORMAL fill:#064e3b,stroke:#10b981,color:#d1fae5
```

## Sequence Diagram — Auto-Scaling Flow

```mermaid
sequenceDiagram
participant User
participant FlaskApp as Flask App (Local)
participant Monitor as Resource Monitor
participant Prometheus
participant Terraform
participant AWS as AWS EC2

User->>FlaskApp: Send heavy requests
FlaskApp->>FlaskApp: CPU/MEM usage increases
loop Every 10 seconds
Monitor->>Monitor: Check CPU, Memory, Disk
Monitor->>Prometheus: Query metrics
Prometheus-->>Monitor: Return metric values
end

Note over Monitor: Usage > 75% for 3 consecutive checks

Monitor->>Monitor: Threshold breached!
Monitor->>Terraform: Execute scale_up.sh
Terraform->>AWS: terraform apply (create EC2 instance)
AWS-->>Terraform: Instance created (public IP assigned)
Terraform->>AWS: Deploy app via SSH + SCP
AWS-->>Terraform: App running on :5000

Monitor-->>User: Scale-up complete notification
User->>AWS: Traffic redirected to cloud instance

Note over Monitor: When load decreases...
Monitor->>Terraform: Execute scale_down.sh
Terraform->>AWS: terraform destroy
AWS-->>Terraform: Resources terminated
User->>FlaskApp: Traffic returns to local VM
```

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│ LOCAL VM (VirtualBox) │
│ │
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────────────────────┐ │
│ │ Flask App │ │ Node Exporter│ │ Resource Monitor │ │
│ │ (Port 5000) │ │ (Port 9100) │ │ (monitor.py) │ │
│ │ │ │ │ │ │ │
│ │ /metrics ────┼──┼──► Prometheus│ │ • Polls CPU/MEM/DISK │ │
│ │ /api/status │ │ (Port 9090) │ • 75% threshold check │ │
│ │ /api/load │ │ │ │ • Sustained breach = scale │ │
│ └──────────────┘ │ ──► Grafana │ │ • 5min cooldown │ │
│ │ (Port 3000) │ │ │
│ └──────────────┘ └──────────┬───────────────────┘ │
│ │ │
└───────────────────────────────────────────────────┼─────────────────────┘
│
┌─────────▼─────────┐
│ Threshold > 75% │
│ for 3 checks? │
└────────┬──────────┘
│ YES
┌────────▼──────────┐
│ scale_up.sh │
│ (Terraform + │
│ AWS CLI) │
└────────┬──────────┘
│
┌──────────────────────────────────────────────────┼──────────────────────┐
│ AMAZON WEB SERVICES (AWS) │ │
│ ▼ │
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────────────────────┐ │
│ │ Security │ │ EC2 │ │ Flask App (Deployed) │ │
│ │ Group │──│ Instance │──│ (Port 5000) │ │
│ │ :5000,:22 │ │ t2.medium │ │ gunicorn + 4 workers │ │
│ └──────────────┘ └──────────────┘ └──────────────────────────────┘ │
│ │
└─────────────────────────────────────────────────────────────────────────┘
```