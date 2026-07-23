#!/bin/bash
# Test 4: High CPU - CPU usage exceeded threshold
# Expected: AAP launches "Investigate High CPU" on db-server-01.example.com

if [ -z "${EDA_EVENT_STREAM_URL}" ] || [ -z "${EDA_BASIC_AUTH}" ]; then
  echo "ERROR: Set EDA_EVENT_STREAM_URL and EDA_BASIC_AUTH before running."
  exit 1
fi

echo "=== Test 4: High CPU ==="
echo "Sending high CPU event to ${EDA_EVENT_STREAM_URL}"

curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @"$(dirname "$0")/case3-high-cpu.json"

echo ""
echo "Check AAP UI → Jobs for: Investigate High CPU"
