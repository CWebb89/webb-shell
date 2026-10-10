#!/bin/bash
# Point the active NetworkManager connection at a DNS preset, or hand DNS back
# to DHCP. Writing a system connection needs NetworkManager's polkit
# authorisation, which the shell's own agent prompts for.
#
# Usage: dns-set.sh auto|cloudflare|google|quad9
set -u
need() { command -v "$1" >/dev/null || { notify-send -u critical "DNS unavailable" "Missing $1 — install: sudo pacman -S ${2:-$1}"; exit 1; }; }
need nmcli networkmanager

PRESET="${1:-}"
case "$PRESET" in
  auto|cloudflare|google|quad9) ;;
  *) echo "usage: dns-set.sh auto|cloudflare|google|quad9" >&2; exit 2 ;;
esac

read -r CONN DEV <<< "$(nmcli -t -f NAME,DEVICE,TYPE connection show --active 2>/dev/null |
  awk -F: '$3 == "802-11-wireless" || $3 == "802-3-ethernet" { print $1, $2; exit }')"
[ -n "${CONN:-}" ] || { notify-send -a webb-shell "DNS" "No active network connection"; exit 1; }

RC=0
case "$PRESET" in
  auto)       nmcli connection modify "$CONN" ipv4.ignore-auto-dns no ipv4.dns "" || RC=1
              ;;
  cloudflare) nmcli connection modify "$CONN" ipv4.dns "1.1.1.1 1.0.0.1" ipv4.ignore-auto-dns yes || RC=1
              ;;
  google)     nmcli connection modify "$CONN" ipv4.dns "8.8.8.8 8.8.4.4" ipv4.ignore-auto-dns yes || RC=1
              ;;
  quad9)      nmcli connection modify "$CONN" ipv4.dns "9.9.9.9 149.112.112.112" ipv4.ignore-auto-dns yes || RC=1
              ;;
esac

if [ "$RC" -ne 0 ]; then
  notify-send -a webb-shell -u critical "DNS not changed" "Authorisation denied for ${CONN}"
  exit 1
fi

if [ -n "${DEV:-}" ]; then
  nmcli device reapply "$DEV" >/dev/null 2>&1 || nmcli connection up "$CONN" >/dev/null 2>&1
fi

SET=$(nmcli -g ipv4.dns connection show "$CONN" 2>/dev/null)
notify-send -a webb-shell "DNS" "${CONN}: ${SET:-automatic (DHCP)}"
