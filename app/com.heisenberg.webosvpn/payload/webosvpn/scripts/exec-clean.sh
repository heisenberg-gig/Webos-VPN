#!/bin/sh
set -eu

# A Homebrew exec request can pass Luna sockets and other native descriptors
# through its shell. A daemon must not keep those service connections alive, or
# the exec call would never return.
#
# The descriptor the shell itself uses to read THIS script is left alone:
# closing it breaks dash ("exec: 10: not found") and is harmless to keep.
SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"

# busybox ash (webOS) accepts multi-digit descriptors in "exec N>&-"; dash only
# accepts 0-9 and would abort. Probe in a subshell and limit the range if needed.
if (eval 'exec 10>&-') 2>/dev/null; then MAXFD=1023; else MAXFD=9; fi

exec_clean() {
  for fd in /proc/self/fd/*; do
    n=${fd##*/}
    case "$n" in
      ''|*[!0-9]*) continue ;;
    esac
    [ "$n" -gt 2 ] && [ "$n" -le "$MAXFD" ] && [ -L "$fd" ] || continue
    [ "$(readlink "$fd" 2>/dev/null)" = "$SELF" ] && continue
    eval "exec $n>&-"
  done
  exec "$@"
}

[ "$#" -gt 0 ] || { echo "ERROR: missing command" >&2; exit 1; }
exec_clean "$@"
