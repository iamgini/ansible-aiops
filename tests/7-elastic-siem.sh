#!/bin/bash
# Test 7: Elastic SIEM Alert - Simulated Elastic SIEM webhook
# Expected: Falls through to AI Intelligence (no specific rule match)

EDA_WEBHOOK_URL="${EDA_WEBHOOK_URL:-https://localhost:5000}"

echo "=== Test 7: Elastic SIEM Alert ==="
echo "Sending Elastic SIEM event to ${EDA_WEBHOOK_URL}/webhook"

curl -sk -X POST "${EDA_WEBHOOK_URL}/webhook" \
  -H "Content-Type: application/json" \
  -d @"$(dirname "$0")/elastic-siem-alert.json"

echo ""
echo "Check AAP UI → Jobs for: AI Intelligence - Unknown Event Remediation"
