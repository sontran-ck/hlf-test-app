.PHONY: help install dev build run test docker-build docker-run push deploy clean

# Configuration
ENV ?= sit
AWS_REGION ?= ap-southeast-1
AWS_ACCOUNT_ID ?= 337608386221
ECR_REPOSITORY ?= $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/hlf-lab-ecr-$(ENV)-test-app
IMAGE_TAG ?= latest
EKS_CLUSTER_NAME ?= hlf-lab-eks-$(ENV)
APP_NAMESPACE ?= default

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

install: ## Install dependencies
	npm install

dev: ## Run application in development mode
	npm run dev

build: ## Build application
	npm run build

run: ## Run application in production mode
	npm start

test: ## Run tests
	npm test

docker-build: ## Build Docker image
	docker build -t hlf-lab-test-app:$(IMAGE_TAG) .

docker-run: ## Run Docker container locally
	docker run -p 8080:8080 \
		-e ENVIRONMENT=development \
		-e LOG_LEVEL=debug \
		-e PORT=8080 \
		hlf-lab-test-app:$(IMAGE_TAG)

ecr-login: ## Login to AWS ECR
	aws ecr get-login-password --region $(AWS_REGION) | \
		docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com

build-and-push: ecr-login ## Build and push Docker image to ECR
	docker build -t $(ECR_REPOSITORY):$(IMAGE_TAG) .
	docker push $(ECR_REPOSITORY):$(IMAGE_TAG)
	@echo "Image pushed: $(ECR_REPOSITORY):$(IMAGE_TAG)"

push: build-and-push ## Alias for build-and-push

update-kubeconfig: ## Update kubectl configuration for EKS
	aws eks update-kubeconfig --name $(EKS_CLUSTER_NAME) --region $(AWS_REGION)

deploy: update-kubeconfig ## Deploy to Kubernetes
	@echo "Deploying to $(ENV) environment in $(APP_NAMESPACE) namespace..."
	ENVIRONMENT=$(ENV) \
	AWS_DEFAULT_REGION=$(AWS_REGION) \
	EKS_CLUSTER_NAME=$(EKS_CLUSTER_NAME) \
	APP_NAMESPACE=$(APP_NAMESPACE) \
	./script/deploy_module.sh

helm-lint: ## Lint Helm charts
	helm lint ./charts/test-app

helm-template: ## Generate Kubernetes manifests from Helm chart
	helm template test-app ./charts/test-app \
		--namespace $(APP_NAMESPACE) \
		--values ./envs/$(ENV)/values.yaml

helm-install: update-kubeconfig ## Install Helm chart
	helm upgrade --install test-app ./charts/test-app \
		--namespace $(APP_NAMESPACE) \
		--values ./envs/$(ENV)/values.yaml \
		--wait --timeout 5m

helm-uninstall: update-kubeconfig ## Uninstall Helm chart
	helm uninstall test-app -n $(APP_NAMESPACE)

k8s-logs: update-kubeconfig ## View Kubernetes logs
	kubectl logs -f deployment/test-app -n $(APP_NAMESPACE)

k8s-status: update-kubeconfig ## Check Kubernetes deployment status
	@echo "Resources in $(APP_NAMESPACE):"
	kubectl get all -n $(APP_NAMESPACE)

k8s-describe: update-kubeconfig ## Describe Kubernetes deployment
	kubectl describe deployment test-app -n $(APP_NAMESPACE)

k8s-pods: update-kubeconfig ## Get pod details
	kubectl get pods -n $(APP_NAMESPACE) -o wide

k8s-events: update-kubeconfig ## Show namespace events
	kubectl get events -n $(APP_NAMESPACE) --sort-by='.lastTimestamp'

clean: ## Clean build artifacts
	rm -rf node_modules
	rm -rf dist
	rm -rf coverage
	rm -f npm-debug.log*

# Full deployment workflow
full-deploy: build-and-push deploy k8s-status ## Build, push and deploy in one command
	@echo "Full deployment completed!"
