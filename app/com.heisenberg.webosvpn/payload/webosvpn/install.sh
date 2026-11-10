#!/bin/sh
set -eu

APPID="com.heisenberg.webosvpn"
DST="/var/lib/webosbrew/webosvpn"
INIT_FILE="/var/lib/webosbrew/init.d/90-webosvpn"

find_appdir() {
  for d in \
    "/media/developer/apps/usr/palm/applications/$APPID" \
    "/media/cryptofs/apps/usr/palm/applications/$APPID" \
    "/media/internal/apps/usr/palm/applications/$APPID"
  do
    if [ -d "$d/payload/webosvpn" ]; then echo "$d"; return 0; fi
  done
  find /media -type d -path "*/applications/$APPID" 2>/dev/null | head -1
}

APPDIR="$(find_appdir)"
SRC="$APPDIR/payload/webosvpn"
[ -d "$SRC" ] || { echo "ERROR: cannot find the app payload"; exit 1; }

echo "== preparing WebOS VPN =="
echo "SRC=$SRC"; echo "DST=$DST"

# Packaging on some systems (Windows) drops the executable bit.
chmod 755 "$SRC/bin/"* "$SRC/scripts/"*.sh "$SRC/install.sh" 2>/dev/null || true

echo; echo "== checking binaries =="
for f in wg wireguard-go wgtv; do
  [ -x "$SRC/bin/$f" ] || { echo "ERROR: missing executable $SRC/bin/$f"; exit 1; }
done
echo; echo "== checking scripts =="
for f in common.sh connect.sh disconnect.sh state.sh profiles.sh settings.sh check.sh diag.sh \
         upload-start.sh upload-stop.sh autostart.sh boot.sh uninstall.sh exec-clean.sh; do
  [ -x "$SRC/scripts/$f" ] || { echo "ERROR: missing executable $SRC/scripts/$f"; exit 1; }
done

mkdir -p "$DST" "$DST/conf" "$DST/run" "$DST/profiles"
chmod 700 "$DST/conf" "$DST/profiles" "$DST/run"

AUTOSTART_WAS_ENABLED=0
{ [ -e "$INIT_FILE" ] || [ -L "$INIT_FILE" ]; } && AUTOSTART_WAS_ENABLED=1

echo; echo "== stopping previous runtime =="
# Intentionally keep the kill switch if it is active: an update must not open
# a window where traffic leaves outside the tunnel.
if [ -x "$DST/scripts/disconnect.sh" ]; then
  sh "$DST/scripts/disconnect.sh" --keep-block 2>&1 || true
fi
killall wgtv 2>/dev/null || true
sleep 1

echo; echo "== linking packaged components =="
rm -rf "$DST/bin" "$DST/scripts"
ln -s "$SRC/bin" "$DST/bin"
ln -s "$SRC/scripts" "$DST/scripts"

echo; echo "== versions =="
"$SRC/bin/wg" --version 2>&1 || true
"$SRC/bin/wireguard-go" --version 2>&1 || true

if [ "$AUTOSTART_WAS_ENABLED" -eq 1 ]; then
  echo; echo "== migrating autostart hook =="
  "$SRC/scripts/autostart.sh" enable
fi

echo; echo "OK: ready. Profiles kept: $(ls "$DST/profiles" 2>/dev/null | wc -l)"
