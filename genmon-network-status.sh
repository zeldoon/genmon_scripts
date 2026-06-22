#!/usr/bin/env bash
# Unified xfce4-genmon network status: WAN IP, LAN IP, interface up/down/monitor.
# Replaces the split genmon-show-{up,down}.sh + genmon-vpn-show-ip.sh workflow.

set -u

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/genmon"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/genmon/network-devices.conf"
WAN_CACHE="${CACHE_DIR}/wan-ip"
WAN_TS="${CACHE_DIR}/wan-ip.ts"
WAN_TTL=60

mkdir -p "$CACHE_DIR"

# Avoid shell aliases (e.g. ip --color=auto) breaking parsing.
IP() { command ip "$@"; }

load_config() {
  WAN_TTL=60
  IFACES=()
  if [[ -f "$CONFIG_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [[ -z "$line" ]] && continue
      if [[ "$line" =~ ^WAN_TTL=([0-9]+)$ ]]; then
        WAN_TTL="${BASH_REMATCH[1]}"
        continue
      fi
      IFACES+=("$line")
    done < "$CONFIG_FILE"
  fi
}

should_skip_iface() {
  local name="$1"
  case "$name" in
    lo|docker0|podman0|tailscale0|br-*|veth*|virbr*|vethernet*)
      return 0
      ;;
  esac
  return 1
}

auto_ifaces() {
  local name
  while read -r name _; do
    should_skip_iface "$name" && continue
    case "$name" in
      eth*|enp*|eno*|ens*|wlan*|wlp*|usb*|tun*|tap*|pan*|ppp*|wwan*)
        printf '%s\n' "$name"
        ;;
    esac
  done < <(IP -o link show | awk -F': ' '{print $2}')
}

iface_ipv4() {
  IP -4 -o addr show dev "$1" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1
}

iface_state() {
  IP -o link show dev "$1" 2>/dev/null | awk -F'[:, ]+' '{for (i=1;i<=NF;i++) if ($i=="state") {print $(i+1); exit}}'
}

iface_mode() {
  local mode
  mode="$(iw dev "$1" info 2>/dev/null | awk '/type /{print $2; exit}')"
  [[ -n "$mode" ]] && printf '%s' "$mode" || printf 'ethernet'
}

iface_status_label() {
  local iface="$1" state mode
  state="$(iface_state "$iface")"
  mode="$(iface_mode "$iface")"

  if [[ "$mode" == "monitor" ]]; then
    printf 'MON'
    return
  fi

  case "${state,,}" in
    up|unknown)
      if IP link show dev "$iface" 2>/dev/null | grep -q 'LOWER_UP'; then
        printf 'UP'
      else
        printf 'DOWN'
      fi
      ;;
    *)
      printf 'DOWN'
      ;;
  esac
}

iface_glyph() {
  case "$1" in
    UP) printf '↑' ;;
    DOWN) printf '↓' ;;
    MON) printf '◎' ;;
    *) printf '?' ;;
  esac
}

get_wan_ip() {
  local now ip ts
  now="$(date +%s)"
  if [[ -f "$WAN_CACHE" && -f "$WAN_TS" ]]; then
    ts="$(cat "$WAN_TS" 2>/dev/null || echo 0)"
    if (( now - ts < WAN_TTL )); then
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

copy_cmd() {
  local value="$1"
  if command -v xclip >/dev/null 2>&1; then
    printf "sh -c 'printf %s | xclip -selection clipboard'" "$value"
  fi
}

load_config

if ((${#IFACES[@]} == 0)); then
  mapfile -t IFACES < <(auto_ifaces)
fi

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
  icon="network-vpn-symbolic"
  tooltip_lines+=("" "VPN: active")
else
  icon="network-transmit-receive-symbolic"
  tooltip_lines+=("" "VPN: off")
fi

tooltip="$(printf '%s\n' "${tooltip_lines[@]}")"

printf '<icon>%s</icon>' "$icon"
printf '<txt>%s</txt>' "$panel_txt"
printf '<tool>%s</tool>' "$tooltip"

if copy_cmd="$(copy_cmd "$wan")"; then
  printf '<iconclick>%s</iconclick>' "$copy_cmd"
  printf '<txtclick>%s</txtclick>' "$copy_cmd"
fi
