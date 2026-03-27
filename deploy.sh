#!/bin/bash
set -euo pipefail

# Usage: ./deploy.sh <project-id> [model]
# Example: ./deploy.sh broze-net qwen3:30b-a3b

PROJECT="${1:?Usage: ./deploy.sh <project-id> [model]}"
MODEL="${2:-qwen3:30b-a3b}"
REGION="us-east4"
SERVICE="qwen-llm"
SA="qwen-runner@${PROJECT}.iam.gserviceaccount.com"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/qwen-repo/${SERVICE}"

echo "=== Deploying ${MODEL} to ${SERVICE} ==="

# Enable APIs
gcloud services enable \
  run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com cloudscheduler.googleapis.com \
  --project="${PROJECT}" --quiet

# Artifact Registry
gcloud artifacts repositories describe qwen-repo \
  --location="${REGION}" --project="${PROJECT}" &>/dev/null ||
  gcloud artifacts repositories create qwen-repo \
    --repository-format=docker --location="${REGION}" --project="${PROJECT}"

# Service account
gcloud iam service-accounts describe "${SA}" --project="${PROJECT}" &>/dev/null ||
  gcloud iam service-accounts create qwen-runner \
    --display-name="Qwen Cloud Run" --project="${PROJECT}"

# Build
gcloud builds submit app/ --tag="${IMAGE}:latest" --project="${PROJECT}" --timeout=1200

# Deploy
gcloud beta run deploy "${SERVICE}" \
  --image="${IMAGE}:latest" \
  --region="${REGION}" \
  --gpu=1 --gpu-type=nvidia-l4 \
  --cpu=8 --memory=32Gi \
  --no-cpu-throttling --cpu-boost \
  --concurrency=4 --timeout=1200 \
  --min-instances=0 --max-instances=1 \
  --set-env-vars="OLLAMA_MODEL=${MODEL}" \
  --no-gpu-zonal-redundancy \
  --no-allow-unauthenticated \
  --service-account="${SA}" \
  --project="${PROJECT}" --quiet

# Scheduler IAM
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT}" --format="value(projectNumber)")
gcloud run services add-iam-policy-binding "${SERVICE}" \
  --region="${REGION}" --member="serviceAccount:${SA}" \
  --role=roles/run.developer --project="${PROJECT}" --quiet &>/dev/null
gcloud iam service-accounts add-iam-policy-binding "${SA}" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloudscheduler.iam.gserviceaccount.com" \
  --role=roles/iam.serviceAccountUser --project="${PROJECT}" --quiet &>/dev/null

# Wake at 7AM, sleep at 9PM Central
for JOB in wake:1:"0 7 * * *" sleep:0:"0 21 * * *"; do
  IFS=: read -r NAME MIN_COUNT CRON <<< "${JOB}"
  JOB_NAME="${SERVICE}-${NAME}"
  VERB="create"; HFLAG="--headers"
  if gcloud scheduler jobs describe "${JOB_NAME}" --location="${REGION}" --project="${PROJECT}" &>/dev/null; then
    VERB="update"; HFLAG="--update-headers"
  fi
  gcloud scheduler jobs ${VERB} http "${JOB_NAME}" \
    --location="${REGION}" \
    --schedule="${CRON}" \
    --time-zone="America/Chicago" \
    --uri="https://run.googleapis.com/v2/projects/${PROJECT}/locations/${REGION}/services/${SERVICE}:patch?updateMask=template.scaling.minInstanceCount" \
    --http-method=POST \
    ${HFLAG}="Content-Type=application/json" \
    --message-body="{\"template\":{\"scaling\":{\"minInstanceCount\":${MIN_COUNT}}}}" \
    --oauth-service-account-email="${SA}" \
    --project="${PROJECT}" --quiet
done

echo ""
echo "Done. Wake: 7AM / Sleep: 9PM (America/Chicago)"
echo "Test: curl -H \"Authorization: Bearer \$(gcloud auth print-identity-token)\" https://\$(gcloud run services describe ${SERVICE} --region=${REGION} --project=${PROJECT} --format='value(status.url)')/v1/models"
