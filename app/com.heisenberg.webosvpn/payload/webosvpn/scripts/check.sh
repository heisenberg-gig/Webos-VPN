#!/bin/sh
# Asks the Mullvad check service where the traffic is coming from.
. "$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)/common.sh"
URL="https://am.i.mullvad.net/json"
if have_cmd curl; then
  curl -fsS --max-time 10 "$URL" 2>&1
elif have_cmd wget; then
  wget -qO- -T 10 "$URL" 2>&1
else
  echo "ERROR: neither curl nor wget is available on this TV"
  exit 1
fi
