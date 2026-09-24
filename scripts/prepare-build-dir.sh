#!/usr/bin/env bash
# Assemble makepkg source directory under build/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
ALARM_CONFIG="$BUILD/alarm.config"
ALARM_VERSION_FILE="${ALARM_VERSION_FILE:-$BUILD/alarm-version.env}"

mkdir -p "$BUILD"
cd "$BUILD"

echo "==> Config baseline: latest ALARM config + local fragments"

if [ "${SKIP_ALARM_FETCH:-0}" != "1" ]; then
    "$ROOT/scripts/fetch-alarm-sources.sh"
else
    echo "==> Using cached ALARM metadata (SKIP_ALARM_FETCH=1)"
    [ -f "$ALARM_CONFIG" ] || {
        echo "Error: SKIP_ALARM_FETCH=1 but missing $ALARM_CONFIG (run fetch-alarm-sources.sh)" >&2
        exit 1
    }
    [ -f "$ALARM_VERSION_FILE" ] || {
        echo "Error: SKIP_ALARM_FETCH=1 but missing $ALARM_VERSION_FILE (run fetch-alarm-sources.sh)" >&2
        exit 1
    }
fi

# shellcheck source=/dev/null
source "$ALARM_VERSION_FILE"
pkgver="${pkgver:?}"
pkgrel="${pkgrel:?}"
_srcname="${_srcname:?}"

kernel_major="${pkgver%%.*}"
base_version="${_srcname#linux-}"
artifacts=("${_srcname}.tar.xz")
if [ "$pkgver" != "$base_version" ]; then
    artifacts+=("patch-${pkgver}.xz")
fi

echo "==> Downloading kernel sources for ${pkgver}..."
for artifact in "${artifacts[@]}"; do
    if [ ! -f "$artifact" ]; then
        partial="${artifact}.part"
        curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
            -o "$partial" \
            "https://www.kernel.org/pub/linux/kernel/v${kernel_major}.x/$artifact"
        mv "$partial" "$artifact"
    fi
done
rm -rf "${_srcname}"
tar -xf "${_srcname}.tar.xz"
if [ "$pkgver" != "$base_version" ]; then
    patch --quiet -d "${_srcname}" -p1 < <(xz -dc "patch-${pkgver}.xz")
fi

echo "==> Merging kernel config against ${pkgver}..."
"$ROOT/scripts/merge-config.sh" "$BUILD/$_srcname" "$BUILD/config.merged" "$ALARM_CONFIG"
"$ROOT/scripts/verify-r2c-config.sh" "$BUILD/config.merged"

cp "$ROOT/packaging/PKGBUILD" "$ROOT/packaging/linux-nanopi-r2c-minimal.preset" \
    "$ROOT/packaging/linux-nanopi-r2c-minimal.install" \
    "$ROOT/packaging/mkinitcpio.linux-nanopi-r2c-minimal.conf" .
cp "$ROOT/packaging/r8152-led-config-from-of.patch" \
    "$ROOT/packaging/rk3328-nanopi-r2c-r8153-led-data.patch" .

# Sync PKGBUILD with the resolved ALARM version.
sed -i "s/^pkgver=.*/pkgver=${pkgver}/" PKGBUILD
sed -i "s/^pkgrel=.*/pkgrel=${pkgrel}/" PKGBUILD
sed -i "s/^_srcname=.*/_srcname=${_srcname}/" PKGBUILD

echo "Build directory ready: $BUILD"
