#!/bin/sh
# Builds the helper for the TV (ARMv7), runs the Go tests and packages the IPK.
# Needs: go, and ares-package (npm i -g @webos-tools/cli) or npx.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP="$ROOT/app/com.heisenberg.webosvpn"

echo "== go test =="
( cd "$ROOT/uploader" && go vet ./... && go test ./... )

echo "== wgtv for ARMv7 =="
( cd "$ROOT/uploader" && GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w" -o "$APP/payload/webosvpn/bin/wgtv" . )

echo "== shell syntax =="
for f in "$APP"/payload/webosvpn/scripts/*.sh "$APP/payload/webosvpn/install.sh"; do sh -n "$f"; done

echo "== package =="
mkdir -p "$ROOT/dist"
if command -v ares-package >/dev/null 2>&1; then
  ares-package "$APP" -o "$ROOT/dist" --no-minify
else
  npx --yes @webos-tools/cli ares-package "$APP" -o "$ROOT/dist" --no-minify
fi
ls -la "$ROOT/dist"
