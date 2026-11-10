#!/bin/sh
. "$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)/common.sh"
UPID="$RUN/wgtv-upload.pid"
kill "$(cat "$UPID" 2>/dev/null)" 2>/dev/null || true
killall wgtv 2>/dev/null || true
rm -f "$UPID" "$RUN/upload-token" "$RUN/upload-url"
have_cmd iptables && iptables -D "$KS_CHAIN" -p tcp --sport 8088 -j ACCEPT 2>/dev/null
echo "Upload server stopped"
exit 0
