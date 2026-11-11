#!/bin/sh
# Intentional stop: tears down the tunnel, restores DNS/IPv6 and lifts the
# kill switch so the TV is back on the normal network.
# Usage: disconnect.sh [--keep-block]   (keep the firewall block in place)
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)/common.sh"

KEEP=0
[ "${1:-}" = "--keep-block" ] && KEEP=1

# stop the watchdog first, then wait (up to 30 s) for a reconnection already in progress
"$HERE/watchdog.sh" stop || true
w=0
while [ -d "$OPERATION_LOCK" ] && [ "$w" -lt 30 ]; do
  lp="$(cat "$OPERATION_LOCK/pid" 2>/dev/null || true)"
  [ -n "$lp" ] && kill -0 "$lp" 2>/dev/null || break
  sleep 1; w=$((w + 1))
done

acquire_lock
trap 'rc=$?; release_lock; exit "$rc"' EXIT HUP INT TERM

rm -f "$DESIRED"
"$HERE/watchdog.sh" stop || true

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
