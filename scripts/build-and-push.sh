#!/bin/bash
set -e

# Configuration
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-337608386221}"
ECR_REPOSITORY="hlf-lab-ecr-sit-test-app"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "=========================================="
echo "Building and Pushing Docker Image"
echo "=========================================="
echo "AWS Region: ${AWS_REGION}"
echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "ECR Repository: ${ECR_REPOSITORY}"
echo "Image Tag: ${IMAGE_TAG}"
echo "=========================================="

# Full ECR URI
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"

# Login to ECR
echo "Logging into Amazon ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build Docker image
echo "Building Docker image..."
docker build -t ${ECR_REPOSITORY}:${IMAGE_TAG} .

# Tag image
echo "Tagging image..."
docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} ${ECR_URI}:${IMAGE_TAG}
docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} ${ECR_URI}:latest

# Push to ECR
echo "Pushing image to ECR..."
docker push ${ECR_URI}:${IMAGE_TAG}
docker push ${ECR_URI}:latest

echo "=========================================="
echo "Image pushed successfully!"
echo "Image: ${ECR_URI}:${IMAGE_TAG}"
echo "=========================================="
