# Makefile
# Automation for build, deploy, and infrastructure management

AWS_REGION ?= us-east-1
CLUSTER_NAME ?= k3s-demo-cluster
ECR_REPO_NAME ?= $(CLUSTER_NAME)-app

.PHONY: all infra-init infra-apply infra-destroy app-build app-push deploy clean

all: infra-init infra-apply app-build app-push deploy

# --- Infrastructure ---
infra-init:
	cd infra && terraform init

infra-plan:
	cd infra && terraform plan

infra-apply:
	cd infra && terraform apply -auto-approve

infra-destroy:
	cd infra && terraform destroy -auto-approve

# --- Application ---
get-ecr-url:
	$(eval ECR_URL := $(shell cd infra && terraform output -raw ecr_repository_url))

app-login:
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(shell cd infra && terraform output -raw ecr_repository_url | cut -d'/' -f1)

app-build: get-ecr-url
	cd app && docker build -t $(ECR_URL):latest .

app-push: get-ecr-url app-login
	docker push $(ECR_URL):latest

# --- Kubernetes ---
fetch-kubeconfig:
	$(eval CP_IP := $(shell cd infra && terraform output -raw control_plane_ip))
	ssh -o StrictHostKeyChecking=no ubuntu@$(CP_IP) "sudo cat /etc/rancher/k3s/k3s.yaml" > k3s.yaml
	sed -i 's/127.0.0.1/$(CP_IP)/g' k3s.yaml
	@echo "Kubeconfig saved to k3s.yaml. Run: export KUBECONFIG=$(PWD)/k3s.yaml"

deploy-infra:
	kubectl apply -f k8s/infra/
	# Install Helm Charts for Monitoring
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install prometheus prometheus-community/prometheus -f monitoring/prometheus-values.yaml
	helm upgrade --install grafana prometheus-community/grafana -f monitoring/grafana-values.yaml

deploy-app: get-ecr-url
	# Replace placeholder with actual ECR URL and apply
	sed "s|REPLACE_ME_WITH_ECR_REPO_URL|$(ECR_URL)|g" k8s/app/deployment.yaml | kubectl apply -f -
	kubectl apply -f k8s/app/service.yaml
	kubectl apply -f k8s/app/hpa.yaml

deploy: deploy-infra deploy-app

load-test:
	$(eval ALB_DNS := $(shell cd infra && terraform output -raw alb_dns_name))
	k6 run -e ALB_DNS=$(ALB_DNS) scripts/load-test.js
