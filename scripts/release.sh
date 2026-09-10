#!/usr/bin/env bash
#
# One-shot release: bump version, build, package, tag, push, publish.
#
# Usage:
#   ./scripts/release.sh v0.2.0            # full flow (asks for confirmation)
#   ./scripts/release.sh v0.2.0 --yes      # full flow, no prompts
#   ./scripts/release.sh v0.2.0 --dry-run  # bump + build + zip only
#
# Requires: PUBLISH_TOKEN when publishing (see publish-release.sh).
set -euo pipefail

cd "$(dirname "$0")/.."

# Prefer a full Xcode toolchain: CommandLineTools ships no XCTest, which breaks
# `swift test` (the release gate). Only override when CommandLineTools is active.
if [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]] \
   && [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

# Load .env if present (repo root). gitignored; holds PUBLISH_* secrets.
if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

TAG="${1:?usage: release.sh <tag> [--dry-run] [--yes]}"
shift || true
DRY=0
YES=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY=1 ;;
        --yes) YES=1 ;;
        *) echo "error: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

case "$TAG" in
    v*) VER="${TAG#v}" ;;
    *) echo "error: tag must start with 'v', e.g. v0.2.0" >&2; exit 2 ;;
esac
[[ "$VER" =~ ^[0-9]+(\.[0-9]+){1,3}([.-][0-9A-Za-z.-]+)?$ ]] \
    || { echo "error: tag must contain a valid marketing version, got '$TAG'" >&2; exit 2; }
ORIGINAL_VERSION="$(tr -d '[:space:]' < VERSION)"

if [[ "$DRY" -eq 0 && "$YES" -eq 0 ]]; then
    read -r -p "Build, tag $TAG, push and publish? [y/N] " ans
    [[ "$ans" == [yY]* ]] || { echo "aborted."; exit 1; }
fi

# Preflight: publishing needs a token. Fail BEFORE creating/tagging/pushing so
# we never end up with a pushed tag and no release.
if [[ "$DRY" -eq 0 && -z "${PUBLISH_TOKEN:-}" ]]; then
    echo "error: PUBLISH_TOKEN is empty. Set it in .env (see .env.example) or pass --dry-run." >&2
    echo "nothing was created, tagged or pushed." >&2
    exit 1
fi

# A release must be reproducible from an explicit clean commit. This also
# prevents accidentally committing unrelated local changes with the version bump.
if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree is not clean; commit or stash changes before releasing." >&2
    exit 1
fi
git diff --check
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "error: local tag $TAG already exists" >&2
    exit 1
fi
REMOTE_TAGS="$(git ls-remote --tags origin "refs/tags/$TAG")" \
    || { echo "error: could not query remote tags" >&2; exit 1; }
if [[ -n "$REMOTE_TAGS" ]]; then
    echo "error: remote tag $TAG already exists" >&2
    exit 1
fi
if [[ "$DRY" -eq 1 ]]; then
    trap 'printf "%s\\n" "$ORIGINAL_VERSION" > VERSION' EXIT
fi

# 1. Version
echo ">> Setting VERSION=$VER"
echo "$VER" > VERSION

# 2. Test: run the FULL suite (client + cover-render) before building/packaging.
echo ">> Running full test suite"
swift test

# 3. Build release bundle
echo ">> Building release bundle"
./scripts/build-app.sh --release

# 4. Package
echo ">> Packaging"
./scripts/package-release.sh
ZIP="dist/Klopydrome-$VER-macos.zip"
[[ -f "$ZIP" ]] || { echo "error: no archive produced at $ZIP" >&2; exit 1; }

if [[ "$DRY" -eq 1 ]]; then
    echo "DRY-RUN: VERSION will be restored to $ORIGINAL_VERSION; would now commit, tag, push and publish."
    exit 0
fi

# 5. Commit version bump
git add VERSION
git commit -m "Release $TAG" >/dev/null

# 6. Tag
git tag "$TAG"

# 7. Push branch + tag
BRANCH="$(git branch --show-current)"
echo ">> Pushing $BRANCH and tag $TAG"
git push origin "HEAD:$BRANCH"
git push origin "refs/tags/$TAG"

# 8. Publish release on the forge
echo ">> Publishing release"
./scripts/publish-release.sh "$TAG"

echo "Done: $TAG -> $ZIP"