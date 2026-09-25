#!/usr/bin/env bash
# Merge ALARM baseline config + build fragments into kernel .config.
# Usage: merge-config.sh <kernel-source-dir> [output-file] [base-config]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KDIR="${1:?kernel source directory required}"
OUT="${2:-$ROOT/build/config.merged}"
BASE="${3:-$ROOT/build/alarm.config}"

FRAGMENTS=(
    "$ROOT/config/fragment.prune"
    "$ROOT/config/fragment.r2c"
)

[ -f "$BASE" ] || {
    echo "Error: missing baseline config $BASE" >&2
    exit 1
}
for frag in "${FRAGMENTS[@]}"; do
    [ -f "$frag" ] || {
        echo "Error: missing $frag" >&2
        exit 1
    }
done
[ -x "$KDIR/scripts/config" ] || {
    echo "Error: $KDIR/scripts/config not found" >&2
    exit 1
}

echo "==> Merging baseline config: $(basename "$BASE")"
cp "$BASE" "$KDIR/.config"
make -C "$KDIR" ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}" olddefconfig >/dev/null

declare -A EXPECTED_VAL

apply_fragment() {
    local frag="$1"
    local key val sym
    echo "==> Applying $(basename "$frag")..."
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="$(printf '%s\n' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$line" || "$line" != CONFIG_*=* ]] && continue
        key="${line%%=*}"
        val="${line#*=}"
        sym="${key#CONFIG_}"
        case "$val" in
            y) "$KDIR/scripts/config" --file "$KDIR/.config" --keep-case --enable "$sym" ;;
            m) "$KDIR/scripts/config" --file "$KDIR/.config" --keep-case --module "$sym" ;;
            n) "$KDIR/scripts/config" --file "$KDIR/.config" --keep-case --disable "$sym" ;;
            *) "$KDIR/scripts/config" --file "$KDIR/.config" --keep-case --set-val "$sym" "$val" ;;
        esac
        EXPECTED_VAL["$key"]="$val"
    done < "$frag"
}

for frag in "${FRAGMENTS[@]}"; do
    apply_fragment "$frag"
done

make -C "$KDIR" ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}" olddefconfig >/dev/null

error_count=0
for key in "${!EXPECTED_VAL[@]}"; do
    val="${EXPECTED_VAL[$key]}"
    if [ "$val" = "n" ]; then
        if grep -qE "^${key}=(y|m)$" "$KDIR/.config"; then
            echo "Warning: ${key}=n requested but kept enabled (forced by Kconfig deps)" >&2
        fi
        continue
    fi
    if ! grep -Fqx "${key}=${val}" "$KDIR/.config"; then
        echo "Error: ${key}=${val} not present after olddefconfig (missing/renamed?)" >&2
        echo "       actual: $(grep -E "^${key}[=(]|^# ${key} is not set" "$KDIR/.config" 2>/dev/null || echo 'symbol absent entirely')" >&2
        error_count=$((error_count + 1))
    fi
done
if [ "$error_count" -gt 0 ]; then
    echo "Error: unresolved config requests: $error_count" >&2
    exit 1
fi

cp "$KDIR/.config" "$OUT"
echo "Merged config written to $OUT"
