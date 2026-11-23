#!/usr/bin/env bash
set -Eeuo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$BASE/root-mx25"

PACKAGES=(
    kdeconnect
    vlc
    mpv
    firmware-amd-graphics
    firmware-intel-graphics
    firmware-nvidia-graphics
    ca-certificates
    gnupg
    pinentry-curses
)

# Upgrade MX's driver manager and installed DKMS sources before the kernel.
DRIVER_PACKAGES=(
    ddm-mx
    broadcom-sta-dkms
)

KERNEL_PACKAGES=(
    linux-image-liquorix-amd64
    linux-headers-liquorix-amd64
)

MOUNTS=()
RESOLV_TARGET="$ROOT/etc/resolv.conf"
RESOLV_BACKUP=""
RESOLV_MODE="none"
NODE_TMP=""
RESOLV_LINK=""

cleanup() {
    local i
    set +e

    for ((i=${#MOUNTS[@]}-1; i>=0; i--)); do
        sudo umount -R "${MOUNTS[$i]}" 2>/dev/null || true
    done

    case "$RESOLV_MODE" in
        symlink)
            sudo rm -f "$RESOLV_TARGET"
            sudo ln -s "$RESOLV_LINK" "$RESOLV_TARGET"
            ;;
        file)
            sudo cp -a "$RESOLV_BACKUP" "$RESOLV_TARGET"
            ;;
        created)
            sudo rm -f "$RESOLV_TARGET"
            ;;
    esac

    [ -z "$RESOLV_BACKUP" ] || sudo rm -f "$RESOLV_BACKUP"
    [ -z "$NODE_TMP" ] || rm -rf "$NODE_TMP"
}
trap cleanup EXIT INT TERM

if [[ "$ROOT" == "/" || ! -d "$ROOT" ]]; then
    echo "ERROR: root-mx25/ nije pronađen."
    echo "Prvo pokreni: ./setup_root.sh"
    exit 1
fi

if [[ ! -x "$ROOT/usr/bin/apt-get" ]]; then
    echo "ERROR: apt-get nije pronađen u root-mx25/."
    exit 1
fi

if [[ ! -d "$ROOT/etc" ]]; then
    echo "ERROR: root-mx25/etc ne postoji."
    exit 1
fi

echo
echo "=========================================="
echo " diya Linux dodatni desktop/audio alati"
echo "=========================================="
echo
echo "Instaliram u root-mx25/:"
echo "MX driver alati i DKMS:"
printf '  %s\n' "${DRIVER_PACKAGES[@]}"
echo "Desktop/audio i firmware:"
printf '  %s\n' "${PACKAGES[@]}"
echo "MX AHS kernel i headeri:"
printf '  %s\n' "${KERNEL_PACKAGES[@]}"
echo

# Chroot koristi DNS konfiguraciju računara na kome se pravi ISO.
RESOLV_BACKUP="$(mktemp)"
if [[ -L "$RESOLV_TARGET" ]]; then
    RESOLV_LINK="$(readlink "$RESOLV_TARGET")"
    RESOLV_MODE="symlink"
    sudo rm -f "$RESOLV_TARGET"
    sudo install -m 0644 /etc/resolv.conf "$RESOLV_TARGET"
elif [[ -e "$RESOLV_TARGET" ]]; then
    RESOLV_MODE="file"
    sudo cp -a "$RESOLV_TARGET" "$RESOLV_BACKUP"
    sudo install -m 0644 /etc/resolv.conf "$RESOLV_TARGET"
else
    RESOLV_MODE="created"
    sudo install -m 0644 /etc/resolv.conf "$RESOLV_TARGET"
fi

for dir in dev proc sys; do
    sudo mount --rbind "/$dir" "$ROOT/$dir"
    MOUNTS+=("$ROOT/$dir")
    sudo mount --make-rslave "$ROOT/$dir"
done

# Remove the temporary upstream header fallback from the previous iteration.
sudo rm -f \
    "$ROOT/etc/apt/sources.list.d/liquorix-headers.sources" \
    "$ROOT/etc/apt/preferences.d/99-liquorix-low-priority" \
    "$ROOT/usr/share/keyrings/liquorix-archive-keyring.gpg"

echo "Osvežavam APT liste u ciljnom sistemu..."
sudo chroot "$ROOT" apt-get update

echo
echo "Prvo ažuriram MX DDM i postojeće DKMS drajvere..."
sudo chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y "${DRIVER_PACKAGES[@]}"

echo
echo "Instaliram desktop/audio pakete i firmware..."
sudo chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y "${PACKAGES[@]}"

echo
echo "Instaliram MX AHS kernel i odgovarajuće headere..."
sudo chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y "${KERNEL_PACKAGES[@]}"

# Keep only the kernel selected by the MX Liquorix metapackage. This leaves
# one unambiguous kernel for update_kernel.sh and matching headers for DDM.
KERNEL_DEPENDS="$(sudo chroot "$ROOT" dpkg-query -W -f='${Depends}' linux-image-liquorix-amd64)"
KERNEL_PACKAGE="$(grep -oE 'linux-image-[^ ,(]+' <<<"$KERNEL_DEPENDS" | head -n1)"
if [[ -z "$KERNEL_PACKAGE" ]]; then
    echo "ERROR: ne mogu da odredim kernel iz linux-image-liquorix-amd64."
    exit 1
fi
TARGET_KERNEL="${KERNEL_PACKAGE#linux-image-}"
echo
echo "Zadržavam MX Liquorix kernel: $TARGET_KERNEL"
shopt -s nullglob
for image in "$ROOT"/boot/vmlinuz-*; do
    old_kernel="${image##*/vmlinuz-}"
    [[ "$old_kernel" == "$TARGET_KERNEL" ]] && continue
    echo "Uklanjam zastareli kernel iz build stabla: $old_kernel"
    sudo chroot "$ROOT" apt-get purge -y "linux-image-$old_kernel"
done
shopt -u nullglob

echo
echo "Instaliram provereni Node.js 24.22.3 i Desktop Commander Remote..."
NODE_VERSION="24.22.3"
NODE_ARCHIVE="node-v${NODE_VERSION}-linux-x64.tar.xz"
NODE_TMP="$(mktemp -d)"
for tool in curl tar xz sha256sum grep; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: nedostaje alat za instalaciju Node.js: $tool"
        exit 1
    }
done
curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" \
    -o "$NODE_TMP/SHASUMS256.txt"
curl -fL --retry 3 \
    "https://nodejs.org/dist/v${NODE_VERSION}/$NODE_ARCHIVE" \
    -o "$NODE_TMP/$NODE_ARCHIVE"
grep -E "^[[:xdigit:]]{64}  $NODE_ARCHIVE$" \
    "$NODE_TMP/SHASUMS256.txt" > "$NODE_TMP/checksum"
if [[ ! -s "$NODE_TMP/checksum" ]]; then
    echo "ERROR: Node.js kontrolni zbir nije pronađen."
    exit 1
fi
(cd "$NODE_TMP" && sha256sum --check checksum)
sudo tar -xJf "$NODE_TMP/$NODE_ARCHIVE" \
    -C "$ROOT/usr/local" --strip-components=1 --no-same-owner

echo "Instaliram Desktop Commander Remote iz npm registra..."
sudo chroot "$ROOT" env HOME=/root PATH=/usr/local/bin:/usr/bin:/bin \
    /usr/local/bin/npm install --global --omit=dev --ignore-scripts --no-audit --no-fund \
    @wonderwhy-er/desktop-commander@0.3.4
sudo rm -rf "$ROOT/root/.npm"

# Desktop Commander PDF rendering uses its private cache or the installed
# system Chrome. The default Puppeteer cache under ~/.cache is not used.
# Do not ship a second Chromium when Google Chrome is already in the image.
if [[ -x "$ROOT/opt/google/chrome/chrome" ]]; then
    echo "Uklanjam nepotreban Puppeteer browser cache..."
    sudo rm -rf "$ROOT/root/.cache/puppeteer"
fi

echo "Dodajem komandu komander i systemd servis..."
sudo install -o root -g root -m 0755 \
    "$BASE/komander" "$ROOT/usr/local/bin/komander"
sudo install -o root -g root -m 0644 \
    "$BASE/komander.service" "$ROOT/etc/systemd/system/komander.service"
sudo install -d -m 0755 "$ROOT/etc/systemd/system/multi-user.target.wants"
sudo ln -sfn ../komander.service \
    "$ROOT/etc/systemd/system/multi-user.target.wants/komander.service"

echo "Provera Node.js i Desktop Commander instalacije..."
sudo chroot "$ROOT" /usr/local/bin/node --version
sudo chroot "$ROOT" /usr/local/bin/npm --version
sudo chroot "$ROOT" /usr/local/bin/desktop-commander remote --help
sudo chroot "$ROOT" /usr/local/bin/node \
    /usr/local/lib/node_modules/@wonderwhy-er/desktop-commander/dist/npm-scripts/verify-ripgrep.js
sudo chroot "$ROOT" dpkg-query -W ca-certificates gnupg pinentry-curses

echo
echo "Uklanjam profil monitora vezan za razvojni računar..."
sudo rm -f \
    "$ROOT/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/displays.xml" \
    "$ROOT/etc/skel/.config/xfce4/desktop/icons.screen0.yaml"

echo
echo "Podešavam automatsko pokretanje KDE Connect indikatora u XFCE..."
sudo install -d -m 0755 "$ROOT/etc/xdg/autostart"
sudo tee "$ROOT/etc/xdg/autostart/kdeconnect-indicator.desktop" >/dev/null <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=KDE Connect
Comment=Connect Android phones and tablets
Exec=kdeconnect-indicator
TryExec=kdeconnect-indicator
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOP

echo
echo
sudo install -d -m 0755 "$ROOT/var/log"
sudo install -o root -g root -m 0640 /dev/null "$ROOT/var/log/ddm.log"

echo "Uklanjam alternativni SysV init; diya Linux koristi isključivo systemd..."
sudo chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive \
    apt-get purge -y sysvinit-init-diversity

INIT_LINK="$(readlink "$ROOT/sbin/init" 2>/dev/null || true)"
if [[ "$INIT_LINK" != "../lib/systemd/systemd" ]]; then
    echo "ERROR: /sbin/init nije povezan sa systemd: $INIT_LINK"
    exit 1
fi

sudo chroot "$ROOT" apt-get clean

# The Live ISO must start without repository indexes or downloaded package
# archives. The first apt update in the running Live system rebuilds them.
echo "Uklanjam APT liste i sve APT cache fajlove iz Live sistema..."
sudo find "$ROOT/var/lib/apt/lists" -mindepth 1 -maxdepth 1 -type f ! -name lock -delete
sudo find "$ROOT/var/lib/apt/lists/partial" -type f -delete 2>/dev/null || true
sudo find "$ROOT/var/cache/apt" -type f ! -path '*/archives/lock' -delete
sudo install -d -o _apt -g root -m 0700 \
    "$ROOT/var/lib/apt/lists/partial" \
    "$ROOT/var/lib/apt/lists/auxfiles" \
    "$ROOT/var/cache/apt/archives/partial"

echo
echo "Provera instaliranih paketa:"
sudo chroot "$ROOT" dpkg-query -W -f='${binary:Package} ${Version} ${db:Status-Abbrev}\n' \
    kdeconnect vlc mpv ddm-mx \
    firmware-amd-graphics firmware-intel-graphics firmware-nvidia-graphics \
    broadcom-sta-dkms linux-image-liquorix-amd64 linux-headers-liquorix-amd64

echo
echo "Gotovo. root-mx25/ je pripremljen za build.sh."
echo "Sledeći korak: ./build.sh"
