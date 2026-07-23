#!/bin/bash
# Run all test scripts sequentially with a pause between each

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${EDA_EVENT_STREAM_URL}" ] || [ -z "${EDA_BASIC_AUTH}" ]; then
  echo "ERROR: Set EDA_EVENT_STREAM_URL and EDA_BASIC_AUTH before running."
  echo "  export EDA_EVENT_STREAM_URL='https://aap.example.com:443/eda-event-streams/api/eda/v1/external_event_stream/<uuid>/post/'"
  echo "  export EDA_BASIC_AUTH='username:password'"
  exit 1
fi

echo "=========================================="
echo "  AIOps EDA Test Suite"
echo "  EDA_EVENT_STREAM_URL: ${EDA_EVENT_STREAM_URL}"
echo "=========================================="
echo ""

for test in "$SCRIPT_DIR"/[0-9]*.sh; do
  bash "$test"
  echo ""
  echo "------------------------------------------"
  read -p "Press Enter to run next test (Ctrl+C to stop)..."
  echo ""
done

echo "All tests completed."
echo "Verify results: AAP UI → Jobs"
