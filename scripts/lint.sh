#!/bin/bash
# Lint gate for the Swift code-size rules. Fails only on NEW violations:
# existing ones are frozen in .swiftlint-baseline.json (see .swiftlint.yml).
#
# Requires SwiftLint and an Xcode toolchain (sourcekitd). If DEVELOPER_DIR is
# not set, fall back to the default Xcode selection.
set -euo pipefail

cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint not found. Install it: brew install swiftlint" >&2
  exit 1
fi

if [[ ! -f .swiftlint-baseline.json ]]; then
  echo "Creating first-time baseline of existing violations…" >&2
  swiftlint lint --write-baseline .swiftlint-baseline.json
fi

echo "Linting (gating on new violations only)…"
swiftlint lint --strict --baseline .swiftlint-baseline.json