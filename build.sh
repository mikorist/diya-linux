#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="$BASE/root-mx25"
ISO_WORK="$BASE/iso-work"
ANTIX="$ISO_WORK/antiX"

LINUXFS_NEW="$BASE/linuxfs.new"
ISO_OUT="$BASE/diya.iso"
ISO_MD5="$BASE/diya.iso.md5"
VERSION_FILE="$ISO_WORK/version"

# ------------------------------------------------------------
# Cleanup na izlazu
# ------------------------------------------------------------

cleanup() {
    echo
    echo "[CLEANUP] Brišem privremene fajlove..."

    sudo rm -f "$LINUXFS_NEW"

    echo "[CLEANUP] Gotovo."
}

trap cleanup EXIT

# ------------------------------------------------------------
# Provere
# ------------------------------------------------------------

echo
echo "=========================================="
echo " MX diya ISO BUILD"
echo "=========================================="
echo

echo "[1/6] Provera strukture..."

test -d "$ROOT" || {
    echo "ERROR: nema root-mx25:"
    echo "$ROOT"
    exit 1
}

test -d "$ISO_WORK" || {
    echo "ERROR: nema iso-work:"
    echo "$ISO_WORK"
    exit 1
}

test -d "$ANTIX" || {
    echo "ERROR: nema:"
    echo "$ANTIX"
    exit 1
}

test -f "$ANTIX/vmlinuz" || {
    echo "ERROR: nema antiX/vmlinuz"
    exit 1
}

test -f "$ANTIX/initrd.gz" || {
    echo "ERROR: nema antiX/initrd.gz"
    exit 1
}

echo "OK"
echo

# ------------------------------------------------------------
# Provera da iso-work nema naše privremene fajlove
# ------------------------------------------------------------

echo "[2/6] Provera iso-work..."

BAD_FILES=()

while IFS= read -r -d '' f; do
    BAD_FILES+=("$f")
done < <(
    find "$ISO_WORK" \
        \( \
        -name '*.tmp' -o \
        -name '*.temp' -o \
        -name '*.new' -o \
        -name '*.backup-*' \
        \) \
        -print0
)

if [ "${#BAD_FILES[@]}" -ne 0 ]; then
    echo
    echo "ERROR: iso-work nije čist."
    echo
    printf '  %s\n' "${BAD_FILES[@]}"
    echo
    echo "Ništa ne brišem automatski."
    exit 1
fi

echo "iso-work je čist."
echo

# ------------------------------------------------------------
# Backup postojećeg linuxfs
# ------------------------------------------------------------

echo "[3/6] Backup postojećeg linuxfs..."

if [ -f "$ANTIX/linuxfs" ]; then

    BACKUP="$BASE/linuxfs.backup-$(date +%Y%m%d-%H%M%S)"

    sudo cp -a \
        "$ANTIX/linuxfs" \
        "$BACKUP"

    echo "Backup:"
    echo "  $BACKUP"
else
    echo "Nema postojećeg linuxfs, preskačem backup."
fi

echo

# ------------------------------------------------------------
# Pravljenje novog linuxfs
# ------------------------------------------------------------

echo "[4/6] Pravim novi linuxfs iz root-mx25..."
echo
echo "Izvor:"
echo "  $ROOT"
echo
echo "Privremeni fajl:"
echo "  $LINUXFS_NEW"
echo

sudo rm -f "$LINUXFS_NEW"

sudo mksquashfs \
    "$ROOT" \
    "$LINUXFS_NEW" \
    -comp xz \
    -b 1M \
    -Xdict-size 1M \
    -Xbcj x86 \
    -noappend

test -s "$LINUXFS_NEW" || {
    echo
    echo "ERROR: mksquashfs nije napravio linuxfs."
    exit 1
}

echo
echo "SquashFS napravljen:"
ls -lh "$LINUXFS_NEW"

echo

# ------------------------------------------------------------
# Zamena linuxfs u ISO stagingu
# ------------------------------------------------------------

echo "Kopiram novi linuxfs u iso-work..."

sudo cp \
    "$LINUXFS_NEW" \
    "$ANTIX/linuxfs"

echo
echo "linuxfs zamenjen:"
ls -lh "$ANTIX/linuxfs"

echo

# ------------------------------------------------------------
# Version
# ------------------------------------------------------------

echo "[VERSION] Upisujem build verziju..."

MONTH=""

case "$(date +%m)" in
    01) MONTH="Januar" ;;
    02) MONTH="Februar" ;;
    03) MONTH="Mart" ;;
    04) MONTH="April" ;;
    05) MONTH="Maj" ;;
    06) MONTH="Jun" ;;
    07) MONTH="Jul" ;;
    08) MONTH="Avgust" ;;
    09) MONTH="Septembar" ;;
    10) MONTH="Oktobar" ;;
    11) MONTH="Novembar" ;;
    12) MONTH="Decembar" ;;
esac

DAY="$(date '+%-d')"
TIME="$(date '+%H:%M')"
YEAR="$(date '+%Y')"

printf 'diya Linux %s %s %s %s\n' \
    "$MONTH" \
    "$DAY" \
    "$TIME" \
    "$YEAR" \
    | sudo tee "$VERSION_FILE" >/dev/null

echo
echo "Version:"
cat "$VERSION_FILE"

echo

# ------------------------------------------------------------
# MD5 za fajlove unutar antiX
# ------------------------------------------------------------

echo "[5/6] Osvežavam MD5..."

(
    cd "$ANTIX"

    md5sum linuxfs > linuxfs.md5
    md5sum vmlinuz > vmlinuz.md5
    md5sum initrd.gz > initrd.gz.md5
)

echo "MD5 OK."
echo

# ------------------------------------------------------------
# ISO
# ------------------------------------------------------------

echo "Pravim ISO:"
echo "  $ISO_OUT"
echo

sudo rm -f "$ISO_OUT"
sudo rm -f "$ISO_MD5"

xorriso -as mkisofs \
    -o "$ISO_OUT" \
    -V 'diya-Live' \
    --modification-date=2026053112240500 \
    -isohybrid-mbr "$BASE/mx-isohybrid-mbr.bin" \
    -partition_cyl_align off \
    -partition_offset 0 \
    --mbr-force-bootable \
    -iso_mbr_part_type 0x00 \
    -c '/boot/isolinux/isolinux.cat' \
    -b '/boot/isolinux/isolinux.bin' \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e '/boot/grub/efi.img' \
    -no-emul-boot \
    -boot-load-size 16384 \
    -isohybrid-gpt-basdat \
    "$ISO_WORK"

echo

# ------------------------------------------------------------
# MD5 za kompletan ISO
# ------------------------------------------------------------

echo "[6/6] Pravim MD5 za ISO..."

md5sum "$ISO_OUT" > "$ISO_MD5"

echo
echo "ISO MD5:"
cat "$ISO_MD5"

echo

# ------------------------------------------------------------
# Završni rezultat
# ------------------------------------------------------------

echo "=========================================="
echo " BUILD GOTOV"
echo "=========================================="
echo

echo "ISO:"
ls -lh "$ISO_OUT"

echo
echo "MD5:"
ls -lh "$ISO_MD5"

echo
echo "Version:"
cat "$VERSION_FILE"

echo
echo "ISO staging:"
echo "  $ISO_WORK"

echo
echo "Privremeni linuxfs:"
echo "  $LINUXFS_NEW"
echo "  biće obrisan pri izlasku"

echo
echo "Provera završena."
echo