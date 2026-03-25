#!/bin/bash
set -e

# Sleep the Qwen GPU — sets min-instances=0 so Cloud Run scales to zero.
# The instance will shut down after the idle timeout (~15 min with no requests).

SERVICE="qwen-personal-assistant"
REGION="us-central1"
PROJECT="$(grep '^project_id:' ~/Secrets/ziggy-ansible-secrets.yml | awk '{print $2}' | tr -d '"'"'"'"')"

echo "Sleeping $SERVICE (setting min-instances=0)..."
gcloud run services update "$SERVICE" \
  --min-instances=0 \
  --region="$REGION" \
  --project="$PROJECT" \
  --quiet

echo "Done. GPU will scale to zero after idle timeout (~15 min)."
echo "No charges once the instance shuts down."
