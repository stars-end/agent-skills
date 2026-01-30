#!/bin/bash
# Verify Ralph Test Results
# Checks that test files exist with correct content

set -e

WORK_DIR="${1:-.}"

if [ ! -d "$WORK_DIR" ]; then
    echo "Error: Directory not found: $WORK_DIR"
    echo "Usage: $0 <work-directory>"
    exit 1
fi

echo "=== Verifying Ralph Test Results ==="
echo "Work directory: $WORK_DIR"
echo ""

PASSED=0
FAILED=0

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Check each test file
for i in {1..5}; do
    FILE="$WORK_DIR/test-file-$i.txt"
    EXPECTED="This is test file $i created by Ralph"

    if [ -f "$FILE" ]; then
        ACTUAL=$(cat "$FILE")
        if [ "$ACTUAL" = "$EXPECTED" ]; then
            echo -e "${GREEN}✅ PASS${NC}: test-file-$i.txt"
            ((PASSED++))
        else
            echo -e "${RED}❌ FAIL${NC}: test-file-$i.txt (wrong content)"
            echo "   Expected: '$EXPECTED'"
            echo "   Got:      '$ACTUAL'"
            ((FAILED++))
        fi
    else
        echo -e "${RED}❌ FAIL${NC}: test-file-$i.txt (not found)"
        ((FAILED++))
    fi
done

echo ""
echo "=== Summary ==="
echo "Passed: $PASSED/5"
echo "Failed: $FAILED/5"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
