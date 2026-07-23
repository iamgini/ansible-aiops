#!/bin/bash
# Test 2: Disk Full - High disk usage alert
# Expected: AAP launches "Remediate Disk Space" on web-server-01.example.com

if [ -z "${EDA_EVENT_STREAM_URL}" ] || [ -z "${EDA_BASIC_AUTH}" ]; then
  echo "ERROR: Set EDA_EVENT_STREAM_URL and EDA_BASIC_AUTH before running."
  exit 1
fi

echo "=== Test 2: Disk Full ==="
echo "Sending disk full event to ${EDA_EVENT_STREAM_URL}"

curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @"$(dirname "$0")/case1-disk-full.json"

echo ""
echo "Check AAP UI → Jobs for: Remediate Disk Space"
