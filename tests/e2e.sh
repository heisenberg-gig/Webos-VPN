#!/bin/bash
# End-to-end test of the shell logic using two network namespaces:
#   tv  = the TV (runs the real scripts, real iptables/ip/mount)
#   lan = router + "Internet" (counts which packets arrive)
# The WireGuard binaries are stubs (no kernel module / module proxy in CI), so
# this proves routing, firewall, DNS and ordering - not the crypto.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/app/com.heisenberg.webosvpn/payload/webosvpn/scripts"
T=/tmp/wgtv-e2e
if [ -z "${WGTV_E2E_INSIDE:-}" ]; then
  rm -rf "$T"; mkdir -p "$T/bin" "$T/fake" "$T/base"
  cp "$ROOT/tests/stubs/"* "$T/bin/"
  (cd "$ROOT/uploader" && go build -o "$T/bin/wgtv" .) || { echo "cannot build wgtv"; exit 2; }
fi

if [ -z "${WGTV_E2E_INSIDE:-}" ]; then
  # Outer shell: create the namespaces, then run this same script inside the
  # "tv" namespace (one persistent mount namespace, so bind mounts are visible).
  ip netns add wgtv-tv 2>/dev/null || { echo "need root + ip netns"; exit 2; }
  ip netns add wgtv-lan
  trap 'ip netns del wgtv-tv 2>/dev/null; ip netns del wgtv-lan 2>/dev/null' EXIT
  ip link add eth0 netns wgtv-tv type veth peer name eth0 netns wgtv-lan
  ip netns exec wgtv-lan sh -c 'ip link set lo up; ip addr add 192.168.50.1/24 dev eth0; ip link set eth0 up
    for a in 203.0.113.9 203.0.113.50 203.0.113.51; do ip addr add $a/32 dev lo; done
    iptables -A INPUT -s 192.168.50.10 -d 203.0.113.9  -m comment --comment inet -j ACCEPT
    iptables -A INPUT -s 192.168.50.10 -d 203.0.113.50 -p udp --dport 51820 -m comment --comment ep50 -j ACCEPT
    iptables -A INPUT -s 192.168.50.10 -d 203.0.113.51 -p udp --dport 51820 -m comment --comment ep51 -j ACCEPT
    iptables -A INPUT -s 192.168.50.10 -d 192.168.50.1 -p udp --dport 8000 -m comment --comment lan -j ACCEPT
    iptables -A INPUT -s 192.168.50.10 -d 192.168.50.1 -p udp --dport 53 -m comment --comment dns -j ACCEPT'
  ip netns exec wgtv-tv sh -c 'ip link set lo up; ip addr add 192.168.50.10/24 dev eth0; ip link set eth0 up; ip route add default via 192.168.50.1'
  WGTV_E2E_INSIDE=1 ip netns exec wgtv-tv bash "$0" "$@"
  exit $?
fi
TV() { "$@"; }
LAN() { ip netns exec wgtv-lan "$@"; }

export WGTV_BASE="$T/base" WGTV_BIN="$T/bin" FAKE_DIR="$T/fake" WGTV_RESOLV="$T/resolv.conf"
printf 'nameserver 192.168.50.1\n' > "$WGTV_RESOLV"
touch "$FAKE_DIR/handshake"

count() { LAN iptables -nvxL INPUT | awk -v n="/* $1 */" 'index($0,n){print $1}'; }
send() { TV python3 -c "
import socket,sys
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.settimeout(0.3)
try: s.sendto(b'x',(sys.argv[1],int(sys.argv[2])))
except Exception: pass" "$1" "$2"; }
S() { TV sh "$SCRIPTS/$1" "${@:2}"; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1  [$2]"; fi; }
sv() { S state.sh | sed -n "s/^$1=//p"; }

KEY1=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=; KEY2=AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=
mk() { cat > "$T/$1.conf" <<CONF
[Interface]
PrivateKey = $KEY1
Address = 10.66.12.34/32,fc00:bbbb:bbbb:bb01::3:c21/128
DNS = 10.64.0.1

[Peer]
PublicKey = $KEY2
AllowedIPs = 0.0.0.0/0,::0/0
Endpoint = $2:51820
CONF
}
mk pt-lis-wg-001 203.0.113.50
mk de-fra-wg-002 203.0.113.51
"$T/bin/wgtv" import "$T/pt-lis-wg-001.conf" "$T/de-fra-wg-002.conf" >/dev/null
S settings.sh set autoreconnect 0 >/dev/null   # sections 1-11 test the drop behaviour itself
export WGTV_WD_INTERVAL=1

echo "== 1. connect to profile A with the kill switch on (default) =="
S connect.sh pt-lis-wg-001 >"$T/c1.log" 2>&1; rc=$?
check "connect exits 0" "[ $rc -eq 0 ]"
check "state is connected" '[ "$(sv status)" = connected ]'
check "profile is A" '[ "$(sv profile)" = pt-lis-wg-001 ]'
check "full tunnel split routes via tunnel" 'TV ip route | grep -q "^0.0.0.0/1 dev wgtv0" && TV ip route | grep -q "^128.0.0.0/1 dev wgtv0"'
check "endpoint pinned outside the tunnel" 'TV ip route | grep -q "^203.0.113.50 via 192.168.50.1 dev eth0"'
check "firewall jump is the first OUTPUT rule" 'TV iptables -S OUTPUT | sed -n 2p | grep -q -- "-j WEBOSVPN"'
check "DNS redirect rule present" 'TV iptables -t nat -S WEBOSVPN_DNS | grep -q "DNAT --to-destination 10.64.0.1"'
check "resolv.conf points at the VPN resolver" 'grep -q "nameserver 10.64.0.1" "$WGTV_RESOLV"'
check "resolv.conf cannot be overwritten (read-only bind)" '! (TV sh -c "echo x > $WGTV_RESOLV") 2>/dev/null'
check "ks_active reported" '[ "$(sv ks_active)" = 1 ]'
check "last_profile remembered" 'S settings.sh get | grep -q "last_profile=pt-lis-wg-001"'

echo "== 2. leaks while connected =="
send 203.0.113.9 9999;  check "public traffic does not reach the Internet side" '[ "$(count inet)" = 0 ]'
send 192.168.50.1 53;   check "DNS to the router is not sent in the clear" '[ "$(count dns)" = 0 ]'
send 203.0.113.50 51820; check "WireGuard endpoint itself is reachable" '[ "$(count ep50)" -ge 1 ]'
send 192.168.50.1 8000; check "LAN stays reachable (allow-LAN on)" '[ "$(count lan)" -ge 1 ]'

echo "== 3. the tunnel dies unexpectedly =="
TV sh -c "kill \$(cat $T/base/run/wireguard-go.pid); sleep 1; ip link del wgtv0 2>/dev/null; true"
check "state shows dropped + blocked" '[ "$(sv status)" = dropped_blocked ]'
send 203.0.113.9 9999;  check "nothing leaks with the tunnel gone" '[ "$(count inet)" = 0 ]'
send 192.168.50.1 53;   check "no DNS leak with the tunnel gone" '[ "$(count dns)" = 0 ]'
check "TCP to the Internet fails fast (REJECT)" 'TV python3 -c "
import socket,sys
s=socket.socket(); s.settimeout(2)
try: s.connect((\"203.0.113.9\",443)); sys.exit(1)
except (ConnectionRefusedError,OSError): sys.exit(0)"'

echo "== 4. switch to profile B (probe packets every 20 ms the whole time) =="
before_inet=$(count inet); before50=$(count ep50)
( for i in $(seq 1 400); do send 203.0.113.9 9999; sleep 0.02; done ) & PROBE=$!
S connect.sh de-fra-wg-002 >"$T/c2.log" 2>&1; rc=$?
wait $PROBE 2>/dev/null
check "switch exits 0" "[ $rc -eq 0 ]"
check "no packet leaked during the whole switch" '[ "$(count inet)" = "$before_inet" ]'
check "state connected to B" '[ "$(sv status)" = connected ] && [ "$(sv profile)" = de-fra-wg-002 ]'
check "firewall now allows B endpoint" 'TV iptables -S WEBOSVPN | grep -q -- "-d 203.0.113.51/32 -p udp -m udp --dport 51820 -j ACCEPT"'
check "firewall no longer allows A endpoint" '! TV iptables -S WEBOSVPN | grep -q -- "203.0.113.50"'
check "A endpoint route removed, B added" '! TV ip route | grep -q "^203.0.113.50 " && TV ip route | grep -q "^203.0.113.51 via"'
check "exactly one jump rule (no duplicates)" '[ "$(TV iptables -S OUTPUT | grep -c -- "-j WEBOSVPN")" = 1 ]'

echo "== 5. settings change on a live connection =="
S settings.sh set lan 0 >/dev/null
send 192.168.50.1 8000; b=$(count lan); send 192.168.50.1 8000
check "allow-LAN off blocks the LAN" '[ "$(count lan)" = "$b" ]'
S settings.sh set lan 1 >/dev/null
S settings.sh set dns_mode ads_trackers_malware >/dev/null
check "DNS preset applied to resolv.conf" 'grep -q "nameserver 100.64.0.7" "$WGTV_RESOLV"'
check "DNS preset applied to the redirect" 'TV iptables -t nat -S WEBOSVPN_DNS | grep -q "to-destination 100.64.0.7"'
S settings.sh set dns_mode custom >/dev/null; S settings.sh set dns_custom 9.9.9.9,1.1.1.1 >/dev/null
check "custom DNS list applied" 'grep -q "nameserver 9.9.9.9" "$WGTV_RESOLV" && grep -q "nameserver 1.1.1.1" "$WGTV_RESOLV"'
check "invalid DNS rejected" '! S settings.sh set dns_custom "not-an-ip" >/dev/null 2>&1'
check "invalid key rejected" '! S settings.sh set bogus 1 >/dev/null 2>&1'
S settings.sh set dns_mode profile >/dev/null
check "back to the profile DNS" 'grep -q "nameserver 10.64.0.1" "$WGTV_RESOLV"'
S settings.sh set killswitch 0 >/dev/null
check "turning the kill switch off removes the rules" '! TV iptables -S OUTPUT | grep -q WEBOSVPN && ! TV iptables -t nat -S OUTPUT | grep -q WEBOSVPN_DNS'
S settings.sh set killswitch 1 >/dev/null
check "turning it on again re-applies them" 'TV iptables -S OUTPUT | grep -q WEBOSVPN'

echo "== 6. no reply from the server =="
rm -f "$FAKE_DIR/handshake"
S connect.sh pt-lis-wg-001 >"$T/c3.log" 2>&1; rc=$?
check "exit code 3 when there is no handshake" "[ $rc -eq 3 ]"
check "state is nohandshake" '[ "$(sv status)" = nohandshake ]'
check "internet stays blocked while unreachable" 'TV iptables -S OUTPUT | grep -q WEBOSVPN'
touch "$FAKE_DIR/handshake"

echo "== 7. disconnect restores everything =="
S disconnect.sh >"$T/d.log" 2>&1; rc=$?
check "disconnect exits 0" "[ $rc -eq 0 ]"
check "state disconnected" '[ "$(sv status)" = disconnected ]'
check "firewall chains gone" '! TV iptables -S | grep -q WEBOSVPN && ! TV iptables -t nat -S | grep -q WEBOSVPN_DNS'
check "resolv.conf restored" 'grep -qx "nameserver 192.168.50.1" "$WGTV_RESOLV"'
check "resolv.conf writable again" '(TV sh -c "echo # >> $WGTV_RESOLV") 2>/dev/null'
check "interface and routes gone" '! TV ip link show wgtv0 >/dev/null 2>&1 && ! TV ip route | grep -q wgtv0 && ! TV ip route | grep -q "^203.0.113"'
send 203.0.113.9 9999; check "normal network works again" '[ "$(count inet)" -ge 1 ]'

echo "== 8. kill switch off + tunnel drops = exposed warning =="
S settings.sh set killswitch 0 >/dev/null
S connect.sh pt-lis-wg-001 >"$T/c4.log" 2>&1
TV sh -c "kill \$(cat $T/base/run/wireguard-go.pid); sleep 1; ip link del wgtv0 2>/dev/null; true"
check "UI would be told the TV is exposed" '[ "$(sv status)" = dropped_exposed ]'
S disconnect.sh >/dev/null 2>&1
S settings.sh set killswitch 1 >/dev/null

echo "== 9. disconnect --keep-block =="
S connect.sh pt-lis-wg-001 >/dev/null 2>&1
S disconnect.sh --keep-block >/dev/null 2>&1
check "blocked state reported" '[ "$(sv status)" = blocked ]'
send 203.0.113.9 9999; b=$(count inet); send 203.0.113.9 9999
check "internet really is blocked" '[ "$(count inet)" = "$b" ]'
S disconnect.sh >/dev/null 2>&1
check "plain disconnect lifts the block" '[ "$(sv status)" = disconnected ]'

echo "== 10. boot script blocks before the network is checked =="
S settings.sh set last_profile pt-lis-wg-001 >/dev/null
TV sh "$SCRIPTS/boot.sh"; sleep 6
check "boot connected to the last profile" '[ "$(sv status)" = connected ] && [ "$(sv profile)" = pt-lis-wg-001 ]'
check "boot log shows the kill switch loaded first" 'head -3 "$T/base/run/autostart.log" | grep -q "kill-switch: active"'
S disconnect.sh >/dev/null 2>&1

echo "== 11. profiles =="
check "list shows both profiles" '[ "$(S profiles.sh list | grep -c ^PROFILE)" = 2 ]'
S connect.sh pt-lis-wg-001 >/dev/null 2>&1
check "cannot delete the profile in use" '! S profiles.sh delete pt-lis-wg-001 >/dev/null 2>&1'
S disconnect.sh >/dev/null 2>&1
S profiles.sh delete de-fra-wg-002 >/dev/null 2>&1
check "delete removes it" '[ "$(S profiles.sh list | grep -c ^PROFILE)" = 1 ]'
check "path traversal refused" '! S profiles.sh delete ../conf >/dev/null 2>&1'
S profiles.sh fav pt-lis-wg-001 >/dev/null
check "favorite is listed" 'S profiles.sh list | grep -q "^FAV.pt-lis-wg-001$"'
check "favorite of a missing profile refused" '! S profiles.sh fav nope >/dev/null 2>&1'
S profiles.sh fav pt-lis-wg-001 >/dev/null
check "second fav toggles it off" '! S profiles.sh list | grep -q "^FAV"'
S profiles.sh fav pt-lis-wg-001 >/dev/null

echo "== 12. automatic reconnection =="
S settings.sh set autoreconnect 1 >/dev/null
S connect.sh pt-lis-wg-001 >"$T/c5.log" 2>&1
check "connected, watchdog running" '[ "$(sv status)" = connected ] && kill -0 "$(cat $T/base/run/watchdog.pid)"'
before_inet=$(count inet)
( for i in $(seq 1 450); do send 203.0.113.9 9999; sleep 0.02; done ) & PROBE=$!
TV sh -c "kill \$(cat $T/base/run/wireguard-go.pid); sleep 0.5; ip link del wgtv0 2>/dev/null; true"
check "the drop is seen as blocked" '[ "$(sv status)" = dropped_blocked ]'
i=0; while [ "$i" -lt 40 ] && [ "$(sv status)" != connected ]; do sleep 1; i=$((i + 1)); done
wait $PROBE 2>/dev/null
check "reconnected on its own to the same profile" '[ "$(sv status)" = connected ] && [ "$(sv profile)" = pt-lis-wg-001 ]'
check "reconnection counted" '[ "$(sv wd_count)" -ge 1 ]'
check "nothing leaked while it was down and reconnecting" '[ "$(count inet)" = "$before_inet" ]'
check "watchdog reports watching again" '[ "$(sv wd_state)" = watching ]'
S disconnect.sh >/dev/null 2>&1
sleep 3
check "intentional disconnect stays disconnected" '[ "$(sv status)" = disconnected ] && ! TV ip link show wgtv0 >/dev/null 2>&1'
check "watchdog gone after disconnect" '[ ! -f "$T/base/run/watchdog.pid" ] && ! pgrep -f "watchdog.sh run" >/dev/null'
S settings.sh set autoreconnect 0 >/dev/null
S connect.sh pt-lis-wg-001 >/dev/null 2>&1
TV sh -c "kill \$(cat $T/base/run/wireguard-go.pid); sleep 0.5; ip link del wgtv0 2>/dev/null; true"
sleep 6
check "setting off: no automatic reconnection" '[ "$(sv status)" = dropped_blocked ]'
S settings.sh set autoreconnect 1 >/dev/null
i=0; while [ "$i" -lt 40 ] && [ "$(sv status)" != connected ]; do sleep 1; i=$((i + 1)); done
check "turning it back on reconnects" '[ "$(sv status)" = connected ]'
S disconnect.sh >/dev/null 2>&1

echo "== 13. uninstall =="
S uninstall.sh >/dev/null 2>&1
check "state dir (with private keys) removed" '[ ! -e "$T/base" ]'

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
