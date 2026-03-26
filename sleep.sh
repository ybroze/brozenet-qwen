#!/bin/bash
set -e

# Sleep the Qwen GPU — sets min-instances=0 so Cloud Run scales to zero.
# The instance will shut down after the idle timeout (~15 min with no requests).
# Usage: ./sleep.sh @/path/to/secrets.yml

VARS="$(cd "$(dirname "$0")" && pwd)/ansible/vars.yml"
SERVICE="$(grep '^service_name:' "$VARS" | awk '{print $2}' | tr -d '\"'"'")"
REGION="$(grep '^region:' "$VARS" | awk '{print $2}' | tr -d '\"'"'")"

if [ -z "$1" ] || [[ "$1" != @* ]]; then
  echo "Usage: $0 @/path/to/secrets.yml"
  exit 1
fi

SECRETS_FILE="${1#@}"
PROJECT="$(grep '^project_id:' "$SECRETS_FILE" | awk '{print $2}' | tr -d '\"'"'")"

echo "Sleeping $SERVICE (setting min-instances=0)..."
gcloud run services update "$SERVICE" \
  --min-instances=0 \
  --region="$REGION" \
  --project="$PROJECT" \
  --quiet

echo "Done. GPU will scale to zero after idle timeout (~15 min)."
echo "No charges once the instance shuts down."
