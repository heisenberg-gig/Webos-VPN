#!/bin/sh
# Removes everything the app created: tunnel, firewall rules, DNS override,
# autostart hook and ALL stored profiles (they contain private keys).
. "$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)/common.sh"
"$HERE/disconnect.sh" 2>&1 || true
"$HERE/upload-stop.sh" 2>&1 || true
ks_remove
rm -f /var/lib/webosbrew/init.d/90-webosvpn
rm -rf "$BASE"
echo "OK: WebOS VPN removed. You can now remove the app from Homebrew Channel."
