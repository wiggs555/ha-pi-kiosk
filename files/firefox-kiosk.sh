#!/bin/bash
# Launch Firefox against Home Assistant in a loop (no --kiosk: that blocks OSK).
set -eu

CONFIG=/etc/ha-pi-kiosk/config.env
if [ -f "$CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi

KIOSK_URL="${KIOSK_URL:-https://home.whigham.me/?kiosk}"
PROFILE_DIR="${HOME}/.mozilla/firefox/ha-kiosk"
export MOZ_ENABLE_WAYLAND=1

FIREFOX_BIN=""
for candidate in firefox firefox-esr; do
  if command -v "$candidate" >/dev/null 2>&1; then
    FIREFOX_BIN="$(command -v "$candidate")"
    break
  fi
done

if [ -z "$FIREFOX_BIN" ]; then
  echo "ha-pi-kiosk: firefox not found" >&2
  exit 1
fi

mkdir -p "$PROFILE_DIR/chrome"

# Ensure profile prefs exist (idempotent)
if [ ! -f "$PROFILE_DIR/user.js" ]; then
  cat >"$PROFILE_DIR/user.js" <<'EOF'
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.max_resumed_crashes", 0);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("app.update.enabled", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("dom.disable_open_during_load", false);
EOF
fi

if [ ! -f "$PROFILE_DIR/chrome/userChrome.css" ]; then
  cat >"$PROFILE_DIR/chrome/userChrome.css" <<'EOF'
/* Hide browser chrome so the panel looks like a dedicated wall display. */
#TabsToolbar,
#nav-bar,
#PersonalToolbar,
#titlebar,
#navigator-toolbox {
  visibility: collapse !important;
}
EOF
fi

while true; do
  "$FIREFOX_BIN" \
    --profile "$PROFILE_DIR" \
    --new-instance \
    --width 800 \
    --height 480 \
    "$KIOSK_URL" || true
  sleep 2
done
