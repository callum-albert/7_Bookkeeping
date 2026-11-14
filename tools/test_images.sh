#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/7jz-ocr.XXXXXX)"
cp "$ROOT/tools/OCRImageTests.swift" "$TEST_DIR/main.swift"
FLAGS=(-O)
if [[ "${SEVEN_OCR_DIAGNOSTICS:-0}" == "1" ]]; then FLAGS+=(-D OCR_DIAGNOSTICS); fi
swiftc "${FLAGS[@]}" "$ROOT/Sources/Model/Models.swift" \
  "$ROOT/Sources/Model/LedgerStore.swift" "$ROOT/Sources/Model/Accounts.swift" \
  "$ROOT/Sources/Model/SyncPayload.swift" "$ROOT/Sources/Parser/BillParser.swift" \
  "$ROOT/Sources/Services/OCRLayout.swift" "$ROOT/Sources/Services/ReceiptOCR.swift" \
  "$TEST_DIR/main.swift" -o "$TEST_DIR/ocr-tests"
"$TEST_DIR/ocr-tests" "$@"
