#!/bin/sh
# Usage: settings.sh get | set <key> <value>
# A change is applied immediately to a running connection (firewall + DNS),
# without restarting the tunnel.
. "$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)/common.sh"

valid_ip_list() { # "a,b" or "a b"
  [ -n "$1" ] || return 1
  for ip in $(echo "$1" | tr ',' ' '); do
    echo "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
    for o in $(echo "$ip" | tr '.' ' '); do [ "$o" -le 255 ] || return 1; done
  done
}

apply_live() {
  id="$(cat "$DESIRED" 2>/dev/null || true)"
  [ -n "$id" ] || return 0
  [ -f "$PROFILES/$id/wg.conf" ] || return 0
  ip link show "$IFACE" >/dev/null 2>&1 || return 0
  KS="$(get_setting killswitch 1)"; LAN="$(get_setting lan 1)"
  DNS_LIST="$(effective_dns "$id")"; DNS_FIRST="${DNS_LIST%% *}"
  if [ "$KS" = "1" ]; then
    ks_apply "$PREP/endpoints" "$LAN" 0 "$DNS_FIRST" || return 1
  else
    ks_remove
  fi
  if [ -n "$DNS_LIST" ]; then dns_apply "$DNS_LIST" || true; else dns_restore quiet; fi
}

print_all() {
  echo "killswitch=$(get_setting killswitch 1)"
  echo "lan=$(get_setting lan 1)"
  echo "dns_mode=$(get_setting dns_mode profile)"
  echo "dns_custom=$(get_setting dns_custom '')"
  echo "last_profile=$(get_setting last_profile '')"
}

case "${1:-get}" in
  get) print_all ;;
  set)
    key="${2:-}"; val="${3:-}"
    case "$key" in
      killswitch|lan) case "$val" in 0|1) ;; *) echo "ERROR: value must be 0 or 1"; exit 2 ;; esac ;;
      dns_mode) case "$val" in profile|mullvad|ads|ads_trackers|ads_trackers_malware|custom) ;; *) echo "ERROR: invalid dns mode"; exit 2 ;; esac ;;
      dns_custom) valid_ip_list "$val" || { echo "ERROR: invalid DNS address list"; exit 2; } ; val="$(echo "$val" | tr ' ' ',')" ;;
      *) echo "ERROR: unknown setting"; exit 2 ;;
    esac
    acquire_lock
    trap 'rc=$?; release_lock; exit "$rc"' EXIT HUP INT TERM
    set_setting "$key" "$val"
    apply_live || echo "WARNING: could not apply the change to the running connection"
    echo "OK: $key=$val"
    ;;
  *) echo "usage: settings.sh get|set <key> <value>"; exit 2 ;;
esac
