#!/usr/bin/env bash
#
# Packages the built release .app into a distributable zip under dist/.
# Usage:
#   ./scripts/package-release.sh [--app path]
#
# Produces dist/Klopydrome-<version>-macos.zip
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="${APP_NAME:-Klopydrome}"
VERSION="$(tr -d '[:space:]' < VERSION)"
EXPECTED_BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.klopydrome.client}"
APP="${1:-$PWD/.build/app/$APP_NAME.app}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}([.-][0-9A-Za-z.-]+)?$ ]] \
    || { echo "error: VERSION must be a valid marketing version, got '$VERSION'" >&2; exit 1; }

if [[ ! -d "$APP" ]]; then
    echo "error: no bundle at $APP (run: make release)" >&2
    exit 1
fi

PLIST="$APP/Contents/Info.plist"
[[ -f "$PLIST" ]] || { echo "error: app bundle has no Info.plist" >&2; exit 1; }
plist_value() {
    plutil -extract "$1" raw -o - "$PLIST" 2>/dev/null || true
}
for key in CFBundleIdentifier CFBundleName CFBundleShortVersionString CFBundleVersion CFBundlePackageType; do
    value="$(plist_value "$key")"
    [[ -n "$value" ]] || { echo "error: app bundle is missing $key" >&2; exit 1; }
done
[[ "$(plist_value CFBundleIdentifier)" == "$EXPECTED_BUNDLE_IDENTIFIER" ]] \
    || { echo "error: bundle identifier does not match $EXPECTED_BUNDLE_IDENTIFIER" >&2; exit 1; }
[[ "$(plist_value CFBundleShortVersionString)" == "$VERSION" ]] \
    || { echo "error: bundle version does not match VERSION=$VERSION" >&2; exit 1; }
codesign --verify --deep --strict "$APP" \
    || { echo "error: app bundle signature verification failed" >&2; exit 1; }

DIST="$PWD/dist"
ARCHIVE="$DIST/$APP_NAME-$VERSION-macos.zip"
mkdir -p "$DIST"
rm -f "$ARCHIVE"

# ditto preserves resource forks/symlinks, unlike `zip`.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

echo "Packaged: $ARCHIVE"