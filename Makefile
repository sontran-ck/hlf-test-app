.PHONY: help install dev build run test docker-build docker-run push deploy clean

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
	docker build -t hlf-lab-test-app:latest .

docker-run: ## Run Docker container locally
	docker run -p 8080:8080 \
		-e ENVIRONMENT=development \
		-e LOG_LEVEL=debug \
		-e PORT=8080 \
		hlf-lab-test-app:latest

push: ## Build and push Docker image to ECR
	./scripts/build-and-push.sh

deploy: ## Deploy to Kubernetes
	./script/deploy_module.sh

helm-lint: ## Lint Helm charts
	helm lint ./charts/test-app

helm-template: ## Generate Kubernetes manifests from Helm chart
	helm template test-app ./charts/test-app \
		--namespace test-app \
		--values ./envs/sit/values.yaml

helm-install: ## Install Helm chart
	helm upgrade --install test-app ./charts/test-app \
		--namespace test-app \
		--create-namespace \
		--values ./envs/sit/values.yaml

helm-uninstall: ## Uninstall Helm chart
	helm uninstall test-app -n test-app

k8s-logs: ## View Kubernetes logs
	kubectl logs -f deployment/test-app -n test-app

k8s-status: ## Check Kubernetes deployment status
	kubectl get all -n test-app

k8s-describe: ## Describe Kubernetes deployment
	kubectl describe deployment test-app -n test-app

clean: ## Clean build artifacts
	rm -rf node_modules
	rm -rf dist
	rm -rf coverage
	rm -f npm-debug.log*
