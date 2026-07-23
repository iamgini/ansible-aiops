#!/bin/bash
# Test 5: Certificate Expiry - SSL cert expiring in 7 days
# Expected: AAP launches "Renew SSL Certificate" on lb-01.example.com

if [ -z "${EDA_EVENT_STREAM_URL}" ] || [ -z "${EDA_BASIC_AUTH}" ]; then
  echo "ERROR: Set EDA_EVENT_STREAM_URL and EDA_BASIC_AUTH before running."
  exit 1
fi

echo "=== Test 5: Certificate Expiry ==="
echo "Sending cert expiry event to ${EDA_EVENT_STREAM_URL}"

curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @"$(dirname "$0")/case4-cert-expiry.json"

echo ""
echo "Check AAP UI → Jobs for: Renew SSL Certificate"
