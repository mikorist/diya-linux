#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# One build at a time: prevents concurrent mksquashfs/xorriso runs.
exec 9>"$BASE/.build.lock"
if ! flock -n 9; then
    echo "ERROR: drugi ISO build je već pokrenut."
    exit 1
fi

ROOT="$BASE/root-mx25"
ISO_WORK="$BASE/iso-work"
ANTIX="$ISO_WORK/antiX"

LINUXFS_NEW="$BASE/linuxfs.new"
ISO_OUT="$BASE/diya.iso"
ISO_MD5="$BASE/diya.iso.md5"
ISO_NEW="$BASE/diya.iso.new"
ISO_MD5_NEW="$BASE/diya.iso.md5.new"
VERSION_FILE="$ISO_WORK/version"

# ------------------------------------------------------------
# Cleanup na izlazu
# ------------------------------------------------------------

cleanup() {
    echo
    echo "[CLEANUP] Brišem privremene fajlove..."

    sudo rm -f "$LINUXFS_NEW"
    rm -f "$ISO_NEW" "$ISO_MD5_NEW"

    echo "[CLEANUP] Gotovo."
}

trap cleanup EXIT

# ------------------------------------------------------------
# Provere
# ------------------------------------------------------------

echo
echo "=========================================="
echo " diya Linux ISO BUILD"
echo "=========================================="
echo

echo "[1/5] Provera strukture..."

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

INIT_LINK="$(readlink "$ROOT/sbin/init" 2>/dev/null || true)"
if [[ "$INIT_LINK" != "../lib/systemd/systemd" ]]; then
    echo "ERROR: diya Linux mora da koristi systemd kao /sbin/init."
    echo "Trenutni /sbin/init: $INIT_LINK"
    exit 1
fi
if sudo chroot "$ROOT" dpkg-query -W -f='${db:Status-Abbrev}' sysvinit-init-diversity 2>/dev/null | grep -q '^ii'; then
    echo "ERROR: sysvinit-init-diversity je instaliran. Ukloni SysV init pre build-a."
    exit 1
fi

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

echo "[2/5] Provera iso-work..."

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

# Stari linuxfs ostaje netaknut dok se novi ne napravi i proveri.
# Zamena se obavlja atomskim mv-om, bez dodatne kopije od ~1.7 GB.

# ------------------------------------------------------------
# Pravljenje novog linuxfs
# ------------------------------------------------------------

echo "[3/5] Pravim novi linuxfs iz root-mx25..."
echo
echo "Izvor:"
echo "  $ROOT"
echo
echo "Privremeni fajl:"
echo "  $LINUXFS_NEW"
echo

sudo rm -f "$LINUXFS_NEW"

# Do not ship repository indexes, package archives or generated APT caches.
# APT recreates them only when the Live user runs the first apt update.
echo "Uklanjam APT liste i cache pre pravljenja ISO-a..."
sudo find "$ROOT/var/lib/apt/lists" -mindepth 1 -maxdepth 1 -type f ! -name lock -delete
sudo find "$ROOT/var/lib/apt/lists/partial" -type f -delete 2>/dev/null || true
sudo find "$ROOT/var/cache/apt" -type f ! -path '*/archives/lock' -delete
sudo install -d -o _apt -g root -m 0700 \
    "$ROOT/var/lib/apt/lists/partial" \
    "$ROOT/var/lib/apt/lists/auxfiles" \
    "$ROOT/var/cache/apt/archives/partial"

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

# Veličina linuxfs-a se samo beleži; ne postavlja se limit pre izrade ISO-a.
LINUXFS_SIZE="$(stat -c %s "$LINUXFS_NEW")"
echo "Veličina linuxfs: $(numfmt --to=iec-i --suffix=B "$LINUXFS_SIZE")"

echo
echo "SquashFS napravljen:"
ls -lh "$LINUXFS_NEW"

echo

# ------------------------------------------------------------
# Zamena linuxfs u ISO stagingu
# ------------------------------------------------------------

echo "Atomski zamenjujem linuxfs u iso-work..."

sudo mv -f \
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

printf 'diya Linux v2.0 %s %s %s %s\n' \
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

echo "[4/5] Osvežavam MD5..."

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

rm -f "$ISO_NEW" "$ISO_MD5_NEW"

# initrd-base.gz is an update_kernel.sh template, not a Live boot asset.
xorriso -as mkisofs \
    -o "$ISO_NEW" \
    -m 'initrd-base.gz' \
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

echo "[5/5] Pravim MD5 za ISO..."

ISO_MD5_SUM="$(md5sum "$ISO_NEW" | awk '{print $1}')"
printf '%s  %s\n' "$ISO_MD5_SUM" "$ISO_OUT" > "$ISO_MD5_NEW"

# Replace the previous ISO only after xorriso and checksum both succeed.
mv -f "$ISO_NEW" "$ISO_OUT"
mv -f "$ISO_MD5_NEW" "$ISO_MD5"

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