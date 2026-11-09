# Home Assistant Pi Kiosk

Lightweight setup script that turns a **Raspberry Pi 4 (2GB)** running **Raspberry Pi OS Lite (64-bit)** into a wall panel for Home Assistant on the **official 7″ Touch Display**.

On boot the Pi shows the logo from `images/logo.png`, auto-logs in, starts a minimal **labwc** Wayland session, launches **Firefox** to your HA dashboard (with HA Kiosk Mode), and runs **squeekboard** for on-screen text input. **SSH** and **Raspberry Pi Connect** stay available for remote access.

## What you get

| Layer | Role |
|--------|------|
| HA `?kiosk` URL | Hides HA sidebar/header (requires HACS [Kiosk Mode](https://github.com/NemesisRE/kiosk-mode) on the server) |
| Firefox maximized | Fullscreen look without compositor `--kiosk` (so the OSK still works) |
| squeekboard | On-screen keyboard when a text field is focused |
| Idle backlight | Dim after 2 min, off after 5 min; touch wakes (wake tap swallowed) |
| Boot splash | `images/logo.png`, centered, until labwc starts |
| SSH | Enabled for shell access |
| Raspberry Pi Connect | Installed; you sign in once for remote shell/screen |

Default URL: `https://home.whigham.me/?kiosk`

## Prerequisites

1. **Home Assistant** — Install HACS **Kiosk Mode** ([NemesisRE/kiosk-mode](https://github.com/NemesisRE/kiosk-mode)) on `home.whigham.me` so `?kiosk` hides chrome.
2. **Flash the SD card** with Raspberry Pi Imager:
   - OS: **Raspberry Pi OS Lite (64-bit)** (Bookworm or newer)
   - Set hostname, username/password, Wi‑Fi if needed
   - **Enable SSH**
3. Attach the **official Raspberry Pi 7″ Touch Display** (DSI) to the Pi 4 and boot.
4. SSH in from your Mac: `ssh <user>@<hostname>.local`

## Install

Copy this repo to the Pi (or clone it), then:

```bash
cd ha-pi-kiosk
cp config.env.example config.env   # optional overrides
./setup.sh
```

`setup.sh` is idempotent — safe to re-run after editing `config.env`.

### Config (`config.env`)

```bash
KIOSK_URL=https://home.whigham.me/?kiosk
DISPLAY_OUTPUT=DSI-1
DISPLAY_ROTATION=normal    # normal | 90 | 180 | 270
KIOSK_USER=                # defaults to the user running setup.sh

# Backlight idle (sysfs; official 7" DSI)
IDLE_ENABLED=1
IDLE_DIM_SEC=120           # dim after 2 minutes
IDLE_OFF_SEC=300           # backlight off after 5 minutes
IDLE_DIM_PERCENT=20
```

Use a specific dashboard if you want, for example:

```bash
KIOSK_URL=https://home.whigham.me/lovelace/home?kiosk
```

After setup, the live copy lives at `/etc/ha-pi-kiosk/config.env`. Edit that and reboot to apply URL/rotation/idle changes.

### Display idle / wake

`swayidle` watches for touch/keyboard/mouse activity:

1. After `IDLE_DIM_SEC` — backlight dims to `IDLE_DIM_PERCENT`
2. After `IDLE_OFF_SEC` — backlight fully off, and a black `swaylock` overlay starts so the wake touch does not click into Home Assistant
3. On any input — backlight restores and the lock is dismissed

Set `IDLE_ENABLED=0` to disable. Test manually:

```bash
backlight-control.sh status
backlight-control.sh dim
backlight-control.sh off
backlight-control.sh on
```

### Display rotation

The official 7″ panel is landscape 800×480. If your mount needs a different orientation, set `DISPLAY_ROTATION` to `90`, `180`, or `270`. The script:

- Applies rotation in labwc via `wlr-randr` on session start
- Adds `video=DSI-1:panel_orientation=...` to `/boot/firmware/cmdline.txt` for console/splash alignment

### Boot splash

Boot shows `images/logo.png` centered on a black background. Plymouth scales the square logo to fit the 800×480 panel without stretching it. The frame stays up until labwc takes the display, and the same logo is shown on shutdown.

`setup.sh` installs the `ha-pi-kiosk` Plymouth theme, rebuilds the initramfs, and sets:

- `quiet splash plymouth.ignore-serial-consoles logo.nologo vt.global_cursor_default=0` on `cmdline.txt`
- `disable_splash=1` in `config.txt` (skips the rainbow square)
- tty1 autologin uses `agetty --skip-login --noissue` and does not clear the VT, so the `login:` banner is not drawn over the logo
- `~/.hushlogin` suppresses the "Last login" line and MOTD before labwc starts

Reboot after `./setup.sh` to see it. After replacing `images/logo.png`, re-run `./setup.sh` so the new image is copied into the initramfs.

## After setup

1. Reboot when prompted (or `sudo reboot`).
2. Pair **Raspberry Pi Connect** (one-time), over SSH as the kiosk user:

   ```bash
   rpi-connect signin
   ```

   Open the URL it prints and approve with your Raspberry Pi ID account.

3. Sign into Home Assistant on the panel (squeekboard appears when you focus username/password fields), or use Connect screen share.

## How boot works

```
firmware (rainbow disabled)
  → Plymouth (images/logo.png, frame kept)
    → getty@tty1 autologin
      → ~/.bash_profile starts labwc
        → labwc autostart
          → squeekboard
          → display-idle.sh (swayidle dim/off/wake)
          → firefox-kiosk.sh → https://home.whigham.me/?kiosk
```

Firefox uses a dedicated profile (`~/.mozilla/firefox/ha-kiosk`) with browser chrome hidden via `userChrome.css`. labwc maximizes the window with decorations off — it looks fullscreen but does **not** use true compositor fullscreen, which would block the on-screen keyboard.

## Files

```
setup.sh                 # installer (run on the Pi)
config.env.example       # defaults / template
images/logo.png          # boot splash artwork
files/
  labwc/autostart        # OSK + idle + browser + rotation
  labwc/rc.xml           # maximize Firefox, no decorations
  labwc/environment      # Wayland env
  firefox-kiosk.sh       # Firefox restart loop
  firefox-profile/       # prefs + userChrome.css
  backlight-control.sh   # sysfs backlight dim/off/on
  display-idle.sh        # swayidle wrapper
  idle-off.sh / idle-wake.sh
  udev/                  # video-group write access to backlight
  getty-autologin.conf   # tty1 autologin drop-in
  bash_profile_snippet.sh
  ha-kiosk-session.service  # optional alternate unit (disabled by default)
  plymouth/              # boot logo theme and retain-splash drop-in
```

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| Black screen after boot | SSH in; `journalctl -b`, check `labwc` / groups (`video`, `input`, `seat`). Confirm seatd: `systemctl status seatd`. |
| Wrong orientation | Set `DISPLAY_ROTATION` in `/etc/ha-pi-kiosk/config.env`, re-run `./setup.sh` or edit and reboot. |
| HA chrome still visible | Confirm HACS Kiosk Mode on the server; URL must include `?kiosk`; hard-refresh or clear Firefox profile cache. |
| OSK never appears | Do not use Chromium `--kiosk` / compositor fullscreen. Confirm `squeekboard` is running: `pgrep -a squeekboard`. |
| Connect not paired | `rpi-connect signin` as the kiosk user after a graphical session is up. |
| Change URL | Edit `/etc/ha-pi-kiosk/config.env`, then reboot (or kill/restart Firefox). |
| Screen never dims/off | Check `pgrep -a swayidle`, `backlight-control.sh status`, and that the user is in group `video`. |
| Wake touch still clicks HA | Confirm `swaylock` is installed; off-path should start it (`idle-off.sh`). |
| Boot log still scrolls | Confirm `quiet splash` is in `/boot/firmware/cmdline.txt`, `plymouth-set-default-theme` prints `ha-pi-kiosk`, and `disable_splash=1` is in `/boot/firmware/config.txt`. Re-run `./setup.sh` and reboot. |
| Login text after the logo | Re-run `./setup.sh` so `getty@tty1` uses `--skip-login --noissue`, `~/.hushlogin` exists, and `/etc/profile.d/00-ha-pi-kiosk.sh` is installed. Then reboot. |

## Out of scope

- Building a custom SD image
- Running Home Assistant *on* this Pi
- Automating Raspberry Pi ID login for Connect
