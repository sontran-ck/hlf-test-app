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

echo "Environment: ${ENVIRONMENT}"
echo "AWS Region: ${AWS_REGION}"
echo "EKS Cluster: ${CLUSTER_NAME}"
echo "Application Namespace: ${APP_NAMESPACE}"

# Check if kubectl is configured
echo "Checking Kubernetes connectivity..."
kubectl cluster-info
kubectl get nodes

# Apply Storage configuration (EFS StorageClass)
if [ -d "./manifests/storage" ]; then
    echo "=========================================="
    echo "Applying Storage configuration..."
    echo "=========================================="
    
    # Get EFS File System ID from CloudFormation
    STACK_NAME="hlf-${ENVIRONMENT}-storage"
    echo "Fetching EFS File System ID from CloudFormation stack: ${STACK_NAME}"
    
    export EFS_FILE_SYSTEM_ID=$(aws cloudformation describe-stacks \
        --stack-name ${STACK_NAME} \
        --region ${AWS_REGION} \
        --query "Stacks[0].Outputs[?OutputKey=='EFSFileSystemId'].OutputValue" \
        --output text)
    
    if [ -z "$EFS_FILE_SYSTEM_ID" ]; then
        echo "Warning: EFS File System ID not found in CloudFormation. Checking alternative output names..."
        # Try alternative output key names
        export EFS_FILE_SYSTEM_ID=$(aws cloudformation describe-stacks \
            --stack-name ${STACK_NAME} \
            --region ${AWS_REGION} \
            --query "Stacks[0].Outputs[?contains(OutputKey,'EFS') && contains(OutputKey,'FileSystem')].OutputValue | [0]" \
            --output text)
    fi
    
    if [ -n "$EFS_FILE_SYSTEM_ID" ] && [ "$EFS_FILE_SYSTEM_ID" != "None" ]; then
        echo "EFS File System ID: ${EFS_FILE_SYSTEM_ID}"
        
        # Apply StorageClass with EFS ID substitution
        if [ -f "./manifests/storage/storageclass-efs.yaml" ]; then
            echo "Creating EFS StorageClass..."
            envsubst < ./manifests/storage/storageclass-efs.yaml | kubectl apply -f -
            
            # Verify StorageClass
            kubectl get storageclass efs-sc || echo "Warning: StorageClass not created"
        fi
    else
        echo "Warning: EFS File System ID not found. Skipping StorageClass creation."
        echo "PersistentVolumeClaims may fail if StorageClass is required."
    fi
    
    echo "Storage configuration applied successfully"
fi

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

# Get ECR repository URL from environment or construct it
ECR_REPOSITORY="${ECR_REPOSITORY_URL:-${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/hlf-lab-ecr-sit-test-app}"
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
echo ""
echo "📦 Deployments:"
kubectl get deployments -n ${APP_NAMESPACE}

echo ""
echo "🚀 Pods:"
kubectl get pods -n ${APP_NAMESPACE}

echo ""
echo "🌐 Services:"
kubectl get services -n ${APP_NAMESPACE}

echo ""
echo "💾 Persistent Volume Claims:"
kubectl get pvc -n ${APP_NAMESPACE} || echo "No PVCs found"

echo ""
echo "📂 StorageClass:"
kubectl get storageclass efs-sc || echo "EFS StorageClass not found"

echo ""
echo "🔐 External Secrets:"
kubectl get externalsecrets -n ${APP_NAMESPACE} || echo "No External Secrets found"

echo ""
echo "🔑 Secrets:"
kubectl get secrets -n ${APP_NAMESPACE} | grep -E "rds-database-secret|NAME" || echo "RDS secret not found"

# Verify integrations
echo ""
echo "=========================================="
echo "Integration Verification"
echo "=========================================="

# Check if PVC is bound
PVC_STATUS=$(kubectl get pvc -n ${APP_NAMESPACE} -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [ "$PVC_STATUS" = "Bound" ]; then
    echo "✅ PVC Status: Bound"
else
    echo "⚠️  PVC Status: $PVC_STATUS"
fi

# Check if secret is synced
SECRET_EXISTS=$(kubectl get secret rds-database-secret -n ${APP_NAMESPACE} -o name 2>/dev/null || echo "")
if [ -n "$SECRET_EXISTS" ]; then
    echo "✅ RDS Secret: Synced"
else
    echo "⚠️  RDS Secret: Not found"
fi

# Check pod readiness
POD_READY=$(kubectl get pods -n ${APP_NAMESPACE} -l app.kubernetes.io/name=test-app -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
if [ "$POD_READY" = "True" ]; then
    echo "✅ Pod Readiness: Ready"
else
    echo "⚠️  Pod Readiness: $POD_READY"
fi

echo ""
echo "=========================================="
echo "Application Module Deployment Completed"
echo "=========================================="
