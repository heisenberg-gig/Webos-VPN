#!/bin/sh
# Intentional stop: tears down the tunnel, restores DNS/IPv6 and lifts the
# kill switch so the TV is back on the normal network.
# Usage: disconnect.sh [--keep-block]   (keep the firewall block in place)
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)/common.sh"

KEEP=0
[ "${1:-}" = "--keep-block" ] && KEEP=1

acquire_lock
trap 'rc=$?; release_lock; exit "$rc"' EXIT HUP INT TERM

rm -f "$DESIRED"

echo "== stopping tunnel =="
tunnel_down

echo "== restoring dns =="
dns_restore

echo "== restoring ipv6 =="
ipv6_restore

if [ "$KEEP" = "1" ]; then
  set_state "blocked"
  echo "OK: tunnel stopped, Internet stays blocked (kill switch)"
else
  echo "== lifting kill switch =="
  ks_remove
  set_state "disconnected"
  echo "OK: disconnected, normal network restored"
fi
