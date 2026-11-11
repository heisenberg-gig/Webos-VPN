#!/bin/sh
# Usage: profiles.sh list | delete <id> | rename <id> <new name> | fav <id>
. "$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)/common.sh"

FAVS="$CONF/favorites"

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
    [ -f "$FAVS" ] && while read -r f; do
      [ -n "$f" ] && [ -f "$PROFILES/$f/wg.conf" ] && printf 'FAV\t%s\n' "$f"
    done < "$FAVS"
    echo "LAST=$(get_setting last_profile '')"
    ;;
  delete)
    id="${2:-}"
    case "$id" in ""|*/*|.*) echo "ERROR: invalid id"; exit 2 ;; esac
    if [ "$(cat "$DESIRED" 2>/dev/null)" = "$id" ]; then
      echo "ERROR: this profile is in use; disconnect first"; exit 1
    fi
    rm -rf "$PROFILES/$id"
    [ -f "$FAVS" ] && { grep -vxF "$id" "$FAVS" > "$FAVS.tmp" || true; mv -f "$FAVS.tmp" "$FAVS"; }
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
  fav)  # toggle
    id="${2:-}"
    case "$id" in ""|*/*|.*) echo "ERROR: invalid id"; exit 2 ;; esac
    [ -f "$PROFILES/$id/wg.conf" ] || { echo "ERROR: no such profile"; exit 1; }
    touch "$FAVS"; chmod 600 "$FAVS"
    if grep -qxF "$id" "$FAVS"; then
      grep -vxF "$id" "$FAVS" > "$FAVS.tmp" || true; mv -f "$FAVS.tmp" "$FAVS"; echo "OK: unfavorited"
    else
      echo "$id" >> "$FAVS"; echo "OK: favorited"
    fi
    ;;
  *) echo "usage: profiles.sh list|delete <id>|rename <id> <name>|fav <id>"; exit 2 ;;
esac
