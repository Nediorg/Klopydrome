#!/usr/bin/env bash
#
# Builds the macOS app via the Xcode project (xcodebuild) and signs it ad-hoc
# without the hardened runtime, so the bundled stock libmpv LuaJIT doesn't crash
# at launch (EXC_BAD_ACCESS / codesigning "Invalid Page").
#
# Usage:
#   ./scripts/build-app.sh [--release] [--no-test] [--no-lint]
#
#   --release   Build the Release configuration (default: Debug)
#   --no-test   Skip the cover-render test gate
#   --no-lint   Skip the SwiftLint gate (new-violations only)
#
# Environment:
#   APP_NAME       Bundle/product name (default: Klopydrome)
#   DEVELOPER_DIR  Xcode developer directory (auto-detected)
set -euo pipefail

cd "$(dirname "$0")/.."

# Prefer a full Xcode toolchain: CommandLineTools ships no XCTest, which breaks
# `swift test` (the release gate). Only override when CommandLineTools is active.
if [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]] \
   && [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

XC="xcrun"
PROJECT="Klopydrome.xcodeproj"
TARGET="Klopydrome"
APP_NAME="${APP_NAME:-Klopydrome}"
APP_VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
[[ "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}([.-][0-9A-Za-z.-]+)?$ ]] \
    || { echo "error: VERSION must be a valid marketing version, got '$APP_VERSION'" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] \
    || { echo "error: BUILD_NUMBER must be a positive integer, got '$BUILD_NUMBER'" >&2; exit 1; }

CONFIG="Debug"
RUN_TESTS=1
RUN_LINT=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --release) CONFIG="Release" ;;
        --no-test) RUN_TESTS=0 ;;
        --no-lint) RUN_LINT=0 ;;
        -h|--help)
            sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "error: unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

# Lint gate (new SwiftLint violations only, frozen in the baseline).
if [[ "${RUN_LINT}" == "1" ]]; then
    if command -v swiftlint >/dev/null 2>&1; then
        [[ -f .swiftlint-baseline.json ]] || swiftlint lint --write-baseline .swiftlint-baseline.json >/dev/null
        swiftlint lint --strict --baseline .swiftlint-baseline.json
    else
        echo "warning: swiftlint not found; skipping lint gate (brew install swiftlint)" >&2
    fi
fi

# Cover-render test gate: pixel-level cover renders via ImageRenderer.
if [[ "${RUN_TESTS}" == "1" ]]; then
    swift test --filter PlaylistCoverPresetTests
fi

# ---------------------------------------------------------------------------
# Build with Xcode (xcodebuild)
# ---------------------------------------------------------------------------
# Sign ad-hoc (CODE_SIGN_IDENTITY=-) and WITHOUT the hardened runtime so the
# bundled stock LuaJIT can never be SIGKILLed by codesigning.
DERIVED="$PWD/.build/xcode-derived"
rm -rf "$DERIVED"
"$XC" xcodebuild -project "$PROJECT" -target "$TARGET" \
    -configuration "$CONFIG" \
    SYMROOT="$DERIVED/Sym" \
    OBJROOT="$DERIVED/Obj" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="-" \
    ENABLE_HARDENED_RUNTIME=NO \
    PRODUCT_BUNDLE_IDENTIFIER=com.klopydrome.client \
    MARKETING_VERSION="$APP_VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build

OUT="$PWD/.build/app"
APP="$OUT/$APP_NAME.app"
rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$DERIVED/Sym/$CONFIG/$APP_NAME.app" "$APP"
APP_BIN="$APP/Contents/MacOS/$APP_NAME"

# Embed NavidromeClient.framework. Klopydrome links it as a *local framework
# target, so Xcode auto-embeds the Swift package (MPVKit) frameworks but not
# this one, and its install name defaults to the absolute /Library/Frameworks/...
# path. Copy it in, rewrite its install name to @rpath, and rewrite the app's
# load command to match, so dyld resolves it inside the bundle at launch.
FW_SRC="$DERIVED/Sym/$CONFIG/NavidromeClient.framework"
FW_DST="$APP/Contents/Frameworks/NavidromeClient.framework"
if [[ -d "$FW_SRC" ]]; then
    cp -R "$FW_SRC" "$FW_DST"
    "$XC" install_name_tool -id \
        "@rpath/NavidromeClient.framework/Versions/A/NavidromeClient" \
        "$FW_DST/Versions/A/NavidromeClient" 2>/dev/null || true
    OLD="$("$XC" otool -l "$APP_BIN" 2>/dev/null \
        | grep -E "name .*NavidromeClient.framework" | head -1 | awk '{print $2}')"
    [[ -n "$OLD" ]] && "$XC" install_name_tool -change "$OLD" \
        "@rpath/NavidromeClient.framework/Versions/A/NavidromeClient" \
        "$APP_BIN" 2>/dev/null || true
    "$XC" otool -l "$APP_BIN" 2>/dev/null | grep -q "@executable_path/../Frameworks" \
        || "$XC" install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BIN" 2>/dev/null || true
    echo "Embedded NavidromeClient.framework"
else
    echo "warning: NavidromeClient.framework not found in build products; the app will fail to launch." >&2
fi

# Re-sign ad-hoc (no hardened runtime). install_name_tool broke the code seals,
# so re-sign the embedded framework and the app.
"$XC" codesign --force --sign - "$FW_DST" >/dev/null 2>&1 || true
"$XC" codesign --force --sign - "$APP" >/dev/null

for key in CFBundleIdentifier CFBundleName CFBundleShortVersionString CFBundleVersion; do
    value="$("$XC" plutil -extract "$key" raw -o - "$APP/Contents/Info.plist" 2>/dev/null || true)"
    [[ -n "$value" ]] || { echo "error: built app is missing $key" >&2; exit 1; }
done
BUNDLE_VERSION="$("$XC" plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
[[ "$BUNDLE_VERSION" == "$APP_VERSION" ]] \
    || { echo "error: bundle version '$BUNDLE_VERSION' does not match VERSION '$APP_VERSION'" >&2; exit 1; }

echo "Built (ad-hoc, no hardened runtime): $APP"
