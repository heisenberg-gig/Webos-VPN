#!/bin/sh
# Starts the temporary upload page on the LAN and prints its URL and code.
. "$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)/common.sh"
UPID="$RUN/wgtv-upload.pid"; ULOG="$RUN/wgtv-upload.log"
TOKENFILE="$RUN/upload-token"; URLFILE="$RUN/upload-url"

[ -x "$WGTV" ] || { echo "ERROR: missing $WGTV"; exit 1; }
kill "$(cat "$UPID" 2>/dev/null)" 2>/dev/null || true
killall wgtv 2>/dev/null || true
rm -f "$TOKENFILE"

DEV="$(ip route show default 2>/dev/null | awk -v w="$IFACE" '$1=="default" && $0 !~ (" dev " w " ") {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
IP=""
[ -n "$DEV" ] && IP="$(ip addr show dev "$DEV" 2>/dev/null | sed -n 's/.*inet \([^/]*\).*/\1/p' | head -1)"
if [ -z "$IP" ]; then
  IP="$(ip addr show 2>/dev/null | awk '/^[0-9]+: /{d=$2; sub(/:.*/,"",d)} /^[[:space:]]*inet /&&d!="'"$IFACE"'"&&$2!~/^127\./{ip=$2; sub(/\/.*/,"",ip); print ip; exit}')"
fi
[ -n "$IP" ] || { echo "ERROR: cannot detect the LAN IP of the TV"; exit 1; }

# With the kill switch on and LAN access off, let the page answer.
if ks_active && [ "$(get_setting lan 1)" = "0" ]; then
  iptables -D "$KS_CHAIN" -p tcp --sport 8088 -j ACCEPT 2>/dev/null || true
  iptables -I "$KS_CHAIN" 1 -p tcp --sport 8088 -j ACCEPT 2>/dev/null || true
fi

WGTV_BASE="$BASE" WGTV_TOKEN_FILE="$TOKENFILE" WGTV_TIMEOUT=600 "$HERE/exec-clean.sh" "$WGTV" serve >"$ULOG" 2>&1 &
echo $! > "$UPID"

i=0
while [ ! -s "$TOKENFILE" ] && [ "$i" -lt 10 ]; do
  kill -0 "$(cat "$UPID")" 2>/dev/null || { echo "ERROR: upload server stopped at startup"; cat "$ULOG"; exit 1; }
  sleep 1; i=$((i + 1))
done
[ -s "$TOKENFILE" ] || { echo "ERROR: timed out waiting for the access code"; exit 1; }

echo "Upload server started"
echo
echo "URL: http://$IP:8088"
echo "CODE: $(cat "$TOKENFILE")"
echo "The page closes after 10 minutes, five wrong codes, or when you finish."
