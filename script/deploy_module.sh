#!/bin/bash
set -e

echo "=========================================="
echo "Application Module Deployment Started"
echo "=========================================="

# Environment variables
ENVIRONMENT="${ENVIRONMENT:-sit}"
AWS_REGION="${AWS_DEFAULT_REGION:-ap-southeast-1}"
CLUSTER_NAME="${EKS_CLUSTER_NAME}"
APP_NAMESPACE="${APP_NAMESPACE:-default}"
PROJECT_NAME="${PROJECT_NAME:-hlf}"
STACK_NAME="${PROJECT_NAME}-${ENVIRONMENT}-stack"
APPLICATION_PREFIX="${APPLICATION_PREFIX:-test-app}"

echo "Environment: ${ENVIRONMENT}"
echo "AWS Region: ${AWS_REGION}"
echo "EKS Cluster: ${CLUSTER_NAME}"
echo "Application Namespace: ${APP_NAMESPACE}"
echo "Stack Name: ${STACK_NAME}"

# Get AWS Account ID
echo "Getting AWS Account ID..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"

# Get ECR Repository URL from CloudFormation
echo "Getting ECR Repository URL from CloudFormation..."
STORAGE_STACK_ID=$(aws cloudformation describe-stack-resources \
    --stack-name "${STACK_NAME}" \
    --region "${AWS_REGION}" \
    --query 'StackResources[?LogicalResourceId==`StorageStack`].PhysicalResourceId' \
    --output text)

if [ -z "$STORAGE_STACK_ID" ]; then
    echo "WARNING: Could not find StorageStack, using default ECR repository name"
    ECR_REPOSITORY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-ecr-${ENVIRONMENT}-${APPLICATION_PREFIX}"
else
    echo "Storage Stack ID: ${STORAGE_STACK_ID}"
    
    # Try to get ECR repository ARN from CloudFormation
    ECR_ARN=$(aws cloudformation describe-stacks \
        --stack-name "${STORAGE_STACK_ID}" \
        --region "${AWS_REGION}" \
        --query 'Stacks[0].Outputs[?OutputKey==`RepositoryArn`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ECR_ARN" ]; then
        # Extract repository name from ARN: arn:aws:ecr:region:account:repository/name
        ECR_REPO_NAME=$(echo "$ECR_ARN" | sed 's/.*repository\///')
        ECR_REPOSITORY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"
        echo "ECR Repository (from CloudFormation): ${ECR_REPOSITORY}"
    else
        echo "WARNING: Could not find ECR repository in CloudFormation, using default name"
        ECR_REPOSITORY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-ecr-${ENVIRONMENT}-${APPLICATION_PREFIX}"
    fi
fi

# Check if kubectl is configured
echo "Checking Kubernetes connectivity..."
kubectl cluster-info
kubectl get nodes

# Apply External Secrets manifests if exist
if [ -d "./manifests/external-secrets" ]; then
    echo "=========================================="
    echo "Applying External Secrets manifests..."
    echo "=========================================="
    
    # Apply SecretStore if exists
    if [ -f "./manifests/external-secrets/secret-store.yaml" ]; then
        echo "Creating SecretStore resources..."
        kubectl apply -f ./manifests/external-secrets/secret-store.yaml
    fi
    
    # Apply ExternalSecret for RDS if exists
    if [ -f "./manifests/external-secrets/external-secret-rds.yaml" ]; then
        echo "Creating ExternalSecret for RDS credentials..."
        kubectl apply -f ./manifests/external-secrets/external-secret-rds.yaml -n ${APP_NAMESPACE}
    fi
    
    # Wait for secrets to be created
    echo "Waiting for secrets to be synced..."
    sleep 5
    
    # Check if secrets are created
    kubectl get externalsecrets -n ${APP_NAMESPACE} || true
    
    echo "External Secrets applied successfully"
fi

# Deploy application using Helm
echo "=========================================="
echo "Deploying application modules..."
echo "=========================================="

# Use ECR repository from CloudFormation or override with environment variable
ECR_REPOSITORY="${ECR_REPOSITORY_URL:-${ECR_REPOSITORY}}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "Using image: ${ECR_REPOSITORY}:${IMAGE_TAG}"

# Deploy the test application
helm upgrade --install test-app ./charts/test-app \
    --namespace ${APP_NAMESPACE} \
    --set image.repository=${ECR_REPOSITORY} \
    --set image.tag=${IMAGE_TAG} \
    --set environment=${ENVIRONMENT} \
    --values ./envs/${ENVIRONMENT}/values.yaml \
    --wait --timeout 5m

echo "Application deployed successfully"

# Show deployment status
echo "=========================================="
echo "Deployment Status"
echo "=========================================="
kubectl get deployments -n ${APP_NAMESPACE}
kubectl get pods -n ${APP_NAMESPACE}
kubectl get services -n ${APP_NAMESPACE}
kubectl get externalsecrets -n ${APP_NAMESPACE} || true
kubectl get secrets -n ${APP_NAMESPACE} | grep -E "rds-database-secret|NAME" || true

echo "=========================================="
echo "Application Module Deployment Completed"
echo "=========================================="
