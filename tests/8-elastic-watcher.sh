#!/bin/bash
# Test 8: Elasticsearch Watcher Alert - Simulated Watcher webhook
# Expected: Matches "High Disk Usage" rule → launches "Remediate Disk Space"

if [ -z "${EDA_EVENT_STREAM_URL}" ] || [ -z "${EDA_BASIC_AUTH}" ]; then
  echo "ERROR: Set EDA_EVENT_STREAM_URL and EDA_BASIC_AUTH before running."
  exit 1
fi

echo "=== Test 8: Elasticsearch Watcher Alert ==="
echo "Sending Elastic Watcher event to ${EDA_EVENT_STREAM_URL}"

curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @"$(dirname "$0")/elastic-watcher-alert.json"

echo ""
echo "Check AAP UI → Jobs for: Remediate Disk Space"
