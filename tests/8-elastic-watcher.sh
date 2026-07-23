#!/bin/bash
# Test 8: Elasticsearch Watcher Alert - Simulated Watcher webhook
# Expected: Matches "High Disk Usage" rule → launches "Remediate Disk Space"

EDA_EVENT_STREAM_URL="${EDA_EVENT_STREAM_URL:-https://aapaio.lab.gineesh.com:443/eda-event-streams/api/eda/v1/external_event_stream/09df4aa9-05ff-4bbd-976e-b5278d314c78/post/}"
EDA_BASIC_AUTH="${EDA_BASIC_AUTH:-edatest:123456789}"

echo "=== Test 8: Elasticsearch Watcher Alert ==="
echo "Sending Elastic Watcher event to ${EDA_EVENT_STREAM_URL}"

curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @"$(dirname "$0")/elastic-watcher-alert.json"

echo ""
echo "Check AAP UI → Jobs for: Remediate Disk Space"
