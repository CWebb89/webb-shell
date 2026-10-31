#!/bin/bash
# KDE Connect state as JSON, for the shell's phone module.
#
#   {"running":true,"devices":[{"id":"…","name":"…","type":"phone",
#                               "reachable":true,"paired":true,
#                               "hasBattery":true,"charge":78,"charging":false}]}
#
# Every property name here comes from the daemon's own D-Bus declarations
# (org.kde.kdeconnect.device, .device.battery, and the daemon's DeviceNames), not
# from a guess: get-property is silent on an unknown member, so a typo would
# read as "no devices" forever.
#
# `running` is about the daemon, not the package: kdeconnect-cli present but
# kdeconnectd stopped answers false, and the shell hides the module either way.
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

DAEMON_PATH="/modules/kdeconnect"
DAEMON_IFACE="org.kde.kdeconnect.daemon"

prop() {
  busctl --user get-property org.kde.kdeconnect.daemon "$1" "$2" "$3" 2>/dev/null \
    | sed -e 's/^[a-z] //' -e 's/^"//' -e 's/"$//' -e 's/\\"/"/g'
}

# `as N "id" …` — the type and count prefix has to go before the quoted tokens
# are read, or the count and the type name both come back as device ids.
ids="$(busctl --user get-property org.kde.kdeconnect.daemon "$DAEMON_PATH" "$DAEMON_IFACE" DeviceNames 2>/dev/null \
       | sed -e 's/^as [0-9]*[[:space:]]*//' -e 's/"//g')"

if [ -z "$ids" ]; then
  paths="$(busctl --user call org.kde.kdeconnect.daemon "$DAEMON_PATH" "$DAEMON_IFACE" devices 2>/dev/null \
           | tr ' ' '\n' | sed -n 's#.*/devices/\([^"/]*\)"#\1#p')"
  ids="$paths"
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

for id in $ids; do
  base="$DAEMON_PATH/devices/$id"
  name="$(prop "$base" org.kde.kdeconnect.device name)"
  type="$(prop "$base" org.kde.kdeconnect.device type)"
  reachable="$(prop "$base" org.kde.kdeconnect.device isReachable)"
  paired="$(prop "$base" org.kde.kdeconnect.device isPaired)"
  has_battery="$(prop "$base/battery" org.kde.kdeconnect.device.battery hasBattery)"
  charge="$(prop "$base/battery" org.kde.kdeconnect.device.battery charge)"
  charging="$(prop "$base/battery" org.kde.kdeconnect.device.battery isCharging)"

  jq -cn --arg id "$id" --arg name "$name" --arg type "$type" \
         --arg reachable "$reachable" --arg paired "$paired" \
         --arg hasBattery "$has_battery" --arg charge "$charge" --arg charging "$charging" \
    '{id: $id,
      name: $name,
      type: $type,
      reachable: ($reachable == "true"),
      paired: ($paired == "true"),
      hasBattery: ($hasBattery == "true"),
      charge: (if ($charge | test("^-?[0-9]+$")) then ($charge | tonumber) else -1 end),
      charging: ($charging == "true")}' >> "$tmp"
done

jq -sc '{running: true, devices: .}' "$tmp"
