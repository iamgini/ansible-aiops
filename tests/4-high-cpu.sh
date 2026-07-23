#!/bin/bash
# Test 4: High CPU - CPU usage exceeded threshold
# Expected: AAP launches "Investigate High CPU" on db-server-01.example.com

EDA_WEBHOOK_URL="${EDA_WEBHOOK_URL:-https://localhost:5000}"

echo "=== Test 4: High CPU ==="
echo "Sending high CPU event to ${EDA_WEBHOOK_URL}/webhook"

curl -sk -X POST "${EDA_WEBHOOK_URL}/webhook" \
  -H "Content-Type: application/json" \
  -d @"$(dirname "$0")/case3-high-cpu.json"

echo ""
echo "Check AAP UI → Jobs for: Investigate High CPU"
