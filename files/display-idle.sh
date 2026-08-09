#!/bin/bash
# Idle dim → off for the DSI panel; wake on touch/input.
# Uses swayidle + sysfs backlight. On full-off, swaylock swallows the wake
# touch so it does not click through into Home Assistant.
set -euo pipefail

CONFIG=/etc/ha-pi-kiosk/config.env
if [[ -f "$CONFIG" ]]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi

IDLE_ENABLED="${IDLE_ENABLED:-1}"
IDLE_DIM_SEC="${IDLE_DIM_SEC:-120}"
IDLE_OFF_SEC="${IDLE_OFF_SEC:-300}"

if [[ "$IDLE_ENABLED" != "1" && "$IDLE_ENABLED" != "true" && "$IDLE_ENABLED" != "yes" ]]; then
  echo "ha-pi-kiosk: display idle disabled"
  exit 0
fi

command -v swayidle >/dev/null 2>&1 || {
  echo "ha-pi-kiosk: swayidle not installed" >&2
  exit 1
}
command -v backlight-control.sh >/dev/null 2>&1 || {
  echo "ha-pi-kiosk: backlight-control.sh not on PATH" >&2
  exit 1
}

case "$IDLE_DIM_SEC" in *[!0-9]*|"") IDLE_DIM_SEC=120 ;; esac
case "$IDLE_OFF_SEC" in *[!0-9]*|"") IDLE_OFF_SEC=300 ;; esac

if [[ "$IDLE_OFF_SEC" -le "$IDLE_DIM_SEC" ]]; then
  IDLE_OFF_SEC=$((IDLE_DIM_SEC + 60))
fi

BACKLIGHT_BIN="$(command -v backlight-control.sh)"
OFF_HELPER=/usr/local/lib/ha-pi-kiosk/idle-off.sh
WAKE_HELPER=/usr/local/lib/ha-pi-kiosk/idle-wake.sh

pkill -x swayidle 2>/dev/null || true
# pkill exit status must not abort under set -e
true

exec swayidle -w \
  timeout "$IDLE_DIM_SEC" "${BACKLIGHT_BIN} dim" \
  timeout "$IDLE_OFF_SEC" "${OFF_HELPER}" \
  resume "${WAKE_HELPER}"
