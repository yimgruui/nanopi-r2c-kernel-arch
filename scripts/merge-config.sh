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
make -C "$KDIR" ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE-aarch64-linux-gnu-}" olddefconfig >/dev/null

declare -A EXPECTED_VAL
declare -A KEY_SOURCE

# Validate the fragments before touching .config: duplicates make the merge
# order-dependent, and a symbol owned by both files violates the profile
# contract (fragment.prune only disables, fragment.r2c enables).
parse_fragment() {
    local frag="$1" line key val lineno=0 name
    name="$(basename "$frag")"
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        line="${line%%#*}"
        line="$(printf '%s\n' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$line" || "$line" != CONFIG_*=* ]] && continue
        key="${line%%=*}"
        val="${line#*=}"
        if [ -n "${KEY_SOURCE[$key]:-}" ]; then
            echo "Error: ${key} appears in both ${KEY_SOURCE[$key]} and ${name}:${lineno}" >&2
            echo "       fragment.prune and fragment.r2c must stay disjoint." >&2
            exit 1
        fi
        KEY_SOURCE["$key"]="${name}:${lineno}"
        EXPECTED_VAL["$key"]="$val"
    done < "$frag"
}

for frag in "${FRAGMENTS[@]}"; do
    parse_fragment "$frag"
done

# Symbols that were removed or renamed upstream make a prune entry silently
# useless.  Check the fragment symbol set against the Kconfig tree that is
# about to be built; CI can turn the warning into a hard failure with
# CONFIG_STRICT_SYMBOLS=1 once the profile is known clean.
kconfig_symbols="$(mktemp)"
trap 'rm -f "$kconfig_symbols"' EXIT
{ grep -rhoE '^[[:space:]]*(menuconfig|config)[[:space:]]+[A-Z0-9_]+' \
    --include='Kconfig*' "$KDIR" || true; } |
    awk '{print $NF}' | sort -u > "$kconfig_symbols"

if [ ! -s "$kconfig_symbols" ]; then
    echo "Warning: no Kconfig files found under $KDIR; skipping symbol existence check" >&2
else
    missing=0
    for key in "${!EXPECTED_VAL[@]}"; do
        if ! grep -qxF "${key#CONFIG_}" "$kconfig_symbols"; then
            echo "Warning: ${KEY_SOURCE[$key]}: ${key} is not defined by this kernel's Kconfig tree" >&2
            missing=$((missing + 1))
        fi
    done
    if [ "$missing" -gt 0 ]; then
        if [ "${CONFIG_STRICT_SYMBOLS:-0}" = "1" ]; then
            echo "Error: ${missing} fragment symbol(s) no longer exist (CONFIG_STRICT_SYMBOLS=1)" >&2
            echo "       Drop them or re-map them in config/fragment.*" >&2
            exit 1
        fi
        echo "       (warning only; set CONFIG_STRICT_SYMBOLS=1 to make this fatal)" >&2
    fi
fi

apply_fragment() {
    local frag="$1" key val sym
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
    done < "$frag"
}

for frag in "${FRAGMENTS[@]}"; do
    apply_fragment "$frag"
done

make -C "$KDIR" ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE-aarch64-linux-gnu-}" olddefconfig >/dev/null

error_count=0
for key in "${!EXPECTED_VAL[@]}"; do
    val="${EXPECTED_VAL[$key]}"
    if [ "$val" = "n" ]; then
        # A prune entry that olddefconfig keeps on means either a Kconfig
        # select/dependency overrides it or the symbol was renamed. Both are
        # drift: fragment.r2c owns the feature list, so =n must hold here.
        if grep -qE "^${key}=(y|m)$" "$KDIR/.config"; then
            echo "Error: ${key}=n not honored after olddefconfig (forced by Kconfig select/deps)" >&2
            echo "       actual: $(grep -E "^${key}=" "$KDIR/.config" | head -1 || true)" >&2
            error_count=$((error_count + 1))
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
