#!/usr/bin/env bash
# Unified xfce4-genmon network status: WAN IP, LAN IP, interface up/down/monitor.
# Replaces the split genmon-show-{up,down}.sh + genmon-vpn-show-ip.sh workflow.

set -u

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/genmon"
WAN_CACHE="${CACHE_DIR}/wan-ip"
WAN_TS="${CACHE_DIR}/wan-ip.ts"

mkdir -p "$CACHE_DIR"

COMMON="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/genmon-network-common.sh"
# shellcheck source=genmon-network-common.sh
source "$COMMON"

IP() { genmon_IP "$@"; }

iface_ipv4() {
  IP -4 -o addr show dev "$1" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1
}

iface_mode() { genmon_iface_mode "$1"; }
iface_status_label() { genmon_iface_status_label "$1"; }
iface_glyph() { genmon_iface_glyph "$1"; }

get_wan_ip() {
  local now ip ts ttl="$GENMON_WAN_TTL"
  now="$(date +%s)"
  if [[ -f "$WAN_CACHE" && -f "$WAN_TS" ]]; then
    ts="$(cat "$WAN_TS" 2>/dev/null || echo 0)"
    if (( now - ts < ttl )); then
      cat "$WAN_CACHE"
      return
    fi
  fi

  ip="$(
    curl -fsS --max-time 4 https://api.ipify.org 2>/dev/null \
      || curl -fsS --max-time 4 http://whatismyip.akamai.com/ 2>/dev/null \
      || echo 'offline'
  )"
  printf '%s' "$ip" > "$WAN_CACHE"
  printf '%s' "$now" > "$WAN_TS"
  printf '%s' "$ip"
}

pick_lan() {
  local iface ip status
  local -a priority=()
  for iface in "$@"; do
    case "$iface" in
      tun*|tap*) priority+=("$iface") ;;
    esac
  done
  for iface in "$@"; do
    case "$iface" in
      wlan*|wlp*) priority+=("$iface") ;;
    esac
  done
  for iface in "$@"; do
    case "$iface" in
      eth*|enp*|eno*|ens*|usb*) priority+=("$iface") ;;
    esac
  done
  for iface in "$@"; do
    priority+=("$iface")
  done

  for iface in "${priority[@]}"; do
    status="$(iface_status_label "$iface")"
    [[ "$status" == "DOWN" || "$status" == "MON" ]] && continue
    ip="$(iface_ipv4 "$iface")"
    [[ -n "$ip" ]] || continue
    printf '%s|%s' "$ip" "$iface"
    return 0
  done
  return 1
}

vpn_active() {
  local iface
  for iface in "$@"; do
    [[ "$iface" == tun* || "$iface" == tap* ]] || continue
    [[ "$(iface_status_label "$iface")" != "DOWN" ]] && return 0
  done
  return 1
}

genmon_discover_ifaces
IFACES=("${GENMON_IFACES[@]}")

wan="$(get_wan_ip)"
lan_ip=""
lan_iface=""
if lan_info="$(pick_lan "${IFACES[@]}")"; then
  lan_ip="${lan_info%%|*}"
  lan_iface="${lan_info##*|}"
fi

declare -a up_parts=()
declare -a down_parts=()
declare -a mon_parts=()
tooltip_lines=("Network status" "──────────────" "WAN: ${wan}")

if [[ -n "$lan_ip" ]]; then
  tooltip_lines+=("LAN: ${lan_ip} (${lan_iface})")
else
  tooltip_lines+=("LAN: none")
fi

tooltip_lines+=("" "Interfaces:")

for iface in "${IFACES[@]}"; do
  status="$(iface_status_label "$iface")"
  glyph="$(iface_glyph "$status")"
  ip="$(iface_ipv4 "$iface")"
  mode="$(iface_mode "$iface")"
  [[ -z "$ip" ]] && ip="—"

  tooltip_lines+=("  ${iface}  ${status}  ${ip}  ${mode}")

  case "$status" in
    UP) up_parts+=("${iface}${glyph}") ;;
    DOWN) down_parts+=("${iface}${glyph}") ;;
    MON) mon_parts+=("${iface}${glyph}") ;;
  esac
done

summary_parts=()
((${#up_parts[@]})) && summary_parts+=("${up_parts[*]}")
((${#mon_parts[@]})) && summary_parts+=("${mon_parts[*]}")
((${#down_parts[@]})) && summary_parts+=("${down_parts[*]}")
iface_summary="${summary_parts[*]}"
iface_summary="${iface_summary// /  }"

if [[ -n "$lan_ip" ]]; then
  panel_txt="${wan} · ${lan_ip}"
else
  panel_txt="${wan}"
fi
[[ -n "$iface_summary" ]] && panel_txt="${panel_txt} · ${iface_summary}"

if vpn_active "${IFACES[@]}"; then
  tooltip_lines+=("" "VPN: active")
else
  tooltip_lines+=("" "VPN: off")
fi

tooltip_lines+=("" "Click text: set UP / DOWN / MON")

tooltip="$(printf '%s\n' "${tooltip_lines[@]}")"

printf '<txt>%s</txt>' "$panel_txt"
printf '<tool>%s</tool>' "$tooltip"
printf '<txtclick>%s</txtclick>' "${HOME}/.local/bin/genmon-network-action.sh"
