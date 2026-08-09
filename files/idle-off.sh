#!/bin/bash
# Full idle-off: backlight off + black swaylock to absorb the wake touch.
set -euo pipefail

/usr/local/bin/backlight-control.sh off

if command -v swaylock >/dev/null 2>&1; then
  pkill -x swaylock 2>/dev/null || true
  # Prefer daemonize when available; otherwise background.
  if swaylock --help 2>&1 | grep -q -- '--daemonize'; then
    swaylock --daemonize --color 000000 || true
  else
    swaylock --color 000000 >/dev/null 2>&1 &
  fi
fi
true
