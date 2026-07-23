#!/bin/bash
# Test 1: Hello AAP - Launch Hello World job template
# Expected: AAP launches "Hello World" job template

if [ -z "${EDA_EVENT_STREAM_URL}" ] || [ -z "${EDA_BASIC_AUTH}" ]; then
  echo "ERROR: Set EDA_EVENT_STREAM_URL and EDA_BASIC_AUTH before running."
  exit 1
fi

echo "=== Test 1: Hello AAP ==="
echo "Sending Hello AAP event to ${EDA_EVENT_STREAM_URL}"

curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @"$(dirname "$0")/hello-aap.json"

echo ""
echo "Check AAP UI → Jobs for: Hello World"
