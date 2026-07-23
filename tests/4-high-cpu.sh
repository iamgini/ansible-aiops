#!/bin/bash
# Test 4: High CPU - CPU usage exceeded threshold
# Expected: AAP launches "Investigate High CPU" on db-server-01.example.com

EDA_EVENT_STREAM_URL="${EDA_EVENT_STREAM_URL:-https://aapaio.lab.gineesh.com:443/eda-event-streams/api/eda/v1/external_event_stream/09df4aa9-05ff-4bbd-976e-b5278d314c78/post/}"
EDA_BASIC_AUTH="${EDA_BASIC_AUTH:-edatest:123456789}"

echo "=== Test 4: High CPU ==="
echo "Sending high CPU event to ${EDA_EVENT_STREAM_URL}"

curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @"$(dirname "$0")/case3-high-cpu.json"

echo ""
echo "Check AAP UI → Jobs for: Investigate High CPU"
