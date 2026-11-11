#!/bin/sh
# Prints the live state as key=value lines (read by the app).
. "$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)/common.sh"

desired="$(cat "$DESIRED" 2>/dev/null || true)"
iface=down
if ip link show "$IFACE" >/dev/null 2>&1 && [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
  iface=up
fi

hs_age=-1; rx=0; tx=0; endpoint=""
if [ "$iface" = "up" ]; then
  ts="$("$WG" show "$IFACE" latest-handshakes 2>/dev/null | awk '{print $2}' | sort -n | tail -1)"
  if [ -n "$ts" ] && [ "$ts" != "0" ]; then
    now="$(date +%s)"; hs_age=$((now - ts)); [ "$hs_age" -lt 0 ] && hs_age=0
  fi
  set -- $("$WG" show "$IFACE" transfer 2>/dev/null | head -1)
  rx="${2:-0}"; tx="${3:-0}"
  endpoint="$("$WG" show "$IFACE" endpoints 2>/dev/null | awk 'NR==1{print $2}')"
fi

ks=0
ks_active && ks=1

if [ -n "$desired" ]; then
  if [ "$iface" = "up" ]; then
    if [ "$hs_age" -ge 0 ] && [ "$hs_age" -le 240 ]; then status=connected
    elif [ "$hs_age" -gt 240 ]; then status=stale
    else status=nohandshake; fi
  elif [ "$ks" = "1" ]; then status=dropped_blocked
  else status=dropped_exposed; fi
else
  if [ "$ks" = "1" ]; then status=blocked; else status=disconnected; fi
fi

name=""
[ -n "$desired" ] && name="$(head -1 "$PROFILES/$desired/name" 2>/dev/null)"
autostart=0
[ -L /var/lib/webosbrew/init.d/90-webosvpn ] && [ -x /var/lib/webosbrew/init.d/90-webosvpn ] && autostart=1

echo "status=$status"
echo "profile=$desired"
echo "profile_name=$name"
echo "iface=$iface"
echo "handshake_age=$hs_age"
echo "rx=$rx"
echo "tx=$tx"
echo "endpoint=$endpoint"
echo "ks_active=$ks"
echo "autostart=$autostart"
echo "dns_applied=$(grep '^nameserver' "$RUN/resolv.vpn" 2>/dev/null | awk '{print $2}' | tr '\n' ' ' | sed 's/ *$//')"
echo "autoreconnect=$(get_setting autoreconnect 1)"
echo "wd_state=$(cat "$RUN/wd-state" 2>/dev/null)"
echo "wd_count=$(cat "$RUN/wd-count" 2>/dev/null || echo 0)"
echo "dns_method=$(cat "$RUN/resolv.method" 2>/dev/null)"
