#!/bin/bash
# Resume from idle: restore backlight and dismiss swaylock.
set -euo pipefail

/usr/local/bin/backlight-control.sh on || true

if command -v swaylock >/dev/null 2>&1; then
  pkill -x -SIGUSR1 swaylock 2>/dev/null || true
  sleep 0.2
  pkill -x swaylock 2>/dev/null || true
fi
