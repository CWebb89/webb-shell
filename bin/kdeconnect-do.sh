#!/bin/bash
# KDE Connect actions kdeconnect-cli does not cover, over the daemon's own
# D-Bus API.
#
#   kdeconnect-do.sh <device-id> mount      → prints the mount point on success
#   kdeconnect-do.sh <device-id> unmount
#   kdeconnect-do.sh <device-id> media <Play|Pause|Next|Previous>
#
# `mount` waits for the share to come up (mountAndWait) instead of firing and
# hoping, so the caller can open the path it prints. Exit status is the answer:
# 0 done, 1 refused, 2 bad usage.
set -uo pipefail

SVC="org.kde.kdeconnect.daemon"

usage() {
  echo "usage: kdeconnect-do.sh <device-id> mount|unmount|media <action>" >&2
  exit 2
}

[ $# -ge 2 ] || usage
id="$1"
verb="$2"

case "$verb" in
  mount|unmount|media) ;;
  *) usage ;;
esac

base="/modules/kdeconnect/devices/$id"

case "$verb" in
  mount)
    if ! command -v sshfs >/dev/null; then
      echo "sshfs is not installed — sudo pacman -S sshfs" >&2
      exit 1
    fi
    ok="$(busctl --user call "$SVC" "$base/sftp" \
          org.kde.kdeconnect.device.sftp mountAndWait 2>/dev/null | sed -e 's/^b //')"
    if [ "$ok" != "true" ]; then
      err="$(busctl --user call "$SVC" "$base/sftp" \
             org.kde.kdeconnect.device.sftp getMountError 2>/dev/null \
             | sed -e 's/^s //' -e 's/^"//' -e 's/"$//')"
      echo "${err:-mount failed}" >&2
      exit 1
    fi
    busctl --user call "$SVC" "$base/sftp" \
      org.kde.kdeconnect.device.sftp mountPoint 2>/dev/null \
      | sed -e 's/^s //' -e 's/^"//' -e 's/"$//'
    ;;
  unmount)
    busctl --user call "$SVC" "$base/sftp" \
      org.kde.kdeconnect.device.sftp unmount 2>/dev/null >/dev/null || exit 1
    ;;
  media)
    action="${3:-}"
    case "$action" in
      Play|Pause|Next|Previous) ;;
      *) usage ;;
    esac
    busctl --user call "$SVC" "$base/mprisremote" \
      org.kde.kdeconnect.device.mprisremote sendAction s "$action" >/dev/null 2>&1
    ;;
esac
