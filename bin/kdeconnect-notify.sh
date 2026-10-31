#!/bin/bash
# Mirrors phone notifications onto this desktop.
#
# kdeconnectd does NOT show them itself: its notifications plugin registers each
# phone notification as a D-Bus object and emits `notificationPosted`, and
# rendering them is the Plasma applet's job (plugins/notifications/
# notificationsplugin.cpp in kdeconnect-kde). There is no applet on Hyprland, so
# without this every mirrored notification is invisible — the packets arrive,
# the objects exist, and nothing draws them.
#
# Posts through org.freedesktop.Notifications, which is webb-shell's own server,
# and closes on the phone's dismissal. Runs until killed; the shell keeps it
# alive only while kdeconnect is installed.
set -uo pipefail

BUS="org.kde.kdeconnect.daemon"
PLUGIN_IFACE="org.kde.kdeconnect.device.notifications"
NOTIF_IFACE="org.kde.kdeconnect.device.notifications.notification"
APP="KDE Connect"

for bin in busctl gdbus jq; do
  command -v "$bin" >/dev/null || exit 0
done

prop() {
  busctl --user get-property "$BUS" "$1" "$NOTIF_IFACE" "$2" 2>/dev/null \
    | sed -e 's/^[a-z] //' -e 's/^"//' -e 's/"$//' -e 's/\\"/"/g'
}

declare -A posted

notify_post() {
  local path="$1" app title body icon summary out id
  app="$(prop "$path" appName)"
  title="$(prop "$path" title)"
  body="$(prop "$path" text)"
  [ -z "$body" ] && body="$(prop "$path" ticker)"
  icon="$(prop "$path" iconPath)"

  summary="${title:-${app:-Phone}}"
  [ -n "$icon" ] && [ ! -e "$icon" ] && icon=""

  out="$(gdbus call --session \
           --dest org.freedesktop.Notifications \
           --object-path /org/freedesktop/Notifications \
           --method org.freedesktop.Notifications.Notify \
           "${app:-$APP}" 0 "${icon:-phone}" "$summary" "$body" "[]" "{}" 8000 2>/dev/null)"
  id="$(printf '%s' "$out" | sed -n 's/.*uint32 \([0-9][0-9]*\).*/\1/p')"
  if [ -n "$id" ]; then
    if [ -n "${posted[$path]:-}" ]; then
      gdbus call --session --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.CloseNotification \
        "${posted[$path]}" >/dev/null 2>&1
    fi
    posted[$path]="$id"
  fi
}

notify_close() {
  local path="$1"
  [ -n "${posted[$path]:-}" ] || return 0
  gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.CloseNotification \
    "${posted[$path]}" >/dev/null 2>&1
  unset 'posted[$path]'
}

busctl --user monitor --json=short --match "type='signal',interface='$PLUGIN_IFACE'" "$BUS" 2>/dev/null |
while read -r line; do
  member="$(printf '%s' "$line" | jq -r '.member // empty' 2>/dev/null)"
  path="$(printf '%s' "$line" | jq -r '.path // empty' 2>/dev/null)"
  [ -n "$member" ] && [ -n "$path" ] || continue

  case "$member" in
    notificationPosted)
      publicId="$(printf '%s' "$line" | jq -r '.payload.data[0] // empty' 2>/dev/null)"
      [ -n "$publicId" ] && notify_post "$path/$publicId"
      ;;
    notificationRemoved)
      publicId="$(printf '%s' "$line" | jq -r '.payload.data[0] // empty' 2>/dev/null)"
      [ -n "$publicId" ] && notify_close "$path/$publicId"
      ;;
    allNotificationsRemoved)
      for key in "${!posted[@]}"; do notify_close "$key"; done
      ;;
  esac
done
