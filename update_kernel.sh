#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="$BASE/root-mx25"
ISO_WORK="$BASE/iso-work"
ANTIX="$ISO_WORK/antiX"
INITRD_BASE="$ANTIX/initrd-base.gz"

BACKUP_DIR="$BASE/kernel-backups"
WORKDIR="$BASE/kernel-work"
CHECK="$BASE/kernel-check"

# Live initrd mora da sadrži KMS module i firmware pre coldplug faze.
# QEMU virtio-gpu nije zamena za fizičke Intel/AMD/NVIDIA adaptere.
GPU_MODULES=(amdgpu i915 nouveau radeon xe)
GPU_FIRMWARE=(amdgpu i915 nvidia radeon xe)

UNPACK="$ROOT/usr/lib/cli-shell-utils/bin/unpack-initrd"
COPYMOD="$ROOT/usr/lib/cli-shell-utils/bin/copy-initrd-modules"

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

cleanup() {
    echo
    echo "[CLEANUP] Brišem radne fajlove..."

    sudo rm -rf "$WORKDIR"
    sudo rm -rf "$CHECK"

    echo "[CLEANUP] Gotovo."
}

trap cleanup EXIT

# ------------------------------------------------------------
# 1. Osnovne provere
# ------------------------------------------------------------

echo
echo "=========================================="
echo " diya MX Live kernel updater"
echo "=========================================="
echo

echo "[1/6] Provera..."

test -d "$ROOT" || {
    echo "ERROR: nema:"
    echo "  $ROOT"
    exit 1
}

test -d "$ISO_WORK" || {
    echo "ERROR: nema:"
    echo "  $ISO_WORK"
    exit 1
}

test -d "$ANTIX" || {
    echo "ERROR: nema:"
    echo "  $ANTIX"
    exit 1
}

test -x "$UNPACK" || {
    echo "ERROR: nema executable:"
    echo "  $UNPACK"
    exit 1
}

test -x "$COPYMOD" || {
    echo "ERROR: nema executable:"
    echo "  $COPYMOD"
    exit 1
}

test -f "$INITRD_BASE" || {
    echo "ERROR: nema osnovnog Live initrd šablona:"
    echo "  $INITRD_BASE"
    exit 1
}

echo "OK"
echo

# ------------------------------------------------------------
# 2. Pronađi kernel
# ------------------------------------------------------------

echo "[2/6] Skeniram root-mx25..."

mapfile -t KERNELS < <(
    find "$ROOT/boot" \
        -maxdepth 1 \
        -type f \
        -name 'vmlinuz-*' \
        -printf '%f\n' \
    | sed 's/^vmlinuz-//' \
    | sort -V
)

if [ "${#KERNELS[@]}" -eq 0 ]; then
    echo
    echo "ERROR: nijedan vmlinuz-* nije pronađen u:"
    echo "  $ROOT/boot"
    exit 1
fi

if [ "${#KERNELS[@]}" -gt 1 ]; then
    echo
    echo "ERROR: pronađeno je više kernela:"
    echo
    printf '  %s\n' "${KERNELS[@]}"
    echo
    echo "Skripta namerno neće da nagađa."
    exit 1
fi

KVER="${KERNELS[0]}"

echo "Pronađen kernel:"
echo "  $KVER"
echo

# ------------------------------------------------------------
# 3. Provera modules stabla
# ------------------------------------------------------------

echo "[3/6] Proveravam modules..."

MODULES="$ROOT/lib/modules/$KVER"

if [ ! -d "$MODULES" ]; then
    MODULES="$(readlink -f "$ROOT/lib/modules/$KVER" 2>/dev/null || true)"
fi

if [ ! -d "$MODULES" ]; then
    echo
    echo "ERROR: nema modules stabla za:"
    echo "  $KVER"
    echo
    echo "Očekivano:"
    echo "  $ROOT/lib/modules/$KVER"
    exit 1
fi

echo "Modules:"
echo "  $MODULES"

OVERLAY="$MODULES/kernel/fs/overlayfs/overlay.ko.zst"

if [ ! -f "$OVERLAY" ]; then
    echo
    echo "ERROR: nema overlay.ko.zst za:"
    echo "  $KVER"
    echo
    echo "$OVERLAY"
    exit 1
fi

echo
echo "overlay.ko.zst: OK"
echo

# ------------------------------------------------------------
# 4. Backup
# ------------------------------------------------------------

echo "[4/6] Backup..."

STAMP="$(date +%Y%m%d-%H%M%S)"

sudo mkdir -p "$BACKUP_DIR"

if [ -f "$ANTIX/vmlinuz" ]; then
    sudo cp -a \
        "$ANTIX/vmlinuz" \
        "$BACKUP_DIR/vmlinuz.backup-$STAMP"
fi

if [ -f "$ANTIX/initrd.gz" ]; then
    sudo cp -a \
        "$ANTIX/initrd.gz" \
        "$BACKUP_DIR/initrd.gz.backup-$STAMP"
fi

echo
echo "Backup napravljen u:"
echo "  $BACKUP_DIR"
echo
echo "Pripremam radni initrd iz osnovnog šablona..."
sudo install -o root -g root -m 0644 "$INITRD_BASE" "$ANTIX/initrd.gz"


# ------------------------------------------------------------
# 5. Kernel + initrd
# ------------------------------------------------------------

echo "[5/6] Ažuriram Live kernel..."

sudo cp -a \
    "$ROOT/boot/vmlinuz-$KVER" \
    "$ANTIX/vmlinuz"

echo
echo "Novi vmlinuz:"
file "$ANTIX/vmlinuz"
echo

# ------------------------------------------------------------
# Radni direktorijum
# ------------------------------------------------------------

sudo rm -rf "$WORKDIR"
sudo mkdir -p "$WORKDIR"
# The unpacker runs as root and may create the work tree with mode 0700.
# Later validation checks run as the invoking user, so make the work root
# traversable before testing files beneath it.
sudo chmod 0755 "$WORKDIR"

echo "Raspakujem postojeći Live initrd..."

sudo "$UNPACK" \
    --clear \
    --from="$ANTIX/initrd.gz" \
    --dir="$WORKDIR/initrd"
sudo chmod 0755 "$WORKDIR/initrd"

test -f "$WORKDIR/initrd/init" || {
    echo
    echo "ERROR: /init nije pronađen u Live initrd-u."
    exit 1
}

# Keep only the module tree for the kernel being installed. Older updates
# otherwise accumulate stale kernel modules inside the Live initrd.
MODULE_ROOT="$WORKDIR/initrd/lib/modules"
if [ -d "$MODULE_ROOT" ]; then
    echo "Uklanjam module starih kernela iz Live initrd-a..."
    while IFS= read -r -d '' OLD_MODULE_DIR; do
        echo "  Uklanjam: $(basename "$OLD_MODULE_DIR")"
        sudo rm -rf -- "$OLD_MODULE_DIR"
    done < <(sudo find "$MODULE_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name "$KVER" -print0)
fi

echo
echo "Live initrd: OK"
echo

# ------------------------------------------------------------
# Kopiranje modula
# ------------------------------------------------------------

echo "Kopiram module za:"
echo "  $KVER"
echo

sudo "$COPYMOD" \
    --from="$ROOT" \
    --kernel="$KVER" \
    --to="$WORKDIR/initrd" \
    --count \
    --verbose

echo
echo "Dodajem fizičke GPU module:"
printf '  %s\n' "${GPU_MODULES[@]}"
printf '%s\n' "${GPU_MODULES[@]}" | sudo "$COPYMOD" \
    --from="$ROOT" \
    --kernel="$KVER" \
    --to="$WORKDIR/initrd" \
    --count \
    --verbose \
    --

echo
echo "Dodajem firmware za fizičke GPU uređaje:"
FIRMWARE_SOURCE="$ROOT/lib/firmware"
FIRMWARE_DEST="$WORKDIR/initrd/lib/firmware"
sudo mkdir -p "$FIRMWARE_DEST"

for FW in "${GPU_FIRMWARE[@]}"; do
    if [ ! -d "$FIRMWARE_SOURCE/$FW" ]; then
        echo "ERROR: nedostaje firmware direktorijum: $FIRMWARE_SOURCE/$FW"
        exit 1
    fi

    sudo rm -rf "$FIRMWARE_DEST/$FW"
    sudo cp -a "$FIRMWARE_SOURCE/$FW" "$FIRMWARE_DEST/"
    echo "  OK  $FW"
done

echo "Firmware veličina:"
sudo du -sh "$FIRMWARE_DEST"

MODULE_COUNT="$(
    sudo find "$WORKDIR/initrd/lib/modules/$KVER" \
        -type f \
        -name '*.ko*' \
        | wc -l
)"

echo "Kopirano modula: $MODULE_COUNT"

if [ "$MODULE_COUNT" -eq 0 ]; then
    echo
    echo "ERROR: nijedan modul nije kopiran."
    exit 1
fi

echo
echo "Provera ključnih modula:"

for MOD in \
    overlay.ko.zst \
    squashfs.ko.zst \
    loop.ko.zst \
    isofs.ko.zst \
    amdgpu.ko.zst \
    i915.ko.zst \
    nouveau.ko.zst \
    radeon.ko.zst \
    xe.ko.zst
do
    FOUND="$(
        sudo find "$WORKDIR/initrd/lib/modules/$KVER" \
            -type f \
            -name "$MOD" \
            -print \
            | head -1
    )"

    if [ -z "$FOUND" ]; then
        echo "ERROR: nedostaje $MOD"
        exit 1
    fi

    echo "  OK  $MOD"
done

echo

# ------------------------------------------------------------
# Repack
# ------------------------------------------------------------

echo "Repackujem initrd..."

sudo "$UNPACK" \
    --from="$ANTIX/initrd.gz" \
    --dir="$WORKDIR/initrd" \
    --repack

test -s "$ANTIX/initrd.gz" || {
    echo
    echo "ERROR: repack nije napravio initrd.gz"
    exit 1
}

echo
echo "Initrd uspešno napravljen."
echo

# ------------------------------------------------------------
# 6. Završna validacija
# ------------------------------------------------------------

echo "[6/6] Završna validacija..."

echo
echo "Kernel:"
file "$ANTIX/vmlinuz"

echo
echo "Initrd:"
ls -lh "$ANTIX/initrd.gz"

# ------------------------------------------------------------
# Validacija novog initrd-a
# ------------------------------------------------------------

sudo rm -rf "$CHECK"

sudo "$UNPACK" \
    --clear \
    --from="$ANTIX/initrd.gz" \
    --dir="$CHECK"
sudo chmod 0755 "$CHECK" "$CHECK/lib" "$CHECK/lib/firmware"

test -f "$CHECK/init" || {
    echo
    echo "ERROR: novi initrd nema /init"
    exit 1
}

for MOD in \
    overlay.ko.zst \
    squashfs.ko.zst \
    loop.ko.zst \
    isofs.ko.zst \
    amdgpu.ko.zst \
    i915.ko.zst \
    nouveau.ko.zst \
    radeon.ko.zst \
    xe.ko.zst
do
    sudo find "$CHECK/lib/modules/$KVER" \
        -type f \
        -name "$MOD" \
        -print \
        | grep -q . || {
            echo
            echo "ERROR: validacija nije našla $MOD"
            exit 1
        }
done

for FW in "${GPU_FIRMWARE[@]}"; do
    test -d "$CHECK/lib/firmware/$FW" || {
        echo
        echo "ERROR: validacija nije našla firmware direktorijum $FW"
        exit 1
    }

    sudo find "$CHECK/lib/firmware/$FW" -type f -print -quit | grep -q . || {
        echo
        echo "ERROR: firmware direktorijum $FW je prazan"
        exit 1
    }
done

FINAL_COUNT="$(
    sudo find "$CHECK/lib/modules/$KVER" \
        -type f \
        -name '*.ko*' \
        | wc -l
)"

echo
echo "Validacija OK."
echo "Modula u initrd-u: $FINAL_COUNT"

# ------------------------------------------------------------
# Provera da iso-work nije dobio radne fajlove
# ------------------------------------------------------------

echo
echo "Proveravam iso-work..."

if find "$ISO_WORK" \
    -type f \
    \( \
        -name '*.backup-*' -o \
        -name '*.tmp' -o \
        -name '*.temp' -o \
        -name '*.new' \
    \) \
    -print -quit | grep -q .
then
    echo
    echo "ERROR: pronađen privremeni/backup fajl u iso-work!"
    exit 1
fi

echo "iso-work je čist."

echo
echo "=========================================="
echo " KERNEL UPDATE GOTOV"
echo "=========================================="
echo
echo "Kernel:"
echo "  $KVER"
echo
echo "Live:"
echo "  $ANTIX/vmlinuz"
echo "  $ANTIX/initrd.gz"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Radni fajlovi:"
echo "  biće obrisani automatski"
echo
echo "=========================================="
echo