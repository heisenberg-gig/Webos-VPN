#!/bin/sh
# Runs every automated test. e2e needs root and network namespaces (it never
# touches the host network); ui needs python3 + playwright with chromium.
set -u
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
rc=0
echo "### go";   ( cd "$ROOT/uploader" && go test ./... ) || rc=1
echo "### e2e";  bash "$ROOT/tests/e2e.sh" || rc=1
echo "### ui";   python3 "$ROOT/tests/ui.py" || rc=1
exit $rc
