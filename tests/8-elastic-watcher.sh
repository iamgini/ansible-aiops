#!/bin/bash
# Test 8: Elasticsearch Watcher Alert - Simulated Watcher webhook
# Expected: Matches "High Disk Usage" rule → launches "Remediate Disk Space"

EDA_WEBHOOK_URL="${EDA_WEBHOOK_URL:-https://localhost:5000}"

echo "=== Test 8: Elasticsearch Watcher Alert ==="
echo "Sending Elastic Watcher event to ${EDA_WEBHOOK_URL}/webhook"

curl -sk -X POST "${EDA_WEBHOOK_URL}/webhook" \
  -H "Content-Type: application/json" \
  -d @"$(dirname "$0")/elastic-watcher-alert.json"

echo ""
echo "Check AAP UI → Jobs for: Remediate Disk Space"
