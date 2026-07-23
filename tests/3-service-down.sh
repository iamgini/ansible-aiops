#!/bin/bash
# Test 3: Service Down - httpd service stopped
# Expected: AAP launches "Restart Service" on app-server-02.example.com

if [ -z "${EDA_EVENT_STREAM_URL}" ] || [ -z "${EDA_BASIC_AUTH}" ]; then
  echo "ERROR: Set EDA_EVENT_STREAM_URL and EDA_BASIC_AUTH before running."
  exit 1
fi

echo "=== Test 3: Service Down ==="
echo "Sending service down event to ${EDA_EVENT_STREAM_URL}"

curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @"$(dirname "$0")/case2-service-down.json"

echo ""
echo "Check AAP UI → Jobs for: Restart Service"
