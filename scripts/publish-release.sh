#!/usr/bin/env bash
#
# Publishes a locally-built release zip to a GitHub-compatible host
# (GitHub, Forgejo or Gitea) using their releases REST API.
#
# Build the zip first on a Mac:  make dist   (or  make release)
#
# Usage:
#   ./scripts/publish-release.sh v0.1.0 [--api URL] [--repo owner/repo]
#
# Configuration (env):
#   PUBLISH_API_URL   API base, e.g. https://git.example.tld/api/v1
#                     Default: guessed from the git remote
#   PUBLISH_TOKEN     Personal access token with release permissions
#   PUBLISH_REPO      owner/repo, default: parsed from the git remote
set -euo pipefail

cd "$(dirname "$0")/.."

# Load .env if present (repo root). gitignored; holds PUBLISH_* secrets.
if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

TAG="${1:?usage: publish-release.sh <tag> [--api URL] [--repo owner/repo]}"
shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --api) API_URL="${2:?}"; shift 2 ;;
        --repo) REPO="${2:?}"; shift 2 ;;
        *) echo "error: unknown argument: $1" >&2; exit 2 ;;
    esac
done

REMOTE="$(git remote get-url origin 2>/dev/null || true)"
guess_repo() {
    # Handles git@host:owner/repo.git, https://host/owner/repo, host:owner/repo
    echo "$REMOTE" | sed -E 's#(git@|https?://[^/]*/|ssh://[^/]*/)##; s#\.git$##'
}
guess_api() {
    local host
    host="$(echo "$REMOTE" | sed -E 's#.*@##; s#(https?://)?([^/:]+).*#\2#')"
    echo "https://$host/api/v1"
}

API_URL="${PUBLISH_API_URL:-${API_URL:-$(guess_api)}}"
REPO="${PUBLISH_REPO:-${REPO:-$(guess_repo)}}"
TOKEN="${PUBLISH_TOKEN:?set PUBLISH_TOKEN (or pass the forge host/token) to publish}"

ZIP="$PWD/dist/Klopydrome-${TAG#v}-macos.zip"
if [[ ! -f "$ZIP" ]]; then
    echo "error: no archive at $ZIP — build it first: make dist" >&2
    exit 1
fi

# Changelog: commit subjects since the previous semver tag, newest first.
PREV_TAG="$(git tag --sort=-version:refname | grep -v "^$TAG$" | head -n 1 || true)"
if [[ -n "$PREV_TAG" ]]; then
    CHANGELOG="$(git log --format='- %s' "$PREV_TAG".."$TAG" 2>/dev/null || true)"
fi
if [[ -z "$CHANGELOG" ]]; then
    CHANGELOG="$(git log --format='- %s' -n 20 "$TAG" 2>/dev/null || true)"
fi

RELEASE_BODY="$CHANGELOG
Generated from commits since ${PREV_TAG:-$TAG}."

echo "Creating release $TAG on $API_URL/repos/$REPO"
RESPONSE="$(mktemp "${TMPDIR:-/tmp}/klopydrome-release.XXXXXX.json")"
trap 'rm -f "$RESPONSE"' EXIT
JSON="$(TAG="$TAG" RELEASE_BODY="$RELEASE_BODY" python3 -c '
import os, json
print(json.dumps({
    "tag_name": os.environ["TAG"],
    "name": "Klopydrome " + os.environ["TAG"],
    "body": os.environ["RELEASE_BODY"],
    "draft": False, "prerelease": False,
}, ensure_ascii=False))
')"
if ! curl --fail-with-body -sS -X POST \
    -H "Authorization: token $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/vnd.github+json" \
    "$API_URL/repos/$REPO/releases" \
    -d "$JSON" \
    -o "$RESPONSE"; then
    echo "error: release creation failed:" >&2
    cat "$RESPONSE" >&2
    exit 1
fi

RELEASE_ID="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["id"])' "$RESPONSE")" \
    || { echo "error: release API returned no usable id:" >&2; cat "$RESPONSE" >&2; exit 1; }
[[ -n "$RELEASE_ID" ]] || { echo "error: release API returned an empty id" >&2; exit 1; }
echo "Uploading $ZIP (release id $RELEASE_ID)"
if ! curl --fail-with-body -sS -X POST \
    -H "Authorization: token $TOKEN" \
    -H "Content-Type: application/zip" \
    --data-binary "@$ZIP" \
    "$API_URL/repos/$REPO/releases/$RELEASE_ID/assets?name=$(basename "$ZIP")" >/dev/null; then
    echo "error: asset upload failed; removing incomplete release $RELEASE_ID" >&2
    if ! curl --fail-with-body -sS -X DELETE \
        -H "Authorization: token $TOKEN" \
        "$API_URL/repos/$REPO/releases/$RELEASE_ID" >/dev/null; then
        echo "warning: could not delete incomplete release $RELEASE_ID" >&2
    fi
    exit 1
fi

echo "Published $TAG -> $API_URL/$REPO"
