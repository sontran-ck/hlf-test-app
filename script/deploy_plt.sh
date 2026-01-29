#!/bin/bash
set -e

echo "=========================================="
echo "Platform Module Deployment Started"
echo "=========================================="

# Environment variables
ENVIRONMENT="${ENVIRONMENT:-sit}"
AWS_REGION="${AWS_DEFAULT_REGION:-ap-southeast-1}"
CLUSTER_NAME="${EKS_CLUSTER_NAME}"
PROJECT_NAME="${PROJECT_NAME:-hlf}"
STACK_NAME="${PROJECT_NAME}-${ENVIRONMENT}-stack"

echo "Environment: ${ENVIRONMENT}"
echo "AWS Region: ${AWS_REGION}"
echo "EKS Cluster: ${CLUSTER_NAME}"
echo "Stack Name: ${STACK_NAME}"

# Check if kubectl is configured
echo "Checking Kubernetes connectivity..."
kubectl cluster-info
kubectl get nodes

# Get EFS File System ID from CloudFormation
echo "=========================================="
echo "Getting EFS File System ID from CloudFormation..."
echo "=========================================="

# Get the Storage Stack ID
STORAGE_STACK_ID=$(aws cloudformation describe-stack-resources \
    --stack-name "${STACK_NAME}" \
    --region "${AWS_REGION}" \
    --query 'StackResources[?LogicalResourceId==`StorageStack`].PhysicalResourceId' \
    --output text)

if [ -z "$STORAGE_STACK_ID" ]; then
    echo "ERROR: Could not find StorageStack in main stack"
    exit 1
fi

echo "Storage Stack ID: ${STORAGE_STACK_ID}"

# Get EFS File System ID from Storage Stack
EFS_FILE_SYSTEM_ID=$(aws cloudformation describe-stacks \
    --stack-name "${STORAGE_STACK_ID}" \
    --region "${AWS_REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`EFSFileSystemId`].OutputValue' \
    --output text)

if [ -z "$EFS_FILE_SYSTEM_ID" ]; then
    echo "ERROR: Could not retrieve EFS File System ID from CloudFormation"
    exit 1
fi

echo "EFS File System ID: ${EFS_FILE_SYSTEM_ID}"

# Deploy EFS StorageClass
echo "=========================================="
echo "Deploying EFS StorageClass..."
echo "=========================================="

if [ -f "./manifests/storage/storageclass-efs.yaml" ]; then
    # Create a temporary file with EFS_FILE_SYSTEM_ID replaced
    TEMP_FILE=$(mktemp)
    sed "s/\${EFS_FILE_SYSTEM_ID}/${EFS_FILE_SYSTEM_ID}/g" ./manifests/storage/storageclass-efs.yaml > "$TEMP_FILE"
    
    echo "Applying EFS StorageClass..."
    kubectl apply -f "$TEMP_FILE"
    
    # Clean up temp file
    rm -f "$TEMP_FILE"
    
    echo "EFS StorageClass deployed successfully"
    kubectl get storageclass efs-sc || true
else
    echo "WARNING: EFS StorageClass manifest not found"
fi

# Deploy platform components
echo "Deploying platform modules..."

# Example: Deploy ingress controller (if needed)
if [ "${NGINX_INGRESS_ENABLE:-false}" = "true" ]; then
    echo "Deploying NGINX Ingress Controller..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --set controller.service.type=LoadBalancer \
        --wait --timeout 5m
    
    echo "NGINX Ingress Controller deployed successfully"
fi

# Example: Deploy metrics-server (if needed)
if [ "${METRICS_SERVER_ENABLE:-false}" = "true" ]; then
    echo "Deploying Metrics Server..."
    helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
    helm repo update
    
    helm upgrade --install metrics-server metrics-server/metrics-server \
        --namespace kube-system \
        --set args={--kubelet-insecure-tls} \
        --wait --timeout 5m
    
    echo "Metrics Server deployed successfully"
fi

echo "=========================================="
echo "Platform Module Deployment Completed"
echo "=========================================="
