#!/usr/bin/env bash
# Set interface state (UP / DOWN / MON) from the genmon panel action menu.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENMON_PLUGIN_ID="${GENMON_PLUGIN_ID:-genmon-13}"
DISPLAY="${DISPLAY:-:0}"
export DISPLAY
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

# shellcheck source=genmon-network-common.sh
source "${SCRIPT_DIR}/genmon-network-common.sh"

IP() { genmon_IP "$@"; }

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send -a genmon-network "Network" "$1"
}

refresh_genmon() {
  command -v xfce4-panel >/dev/null 2>&1 \
    && xfce4-panel --plugin-event="${GENMON_PLUGIN_ID}:refresh:bool:true" 2>/dev/null || true
  rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/genmon/wan-ip" "${XDG_CACHE_HOME:-$HOME/.cache}/genmon/wan-ip.ts" 2>/dev/null || true
}

menu_runner() {
  if [[ -t 0 && -t 1 ]] && command -v whiptail >/dev/null 2>&1; then
    printf '%s' whiptail
  elif command -v dialog >/dev/null 2>&1; then
    printf '%s' dialog
  fi
}

state_label() {
  case "${1,,}" in
    up) printf 'UP' ;;
    down) printf 'DOWN' ;;
    mon|monitor) printf 'MON' ;;
    *) printf '%s' "$1" ;;
  esac
}

set_iface_down() {
  local iface="$1"
  if command -v nmcli >/dev/null 2>&1; then
    nmcli device disconnect "$iface" 2>/dev/null || true
  fi
  sudo -n IP link set "$iface" down 2>/dev/null \
    || sudo IP link set "$iface" down || return 1
}

set_iface_managed() {
  local iface="$1"
  genmon_is_wireless "$iface" || return 0
  sudo -n IP link set "$iface" down 2>/dev/null || sudo IP link set "$iface" down || true
  sudo -n iw dev "$iface" set type managed 2>/dev/null \
    || sudo iw dev "$iface" set type managed || return 1
}

set_iface_state() {
  local iface="$1" target
  target="$(state_label "$2")"

  case "$target" in
    UP)
      if [[ "$(genmon_iface_status_label "$iface")" == "MON" ]]; then
        set_iface_managed "$iface" || { notify "Failed to restore managed mode on $iface"; return 1; }
      fi
      sudo -n IP link set "$iface" up 2>/dev/null \
        || sudo IP link set "$iface" up || { notify "Failed to set $iface UP"; return 1; }
      if command -v nmcli >/dev/null 2>&1; then
        nmcli device set "$iface" managed yes 2>/dev/null || true
        nmcli device connect "$iface" 2>/dev/null || true
      fi
      notify "$iface → UP"
      ;;
    DOWN)
      set_iface_down "$iface" || { notify "Failed to set $iface DOWN"; return 1; }
      notify "$iface → DOWN"
      ;;
    MON)
      genmon_is_wireless "$iface" || { notify "MON only applies to wireless ($iface)"; return 1; }
      if command -v nmcli >/dev/null 2>&1; then
        nmcli device disconnect "$iface" 2>/dev/null || true
        nmcli device set "$iface" managed no 2>/dev/null || true
      fi
      if command -v airmon-ng >/dev/null 2>&1; then
        sudo -n airmon-ng check kill >/dev/null 2>&1 || sudo airmon-ng check kill >/dev/null 2>&1 || true
      fi
      sudo -n IP link set "$iface" down 2>/dev/null || sudo IP link set "$iface" down || true
      sudo -n iw dev "$iface" set type monitor 2>/dev/null \
        || sudo iw dev "$iface" set type monitor || { notify "Failed to set $iface MON"; return 1; }
      sudo -n IP link set "$iface" up 2>/dev/null || sudo IP link set "$iface" up || true
      notify "$iface → MON"
      ;;
    *)
      notify "Unknown state: $2"
      return 1
      ;;
  esac

  refresh_genmon
}

run_menu() {
  local menu_cmd
  menu_cmd="$(menu_runner)" || { notify "Install whiptail or dialog for the network menu."; return 1; }

  genmon_discover_ifaces
  ((${#GENMON_IFACES[@]})) || { notify "No interfaces found."; return 1; }

  local -a iface_items=() iface current ip mode
  for iface in "${GENMON_IFACES[@]}"; do
    current="$(genmon_iface_status_label "$iface")"
    ip="$(genmon_IP -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
    mode="$(genmon_iface_mode "$iface")"
    [[ -z "$ip" ]] && ip="no-ip"
    iface_items+=("$iface" "${current}  ${ip}  ${mode}")
  done

  local pick
  pick="$("$menu_cmd" --stdout --title "Network device" --menu "Select interface" 20 68 12 "${iface_items[@]}" 2>/dev/null)" || return 0
  [[ -n "$pick" ]] || return 0

  current="$(genmon_iface_status_label "$pick")"
  local -a state_items=(
    up "UP — bring link up"
    down "DOWN — bring link down"
  )
  if genmon_is_wireless "$pick"; then
    state_items+=(mon "MON — monitor mode")
  fi

  local tag desc
  for ((i = 0; i < ${#state_items[@]}; i += 2)); do
    tag="${state_items[i]}"
    desc="${state_items[i + 1]}"
    if [[ "$(state_label "$tag")" == "$current" ]]; then
      state_items[i + 1]="${desc} (current)"
    fi
  done

  local choice
  choice="$("$menu_cmd" --stdout --title "$pick" --menu "Set state (now: ${current})" 14 60 6 "${state_items[@]}" 2>/dev/null)" || return 0
  [[ -n "$choice" ]] || return 0

  if [[ "$(state_label "$choice")" == "$current" ]]; then
    notify "$pick already ${current}"
    return 0
  fi

  set_iface_state "$pick" "$choice"
}

launch_terminal_menu() {
  local term="" self="${BASH_SOURCE[0]}"
  for candidate in qterminal xfce4-terminal xterm; do
    command -v "$candidate" >/dev/null 2>&1 && { term="$candidate"; break; }
  done
  [[ -n "$term" ]] || { notify "No terminal found for network menu."; return 1; }

  case "$term" in
    qterminal) "$term" -e bash -lc "\"$self\" --menu; read -rp 'Press Enter to close...'" ;;
    xfce4-terminal) "$term" --hold -e bash -lc "\"$self\" --menu" ;;
    *) "$term" -e bash -lc "\"$self\" --menu; read -rp 'Press Enter to close...'" ;;
  esac
}

main() {
  if [[ "${1:-}" == "--menu" ]]; then
    run_menu
    return
  fi

  if [[ -t 0 && -t 1 ]]; then
    run_menu
  else
    launch_terminal_menu
  fi
}

main "$@"
