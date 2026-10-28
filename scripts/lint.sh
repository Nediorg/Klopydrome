#!/bin/bash
# Lint gate for Swift code-size and quality rules.
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

echo "Linting..."
swiftlint lint --strict