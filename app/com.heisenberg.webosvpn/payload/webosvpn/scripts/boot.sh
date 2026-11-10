#!/bin/sh
# Runs at every boot through /var/lib/webosbrew/init.d.
# With the kill switch on, the block is loaded immediately, before the network
# is even up, so nothing leaves the TV unprotected while the VPN connects.
set -u
SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
HERE="$(CDPATH= cd -- "$(dirname -- "$SELF")" && pwd)"
BASE="${WGTV_BASE:-/var/lib/webosbrew/webosvpn}"

if [ ! -x "$HERE/connect.sh" ] || [ ! -x "$HERE/../bin/wg" ]; then
  # The app was removed without running Uninstall: clean everything up.
  rm -f /var/lib/webosbrew/init.d/90-webosvpn
  while iptables -D OUTPUT -j WEBOSVPN 2>/dev/null; do :; done
  iptables -F WEBOSVPN 2>/dev/null; iptables -X WEBOSVPN 2>/dev/null
  while iptables -t nat -D OUTPUT -j WEBOSVPN_DNS 2>/dev/null; do :; done
  iptables -t nat -F WEBOSVPN_DNS 2>/dev/null; iptables -t nat -X WEBOSVPN_DNS 2>/dev/null
  rm -rf "$BASE"
  exit 0
fi

. "$HERE/common.sh"
mkdir -p "$RUN"

LAST="$(get_setting last_profile '')"
[ -n "$LAST" ] && [ -f "$PROFILES/$LAST/wg.conf" ] || exit 0

(
  if [ "$(get_setting killswitch 1)" = "1" ]; then
    # endpoints written as IP literals can be allowed right away
    sed -n 's/^\([0-9.]*\):\([0-9]*\)$/\1 \2/p' "$PROFILES/$LAST/endpoints" > "$RUN/boot-endpoints"
    ks_apply "$RUN/boot-endpoints" "$(get_setting lan 1)" 0 "$(effective_dns "$LAST" | cut -d' ' -f1)"
  fi

  # Some TVs restore networking late after a cold boot. Wait up to 60 seconds.
  i=0
  while [ "$i" -lt 60 ]; do
    ip route show default | grep -q default && break
    sleep 1; i=$((i + 1))
  done
  if ! ip route show default | grep -q default; then
    echo "ERROR: no default route after 60 seconds (the kill switch keeps the TV offline)"
    exit 1
  fi
  "$HERE/connect.sh" "$LAST"
) >"$RUN/autostart.log" 2>&1 &
exit 0
