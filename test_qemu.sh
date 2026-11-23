#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO="$BASE/diya.iso"
QEMU_VGA="${QEMU_VGA:-virtio}"

# ------------------------------------------------------------
# Provera / instalacija QEMU
# ------------------------------------------------------------

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then

    echo
    echo "QEMU nije instaliran."
    echo
    echo "Instaliram potrebne pakete..."
    echo

    sudo apt update

    sudo apt install -y \
        qemu-system-x86 \
        qemu-utils \
        qemu-system-gui

    echo
    echo "QEMU instaliran."
    echo
fi

# ------------------------------------------------------------
# Provera ISO-a
# ------------------------------------------------------------

test -f "$ISO" || {
    echo
    echo "ERROR: nema ISO fajla:"
    echo "  $ISO"
    echo
    echo "Prvo pokreni:"
    echo "  ./build.sh"
    echo
    exit 1
}

# ------------------------------------------------------------
# Pokretanje QEMU
# ------------------------------------------------------------

echo
echo "=========================================="
echo " diya Linux QEMU TEST"
echo "=========================================="
echo
echo "ISO:"
echo "  $ISO"
echo
echo "QEMU video adapter:"
echo "  $QEMU_VGA"
echo

qemu-system-x86_64 \
    -enable-kvm \
    -machine q35 \
    -m 4096 \
    -smp 4 \
    -cpu host \
    -drive file="$ISO",media=cdrom,readonly=on \
    -boot d \
    -vga "$QEMU_VGA" \
    -display gtk \
    -nic user,model=virtio,hostfwd=tcp:127.0.0.1:2222-:22