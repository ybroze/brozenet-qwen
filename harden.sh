#!/bin/bash
set -e

# Post-deploy security hardening checks for qwen.broze.net
# Run after ./deploy.sh and IAP setup to verify everything is locked down.

SERVICE="qwen-personal-assistant"
REGION="us-central1"
PROJECT="$(grep '^project_id:' ~/Secrets/ziggy-ansible-secrets.yml | awk '{print $2}' | tr -d '"'"'"'"')"
REPO="qwen-repo"
SECRET="hf-token"

PASS=0
FAIL=0
WARN=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  WARN: $1"; WARN=$((WARN + 1)); }

echo "=== Qwen Hardening Check ==="
echo "Project: $PROJECT | Service: $SERVICE | Region: $REGION"
echo ""

# --- 1. IAP ---
echo "[1/6] Checking IAP status..."
IAP_ENABLED=$(gcloud run services describe "$SERVICE" --region="$REGION" --project="$PROJECT" \
  --format="value(metadata.annotations['run.googleapis.com/iap-enabled'])" 2>/dev/null || echo "")
if [ "$IAP_ENABLED" = "true" ]; then
  pass "IAP is enabled on $SERVICE"
else
  fail "IAP is NOT enabled. Go to Cloud Console -> Cloud Run -> $SERVICE -> Security -> Identity-Aware Proxy"
fi

# --- 2. No public access (allUsers / allAuthenticatedUsers) ---
echo "[2/6] Checking IAM policy for public access..."
IAM_POLICY=$(gcloud run services get-iam-policy "$SERVICE" --region="$REGION" --project="$PROJECT" --format=json 2>/dev/null)
if echo "$IAM_POLICY" | grep -q "allUsers\|allAuthenticatedUsers"; then
  fail "Public access found in IAM policy! Remove allUsers/allAuthenticatedUsers:"
  echo "$IAM_POLICY" | grep -A2 "allUsers\|allAuthenticatedUsers"
else
  pass "No public access in IAM policy"
fi

# --- 3. Artifact Registry not public ---
echo "[3/6] Checking Artifact Registry IAM..."
AR_POLICY=$(gcloud artifacts repositories get-iam-policy "$REPO" --location="$REGION" --project="$PROJECT" --format=json 2>/dev/null)
if echo "$AR_POLICY" | grep -q "allUsers\|allAuthenticatedUsers"; then
  fail "Artifact Registry repo '$REPO' has public access! Remove it:"
  echo "  gcloud artifacts repositories remove-iam-policy-binding $REPO --location=$REGION --member=allUsers --role=roles/artifactregistry.reader --project=$PROJECT"
else
  pass "Artifact Registry repo is not public"
fi

# --- 4. Secret Manager IAM ---
echo "[4/6] Checking Secret Manager access..."
SECRET_POLICY=$(gcloud secrets get-iam-policy "$SECRET" --project="$PROJECT" --format=json 2>/dev/null)
SECRET_MEMBERS=$(echo "$SECRET_POLICY" | grep -c '"members"' 2>/dev/null || echo "0")
if echo "$SECRET_POLICY" | grep -q "allUsers\|allAuthenticatedUsers"; then
  fail "HF token secret has public access!"
else
  pass "HF token secret is not public ($SECRET_MEMBERS binding(s))"
fi

# --- 5. Billing alert ---
echo "[5/6] Checking billing budgets..."
BUDGETS=$(gcloud billing budgets list --billing-account="$(gcloud billing projects describe "$PROJECT" --format='value(billingAccountName)' 2>/dev/null | sed 's|billingAccounts/||')" --format=json 2>/dev/null || echo "[]")
if [ "$BUDGETS" = "[]" ] || [ -z "$BUDGETS" ]; then
  warn "No billing budgets found. Create one at: Cloud Console -> Billing -> Budgets & alerts"
  echo "        Recommended: set alert at \$300/mo to catch a forgotten ./wake.sh"
else
  BUDGET_COUNT=$(echo "$BUDGETS" | grep -c '"displayName"' 2>/dev/null || echo "0")
  pass "Found $BUDGET_COUNT billing budget(s)"
fi

# --- 6. Docker image pin ---
echo "[6/6] Checking Dockerfile image pin..."
DOCKERFILE="$(cd "$(dirname "$0")" && pwd)/app/Dockerfile"
if grep -q "server-cuda$" "$DOCKERFILE" 2>/dev/null; then
  warn "Dockerfile uses unpinned :server-cuda tag. Pin to a specific version:"
  echo "        Check tags at: https://github.com/ggml-org/llama.cpp/pkgs/container/llama.cpp"
  echo "        Then update FROM line, e.g.: ghcr.io/ggml-org/llama.cpp:server-cuda-b5361"
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
  echo "Fix the FAILed checks above, then re-run: ./harden.sh"
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
