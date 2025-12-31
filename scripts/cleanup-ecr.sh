#!/bin/bash
# cleanup-ecr.sh
# Delete all images from ECR repository before destroying infrastructure

# Fetch details from Terraform
REPO_URL=$(cd infra && terraform output -raw ecr_repository_url)
REGION=$(echo $REPO_URL | cut -d'.' -f4)
REPO_NAME=$(echo $REPO_URL | cut -d'/' -f2)

echo "Deleting all images from ECR repository: $REPO_NAME in region: $REGION"

# Get all image digests
IMAGE_DIGESTS=$(aws ecr list-images --repository-name $REPO_NAME --region $REGION --query 'imageIds[*].imageDigest' --output text)

if [ -z "$IMAGE_DIGESTS" ]; then
    echo "No images found in repository"
    exit 0
fi

# Delete all images
for DIGEST in $IMAGE_DIGESTS; do
    echo "Deleting image: $DIGEST"
    aws ecr batch-delete-image \
        --repository-name $REPO_NAME \
        --region $REGION \
        --image-ids imageDigest=$DIGEST
done

echo "All images deleted successfully"
