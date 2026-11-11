#!/bin/sh
# Connect to a profile, or switch from the current one to another.
# Usage: connect.sh <profile-id>
#
# Order matters for the kill switch: the firewall block is (re)loaded BEFORE
# the old tunnel is torn down and BEFORE the new one is started, so no packet
# can reach the Internet outside a tunnel at any point while switching.
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)/common.sh"

ID="${1:-}"
case "$ID" in
  ""|*/*|.*) echo "ERROR: usage: connect.sh <profile-id>"; exit 2 ;;
esac

START_OK=0
cleanup() {
  rc=$?
  if [ "$START_OK" -eq 0 ] && [ "$rc" -ne 0 ]; then
    # Failed half way: leave the kill switch in place (if enabled) on purpose,
    # but do not leave the half-configured tunnel behind.
    set_state "error"
  fi
  release_lock
  exit "$rc"
}

acquire_lock
trap cleanup EXIT HUP INT TERM

[ -x "$WG" ] && [ -x "$WGGO" ] && [ -x "$WGTV" ] || { echo "ERROR: missing binaries in $BIN"; exit 1; }
[ -x "$HERE/exec-clean.sh" ] || { echo "ERROR: missing clean launcher"; exit 1; }
[ -f "$PROFILES/$ID/wg.conf" ] || { echo "ERROR: profile '$ID' does not exist"; exit 1; }

KS="$(get_setting killswitch 1)"
LAN="$(get_setting lan 1)"
MTU="$(cat "$PROFILES/$ID/mtu" 2>/dev/null || echo 1420)"
DNS_LIST="$(effective_dns "$ID")"
DNS_FIRST="${DNS_LIST%% *}"

set_state "connecting"
echo "$ID" > "$DESIRED"
"$HERE/watchdog.sh" start || true
echo "== profile: $ID =="

# -- 1. original default route (never the tunnel itself) -----------------------
DEFAULT_LINE="$(ip route show default | grep -v " dev $IFACE " | head -1 || true)"
ORIG_GW="$(echo "$DEFAULT_LINE" | sed -n 's/.*default via \([^ ]*\).*/\1/p')"
ORIG_DEV="$(echo "$DEFAULT_LINE" | sed -n 's/.* dev \([^ ]*\).*/\1/p')"
if [ -z "$ORIG_DEV" ] && [ -f "$DEVFILE" ]; then
  ORIG_DEV="$(cat "$DEVFILE")"; ORIG_GW="$(cat "$GWFILE" 2>/dev/null || true)"
fi
if [ -n "$ORIG_DEV" ]; then
  echo "$ORIG_DEV" > "$DEVFILE"; echo "$ORIG_GW" > "$GWFILE"
  echo "original route: ${ORIG_GW:+via $ORIG_GW }dev $ORIG_DEV"
else
  echo "ERROR: no network connection (no default route)"; exit 1
fi

# -- 2. resolve endpoints (host names need DNS, so open it briefly if needed) --
mkdir -p "$PREP"; chmod 700 "$PREP"
NEED_DNS=0
while read -r ep; do
  host="${ep%:*}"
  case "$host" in
    *[!0-9.]*) NEED_DNS=1 ;;
  esac
done < "$PROFILES/$ID/endpoints"

if [ "$NEED_DNS" = "1" ] && [ "$KS" = "1" ] && ! ks_active; then
  : > "$PREP/empty"
  ks_apply "$PREP/empty" "$LAN" 1 "" >/dev/null || true
elif [ "$NEED_DNS" = "1" ] && [ "$KS" = "1" ]; then
  ks_apply "$PREP/endpoints" "$LAN" 1 "" >/dev/null 2>&1 || true
fi

"$WGTV" prepare "$ID" "$PREP" || { echo "ERROR: could not prepare the profile"; exit 1; }

# -- 3. firewall first -------------------------------------------------------
if [ "$KS" = "1" ]; then
  echo "== kill switch =="
  ks_apply "$PREP/endpoints" "$LAN" 0 "$DNS_FIRST" || {
    echo "ERROR: kill switch is enabled but could not be applied; refusing to connect unprotected."
    echo "Disable the kill switch in Settings if this TV has no iptables."
    exit 1
  }
else
  ks_remove
fi

# -- 4. tear down the previous tunnel (the firewall stays) ---------------------
echo "== stopping previous tunnel =="
tunnel_down

# -- 5. IPv6 off on the physical interface -------------------------------------
if [ -n "$ORIG_DEV" ]; then
  if [ ! -f "$IPV6_STATE_FILE" ]; then
    cur="$(sysctl -n "net.ipv6.conf.$ORIG_DEV.disable_ipv6" 2>/dev/null || true)"
    [ -n "$cur" ] && echo "$cur" > "$IPV6_STATE_FILE"
  fi
  [ -f "$IPV6_STATE_FILE" ] && sysctl -w "net.ipv6.conf.$ORIG_DEV.disable_ipv6=1" >/dev/null 2>&1 || true
fi

# -- 6. start wireguard-go ---------------------------------------------------
echo "== starting wireguard-go =="
mkdir -p /var/run/wireguard
LOG_LEVEL=info "$HERE/exec-clean.sh" "$WGGO" -f "$IFACE" >"$LOGFILE" 2>&1 &
echo $! > "$PIDFILE"

i=0
while [ "$i" -lt 10 ]; do
  ip link show "$IFACE" >/dev/null 2>&1 && break
  sleep 1; i=$((i + 1))
done
if ! ip link show "$IFACE" >/dev/null 2>&1; then
  echo "ERROR: interface $IFACE was not created"; cat "$LOGFILE" 2>/dev/null || true
  tunnel_down; exit 1
fi

"$WG" setconf "$IFACE" "$PREP/wg.setconf" || { echo "ERROR: wg setconf failed"; tunnel_down; exit 1; }

# -- 7. keep the server reachable outside the tunnel -------------------------
: > "$ENDPOINT_ROUTES"
while read -r ip port; do
  [ -n "$ip" ] || continue
  if [ -n "$ORIG_GW" ]; then
    ip route replace "$ip" via "$ORIG_GW" dev "$ORIG_DEV"
  else
    ip route replace "$ip" dev "$ORIG_DEV"
  fi
  echo "$ip" >> "$ENDPOINT_ROUTES"
done < "$PREP/endpoints"

# -- 8. address, mtu, routes ---------------------------------------------------
while read -r addr; do
  [ -n "$addr" ] && ip addr add "$addr" dev "$IFACE" 2>/dev/null || true
done < "$PROFILES/$ID/address"
ip link set mtu "$MTU" up dev "$IFACE"

: > "$ROUTES_APPLIED"
while read -r route; do
  [ -n "$route" ] || continue
  if [ "$route" = "0.0.0.0/0" ]; then
    echo "0.0.0.0/1" >> "$ROUTES_APPLIED"; echo "128.0.0.0/1" >> "$ROUTES_APPLIED"
  else
    echo "$route" >> "$ROUTES_APPLIED"
  fi
done < "$PROFILES/$ID/routes"
while read -r route; do
  [ -n "$route" ] && ip route replace "$route" dev "$IFACE"
done < "$ROUTES_APPLIED"

# -- 9. DNS ------------------------------------------------------------------
echo "== dns =="
if [ -n "$DNS_LIST" ]; then
  dns_apply "$DNS_LIST" || true
else
  dns_restore quiet
  echo "dns: this profile has no DNS entry; the system resolvers are left as they are"
fi

# -- 10. wait for the first handshake ------------------------------------------
echo "== waiting for handshake =="
i=0; HS=0
while [ "$i" -lt 10 ]; do
  HS="$("$WG" show "$IFACE" latest-handshakes 2>/dev/null | awk '{print $2}' | sort -n | tail -1)"
  [ -n "$HS" ] && [ "$HS" != "0" ] && break
  HS=0
  # a packet through the tunnel triggers the handshake if keepalive has not
  [ -n "$DNS_FIRST" ] && ping -c 1 -W 1 "$DNS_FIRST" >/dev/null 2>&1 || sleep 1
  i=$((i + 1))
done

set_setting last_profile "$ID"
START_OK=1
if [ "$HS" != "0" ]; then
  set_state "connected"
  echo "OK: connected to $ID"
else
  set_state "nohandshake"
  echo "WARNING: no reply from the server after 10 s."
  [ "$KS" = "1" ] && echo "The kill switch keeps the Internet blocked. Try another server or press Disconnect."
  exit 3
fi
