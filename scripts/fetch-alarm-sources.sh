#!/usr/bin/env bash
# Shallow-clone ALARM PKGBUILDs and read linux-aarch64 PKGBUILD + config from one checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
ALARM_REPO="${ALARM_REPO:-https://github.com/archlinuxarm/PKGBUILDs.git}"
LINUX_PKGDIR="core/linux-aarch64"
ALARM_CONFIG="$BUILD/alarm.config"
ALARM_VERSION_FILE="${ALARM_VERSION_FILE:-$BUILD/alarm-version.env}"
ALARM_SOURCE_SUMS="${ALARM_SOURCE_SUMS:-$BUILD/alarm-source-md5.txt}"
ALARM_DIR="$(mktemp -d)"

trap 'rm -rf "$ALARM_DIR"' EXIT

echo "==> Fetching ALARM PKGBUILDs (shallow clone)..."
mkdir -p "$BUILD" "$(dirname "$ALARM_VERSION_FILE")"
git clone --depth=1 "$ALARM_REPO" "$ALARM_DIR"

LINUX_DIR="$ALARM_DIR/$LINUX_PKGDIR"
PKGBUILD="$LINUX_DIR/PKGBUILD"
CONFIG="$LINUX_DIR/config"

[ -f "$PKGBUILD" ] && [ -f "$CONFIG" ] || {
    echo "Error: missing PKGBUILD or config under $LINUX_DIR" >&2
    exit 1
}

pkgver="$(awk -F= '/^pkgver=/ { gsub(/[^0-9.a-z]/, "", $2); print $2; exit }' "$PKGBUILD")"
pkgrel="$(awk -F= '/^pkgrel=/ { gsub(/[^0-9]/, "", $2); print $2; exit }' "$PKGBUILD")"
_srcname="$(awk -F= '/^_srcname=/ { gsub(/"/, "", $2); print $2; exit }' "$PKGBUILD")"

[ -n "$pkgver" ] && [ -n "$pkgrel" ] && [ -n "$_srcname" ] || {
    echo "Error: could not parse PKGBUILD" >&2
    exit 1
}

cp "$CONFIG" "$ALARM_CONFIG"
alarm_commit="$(git -C "$ALARM_DIR" rev-parse HEAD)"

# Extract the expected hashes for the kernel tarball (and patch) from the ALARM
# PKGBUILD.  ALARM publishes md5sums (not sha256) for these downloads; checking
# them still catches truncation, CDN corruption and a swapped tarball.  The
# generated PKGBUILD records the sha256 of everything that was actually built,
# and those values are signed and published with the package.
mapfile -t alarm_source_entries < <(
    bash -c 'set +u; source "$1" >/dev/null 2>&1; printf "%s\n" "${source[@]}"' \
        _ "$PKGBUILD"
)
mapfile -t alarm_source_sums < <(
    bash -c 'set +u; source "$1" >/dev/null 2>&1; printf "%s\n" "${md5sums[@]}"' \
        _ "$PKGBUILD"
)
if [ "${#alarm_source_entries[@]}" -ne "${#alarm_source_sums[@]}" ]; then
    echo "Error: could not read source[]/md5sums[] from $PKGBUILD" >&2
    exit 1
fi

collect_sum() {
    local wanted="$1" entry base i
    for i in "${!alarm_source_entries[@]}"; do
        entry="${alarm_source_entries[$i]%%::*}"
        base="${entry##*/}"
        [ "$base" = "$wanted" ] || continue
        printf '%s  %s\n' "${alarm_source_sums[$i]}" "$wanted"
        return 0
    done
    return 1
}

: > "$ALARM_SOURCE_SUMS"
if ! collect_sum "${_srcname}.tar.xz" >> "$ALARM_SOURCE_SUMS"; then
    echo "Error: ALARM PKGBUILD lists no ${_srcname}.tar.xz source" >&2
    exit 1
fi
if [ "$pkgver" != "${_srcname#linux-}" ]; then
    if ! collect_sum "patch-${pkgver}.xz" >> "$ALARM_SOURCE_SUMS"; then
        echo "Error: ALARM PKGBUILD lists no patch-${pkgver}.xz source" >&2
        exit 1
    fi
fi
if [ ! -s "$ALARM_SOURCE_SUMS" ] || grep -qvE '^[0-9a-f]{32}  [^ ]+$' "$ALARM_SOURCE_SUMS"; then
    echo "Error: unusable source hashes in $ALARM_SOURCE_SUMS" >&2
    exit 1
fi

{
    printf '# ALARM linux-aarch64 at clone %s\n' "$alarm_commit"
    printf 'alarm_repo=%q\n' "$ALARM_REPO"
    printf 'alarm_commit=%q\n' "$alarm_commit"
    printf 'pkgver=%q\n' "$pkgver"
    printf 'pkgrel=%q\n' "$pkgrel"
    printf '_srcname=%q\n' "$_srcname"
} > "$ALARM_VERSION_FILE"

echo "    ALARM version: ${pkgver}-${pkgrel} ($_srcname) -> $ALARM_VERSION_FILE"
echo "    ALARM config: $(wc -l < "$ALARM_CONFIG") lines → $ALARM_CONFIG"
echo "Done."
