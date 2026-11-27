#!/usr/bin/env bash
# Assemble makepkg source directory under build/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
ALARM_CONFIG="$BUILD/alarm.config"
ALARM_VERSION_FILE="${ALARM_VERSION_FILE:-$BUILD/alarm-version.env}"
ALARM_SOURCE_SUMS="${ALARM_SOURCE_SUMS:-$BUILD/alarm-source-md5.txt}"

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

[ -f "$ALARM_SOURCE_SUMS" ] || {
    echo "Error: missing $ALARM_SOURCE_SUMS (run scripts/fetch-alarm-sources.sh)" >&2
    exit 1
}

echo "==> Downloading kernel sources for ${pkgver}..."
for artifact in "${artifacts[@]}"; do
    if [ -f "$artifact" ]; then
        echo "    reusing cached $artifact"
    else
        partial="${artifact}.part"
        curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
            -o "$partial" \
            "https://www.kernel.org/pub/linux/kernel/v${kernel_major}.x/$artifact"
        mv "$partial" "$artifact"
    fi

    # Verify against the hash published in the ALARM PKGBUILD, every run --
    # a cached/tampered file must not silently feed the build.
    expected="$(awk -v name="$artifact" '$2 == name { print $1 }' "$ALARM_SOURCE_SUMS")"
    [ -n "$expected" ] || {
        echo "Error: no expected hash for $artifact in $ALARM_SOURCE_SUMS" >&2
        exit 1
    }
    actual="$(md5sum "$artifact" | awk '{ print $1 }')"
    if [ "$actual" != "$expected" ]; then
        echo "Error: $artifact hash mismatch" >&2
        echo "       expected $expected" >&2
        echo "       actual   $actual" >&2
        rm -f "$artifact"
        exit 1
    fi
    echo "    verified $artifact ($expected)"
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

# Replace the SKIP placeholders with the real hashes of exactly the sources
# that are about to be built.
checksum_files=(
    "${_srcname}.tar.xz"
    config.merged
    linux-nanopi-r2c-minimal.preset
    mkinitcpio.linux-nanopi-r2c-minimal.conf
    r8152-led-config-from-of.patch
    rk3328-nanopi-r2c-r8153-led-data.patch
)
if [ "$pkgver" != "$base_version" ]; then
    checksum_files+=("patch-${pkgver}.xz")
fi
checksums=()
for file in "${checksum_files[@]}"; do
    checksums+=("$(sha256sum "$file" | awk '{ print $1 }')")
done

sums_file="$(mktemp)"
{
    echo "sha256sums=("
    for i in "${!checksum_files[@]}"; do
        printf "    '%s'  # %s\n" "${checksums[$i]}" "${checksum_files[$i]}"
    done
    echo ")"
} > "$sums_file"

awk -v block="$sums_file" '
    BEGIN { replaced = 0 }
    /^sha256sums=\(/ && !replaced {
        while ((getline line < block) > 0) print line
        close(block)
        replaced = 1
        next
    }
    { print }
' PKGBUILD > PKGBUILD.new
mv PKGBUILD.new PKGBUILD
rm -f "$sums_file"

if grep -q "SKIP" PKGBUILD; then
    echo "Error: PKGBUILD still contains SKIP checksums after generation" >&2
    exit 1
fi
echo "    sha256sums generated for ${#checksum_files[@]} sources"

echo "Build directory ready: $BUILD"
