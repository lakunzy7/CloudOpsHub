#!/bin/bash
# Script to create Terraform state backend bucket in GCP
# Run this BEFORE running terraform init

set -e

PROJECT_ID="${1:-expandox-cloudehub}"
REGION="${2:-us-central1}"
BUCKET_NAME="${PROJECT_ID}-cloudopshub-tf-state"

echo "Creating Terraform state bucket: $BUCKET_NAME"
echo "Project: $PROJECT_ID"
echo "Region: $REGION"

# Enable required APIs if not already enabled
echo "Enabling required APIs..."
gcloud services enable storage.googleapis.com cloudresourcemanager.googleapis.com --project="$PROJECT_ID"

# Create the bucket with versioning enabled
gsutil mb -l "$REGION" -p "$PROJECT_ID" "gs://$BUCKET_NAME" || echo "Bucket may already exist, continuing..."
gsutil versioning set on "gs://$BUCKET_NAME"

# Optional: Set lifecycle rules for state files
cat > lifecycle.json <<EOF
{
  "rule": [
    {
      "action": { "type": "Delete" },
      "condition": { "num_newer_versions": 5 }
    }
  ]
}
EOF
gsutil lifecycle set lifecycle.json "gs://$BUCKET_NAME"
rm lifecycle.json

echo "✅ Terraform backend bucket created: gs://$BUCKET_NAME"
echo "You can now run: terraform init"
