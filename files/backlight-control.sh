#!/bin/bash
# Control the official DSI panel backlight via sysfs.
# Usage: backlight-control.sh {dim|off|on|status|path}
set -euo pipefail

CONFIG=/etc/ha-pi-kiosk/config.env
if [[ -f "$CONFIG" ]]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi

IDLE_DIM_PERCENT="${IDLE_DIM_PERCENT:-20}"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/ha-pi-kiosk"
STATE_FILE="${STATE_DIR}/brightness"
mkdir -p "$STATE_DIR"

find_backlight() {
  local d
  # Prefer the classic rpi_backlight name, then any sysfs backlight device.
  if [[ -d /sys/class/backlight/rpi_backlight ]]; then
    echo /sys/class/backlight/rpi_backlight
    return 0
  fi
  for d in /sys/class/backlight/*; do
    if [[ -d "$d" && -f "$d/brightness" && -f "$d/max_brightness" ]]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

BACKLIGHT_DIR="$(find_backlight || true)"
if [[ -z "${BACKLIGHT_DIR}" ]]; then
  echo "ha-pi-kiosk: no backlight device found under /sys/class/backlight" >&2
  exit 1
fi

BRIGHTNESS_FILE="${BACKLIGHT_DIR}/brightness"
MAX_FILE="${BACKLIGHT_DIR}/max_brightness"
BL_POWER_FILE="${BACKLIGHT_DIR}/bl_power"

read_max() { cat "$MAX_FILE"; }
read_cur() { cat "$BRIGHTNESS_FILE"; }

write_brightness() {
  local value="$1"
  if [[ -w "$BRIGHTNESS_FILE" ]]; then
    echo "$value" >"$BRIGHTNESS_FILE"
  else
    # Fallback when udev perms are not yet applied
    echo "$value" | sudo tee "$BRIGHTNESS_FILE" >/dev/null
  fi
}

set_bl_power_on() {
  if [[ -f "$BL_POWER_FILE" ]]; then
    if [[ -w "$BL_POWER_FILE" ]]; then
      echo 0 >"$BL_POWER_FILE" || true
    else
      echo 0 | sudo tee "$BL_POWER_FILE" >/dev/null 2>&1 || true
    fi
  fi
}

set_bl_power_off() {
  if [[ -f "$BL_POWER_FILE" ]]; then
    if [[ -w "$BL_POWER_FILE" ]]; then
      echo 1 >"$BL_POWER_FILE" || true
    else
      echo 1 | sudo tee "$BL_POWER_FILE" >/dev/null 2>&1 || true
    fi
  fi
}

save_if_needed() {
  local cur
  cur="$(read_cur)"
  # Only remember a "real" brightness so dim/off don't overwrite the restore target.
  if [[ "$cur" -gt 0 ]]; then
    echo "$cur" >"$STATE_FILE"
  elif [[ ! -f "$STATE_FILE" ]]; then
    echo "$(read_max)" >"$STATE_FILE"
  fi
}

cmd_dim() {
  local max target
  max="$(read_max)"
  target=$((max * IDLE_DIM_PERCENT / 100))
  if [[ "$target" -lt 1 ]]; then
    target=1
  fi
  save_if_needed
  set_bl_power_on
  write_brightness "$target"
}

cmd_off() {
  save_if_needed
  write_brightness 0
  set_bl_power_off
}

cmd_on() {
  local restore max
  max="$(read_max)"
  if [[ -f "$STATE_FILE" ]]; then
    restore="$(cat "$STATE_FILE")"
  else
    restore="$max"
  fi
  if [[ "$restore" -lt 1 ]]; then
    restore="$max"
  fi
  if [[ "$restore" -gt "$max" ]]; then
    restore="$max"
  fi
  set_bl_power_on
  write_brightness "$restore"
}

cmd_status() {
  echo "path=${BACKLIGHT_DIR}"
  echo "brightness=$(read_cur)/$(read_max)"
  if [[ -f "$STATE_FILE" ]]; then
    echo "saved=$(cat "$STATE_FILE")"
  fi
}

case "${1:-}" in
  dim) cmd_dim ;;
  off) cmd_off ;;
  on) cmd_on ;;
  status) cmd_status ;;
  path) echo "$BACKLIGHT_DIR" ;;
  *)
    echo "usage: $0 {dim|off|on|status|path}" >&2
    exit 2
    ;;
esac
