#!/usr/bin/env bash
# Write source notes for release assets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD:-$ROOT/build}"
OUT="${1:-$BUILD/SOURCE_INFO.txt}"
ALARM_VERSION_FILE="${ALARM_VERSION_FILE:-$BUILD/alarm-version.env}"

[ -f "$ALARM_VERSION_FILE" ] || {
    echo "Error: missing version metadata: $ALARM_VERSION_FILE" >&2
    exit 1
}
: "${RELEASE_TAG:?RELEASE_TAG is required}"

# shellcheck source=/dev/null
source "$ALARM_VERSION_FILE"

repo_commit="${GITHUB_SHA:-$(git -C "$ROOT" rev-parse HEAD)}"
repo_web_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-therealcoder1337/nanopi-r2c-kernel-arch}"
source_package="linux-nanopi-r2c-minimal-${pkgver}-${pkgrel}.src.tar.gz"

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<EOF
Package: linux-nanopi-r2c-minimal-${pkgver}-${pkgrel}
Repository: ${repo_web_url}
Repository commit: ${repo_commit}
ALARM PKGBUILDs: ${alarm_repo}
ALARM commit: ${alarm_commit}
Release tag: ${RELEASE_TAG}
Source package: ${repo_web_url}/releases/download/${RELEASE_TAG}/${source_package}

Rebuild command
  CARCH=aarch64 makepkg -Cfs
EOF

echo "Source info written to $OUT"
