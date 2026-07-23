#!/bin/bash
# Test 6: Unknown Event - No matching rule, triggers AI intelligence
# Expected: AAP launches "AI Intelligence - Unknown Event Remediation"
#           (MCP search → AI playbook generation → Git push)

EDA_WEBHOOK_URL="${EDA_WEBHOOK_URL:-https://localhost:5000}"

echo "=== Test 6: Unknown Event (AI Intelligence) ==="
echo "Sending unknown event to ${EDA_WEBHOOK_URL}/webhook"

curl -sk -X POST "${EDA_WEBHOOK_URL}/webhook" \
  -H "Content-Type: application/json" \
  -d @"$(dirname "$0")/case-unknown-event.json"

echo ""
echo "Check AAP UI → Jobs for: AI Intelligence - Unknown Event Remediation"
