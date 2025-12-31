# Kubernetes Auto-Scaling Production Cluster (AWS - K3s)

This project provisions a production-grade Kubernetes cluster using **K3s on AWS EC2**, implementing full auto-scaling capabilities (HPA + Cluster Autoscaler) and observability (Prometheus/Grafana).

## Architecture

![Architecture](diagrams/architecture.png)

**Key Design Decisions:**
- **Infrastructure**: Terraform-managed VPC with two public subnets across AZs.
- **Compute**: EC2 `t3.small` instances (2 vCPU, 2GB RAM). Upgraded from `t3.micro` to handle the full monitoring stack reliably.
- **Kubeconfig Access**: Secured via **AWS Systems Manager (SSM)**. No SSH keys or public SSH ports required. The retrieval process uses Gzip + Base64 to handle SSM output limits.
- **Auto-Scaling**:
  - **Horizontal Pod Autoscaler (HPA)**: Scales application pods based on 50% CPU utilization.
  - **Cluster Autoscaler**: Integrated with AWS Auto Scaling Group (ASG) to add/remove EC2 nodes based on pod demand.
- **Cost Optimization**: All resources reside in public subnets to avoid NAT Gateway costs (~$32/mo savings).

## Folder Structure

```
├── app/              # Python Flask App (w/ /health, /metrics, /load)
├── infra/            # Terraform (VPC, IAM, EC2, ASG, ALB, ECR)
├── k8s/              # Kubernetes Manifests (App & Cluster Autoscaler)
├── monitoring/       # Helm Values for Prometheus & Grafana
├── scripts/          # Automation (Fetch Kubeconfig, Load Test, ECR Cleanup)
└── Makefile          # Project Command Center
```

## Prerequisites

- **AWS CLI** configured (`aws configure`)
- **Terraform**, **kubectl**, **Helm**, **Docker**, **Python 3**
- **k6** (for load testing)

## Deployment Guide

### 1. Provision Infrastructure
```bash
make infra-init
make infra-apply
```

### 2. Build and Push Application
```bash
make app-build
make app-push
```

### 3. Fetch Kubeconfig
Uses a robust Python script to fetch, decompress, and sanitize the kubeconfig via SSM.
```bash
make fetch-kubeconfig
# The Makefile now auto-detects k3s.yaml if it exists.
# No manual export is required for make commands!
```

### 4. Deploy Everything
Deploys Cluster Autoscaler, Prometheus, Grafana, and the Flask App.
```bash
make deploy
```

## Validation & Auto-Scaling

### 1. Verification
```bash
kubectl get pods -A
# Access health endpoint
curl http://$(cd infra && terraform output -raw alb_dns_name)/health
```

### 2. Trigger Auto-Scaling (Load Test)
Run the load test in one terminal and watch the HPA/Nodes in others:
```bash
# Terminal A: Watch HPA
kubectl get hpa -w

# Terminal B: Watch Nodes
kubectl get nodes -w

# Terminal C: Start Load
make load-test
```

### 3. Observability
- **Grafana**: `kubectl port-forward svc/grafana 3000:80` (Visit `localhost:3000`, admin/admin)
- **Prometheus**: `kubectl port-forward svc/prometheus-server 9090:80`

## Cost Analysis & Teardown

- **EC2**: 1 server + 1-3 agents (`t3.small`). Total ~$0.04 - $0.09/hour.
- **ALB**: ~$0.022/hour.

**CRITICAL: Destroy resources after use to avoid billing!**
```bash
# 1. Cleanup ECR images first
chmod +x scripts/cleanup-ecr.sh
./scripts/cleanup-ecr.sh

# 2. Destroy infrastructure
make infra-destroy
```
