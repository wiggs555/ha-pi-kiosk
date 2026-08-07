#!/bin/bash
# ha-pi-kiosk — configure Raspberry Pi OS Lite as a Home Assistant wall panel
# Run on the Pi as a sudo-capable user:  ./setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="${SCRIPT_DIR}/files"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[[ "$(id -u)" -ne 0 ]] || die "run as a normal user with sudo (not as root)"
command -v sudo >/dev/null || die "sudo is required"

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/config.env"
elif [[ -f "${SCRIPT_DIR}/config.env.example" ]]; then
  info "No config.env found; using config.env.example defaults"
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/config.env.example"
fi

KIOSK_URL="${KIOSK_URL:-https://home.whigham.me/?kiosk}"
DISPLAY_OUTPUT="${DISPLAY_OUTPUT:-DSI-1}"
DISPLAY_ROTATION="${DISPLAY_ROTATION:-normal}"
KIOSK_USER="${KIOSK_USER:-$USER}"

id "$KIOSK_USER" >/dev/null 2>&1 || die "user '$KIOSK_USER' does not exist"
KIOSK_UID="$(id -u "$KIOSK_USER")"
KIOSK_HOME="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"
[[ -n "$KIOSK_HOME" && -d "$KIOSK_HOME" ]] || die "home directory for $KIOSK_USER not found"

info "Kiosk user: $KIOSK_USER (uid $KIOSK_UID)"
info "URL: $KIOSK_URL"
info "Display: $DISPLAY_OUTPUT rotation=$DISPLAY_ROTATION"

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------
info "Updating apt and installing packages"
sudo apt-get update -y

FIREFOX_PKG="firefox"
if ! apt-cache show firefox >/dev/null 2>&1; then
  FIREFOX_PKG="firefox-esr"
fi

PACKAGES=(
  labwc
  seatd
  wlr-randr
  squeekboard
  "$FIREFOX_PKG"
  fonts-liberation
  fonts-noto-core
  rpi-connect
)

if apt-cache show rpi-connect-wayvnc >/dev/null 2>&1; then
  PACKAGES+=(rpi-connect-wayvnc)
fi

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}"

# ---------------------------------------------------------------------------
# Persist runtime config
# ---------------------------------------------------------------------------
info "Installing /etc/ha-pi-kiosk/config.env"
sudo mkdir -p /etc/ha-pi-kiosk /usr/local/share/ha-pi-kiosk
sudo tee /etc/ha-pi-kiosk/config.env >/dev/null <<EOF
KIOSK_URL=${KIOSK_URL}
DISPLAY_OUTPUT=${DISPLAY_OUTPUT}
DISPLAY_ROTATION=${DISPLAY_ROTATION}
KIOSK_USER=${KIOSK_USER}
EOF
sudo chmod 644 /etc/ha-pi-kiosk/config.env

if [[ -f "${SCRIPT_DIR}/README.md" ]]; then
  sudo install -m 644 "${SCRIPT_DIR}/README.md" /usr/local/share/ha-pi-kiosk/README.md
fi

# ---------------------------------------------------------------------------
# SSH
# ---------------------------------------------------------------------------
info "Ensuring SSH is enabled"
if systemctl list-unit-files ssh.service >/dev/null 2>&1; then
  sudo systemctl enable --now ssh
elif systemctl list-unit-files sshd.service >/dev/null 2>&1; then
  sudo systemctl enable --now sshd
fi

# Wait for network at boot so Home Assistant can load
if command -v raspi-config >/dev/null 2>&1; then
  sudo raspi-config nonint do_boot_wait 0 || true
fi

# ---------------------------------------------------------------------------
# seatd + groups
# ---------------------------------------------------------------------------
info "Enabling seatd"
sudo systemctl enable --now seatd

for grp in video render input seat; do
  if getent group "$grp" >/dev/null 2>&1; then
    sudo usermod -aG "$grp" "$KIOSK_USER" || true
  fi
done

# ---------------------------------------------------------------------------
# labwc + Firefox kiosk files
# ---------------------------------------------------------------------------
info "Installing labwc config for $KIOSK_USER"
sudo -u "$KIOSK_USER" mkdir -p "${KIOSK_HOME}/.config/labwc"
sudo install -o "$KIOSK_USER" -g "$KIOSK_USER" -m 644 \
  "${FILES_DIR}/labwc/rc.xml" "${KIOSK_HOME}/.config/labwc/rc.xml"
sudo install -o "$KIOSK_USER" -g "$KIOSK_USER" -m 644 \
  "${FILES_DIR}/labwc/environment" "${KIOSK_HOME}/.config/labwc/environment"
sudo install -o "$KIOSK_USER" -g "$KIOSK_USER" -m 755 \
  "${FILES_DIR}/labwc/autostart" "${KIOSK_HOME}/.config/labwc/autostart"

info "Installing firefox-kiosk launcher"
sudo install -m 755 "${FILES_DIR}/firefox-kiosk.sh" /usr/local/bin/firefox-kiosk.sh

info "Seeding Firefox kiosk profile"
PROFILE_DIR="${KIOSK_HOME}/.mozilla/firefox/ha-kiosk"
sudo -u "$KIOSK_USER" mkdir -p "${PROFILE_DIR}/chrome"
sudo install -o "$KIOSK_USER" -g "$KIOSK_USER" -m 644 \
  "${FILES_DIR}/firefox-profile/user.js" "${PROFILE_DIR}/user.js"
sudo install -o "$KIOSK_USER" -g "$KIOSK_USER" -m 644 \
  "${FILES_DIR}/firefox-profile/chrome/userChrome.css" \
  "${PROFILE_DIR}/chrome/userChrome.css"

# ---------------------------------------------------------------------------
# Autologin on tty1 → start labwc from shell profile
# ---------------------------------------------------------------------------
info "Configuring tty1 autologin for $KIOSK_USER"

# Remove any previous mask from an older setup attempt
sudo systemctl unmask getty@tty1.service 2>/dev/null || true

sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
TMP_GETTY="$(mktemp)"
sed "s/__KIOSK_USER__/${KIOSK_USER}/g" \
  "${FILES_DIR}/getty-autologin.conf" >"$TMP_GETTY"
sudo install -m 644 "$TMP_GETTY" \
  /etc/systemd/system/getty@tty1.service.d/autologin.conf
rm -f "$TMP_GETTY"

# Optional systemd unit kept disabled — profile-based start is the primary path
if [[ -f "${FILES_DIR}/ha-kiosk-session.service" ]]; then
  TMP_UNIT="$(mktemp)"
  sed \
    -e "s/__KIOSK_USER__/${KIOSK_USER}/g" \
    -e "s/__KIOSK_UID__/${KIOSK_UID}/g" \
    "${FILES_DIR}/ha-kiosk-session.service" >"$TMP_UNIT"
  sudo install -m 644 "$TMP_UNIT" /etc/systemd/system/ha-kiosk-session.service
  rm -f "$TMP_UNIT"
  sudo systemctl disable ha-kiosk-session.service 2>/dev/null || true
fi

MARKER="# >>> ha-pi-kiosk >>>"
END_MARKER="# <<< ha-pi-kiosk <<<"
PROFILE="${KIOSK_HOME}/.bash_profile"
if [[ ! -f "$PROFILE" ]]; then
  sudo -u "$KIOSK_USER" touch "$PROFILE"
fi

# Idempotent: replace any previous block
if grep -q "$MARKER" "$PROFILE" 2>/dev/null; then
  info "Updating ha-pi-kiosk block in $PROFILE"
  TMP_PROFILE="$(mktemp)"
  sudo awk -v m="$MARKER" -v e="$END_MARKER" '
    $0 == m {skip=1; next}
    $0 == e {skip=0; next}
    !skip {print}
  ' "$PROFILE" >"$TMP_PROFILE"
  sudo install -o "$KIOSK_USER" -g "$KIOSK_USER" -m 644 "$TMP_PROFILE" "$PROFILE"
  rm -f "$TMP_PROFILE"
fi

{
  echo "$MARKER"
  cat "${FILES_DIR}/bash_profile_snippet.sh"
  echo "$END_MARKER"
} | sudo tee -a "$PROFILE" >/dev/null
sudo chown "$KIOSK_USER:$KIOSK_USER" "$PROFILE"

# Ensure non-bash login shells still pick up the kiosk start
PROFILE_DOT="${KIOSK_HOME}/.profile"
sudo -u "$KIOSK_USER" touch "$PROFILE_DOT"
if ! grep -q 'ha-pi-kiosk: ensure bash_profile' "$PROFILE_DOT" 2>/dev/null; then
  {
    echo ''
    echo '# ha-pi-kiosk: ensure bash_profile runs for login shells'
    echo '[ -f "$HOME/.bash_profile" ] && . "$HOME/.bash_profile"'
  } | sudo tee -a "$PROFILE_DOT" >/dev/null
  sudo chown "$KIOSK_USER:$KIOSK_USER" "$PROFILE_DOT"
fi

sudo systemctl daemon-reload
sudo systemctl enable getty@tty1.service

# ---------------------------------------------------------------------------
# Boot splash / console orientation for official 7" panel
# ---------------------------------------------------------------------------
map_orientation() {
  case "$1" in
    normal|"") echo "normal" ;;
    90) echo "left_side_up" ;;
    180) echo "upside_down" ;;
    270) echo "right_side_up" ;;
    *) echo "" ;;
  esac
}

ORIENTATION="$(map_orientation "$DISPLAY_ROTATION")"
CMDLINE=""
for candidate in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
  if [[ -f "$candidate" ]]; then
    CMDLINE="$candidate"
    break
  fi
done

if [[ -n "$CMDLINE" && -n "$ORIENTATION" && "$ORIENTATION" != "normal" ]]; then
  info "Setting panel orientation in $CMDLINE ($ORIENTATION)"
  CURRENT="$(tr -d '\n' <"$CMDLINE")"
  STRIPPED="$(echo "$CURRENT" | sed -E 's/ *video=DSI-[0-9]:panel_orientation=[^ ]*//g')"
  NEW="${STRIPPED} video=${DISPLAY_OUTPUT}:panel_orientation=${ORIENTATION}"
  echo "$NEW" | sudo tee "$CMDLINE" >/dev/null
elif [[ -n "$CMDLINE" && "$ORIENTATION" == "normal" ]]; then
  CURRENT="$(tr -d '\n' <"$CMDLINE")"
  if echo "$CURRENT" | grep -q 'panel_orientation='; then
    info "Clearing panel_orientation from $CMDLINE"
    STRIPPED="$(echo "$CURRENT" | sed -E 's/ *video=DSI-[0-9]:panel_orientation=[^ ]*//g')"
    echo "$STRIPPED" | sudo tee "$CMDLINE" >/dev/null
  fi
fi

# ---------------------------------------------------------------------------
# Raspberry Pi Connect
# ---------------------------------------------------------------------------
info "Enabling Raspberry Pi Connect"
sudo loginctl enable-linger "$KIOSK_USER" 2>/dev/null || true

if command -v rpi-connect >/dev/null 2>&1; then
  # Best-effort enable; full sign-in must be done interactively after reboot
  sudo -u "$KIOSK_USER" \
    XDG_RUNTIME_DIR="/run/user/${KIOSK_UID}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${KIOSK_UID}/bus" \
    rpi-connect on 2>/dev/null || true
fi

for unit in rpi-connect.service rpi-connect-wayvnc.service; do
  if systemctl --global list-unit-files "$unit" >/dev/null 2>&1; then
    sudo systemctl --global enable "$unit" 2>/dev/null || true
  fi
done

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
cat <<EOF

------------------------------------------------------------------
ha-pi-kiosk setup complete

  URL:      ${KIOSK_URL}
  User:     ${KIOSK_USER}
  Display:  ${DISPLAY_OUTPUT} (${DISPLAY_ROTATION})
  Browser:  ${FIREFOX_PKG} (maximized, undecorated)
  OSK:      squeekboard

Next steps:
  1. Ensure HACS "Kiosk Mode" is installed on Home Assistant so ?kiosk works.
  2. Reboot:
       sudo reboot
  3. Pair Raspberry Pi Connect (one-time), as ${KIOSK_USER} over SSH:
       rpi-connect signin
     Open the printed URL and approve with your Raspberry Pi ID account.
  4. Sign into Home Assistant on the panel (squeekboard) or via Connect screen share.

To change the URL or rotation later, edit /etc/ha-pi-kiosk/config.env and reboot
(rotation also updates on the next labwc autostart).
------------------------------------------------------------------
EOF

read -r -p "Reboot now? [y/N] " reply || true
case "${reply:-}" in
  y|Y|yes|YES)
    sudo reboot
    ;;
  *)
    info "Skipping reboot. Reboot when ready: sudo reboot"
    ;;
esac
