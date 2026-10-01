#!/usr/bin/env bash
# Usage: annotate-failure.sh <log file> <title>
# Turns the important lines of a failed build log into GitHub annotations,
# so failures are readable from the Checks API without downloading logs.
LOG="$1"
TITLE="${2:-Build failed}"
[[ -f "$LOG" ]] || { echo "::error title=$TITLE::Log $LOG not found"; exit 0; }

escape() { sed -e 's/%/%25/g' -e 's/\r//g' | awk 'BEGIN{ORS="%0A"} {print}'; }

# Compiler/linker errors first (deduplicated, capped).
grep -E "(error:|Error:|fatal error|Undefined symbol|ld: |\*\* (BUILD|TEST) FAILED|Test Case .* failed|XCTAssert|failed \()" "$LOG" \
  | awk '!seen[$0]++' | head -40 > /tmp/annot-errors.txt || true

if [[ -s /tmp/annot-errors.txt ]]; then
  echo "::error title=$TITLE (errors)::$(escape < /tmp/annot-errors.txt | cut -c1-60000)"
fi
echo "::error title=$TITLE (log tail)::$(tail -80 "$LOG" | escape | cut -c1-60000)"
