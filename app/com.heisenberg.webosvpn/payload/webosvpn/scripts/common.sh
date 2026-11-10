#!/bin/sh
# Shared helpers, sourced by the other scripts. Not meant to be run directly.
#
# Environment overrides (used by the tests):
#   WGTV_BASE  state directory        (default /var/lib/webosbrew/webosvpn)
#   WGTV_BIN   directory with binaries (default ../bin next to the scripts)

BASE="${WGTV_BASE:-/var/lib/webosbrew/webosvpn}"
SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
HERE="$(CDPATH= cd -- "$(dirname -- "$SELF")" && pwd)"
BIN="${WGTV_BIN:-$HERE/../bin}"
WG="$BIN/wg"
WGGO="$BIN/wireguard-go"
WGTV="$BIN/wgtv"

IFACE="wgtv0"
CONF="$BASE/conf"
PROFILES="$BASE/profiles"
RUN="$BASE/run"
SETTINGS="$CONF/settings"

PIDFILE="$RUN/wireguard-go.pid"
LOGFILE="$RUN/wireguard-go.log"
STATEFILE="$RUN/state"
DESIRED="$RUN/desired"            # profile id the user wants to be connected to
PREP="$RUN/prep"                  # resolved config for the active profile
ROUTES_APPLIED="$RUN/applied-routes"
ENDPOINT_ROUTES="$RUN/endpoint-routes"
GWFILE="$RUN/original-gateway"
DEVFILE="$RUN/original-dev"
IPV6_STATE_FILE="$RUN/original-ipv6-disabled"
OPERATION_LOCK="$RUN/operation.lock"

KS_CHAIN="WEBOSVPN"
KS_NAT_CHAIN="WEBOSVPN_DNS"

mkdir -p "$RUN" "$CONF" "$PROFILES" 2>/dev/null || true
chmod 700 "$CONF" "$PROFILES" "$RUN" 2>/dev/null || true

log() { echo "$*"; }

# ---- settings (key=value file) ---------------------------------------------

get_setting() { # key default
  v=""
  [ -f "$SETTINGS" ] && v="$(sed -n "s/^$1=//p" "$SETTINGS" | tail -1)"
  if [ -n "$v" ]; then echo "$v"; else echo "$2"; fi
}

set_setting() { # key value
  tmp="$SETTINGS.tmp.$$"
  { [ -f "$SETTINGS" ] && grep -v "^$1=" "$SETTINGS"; echo "$1=$2"; } > "$tmp" || true
  chmod 600 "$tmp"
  mv -f "$tmp" "$SETTINGS"
}

# ---- locking ---------------------------------------------------------------

acquire_lock() {
  if mkdir "$OPERATION_LOCK" 2>/dev/null; then
    echo "$$" > "$OPERATION_LOCK/pid"
    return 0
  fi
  lock_pid="$(cat "$OPERATION_LOCK/pid" 2>/dev/null || true)"
  if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
    echo "ERROR: another operation is running (PID $lock_pid)"
    exit 1
  fi
  rm -rf "$OPERATION_LOCK"
  mkdir "$OPERATION_LOCK"
  echo "$$" > "$OPERATION_LOCK/pid"
}

release_lock() { rm -rf "$OPERATION_LOCK"; }

set_state() { echo "$1" > "$STATEFILE"; }

# ---- DNS resolution of the setting -----------------------------------------

# Prints the resolver list (space separated) that must be used for a profile.
# $1 = profile id
effective_dns() {
  mode="$(get_setting dns_mode profile)"
  case "$mode" in
    mullvad)              echo "10.64.0.1" ;;
    ads)                  echo "100.64.0.1" ;;
    ads_trackers)         echo "100.64.0.3" ;;
    ads_trackers_malware) echo "100.64.0.7" ;;
    custom)
      c="$(get_setting dns_custom '' | tr ',' ' ')"
      [ -n "$c" ] && { echo "$c"; return; }
      tr '\n' ' ' < "$PROFILES/$1/dns" 2>/dev/null | sed 's/ *$//'
      ;;
    *)
      tr '\n' ' ' < "$PROFILES/$1/dns" 2>/dev/null | sed 's/ *$//'
      ;;
  esac
}

# ---- kill switch (firewall) -------------------------------------------------

have_cmd() { command -v "$1" >/dev/null 2>&1; }

ks_available() { have_cmd iptables && iptables -S OUTPUT >/dev/null 2>&1; }

ks_active() {
  have_cmd iptables && iptables -S OUTPUT 2>/dev/null | grep -q -- "-j $KS_CHAIN"
}

# Prints iptables-restore input for the filter table.
# args: endpoints-file lan(0/1) open_dns(0/1) reject_target
ks_filter_rules() {
  eps="$1"; lan="$2"; open_dns="$3"; target="$4"
  echo "*filter"
  echo ":$KS_CHAIN - [0:0]"
  echo "-A $KS_CHAIN -o lo -j ACCEPT"
  echo "-A $KS_CHAIN -o $IFACE -j ACCEPT"
  if [ -s "$eps" ]; then
    while read -r ip port; do
      [ -n "$ip" ] && [ -n "$port" ] || continue
      echo "-A $KS_CHAIN -p udp -d $ip --dport $port -j ACCEPT"
    done < "$eps"
  fi
  echo "-A $KS_CHAIN -p udp --sport 68 --dport 67 -j ACCEPT"
  if [ "$open_dns" = "1" ]; then
    echo "-A $KS_CHAIN -p udp --dport 53 -j ACCEPT"
    echo "-A $KS_CHAIN -p tcp --dport 53 -j ACCEPT"
  else
    # DNS may only travel through the tunnel, even towards the LAN router.
    echo "-A $KS_CHAIN -p udp --dport 53 -j $target"
    echo "-A $KS_CHAIN -p tcp --dport 53 -j $target"
    echo "-A $KS_CHAIN -p tcp --dport 853 -j $target"
  fi
  if [ "$lan" = "1" ]; then
    for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 224.0.0.0/4 255.255.255.255/32; do
      echo "-A $KS_CHAIN -d $net -j ACCEPT"
    done
  fi
  echo "-A $KS_CHAIN -j $target"
  echo "COMMIT"
}

# nat rules that force every DNS query that would leave outside the tunnel to
# the VPN resolver. $1 = resolver ip
ks_nat_rules() {
  echo "*nat"
  echo ":$KS_NAT_CHAIN - [0:0]"
  echo "-A $KS_NAT_CHAIN -o lo -j RETURN"
  echo "-A $KS_NAT_CHAIN -o $IFACE -j RETURN"
  echo "-A $KS_NAT_CHAIN -p udp --dport 53 -j DNAT --to-destination $1"
  echo "-A $KS_NAT_CHAIN -p tcp --dport 53 -j DNAT --to-destination $1"
  echo "COMMIT"
}

ensure_jump() { # table chain-in-table target
  tbl="$1"; from="$2"; to="$3"
  if iptables -t "$tbl" -S "$from" 2>/dev/null | grep -q -- "-j $to\$"; then
    return 0
  fi
  iptables -t "$tbl" -I "$from" 1 -j "$to"
}

reject_target() {
  # REJECT makes apps fail fast; fall back to DROP when the module is missing.
  if iptables -N WEBOSVPN_PROBE 2>/dev/null; then
    if iptables -A WEBOSVPN_PROBE -j REJECT 2>/dev/null; then t=REJECT; else t=DROP; fi
    iptables -F WEBOSVPN_PROBE 2>/dev/null || true
    iptables -X WEBOSVPN_PROBE 2>/dev/null || true
    echo "$t"
  else
    echo DROP
  fi
}

# ks_apply endpoints-file lan open_dns dns_ip
# The chain contents are replaced in one atomic iptables-restore transaction,
# so there is never a moment without the block while it is being updated.
ks_apply() {
  eps="$1"; lan="$2"; open_dns="$3"; dns_ip="$4"
  ks_available || { echo "ERROR: iptables is not available on this TV"; return 1; }
  target="$(reject_target)"

  if have_cmd iptables-restore; then
    ks_filter_rules "$eps" "$lan" "$open_dns" "$target" | iptables-restore --noflush || {
      echo "ERROR: could not load the kill switch rules"; return 1; }
  else
    iptables -N "$KS_CHAIN" 2>/dev/null || true
    ks_filter_rules "$eps" "$lan" "$open_dns" "$target" | while read -r l; do
      case "$l" in -A*) iptables $l || exit 1 ;; esac
    done
  fi
  ensure_jump filter OUTPUT "$KS_CHAIN" || return 1

  # nat: optional, only when the kernel has it and we know a resolver.
  if [ "$open_dns" != "1" ] && [ -n "$dns_ip" ] && iptables -t nat -S OUTPUT >/dev/null 2>&1 \
     && have_cmd iptables-restore; then
    if ks_nat_rules "$dns_ip" | iptables-restore --noflush 2>/dev/null; then
      ensure_jump nat OUTPUT "$KS_NAT_CHAIN" || true
      echo "dns-redirect: active ($dns_ip)"
    else
      echo "WARNING: DNS redirect not available; relying on the block rules"
    fi
  elif [ "$open_dns" != "1" ]; then
    ks_nat_remove
  fi

  # IPv6: nothing may leave except loopback and the tunnel.
  if have_cmd ip6tables && ip6tables -S OUTPUT >/dev/null 2>&1 && have_cmd ip6tables-restore; then
    {
      echo "*filter"
      echo ":$KS_CHAIN - [0:0]"
      echo "-A $KS_CHAIN -o lo -j ACCEPT"
      echo "-A $KS_CHAIN -o $IFACE -j ACCEPT"
      echo "-A $KS_CHAIN -j $target"
      echo "COMMIT"
    } | ip6tables-restore --noflush 2>/dev/null && {
      ip6tables -S OUTPUT 2>/dev/null | grep -q -- "-j $KS_CHAIN\$" || ip6tables -I OUTPUT 1 -j "$KS_CHAIN" 2>/dev/null || true
    }
  fi
  echo "kill-switch: active"
}

ks_nat_remove() {
  have_cmd iptables || return 0
  while iptables -t nat -D OUTPUT -j "$KS_NAT_CHAIN" 2>/dev/null; do :; done
  iptables -t nat -F "$KS_NAT_CHAIN" 2>/dev/null || true
  iptables -t nat -X "$KS_NAT_CHAIN" 2>/dev/null || true
}

ks_remove() {
  have_cmd iptables || return 0
  while iptables -D OUTPUT -j "$KS_CHAIN" 2>/dev/null; do :; done
  iptables -F "$KS_CHAIN" 2>/dev/null || true
  iptables -X "$KS_CHAIN" 2>/dev/null || true
  ks_nat_remove
  if have_cmd ip6tables; then
    while ip6tables -D OUTPUT -j "$KS_CHAIN" 2>/dev/null; do :; done
    ip6tables -F "$KS_CHAIN" 2>/dev/null || true
    ip6tables -X "$KS_CHAIN" 2>/dev/null || true
  fi
}

# ---- DNS (resolv.conf) -----------------------------------------------------

RESOLV_REAL=""
resolv_target() {
  if have_cmd readlink && [ -L /etc/resolv.conf ]; then
    RESOLV_REAL="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
  fi
  [ -n "$RESOLV_REAL" ] || RESOLV_REAL="${WGTV_RESOLV:-/etc/resolv.conf}"
  [ -z "${WGTV_RESOLV:-}" ] || RESOLV_REAL="$WGTV_RESOLV"
}

dns_apply() { # "ip ip ..."
  [ -n "$1" ] || return 0
  resolv_target
  dns_restore quiet
  mkdir -p "$RUN"
  [ -e "$RESOLV_REAL" ] || : > "$RESOLV_REAL" 2>/dev/null || true
  cp -p "$RESOLV_REAL" "$RUN/resolv.orig" 2>/dev/null || : > "$RUN/resolv.orig"
  echo "$RESOLV_REAL" > "$RUN/resolv.target"
  {
    echo "# managed by WebOS VPN - restored when the VPN stops"
    for d in $1; do echo "nameserver $d"; done
    echo "options timeout:2 attempts:2"
  } > "$RUN/resolv.vpn"
  chmod 644 "$RUN/resolv.vpn"

  if mount -o bind "$RUN/resolv.vpn" "$RESOLV_REAL" 2>/dev/null; then
    mount -o remount,ro,bind "$RESOLV_REAL" 2>/dev/null || true
    echo bind > "$RUN/resolv.method"
  elif cat "$RUN/resolv.vpn" > "$RESOLV_REAL" 2>/dev/null; then
    echo copy > "$RUN/resolv.method"
  else
    echo "WARNING: could not change $RESOLV_REAL"
    rm -f "$RUN/resolv.method"
    return 1
  fi
  echo "dns: $1 (via $(cat "$RUN/resolv.method"))"
}

dns_restore() {
  [ -f "$RUN/resolv.method" ] || return 0
  tgt="$(cat "$RUN/resolv.target" 2>/dev/null)"
  method="$(cat "$RUN/resolv.method")"
  if [ "$method" = "bind" ]; then
    umount "$tgt" 2>/dev/null || umount -l "$tgt" 2>/dev/null || true
  elif [ -f "$RUN/resolv.orig" ]; then
    cat "$RUN/resolv.orig" > "$tgt" 2>/dev/null || true
  fi
  rm -f "$RUN/resolv.method" "$RUN/resolv.target"
  [ "${1:-}" = "quiet" ] || echo "dns: original resolvers restored"
}

# ---- tunnel helpers --------------------------------------------------------

tunnel_down() {
  if [ -f "$ROUTES_APPLIED" ]; then
    while read -r r; do
      [ -n "$r" ] && ip route del "$r" dev "$IFACE" 2>/dev/null || true
    done < "$ROUTES_APPLIED"
    rm -f "$ROUTES_APPLIED"
  fi
  if [ -f "$ENDPOINT_ROUTES" ]; then
    while read -r h; do
      [ -n "$h" ] && ip route del "$h" 2>/dev/null || true
    done < "$ENDPOINT_ROUTES"
    rm -f "$ENDPOINT_ROUTES"
  fi
  ip link del "$IFACE" 2>/dev/null || true
  if [ -f "$PIDFILE" ]; then
    old="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [ -n "$old" ]; then
      kill "$old" 2>/dev/null || true
      # Let the old daemon finish before a new one is started: a late exit
      # could otherwise remove the interface of the new tunnel.
      w=0
      while kill -0 "$old" 2>/dev/null && [ "$w" -lt 5 ]; do sleep 1; w=$((w + 1)); done
      kill -9 "$old" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
  fi
  killall wireguard-go 2>/dev/null || true
  ip link del "$IFACE" 2>/dev/null || true
  rm -f "/var/run/wireguard/$IFACE.sock"
}

ipv6_restore() {
  if [ -f "$DEVFILE" ] && [ -f "$IPV6_STATE_FILE" ]; then
    d="$(cat "$DEVFILE")"; v="$(cat "$IPV6_STATE_FILE")"
    if [ -n "$d" ] && [ -n "$v" ]; then
      sysctl -w "net.ipv6.conf.$d.disable_ipv6=$v" >/dev/null 2>&1 || echo "WARNING: could not restore IPv6 on $d"
    fi
    rm -f "$IPV6_STATE_FILE"
  fi
}
