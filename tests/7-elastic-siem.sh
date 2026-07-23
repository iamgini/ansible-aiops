#!/bin/bash
# Test 7: Elastic SIEM Alert - Simulated Elastic SIEM webhook
# Expected: Falls through to AI Intelligence (no specific rule match)

if [ -z "${EDA_EVENT_STREAM_URL}" ] || [ -z "${EDA_BASIC_AUTH}" ]; then
  echo "ERROR: Set EDA_EVENT_STREAM_URL and EDA_BASIC_AUTH before running."
  exit 1
fi

echo "=== Test 7: Elastic SIEM Alert ==="
echo "Sending Elastic SIEM event to ${EDA_EVENT_STREAM_URL}"

curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @"$(dirname "$0")/elastic-siem-alert.json"

echo ""
echo "Check AAP UI → Jobs for: AI Intelligence - Unknown Event Remediation"
