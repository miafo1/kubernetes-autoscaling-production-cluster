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
	# Refreshing terraform state to ensure we have the instance ID
	cd infra && terraform refresh
	$(eval CP_ID := $(shell cd infra && terraform output -raw control_plane_id))
	$(eval CP_IP := $(shell cd infra && terraform output -raw control_plane_ip))
	python3 scripts/fetch_kubeconfig.py $(AWS_REGION) $(CP_ID) $(CP_IP)

deploy-infra:
	kubectl apply -f k8s/infra/ --request-timeout=5m --validate=false
	# Install Helm Charts for Monitoring (without --wait to avoid TLS timeouts on t3.micro)
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install prometheus prometheus-community/prometheus -f monitoring/prometheus-values.yaml --timeout 5m
	helm upgrade --install grafana prometheus-community/grafana -f monitoring/grafana-values.yaml --timeout 5m

deploy-app: get-ecr-url
	# Replace placeholder with actual ECR URL and apply
	sed "s|REPLACE_ME_WITH_ECR_REPO_URL|$(ECR_URL)|g" k8s/app/deployment.yaml | kubectl apply -f - --request-timeout=5m --validate=false
	kubectl apply -f k8s/app/service.yaml --request-timeout=5m
	kubectl apply -f k8s/app/hpa.yaml --request-timeout=5m

deploy: deploy-infra deploy-app

load-test:
	$(eval ALB_DNS := $(shell cd infra && terraform output -raw alb_dns_name))
	k6 run -e ALB_DNS=$(ALB_DNS) scripts/load-test.js
