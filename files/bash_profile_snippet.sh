# ha-pi-kiosk — start labwc on tty1 after autologin
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
  case "$(tty 2>/dev/null || true)" in
    /dev/tty1)
      if command -v labwc >/dev/null 2>&1; then
        export MOZ_ENABLE_WAYLAND=1
        export XDG_SESSION_TYPE=wayland
        export XDG_CURRENT_DESKTOP=labwc:wlroots
        exec labwc -C "${HOME}/.config/labwc"
      fi
      ;;
  esac
fi
