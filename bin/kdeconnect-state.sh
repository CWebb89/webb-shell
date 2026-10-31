#!/bin/bash
# KDE Connect state as JSON, for the shell's phone module.
#
#   {"running":true,"devices":[{"id":"…","name":"Galaxy S24 Ultra","type":"phone",
#                               "reachable":true,"paired":true,
#                               "hasBattery":true,"charge":96,"charging":false,
#                               "network":"LTE","strength":3,"notifications":0,
#                               "mounted":false,"mountPoint":"",
#                               "mediaTitle":"","mediaArtist":"","mediaPlaying":false}]}
#
# Property names come from the daemon's own D-Bus declarations. Two things this
# script has to get right, both learned the hard way against kdeconnectd 25.x:
#
#  * there is no `DeviceNames` property on this build — `get-property` answers
#    "Property … was not found" and a reader that only asks for it sees zero
#    devices forever. Device ids come from the daemon's `devices()` method,
#    which answers an `as` array of bare ids, not object paths.
#  * the device object lives at /modules/kdeconnect/devices/<id>; its modules
#    hang off that path (…/battery, …/connectivity_report, …/sftp, …/mprisremote).
#
# `running` is about the daemon, not the package: kdeconnect-cli installed but
# kdeconnectd stopped answers false.
set -uo pipefail

emit() { printf '%s\n' "$1"; }

if ! command -v busctl >/dev/null; then
  emit '{"running":false,"devices":[]}'
  exit 0
fi

if ! busctl --user list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx 'org.kde.kdeconnect'; then
  emit '{"running":false,"devices":[]}'
  exit 0
fi

SVC="org.kde.kdeconnect.daemon"
BASE="/modules/kdeconnect"

bget() { busctl --user get-property "$SVC" "$1" "$2" "$3" 2>/dev/null; }

# `s "value"` → value
bstr() { bget "$@" | sed -e 's/^s //' -e 's/^"//' -e 's/"$//' -e 's/\\"/"/g'; }

# `b true` / `i 96` / `as 2 "a" "b"` → the scalar after the type tag.
bval() { bget "$@" | sed -e 's/^[a-z]* //' -e 's/"//g'; }

# `as 2 "id1" "id2"` → one id per line.
ids="$(busctl --user call "$SVC" "$BASE" org.kde.kdeconnect.daemon devices 2>/dev/null \
       | sed -e 's/^as [0-9]*[[:space:]]*//' -e 's/"//g' -e 's/[[:space:]]*$//')"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

for id in $ids; do
  base="$BASE/devices/$id"

  name="$(bstr "$base" org.kde.kdeconnect.device name)"
  type="$(bstr "$base" org.kde.kdeconnect.device type)"
  reachable="$(bval "$base" org.kde.kdeconnect.device isReachable)"
  paired="$(bval "$base" org.kde.kdeconnect.device isPaired)"

  has_battery="$(bval "$base/battery" org.kde.kdeconnect.device.battery hasBattery)"
  charge="$(bval "$base/battery" org.kde.kdeconnect.device.battery charge)"
  charging="$(bval "$base/battery" org.kde.kdeconnect.device.battery isCharging)"

  network="$(bstr "$base/connectivity_report" org.kde.kdeconnect.device.connectivity_report cellularNetworkType)"
  strength="$(bval "$base/connectivity_report" org.kde.kdeconnect.device.connectivity_report cellularNetworkStrength)"

  notifications="$(busctl --user call "$SVC" "$base/notifications" \
                   org.kde.kdeconnect.device.notifications activeNotifications 2>/dev/null \
                   | awk 'NR==1 {print $2}')"

  mounted="$(busctl --user call "$SVC" "$base/sftp" \
             org.kde.kdeconnect.device.sftp isMounted 2>/dev/null \
             | sed -e 's/^b //')"
  mountpoint=""
  if [ "$mounted" = "true" ]; then
    mountpoint="$(busctl --user call "$SVC" "$base/sftp" \
                  org.kde.kdeconnect.device.sftp mountPoint 2>/dev/null \
                  | sed -e 's/^s //' -e 's/^"//' -e 's/"$//')"
  fi

  m_title="$(bstr "$base/mprisremote" org.kde.kdeconnect.device.mprisremote title)"
  m_artist="$(bstr "$base/mprisremote" org.kde.kdeconnect.device.mprisremote artist)"
  m_playing="$(bval "$base/mprisremote" org.kde.kdeconnect.device.mprisremote isPlaying)"

  jq -cn --arg id "$id" --arg name "$name" --arg type "$type" \
         --arg reachable "$reachable" --arg paired "$paired" \
         --arg hasBattery "$has_battery" --arg charge "$charge" --arg charging "$charging" \
         --arg network "$network" --arg strength "$strength" \
         --arg notifications "${notifications:-0}" \
         --arg mounted "$mounted" --arg mountPoint "$mountpoint" \
         --arg mediaTitle "$m_title" --arg mediaArtist "$m_artist" \
         --arg mediaPlaying "$m_playing" \
    '{id: $id,
      name: $name,
      type: $type,
      reachable: ($reachable == "true"),
      paired: ($paired == "true"),
      hasBattery: ($hasBattery == "true"),
      charge: (if ($charge | test("^-?[0-9]+$")) then ($charge | tonumber) else -1 end),
      charging: ($charging == "true"),
      network: $network,
      strength: (if ($strength | test("^-?[0-9]+$")) then ($strength | tonumber) else -1 end),
      notifications: (if ($notifications | test("^[0-9]+$")) then ($notifications | tonumber) else 0 end),
      mounted: ($mounted == "true"),
      mountPoint: $mountPoint,
      mediaTitle: $mediaTitle,
      mediaArtist: $mediaArtist,
      mediaPlaying: ($mediaPlaying == "true")}' >> "$tmp"
done

jq -sc '{running: true, devices: .}' "$tmp"
