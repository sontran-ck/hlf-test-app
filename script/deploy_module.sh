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
APPLICATION_PREFIX="${APPLICATION_PREFIX:-static-app}"

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

# Get RDS connection information from CloudFormation
echo "=========================================="
echo "Getting RDS connection info from CloudFormation..."
echo "=========================================="

# Get RDS Stack ID
RDS_STACK_ID=$(aws cloudformation describe-stack-resources \
    --stack-name "${STACK_NAME}" \
    --region "${AWS_REGION}" \
    --query 'StackResources[?LogicalResourceId==`RDSStack`].PhysicalResourceId' \
    --output text)

if [ -z "$RDS_STACK_ID" ]; then
    echo "ERROR: Could not find RDS Stack!"
    exit 1
fi

echo "RDS Stack ID: ${RDS_STACK_ID}"

# Get RDS connection details from CloudFormation outputs
DB_HOST=$(aws cloudformation describe-stacks \
    --stack-name "${RDS_STACK_ID}" \
    --region "${AWS_REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ClusterEndpoint`].OutputValue' \
    --output text)

DB_PORT=$(aws cloudformation describe-stacks \
    --stack-name "${RDS_STACK_ID}" \
    --region "${AWS_REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ClusterPort`].OutputValue' \
    --output text)

DB_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${RDS_STACK_ID}" \
    --region "${AWS_REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`DatabaseName`].OutputValue' \
    --output text)

DB_USERNAME=$(aws cloudformation describe-stacks \
    --stack-name "${RDS_STACK_ID}" \
    --region "${AWS_REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`MasterUsername`].OutputValue' \
    --output text)

MASTER_SECRET_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${RDS_STACK_ID}" \
    --region "${AWS_REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`MasterUserSecretArn`].OutputValue' \
    --output text)

# Get RDS secret name directly from CloudFormation output
# Note: CloudFormation returns full secret name with version suffix (e.g., rds!cluster-xxx-YYYYYY)
# We need to remove the last 7 characters (-YYYYYY) to get the actual secret name
RDS_SECRET_NAME_WITH_SUFFIX=$(aws cloudformation describe-stacks \
    --stack-name "${RDS_STACK_ID}" \
    --region "${AWS_REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`MasterUserSecretName`].OutputValue' \
    --output text)

# Remove the version suffix (last 7 characters: -XXXXXX)
# AWS Secrets Manager secret names from RDS don't include the version suffix
RDS_SECRET_NAME="${RDS_SECRET_NAME_WITH_SUFFIX%-??????}"

if [ -z "$DB_HOST" ] || [ -z "$DB_PORT" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USERNAME" ] || [ -z "$RDS_SECRET_NAME" ]; then
    echo "ERROR: Failed to retrieve RDS connection information from CloudFormation!"
    echo "DB_HOST: ${DB_HOST}"
    echo "DB_PORT: ${DB_PORT}"
    echo "DB_NAME: ${DB_NAME}"
    echo "DB_USERNAME: ${DB_USERNAME}"
    echo "RDS_SECRET_NAME_WITH_SUFFIX: ${RDS_SECRET_NAME_WITH_SUFFIX}"
    echo "RDS_SECRET_NAME: ${RDS_SECRET_NAME}"
    exit 1
fi

echo "DB_HOST: ${DB_HOST}"
echo "DB_PORT: ${DB_PORT}"
echo "DB_NAME: ${DB_NAME}"
echo "DB_USERNAME: ${DB_USERNAME}"
echo "MASTER_SECRET_ARN: ${MASTER_SECRET_ARN}"
echo "RDS_SECRET_NAME (for External Secrets): ${RDS_SECRET_NAME}"

# Get EKS Security Group IDs from CloudFormation (for SecurityGroupPolicy in Helm)
echo "=========================================="
echo "Getting EKS Security Group IDs..."
echo "=========================================="

EKS_POD_SG_ID=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${AWS_REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`EKSPodSecurityGroupId`].OutputValue' \
    --output text)

EKS_CLUSTER_SG_ID=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${AWS_REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`EKSClusterSecurityGroupId`].OutputValue' \
    --output text)

if [ -z "$EKS_POD_SG_ID" ] || [ -z "$EKS_CLUSTER_SG_ID" ]; then
    echo "WARNING: Could not retrieve EKS Security Group IDs from CloudFormation"
    echo "EKS_POD_SG_ID: ${EKS_POD_SG_ID}"
    echo "EKS_CLUSTER_SG_ID: ${EKS_CLUSTER_SG_ID}"
else
    echo "EKS Pod Security Group ID: ${EKS_POD_SG_ID}"
    echo "EKS Cluster Security Group ID: ${EKS_CLUSTER_SG_ID}"
fi

# Deploy application using Helm
echo "=========================================="
echo "Deploying application modules..."
echo "=========================================="

# Use ECR repository from CloudFormation or override with environment variable
ECR_REPOSITORY="${ECR_REPOSITORY_URL:-${ECR_REPOSITORY}}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "Using image: ${ECR_REPOSITORY}:${IMAGE_TAG}"

# Deploy the test application with RDS connection info from CloudFormation
# Note: SecurityGroupPolicy and ExternalSecret are now managed as Helm templates

# Check if release already exists
if helm list -n ${APP_NAMESPACE} | grep -q "^static-app"; then
    echo "Release static-app already exists. Checking for changes..."
    
    # Get current revision
    CURRENT_REVISION=$(helm list -n ${APP_NAMESPACE} -o json | jq -r '.[] | select(.name=="static-app") | .revision')
    
    helm upgrade static-app ./charts/static-app \
        --namespace ${APP_NAMESPACE} \
        --set image.repository=${ECR_REPOSITORY} \
        --set image.tag=${IMAGE_TAG} \
        --set environment=${ENVIRONMENT} \
        --set database.host=${DB_HOST} \
        --set database.port=${DB_PORT} \
        --set database.name=${DB_NAME} \
        --set database.username=${DB_USERNAME} \
        --set securityGroups.eksClusterSecurityGroupId=${EKS_CLUSTER_SG_ID} \
        --set securityGroups.eksPodSecurityGroupId=${EKS_POD_SG_ID} \
        --set externalSecrets.rdsSecretKey=${RDS_SECRET_NAME} \
        --values ./envs/${ENVIRONMENT}/values.yaml \
        --wait --timeout 5m > /dev/null 2>&1
    
    # Get new revision
    NEW_REVISION=$(helm list -n ${APP_NAMESPACE} -o json | jq -r '.[] | select(.name=="static-app") | .revision')
    
    if [ "$CURRENT_REVISION" = "$NEW_REVISION" ]; then
        echo "No changes detected. Release unchanged (revision ${CURRENT_REVISION})"
    else
        echo "Application upgraded (revision ${CURRENT_REVISION} → ${NEW_REVISION})"
    fi
else
    helm install static-app ./charts/static-app \
        --namespace ${APP_NAMESPACE} \
        --set image.repository=${ECR_REPOSITORY} \
        --set image.tag=${IMAGE_TAG} \
        --set environment=${ENVIRONMENT} \
        --set database.host=${DB_HOST} \
        --set database.port=${DB_PORT} \
        --set database.name=${DB_NAME} \
        --set database.username=${DB_USERNAME} \
        --set securityGroups.eksClusterSecurityGroupId=${EKS_CLUSTER_SG_ID} \
        --set securityGroups.eksPodSecurityGroupId=${EKS_POD_SG_ID} \
        --set externalSecrets.rdsSecretKey=${RDS_SECRET_NAME} \
        --values ./envs/${ENVIRONMENT}/values.yaml \
        --wait --timeout 5m > /dev/null 2>&1
    
    echo "Application deployed successfully"
fi

# Wait for External Secrets to sync
echo "Waiting for External Secrets to sync..."
echo "Checking ExternalSecret status..."

# Wait up to 2 minutes for ExternalSecret to be ready
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    ES_STATUS=$(kubectl get externalsecret static-app-rds-credentials -n ${APP_NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    
    if [ "$ES_STATUS" = "True" ]; then
        echo "ExternalSecret is ready and synced"
        
        # Verify the secret exists and has data
        if kubectl get secret static-app-database-secret -n ${APP_NAMESPACE} -o jsonpath='{.data.DB_PASSWORD}' 2>/dev/null | base64 -d | grep -q .; then
            echo "Database password secret is available"
            break
        else
            echo "Secret exists but DB_PASSWORD is empty, waiting..."
        fi
    else
        echo "Waiting for ExternalSecret to sync... (${ELAPSED}s/${TIMEOUT}s)"
    fi
    
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: ExternalSecret failed to sync within ${TIMEOUT} seconds!"
    kubectl describe externalsecret static-app-rds-credentials -n ${APP_NAMESPACE} || true
    exit 1
fi

# Force pod restart to ensure it picks up the secret
# This is critical: pods that started before the secret existed won't have DB_PASSWORD
echo "Ensuring pods have the latest secrets..."
kubectl rollout restart deployment/static-app -n ${APP_NAMESPACE}
kubectl rollout status deployment/static-app -n ${APP_NAMESPACE} --timeout=5m

echo "All pods restarted with database credentials"

# Show deployment status
echo "=========================================="
echo "Deployment Status"
echo "=========================================="
kubectl get deployments -n ${APP_NAMESPACE}
kubectl get pods -n ${APP_NAMESPACE}
kubectl get services -n ${APP_NAMESPACE}
kubectl get securitygrouppolicies -n ${APP_NAMESPACE} || true
kubectl get externalsecrets -n ${APP_NAMESPACE} || true
kubectl get secrets -n ${APP_NAMESPACE} | grep "database-secret" || true

echo "=========================================="
echo "Application Module Deployment Completed"
echo "=========================================="
