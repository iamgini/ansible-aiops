#!/bin/bash
# Test 0: Debug - Verify EDA is receiving events via Event Stream
# Expected: EDA prints "Hello" in logs (no job template launched)

if [ -z "${EDA_EVENT_STREAM_URL}" ] || [ -z "${EDA_BASIC_AUTH}" ]; then
  echo "ERROR: Set EDA_EVENT_STREAM_URL and EDA_BASIC_AUTH before running."
  echo "  export EDA_EVENT_STREAM_URL='https://aap.example.com:443/eda-event-streams/api/eda/v1/external_event_stream/<uuid>/post/'"
  echo "  export EDA_BASIC_AUTH='username:password'"
  exit 1
fi

echo "=== Test 0: Debug ==="
echo "Sending debug event to ${EDA_EVENT_STREAM_URL}"

HTTP_CODE=$(curl -sk -o /tmp/eda_response.txt -w "%{http_code}" \
  -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @"$(dirname "$0")/debug.json")

echo ""
if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo "SUCCESS (HTTP ${HTTP_CODE})"
else
  echo "FAILED (HTTP ${HTTP_CODE})"
  cat /tmp/eda_response.txt
  echo ""
  exit 1
fi
echo "Check EDA logs for: Hello"
