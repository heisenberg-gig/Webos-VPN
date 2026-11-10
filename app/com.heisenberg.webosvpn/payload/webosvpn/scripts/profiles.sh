#!/bin/sh
# Usage: profiles.sh list | delete <id> | rename <id> <new name>
. "$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)/common.sh"

case "${1:-list}" in
  list)
    for d in "$PROFILES"/*/; do
      [ -f "${d}wg.conf" ] || continue
      id="$(basename "$d")"
      name="$(head -1 "${d}name" 2>/dev/null | tr '\t|' '  ')"
      ep="$(head -1 "${d}endpoints" 2>/dev/null)"
      dns="$(tr '\n' ',' < "${d}dns" 2>/dev/null | sed 's/,$//')"
      printf 'PROFILE\t%s\t%s\t%s\t%s\n' "$id" "$name" "$ep" "$dns"
    done
    echo "LAST=$(get_setting last_profile '')"
    ;;
  delete)
    id="${2:-}"
    case "$id" in ""|*/*|.*) echo "ERROR: invalid id"; exit 2 ;; esac
    if [ "$(cat "$DESIRED" 2>/dev/null)" = "$id" ]; then
      echo "ERROR: this profile is in use; disconnect first"; exit 1
    fi
    rm -rf "$PROFILES/$id"
    [ "$(get_setting last_profile '')" = "$id" ] && set_setting last_profile ""
    echo "OK: deleted $id"
    ;;
  rename)
    id="${2:-}"; shift 2 2>/dev/null || true
    new="$*"
    case "$id" in ""|*/*|.*) echo "ERROR: invalid id"; exit 2 ;; esac
    [ -d "$PROFILES/$id" ] && [ -n "$new" ] || { echo "ERROR: nothing to rename"; exit 1; }
    printf '%s\n' "$new" | head -c 60 > "$PROFILES/$id/name"; echo >> "$PROFILES/$id/name"
    echo "OK"
    ;;
  *) echo "usage: profiles.sh list|delete <id>|rename <id> <name>"; exit 2 ;;
esac
