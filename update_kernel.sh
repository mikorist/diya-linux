#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="$BASE/root-mx25"
ISO_WORK="$BASE/iso-work"
ANTIX="$ISO_WORK/antiX"

BACKUP_DIR="$BASE/kernel-backups"
WORKDIR="$BASE/kernel-work"
CHECK="$BASE/kernel-check"

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

test -f "$ANTIX/initrd.gz" || {
    echo "ERROR: nema:"
    echo "  $ANTIX/initrd.gz"
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

echo "Raspakujem postojeći Live initrd..."

sudo "$UNPACK" \
    --clear \
    --from="$ANTIX/initrd.gz" \
    --dir="$WORKDIR/initrd"

test -f "$WORKDIR/initrd/init" || {
    echo
    echo "ERROR: /init nije pronađen u Live initrd-u."
    exit 1
}

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
    isofs.ko.zst
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

test -f "$CHECK/init" || {
    echo
    echo "ERROR: novi initrd nema /init"
    exit 1
}

for MOD in \
    overlay.ko.zst \
    squashfs.ko.zst \
    loop.ko.zst \
    isofs.ko.zst
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