#!/bin/bash
set -e

# Wake the Qwen GPU — sets min-instances=1 so Cloud Run keeps a warm instance.
# Usage:
#   ./wake.sh          # wake indefinitely (remember to ./sleep.sh later)
#   ./wake.sh 2h       # wake for 2 hours, then auto-sleep
#   ./wake.sh 30m      # wake for 30 minutes, then auto-sleep

SERVICE="qwen-personal-assistant"
REGION="us-central1"
PROJECT="$(grep '^project_id:' ~/Secrets/ziggy-ansible-secrets.yml | awk '{print $2}' | tr -d '"'"'"'"')"
DURATION="${1:-}"

# Validate duration if provided
if [ -n "$DURATION" ] && ! echo "$DURATION" | grep -qE '^[0-9]+[smhd]?$'; then
  echo "ERROR: Invalid duration '$DURATION'. Use a number with optional suffix: 30m, 2h, 1d"
  exit 1
fi

echo "Waking $SERVICE (setting min-instances=1)..."
gcloud run services update "$SERVICE" \
  --min-instances=1 \
  --region="$REGION" \
  --project="$PROJECT" \
  --quiet

echo "GPU instance warming up. First cold start takes ~5-10 min (model download + load)."
echo "Waiting for ready..."
for i in $(seq 1 90); do
  STATUS=$(gcloud run services describe "$SERVICE" --region="$REGION" --project="$PROJECT" --format="value(status.conditions[0].status)" 2>/dev/null || echo "Unknown")
  if [ "$STATUS" = "True" ]; then
    echo "Service is ready."
    break
  fi
  sleep 10
done

if [ -n "$DURATION" ]; then
  echo "Auto-sleep scheduled in $DURATION."
  SLEEP_SCRIPT="$(cd "$(dirname "$0")" && pwd)/sleep.sh"
  nohup bash -c "sleep '$DURATION' && '$SLEEP_SCRIPT'" >/dev/null 2>&1 &
  TIMER_PID=$!
  echo "Timer PID: $TIMER_PID (kill $TIMER_PID to cancel auto-sleep)"
fi

echo "Use ./sleep.sh to shut down the GPU when done."
