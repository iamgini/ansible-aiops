#!/bin/bash
# Test 3: Service Down - httpd service stopped
# Expected: AAP launches "Restart Service" on app-server-02.example.com

EDA_WEBHOOK_URL="${EDA_WEBHOOK_URL:-https://localhost:5000}"

echo "=== Test 3: Service Down ==="
echo "Sending service down event to ${EDA_WEBHOOK_URL}/webhook"

curl -sk -X POST "${EDA_WEBHOOK_URL}/webhook" \
  -H "Content-Type: application/json" \
  -d @"$(dirname "$0")/case2-service-down.json"

echo ""
echo "Check AAP UI → Jobs for: Restart Service"
