#!/bin/bash
# Test 6: Unknown Event - No matching rule, triggers AI intelligence
# Expected: AAP launches "AI Intelligence - Unknown Event Remediation"
#           (MCP search → AI playbook generation → Git push)

if [ -z "${EDA_EVENT_STREAM_URL}" ] || [ -z "${EDA_BASIC_AUTH}" ]; then
  echo "ERROR: Set EDA_EVENT_STREAM_URL and EDA_BASIC_AUTH before running."
  exit 1
fi

echo "=== Test 6: Unknown Event (AI Intelligence) ==="
echo "Sending unknown event to ${EDA_EVENT_STREAM_URL}"

curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @"$(dirname "$0")/case-unknown-event.json"

echo ""
echo "Check AAP UI → Jobs for: AI Intelligence - Unknown Event Remediation"
