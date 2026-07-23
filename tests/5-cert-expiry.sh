#!/bin/bash
# Test 5: Certificate Expiry - SSL cert expiring in 7 days
# Expected: AAP launches "Renew SSL Certificate" on lb-01.example.com

EDA_WEBHOOK_URL="${EDA_WEBHOOK_URL:-https://localhost:5000}"

echo "=== Test 5: Certificate Expiry ==="
echo "Sending cert expiry event to ${EDA_WEBHOOK_URL}/webhook"

curl -sk -X POST "${EDA_WEBHOOK_URL}/webhook" \
  -H "Content-Type: application/json" \
  -d @"$(dirname "$0")/case4-cert-expiry.json"

echo ""
echo "Check AAP UI → Jobs for: Renew SSL Certificate"
