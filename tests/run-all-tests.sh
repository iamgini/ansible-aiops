#!/bin/bash
# Run all test scripts sequentially with a pause between each

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=========================================="
echo "  AIOps EDA Test Suite"
echo "  EDA_EVENT_STREAM_URL: ${EDA_EVENT_STREAM_URL:-https://aapaio.lab.gineesh.com:443/eda-event-streams/api/eda/v1/external_event_stream/09df4aa9-05ff-4bbd-976e-b5278d314c78/post/}"
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
