#!/bin/bash
# Test 0: Debug - Verify EDA is receiving events
# Expected: EDA prints "Hello" in logs (no job template launched)

EDA_WEBHOOK_URL="${EDA_WEBHOOK_URL:-https://localhost:5000}"

echo "=== Test 0: Debug ==="
echo "Sending debug event to ${EDA_WEBHOOK_URL}/webhook"

curl -sk -X POST "${EDA_WEBHOOK_URL}/webhook" \
  -H "Content-Type: application/json" \
  -d @"$(dirname "$0")/debug.json"

echo ""
echo "Check EDA logs for: Hello"
