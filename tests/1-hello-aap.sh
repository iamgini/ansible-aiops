#!/bin/bash
# Test 1: Hello AAP - Launch Hello World job template
# Expected: AAP launches "Hello World" job template

EDA_WEBHOOK_URL="${EDA_WEBHOOK_URL:-https://localhost:5000}"

echo "=== Test 1: Hello AAP ==="
echo "Sending Hello AAP event to ${EDA_WEBHOOK_URL}/webhook"

curl -sk -X POST "${EDA_WEBHOOK_URL}/webhook" \
  -H "Content-Type: application/json" \
  -d @"$(dirname "$0")/hello-aap.json"

echo ""
echo "Check AAP UI → Jobs for: Hello World"
