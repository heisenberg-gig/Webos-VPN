#!/bin/sh
# Everything needed to understand a problem, with secrets removed.
. "$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)/common.sh"
echo "== system =="; uname -a; uname -m
echo; echo "== tun =="; ls -l /dev/net/tun 2>&1
echo; echo "== iptables =="; iptables --version 2>&1 | head -1
echo; echo "== state =="; "$HERE/state.sh"
echo; echo "== kill switch rules =="
iptables -S "$KS_CHAIN" 2>&1 | head -30
iptables -t nat -S "$KS_NAT_CHAIN" 2>&1 | head -10
echo; echo "== resolv.conf =="; cat /etc/resolv.conf 2>&1
echo; echo "== routes =="; ip route 2>&1
echo; echo "== wireguard =="
"$WG" show "$IFACE" 2>&1 | sed -E 's/^(  *(private|preshared) key: ).*/\1(hidden)/'
echo; echo "== wireguard-go log =="; tail -40 "$LOGFILE" 2>/dev/null
echo; echo "== autostart log =="; tail -20 "$RUN/autostart.log" 2>/dev/null
echo; echo "== upload log =="; tail -20 "$RUN/wgtv-upload.log" 2>/dev/null
