#!/usr/bin/env bash
# Add built packages to a pacman repo directory.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="${REPO_DIR:-$ROOT/repo/aarch64}"
PKG_GLOB="${PKG_GLOB:-$ROOT/build/linux-nanopi-r2c-minimal-*.pkg.tar.zst}"

mkdir -p "$REPO_DIR"
shopt -s nullglob
# shellcheck disable=SC2206  # intentional glob expansion under nullglob
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
    if [ -f "${p}.sig" ]; then
        cp "${p}.sig" "$REPO_DIR/"
    else
        echo "Error: ${p}.sig is missing; refusing to publish an unsigned repository" >&2
        exit 1
    fi
done

if [ -n "${REPO_PUBKEY_FILE:-}" ]; then
    [ -f "$REPO_PUBKEY_FILE" ] || {
        echo "Error: REPO_PUBKEY_FILE=$REPO_PUBKEY_FILE does not exist" >&2
        exit 1
    }
    cp "$REPO_PUBKEY_FILE" "$REPO_DIR/nanopi-r2c-kernel-arch.pub"
fi

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

    # Checksums cover every file a pacman client downloads: the packages, the
    # detached signatures and the repository key.  Do not hide failures with
    # `|| true`; a missing checksum entry is a broken repository.
    checksum_files=( linux-nanopi-r2c-minimal-*.pkg.tar.zst )
    if compgen -G "linux-nanopi-r2c-minimal-*.pkg.tar.zst.sig" >/dev/null; then
        checksum_files+=( linux-nanopi-r2c-minimal-*.pkg.tar.zst.sig )
    fi
    if [ -f nanopi-r2c-kernel-arch.pub ]; then
        checksum_files+=( nanopi-r2c-kernel-arch.pub )
    fi
    sha256sum "${checksum_files[@]}" > SHA256SUMS
    sha256sum -c SHA256SUMS >/dev/null
)

echo "Repo published under $REPO_DIR"
