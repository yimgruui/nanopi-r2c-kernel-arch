#!/usr/bin/env bash
# Add built packages to a pacman repo directory.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="${REPO_DIR:-$ROOT/repo/aarch64}"
PKG_GLOB="${PKG_GLOB:-$ROOT/build/linux-nanopi-r2c-minimal-*.pkg.tar.zst}"

mkdir -p "$REPO_DIR"
shopt -s nullglob
pkgs=( $PKG_GLOB )
if [ "${#pkgs[@]}" -eq 0 ]; then
    echo "Error: no packages matching $PKG_GLOB" >&2
    exit 1
fi

if ! command -v repo-add >/dev/null 2>&1; then
    echo "Error: repo-add not found (install pacman)" >&2
    exit 1
fi

for p in "${pkgs[@]}"; do
    cp "$p" "$REPO_DIR/"
    [ -f "${p}.sig" ] && cp "${p}.sig" "$REPO_DIR/"
done

(
    cd "$REPO_DIR"
    db="nanopi-r2c-kernel-arch.db.tar.gz"
    names=( "${pkgs[@]##*/}" )
    echo "==> repo-add ${#names[@]} package(s)"
    repo_add_flags=()
    if [ -n "${PACMAN_KEY_ID:-}" ]; then
        repo_add_flags=(--sign --key "$PACMAN_KEY_ID")
    fi
    repo-add "${repo_add_flags[@]}" "$db" "${names[@]}"
    for kind in db files; do
        compressed="nanopi-r2c-kernel-arch.${kind}.tar.gz"
        plain="nanopi-r2c-kernel-arch.${kind}"
        [ -f "$compressed" ] || continue
        rm -f "$plain" "${plain}.sig"
        cp "$compressed" "$plain"
        [ -f "${compressed}.sig" ] && cp "${compressed}.sig" "${plain}.sig"
    done
    sha256sum linux-nanopi-r2c-minimal-*.pkg.tar.zst > SHA256SUMS 2>/dev/null || true
)

echo "Repo published under $REPO_DIR"
