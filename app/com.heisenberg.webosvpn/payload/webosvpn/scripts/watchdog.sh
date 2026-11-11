#!/bin/sh
# Keeps the VPN alive. While a profile is wanted (DESIRED exists) and the tunnel
# is unhealthy, it reconnects to the same profile with growing pauses. The kill
# switch stays in place the whole time, so nothing leaks while it retries.
# Usage: watchdog.sh start | stop | run
. "$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)/common.sh"

WD_PID="$RUN/watchdog.pid"
WD_STATE="$RUN/wd-state"       # watching | retrying
WD_COUNT="$RUN/wd-count"       # successful automatic reconnections
INTERVAL="${WGTV_WD_INTERVAL:-5}"

wd_alive() { p="$(cat "$WD_PID" 2>/dev/null || true)"; [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }

healthy() {
  ip link show "$IFACE" >/dev/null 2>&1 || return 1
  p="$(cat "$PIDFILE" 2>/dev/null || true)"
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null || return 1
  ts="$("$WG" show "$IFACE" latest-handshakes 2>/dev/null | awk '{print $2}' | sort -n | tail -1)"
  [ -n "$ts" ] && [ "$ts" != "0" ] || return 1
  age=$(( $(date +%s) - ts ))
  [ "$age" -le 240 ]
}

busy() { # another operation (connect/disconnect/settings) is running
  [ -d "$OPERATION_LOCK" ] || return 1
  lp="$(cat "$OPERATION_LOCK/pid" 2>/dev/null || true)"
  [ -n "$lp" ] && kill -0 "$lp" 2>/dev/null
}

case "${1:-run}" in
  start)
    wd_alive && exit 0
    "$HERE/exec-clean.sh" "$HERE/watchdog.sh" run >>"$RUN/watchdog.log" 2>&1 &
    echo $! > "$WD_PID"
    ;;
  stop)
    p="$(cat "$WD_PID" 2>/dev/null || true)"
    [ -n "$p" ] && kill "$p" 2>/dev/null || true
    rm -f "$WD_PID" "$WD_STATE" "$WD_COUNT"
    ;;
  run)
    echo $$ > "$WD_PID"
    trap 'rm -f "$WD_PID" "$WD_STATE"; exit 0' TERM INT HUP
    fails=0; delay=5; next=0
    echo watching > "$WD_STATE"
    while :; do
      sleep "$INTERVAL"
      [ -f "$DESIRED" ] || { rm -f "$WD_PID" "$WD_STATE"; exit 0; }   # intentional disconnect
      if [ "$(get_setting autoreconnect 1)" != "1" ]; then fails=0; echo watching > "$WD_STATE"; continue; fi
      busy && continue
      if healthy; then
        fails=0; delay=5; echo watching > "$WD_STATE"
        continue
      fi
      fails=$((fails + 1))
      [ "$fails" -ge 2 ] || continue            # one grace tick before acting
      echo retrying > "$WD_STATE"
      now="$(date +%s)"
      [ "$now" -ge "$next" ] || continue
      id="$(cat "$DESIRED" 2>/dev/null || true)"
      [ -n "$id" ] || continue
      echo "$(date '+%F %T') tunnel unhealthy; reconnecting to $id (pause $delay s)"
      if "$HERE/connect.sh" "$id" >>"$RUN/watchdog.log" 2>&1; then
        n="$(cat "$WD_COUNT" 2>/dev/null || echo 0)"; echo $((n + 1)) > "$WD_COUNT"
        fails=0; delay=5; next=0; echo watching > "$WD_STATE"
        echo "$(date '+%F %T') reconnected"
      else
        delay=$((delay * 2)); [ "$delay" -gt 60 ] && delay=60
        next=$(( $(date +%s) + delay ))
      fi
    done
    ;;
  *) echo "usage: watchdog.sh start|stop|run"; exit 2 ;;
esac
