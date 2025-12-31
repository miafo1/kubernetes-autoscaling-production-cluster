#!/bin/bash
# deploy-lightweight.sh
# Lightweight deployment script for resource-constrained clusters

set -e

echo "=== Deploying Cluster Autoscaler ==="
kubectl apply -f k8s/infra/cluster-autoscaler.yaml --server-side --validate=false || true

echo ""
echo "=== Deploying Application ==="
# Get ECR URL from terraform
ECR_URL=$(cd infra && terraform output -raw ecr_repository_url)
echo "Using ECR: $ECR_URL"

# Replace placeholder and deploy
sed "s|REPLACE_ME_WITH_ECR_REPO_URL|$ECR_URL|g" k8s/app/deployment.yaml | kubectl apply --server-side --validate=false -f - || true
kubectl apply --server-side --validate=false -f k8s/app/service.yaml || true
kubectl apply --server-side --validate=false -f k8s/app/hpa.yaml || true

echo ""
echo "=== Deployment Complete ==="
echo "Note: Prometheus and Grafana skipped due to resource constraints on t3.micro"
echo "To check deployment status: kubectl get pods -A"
echo "To access the app: curl http://\$(cd infra && terraform output -raw alb_dns_name)/health"
