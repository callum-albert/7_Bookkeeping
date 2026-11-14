#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/7jz-tests.XXXXXX)"
cp "$ROOT/tools/ParserTests.swift" "$TEST_DIR/main.swift"
swiftc -O "$ROOT/Sources/Model/Models.swift" "$ROOT/Sources/Model/CategoryStore.swift" \
  "$ROOT/Sources/Model/LedgerStore.swift" "$ROOT/Sources/Model/Accounts.swift" \
  "$ROOT/Sources/Model/SyncPayload.swift" "$ROOT/Sources/Parser/BillParser.swift" \
  "$ROOT/Sources/Services/OCRLayout.swift" \
  "$TEST_DIR/main.swift" -o "$TEST_DIR/tests"
"$TEST_DIR/tests"
