#!/bin/bash
set -e

# Post-deploy security hardening checks for qwen.broze.net
# Run after ./deploy.sh to verify everything is locked down.
# Usage: ./harden.sh @/path/to/secrets.yml

VARS="$(cd "$(dirname "$0")" && pwd)/ansible/vars.yml"
SERVICE="$(grep '^service_name:' "$VARS" | awk '{print $2}' | tr -d '\"'"'")"
REGION="$(grep '^region:' "$VARS" | awk '{print $2}' | tr -d '\"'"'")"
REPO="$(grep '^ar_repo:' "$VARS" | awk '{print $2}' | tr -d '\"'"'")"
SECRET="hf-token"

if [ -z "$1" ] || [[ "$1" != @* ]]; then
  echo "Usage: $0 @/path/to/secrets.yml"
  exit 1
fi

SECRETS_FILE="${1#@}"
PROJECT="$(grep '^project_id:' "$SECRETS_FILE" | awk '{print $2}' | tr -d '\"'"'")"

PASS=0
FAIL=0
WARN=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  WARN: $1"; WARN=$((WARN + 1)); }

echo "=== Qwen Hardening Check ==="
echo "Project: $PROJECT | Service: $SERVICE | Region: $REGION"
echo ""

# --- 1. No public access (allUsers / allAuthenticatedUsers) ---
echo "[1/5] Checking IAM policy for public access..."
IAM_POLICY=$(gcloud run services get-iam-policy "$SERVICE" --region="$REGION" --project="$PROJECT" --format=json 2>/dev/null)
if echo "$IAM_POLICY" | grep -q "allUsers\|allAuthenticatedUsers"; then
  fail "Public access found in IAM policy! Remove allUsers/allAuthenticatedUsers:"
  echo "$IAM_POLICY" | grep -A2 "allUsers\|allAuthenticatedUsers"
else
  pass "No public access in IAM policy"
fi

# --- 2. Artifact Registry not public ---
echo "[2/5] Checking Artifact Registry IAM..."
AR_POLICY=$(gcloud artifacts repositories get-iam-policy "$REPO" --location="$REGION" --project="$PROJECT" --format=json 2>/dev/null)
if echo "$AR_POLICY" | grep -q "allUsers\|allAuthenticatedUsers"; then
  fail "Artifact Registry repo '$REPO' has public access! Remove it:"
  echo "  gcloud artifacts repositories remove-iam-policy-binding $REPO --location=$REGION --member=allUsers --role=roles/artifactregistry.reader --project=$PROJECT"
else
  pass "Artifact Registry repo is not public"
fi

# --- 3. Secret Manager IAM ---
echo "[3/5] Checking Secret Manager access..."
SECRET_POLICY=$(gcloud secrets get-iam-policy "$SECRET" --project="$PROJECT" --format=json 2>/dev/null)
SECRET_MEMBERS=$(echo "$SECRET_POLICY" | grep -c '"members"' 2>/dev/null || echo "0")
if echo "$SECRET_POLICY" | grep -q "allUsers\|allAuthenticatedUsers"; then
  fail "HF token secret has public access!"
else
  pass "HF token secret is not public ($SECRET_MEMBERS binding(s))"
fi

# --- 4. Billing alert ---
echo "[4/5] Checking billing budgets..."
BUDGETS=$(gcloud billing budgets list --billing-account="$(gcloud billing projects describe "$PROJECT" --format='value(billingAccountName)' 2>/dev/null | sed 's|billingAccounts/||')" --format=json 2>/dev/null || echo "[]")
if [ "$BUDGETS" = "[]" ] || [ -z "$BUDGETS" ]; then
  warn "No billing budgets found. Create one at: Cloud Console -> Billing -> Budgets & alerts"
  echo "        Recommended: set alert at \$300/mo to catch a forgotten ./wake.sh"
else
  BUDGET_COUNT=$(echo "$BUDGETS" | grep -c '"displayName"' 2>/dev/null || echo "0")
  pass "Found $BUDGET_COUNT billing budget(s)"
fi

# --- 5. Docker image pin ---
echo "[5/5] Checking Dockerfile image pin..."
DOCKERFILE="$(cd "$(dirname "$0")" && pwd)/app/Dockerfile"
if grep -q "server-cuda$" "$DOCKERFILE" 2>/dev/null; then
  warn "Dockerfile uses unpinned :server-cuda tag. Pin to a specific version:"
  echo "        Check tags at: https://github.com/ggml-org/llama.cpp/pkgs/container/llama.cpp"
  echo "        Example: ghcr.io/ggml-org/llama.cpp:server-cuda-b5361"
elif grep -q "server-cuda-b[0-9]" "$DOCKERFILE" 2>/dev/null; then
  TAG=$(grep "^FROM" "$DOCKERFILE" | head -1 | awk '{print $2}')
  pass "Dockerfile pinned to: $TAG"
else
  warn "Could not determine Dockerfile image pin status"
fi

# --- Summary ---
echo ""
echo "=== Results ==="
echo "  $PASS passed, $FAIL failed, $WARN warnings"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Fix the FAILed checks above, then re-run: $0 $1"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo ""
  echo "All critical checks passed. Address warnings when convenient."
  exit 0
else
  echo ""
  echo "All checks passed. Service is hardened."
  exit 0
fi
