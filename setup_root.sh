#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO="mikorist/diya-linux"
RELEASE_TAG="diya_linux"

SNAPSHOT="diya-root-mx25.tar.zst"
CHECKSUM="${SNAPSHOT}.sha256"

ROOT_DIR="$BASE/root-mx25"
TMP_DIR="$BASE/.setup-root-tmp"

SNAPSHOT_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${SNAPSHOT}"
CHECKSUM_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${CHECKSUM}"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

echo
echo "=========================================="
echo " diya Linux root filesystem setup"
echo "=========================================="
echo

if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl nije instaliran."
    echo
    echo "Instaliraj ga pomoću:"
    echo "  sudo apt install curl"
    echo
    exit 1
fi

if ! command -v sha256sum >/dev/null 2>&1; then
    echo "ERROR: sha256sum nije dostupan."
    echo
    exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
    echo "ERROR: tar nije instaliran."
    echo
    exit 1
fi

if ! command -v zstd >/dev/null 2>&1; then
    echo "ERROR: zstd nije instaliran."
    echo
    echo "Instaliraj ga pomoću:"
    echo "  sudo apt install zstd"
    echo
    exit 1
fi

if [ -e "$ROOT_DIR" ]; then
    if [ "$(find "$ROOT_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]; then
        echo "ERROR: root-mx25/ već postoji i nije prazan:"
        echo
        echo "  $ROOT_DIR"
        echo
        echo "Neću pregaziti postojeći filesystem."
        echo
        exit 1
    fi
fi

mkdir -p "$TMP_DIR"

echo "Repozitorijum:"
echo "  $REPO"
echo

echo "Preuzimam snapshot:"
echo "  $SNAPSHOT"
echo

curl -fL \
    --progress-bar \
    -o "$TMP_DIR/$SNAPSHOT" \
    "$SNAPSHOT_URL"

echo
echo "Preuzimam SHA256:"
echo "  $CHECKSUM"
echo

curl -fL \
    --progress-bar \
    -o "$TMP_DIR/$CHECKSUM" \
    "$CHECKSUM_URL"

echo
echo "Proveravam SHA256..."
echo

cd "$TMP_DIR"

sha256sum -c "$CHECKSUM"

echo
echo "SHA256 provera uspešna."
echo

mkdir -p "$ROOT_DIR"

echo "Raspakujem snapshot u:"
echo "  $ROOT_DIR"
echo

sudo tar \
    --numeric-owner \
    --acls \
    --xattrs \
    --zstd \
    -xf "$SNAPSHOT" \
    -C "$ROOT_DIR"

echo
echo "Snapshot je uspešno obnovljen."
echo

echo "Root filesystem:"
echo "  $ROOT_DIR"
echo

echo "Sledeći korak:"
echo
echo "  ./build.sh"
echo
