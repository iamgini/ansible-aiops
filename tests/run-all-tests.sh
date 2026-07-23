#!/bin/bash
# Run all test scripts sequentially with a pause between each

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=========================================="
echo "  AIOps EDA Test Suite"
echo "  EDA_WEBHOOK_URL: ${EDA_WEBHOOK_URL:-https://localhost:5000}"
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
