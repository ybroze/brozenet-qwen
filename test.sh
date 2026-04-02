#!/bin/bash
set -euo pipefail

HOST="${QWEN_HOST:-https://qwen.broze.net}"
: "${QWEN_API_KEY:?Set QWEN_API_KEY}"

pass=0
fail=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "PASS  $name"
        ((pass++))
    else
        echo "FAIL  $name (expected $expected, got $actual)"
        ((fail++))
    fi
}

# 1. Health endpoint (no auth)
code=$(curl -s -o /dev/null -w '%{http_code}' "$HOST/health")
check "health endpoint returns 200" "200" "$code"

# 2. No auth returns 401
code=$(curl -s -o /dev/null -w '%{http_code}' "$HOST/api/tags")
check "no auth returns 401" "401" "$code"

# 3. Bad token returns 401
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer wrong" "$HOST/api/tags")
check "bad token returns 401" "401" "$code"

# 4. List models succeeds
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $QWEN_API_KEY" "$HOST/api/tags")
check "list models returns 200" "200" "$code"

# 5. Chat completion works
response=$(curl -s -w '\n%{http_code}' -H "Authorization: Bearer $QWEN_API_KEY" \
    -d '{"model":"qwen3:30b-a3b","messages":[{"role":"user","content":"Say hello in exactly one word."}],"stream":false}' \
    "$HOST/api/chat")
code=$(echo "$response" | tail -1)
body=$(echo "$response" | sed '$d')
check "chat completion returns 200" "200" "$code"

if [ "$code" = "200" ]; then
    content=$(echo "$body" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "      model responded: $content"
fi

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
