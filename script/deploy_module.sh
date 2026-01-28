#!/bin/bash
set -e

echo "=========================================="
echo "Application Module Deployment Started"
echo "=========================================="

# Environment variables
ENVIRONMENT="${ENVIRONMENT:-sit}"
AWS_REGION="${AWS_DEFAULT_REGION:-ap-southeast-1}"
CLUSTER_NAME="${EKS_CLUSTER_NAME}"
APP_NAMESPACE="${APP_NAMESPACE:-test-app}"

echo "Environment: ${ENVIRONMENT}"
echo "AWS Region: ${AWS_REGION}"
echo "EKS Cluster: ${CLUSTER_NAME}"
echo "Application Namespace: ${APP_NAMESPACE}"

# Check if kubectl is configured
echo "Checking Kubernetes connectivity..."
kubectl cluster-info
kubectl get nodes

# Create namespace if it doesn't exist
echo "Creating namespace ${APP_NAMESPACE} if not exists..."
kubectl create namespace ${APP_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Deploy application using Helm
echo "Deploying application modules..."

# Get ECR repository URL from environment or construct it
ECR_REPOSITORY="${ECR_REPOSITORY_URL:-${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/hlf-lab-ecr-sit-test-app}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "Using image: ${ECR_REPOSITORY}:${IMAGE_TAG}"

# Deploy the test application
helm upgrade --install test-app ./charts/test-app \
    --namespace ${APP_NAMESPACE} \
    --create-namespace \
    --set image.repository=${ECR_REPOSITORY} \
    --set image.tag=${IMAGE_TAG} \
    --set environment=${ENVIRONMENT} \
    --values ./envs/${ENVIRONMENT}/values.yaml \
    --wait --timeout 5m

echo "Application deployed successfully"

# Show deployment status
echo "Deployment status:"
kubectl get deployments -n ${APP_NAMESPACE}
kubectl get pods -n ${APP_NAMESPACE}
kubectl get services -n ${APP_NAMESPACE}

echo "=========================================="
echo "Application Module Deployment Completed"
echo "=========================================="
