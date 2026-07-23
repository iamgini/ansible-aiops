#!/bin/bash
# Test 2: Disk Full - High disk usage alert
# Expected: AAP launches "Remediate Disk Space" on web-server-01.example.com

EDA_WEBHOOK_URL="${EDA_WEBHOOK_URL:-https://localhost:5000}"

echo "=== Test 2: Disk Full ==="
echo "Sending disk full event to ${EDA_WEBHOOK_URL}/webhook"

curl -sk -X POST "${EDA_WEBHOOK_URL}/webhook" \
  -H "Content-Type: application/json" \
  -d @"$(dirname "$0")/case1-disk-full.json"

echo ""
echo "Check AAP UI → Jobs for: Remediate Disk Space"
