# Shared interface discovery for genmon network scripts.
# Auto-detects interfaces on every run; config is optional (TTL, skip, force-include).

genmon_IP() { command ip "$@"; }

genmon_should_skip_iface() {
  case "$1" in
    lo|docker0|podman0|tailscale0|br-*|veth*|virbr*|vethernet*)
      return 0
      ;;
  esac
  return 1
}

genmon_matches_iface_pattern() {
  case "$1" in
    eth*|enp*|eno*|ens*|wlan*|wlp*|wlx*|usb*|tun*|tap*|pan*|bnep*|hci*|ppp*|wwan*)
      return 0
      ;;
  esac
  return 1
}

genmon_load_settings() {
  local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/genmon/network-devices.conf"
  GENMON_WAN_TTL=60
  GENMON_SKIP_IFACES=()
  GENMON_EXTRA_IFACES=()

  [[ -f "$config_file" ]] || return 0

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^WAN_TTL=([0-9]+)$ ]]; then
      GENMON_WAN_TTL="${BASH_REMATCH[1]}"
      continue
    fi
    if [[ "$line" == -* ]]; then
      line="${line#-}"
      line="${line#"${line%%[![:space:]]*}"}"
      [[ -n "$line" ]] && GENMON_SKIP_IFACES+=("$line")
      continue
    fi
    if [[ "$line" == +* ]]; then
      line="${line#+}"
      line="${line#"${line%%[![:space:]]*}"}"
      [[ -n "$line" ]] && GENMON_EXTRA_IFACES+=("$line")
      continue
    fi

    # Legacy plain names: treat as force-include for backward compatibility.
    GENMON_EXTRA_IFACES+=("$line")
  done < "$config_file"
}

genmon_iface_skipped() {
  local name="$1" skip
  for skip in "${GENMON_SKIP_IFACES[@]}"; do
    [[ "$name" == "$skip" ]] && return 0
  done
  return 1
}

genmon_is_wireless() {
  iw dev "$1" info &>/dev/null
}

genmon_iface_link_state() {
  genmon_IP -o link show dev "$1" 2>/dev/null \
    | awk -F'[:, ]+' '{for (i=1;i<=NF;i++) if ($i=="state") {print $(i+1); exit}}'
}

genmon_iface_mode() {
  local iface="$1" mode
  case "$iface" in
    bnep*|hci*) printf 'bt-pan'; return ;;
    pan*) printf 'bt-pan'; return ;;
  esac
  mode="$(iw dev "$iface" info 2>/dev/null | awk '/type /{print $2; exit}')"
  [[ -n "$mode" ]] && printf '%s' "$mode" || printf 'ethernet'
}

genmon_iface_status_label() {
  local iface="$1" state mode
  state="$(genmon_iface_link_state "$iface")"
  mode="$(genmon_iface_mode "$iface")"

  if [[ "$mode" == "monitor" ]]; then
    printf 'MON'
    return
  fi

  case "${state,,}" in
    up|unknown)
      if genmon_IP link show dev "$iface" 2>/dev/null | grep -q 'LOWER_UP'; then
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

genmon_iface_glyph() {
  case "$1" in
    UP) printf '↑' ;;
    DOWN) printf '↓' ;;
    MON) printf '◎' ;;
    *) printf '?' ;;
  esac
}

# True when a VPN tunnel or NM VPN connection is active.
genmon_vpn_active() {
  local iface
  while read -r iface _; do
    case "$iface" in
      tun*|tap*)
        genmon_IP link show dev "$iface" 2>/dev/null | grep -q 'LOWER_UP' && return 0
        ;;
    esac
  done < <(genmon_IP -o link show 2>/dev/null | awk -F': ' '{print $2}')

  if command -v nmcli >/dev/null 2>&1; then
    nmcli -t -f TYPE,STATE connection show --active 2>/dev/null \
      | grep -qE '^vpn:(activated|activating)$' && return 0
  fi
  return 1
}

genmon_vpn_label() {
  genmon_vpn_active || return 1
  if command -v nmcli >/dev/null 2>&1; then
    nmcli -t -f NAME,TYPE connection show --active 2>/dev/null \
      | awk -F: '$2=="vpn"{print $1; exit}'
  fi
}

genmon_vpn_panel_markup() {
  if genmon_vpn_active; then
    printf "<span foreground='#2ecc71'>VPN</span>"
  else
    printf "<span foreground='#e74c3c'>VPN</span>"
  fi
}

# Pango markup for xfce4-genmon panel (green up / red down).
genmon_iface_glyph_markup() {
  case "$1" in
    UP) printf "<span foreground='#2ecc71'>↑</span>" ;;
    DOWN) printf "<span foreground='#e74c3c'>↓</span>" ;;
    MON) printf "<span foreground='#f39c12'>◎</span>" ;;
    *) printf '?' ;;
  esac
}

# Panel: color the interface name by status (IPs stay default/white).
genmon_iface_name_markup() {
  local iface="$1" status="$2"
  case "$status" in
    UP) printf "<span foreground='#2ecc71'>%s</span>" "$iface" ;;
    DOWN) printf "<span foreground='#e74c3c'>%s</span>" "$iface" ;;
    MON) printf "<span foreground='#f39c12'>%s</span>" "$iface" ;;
    *) printf '%s' "$iface" ;;
  esac
}

# WiFi SSID / NM connection name (e.g. LEYDEN, rpi5) instead of raw iface.
genmon_nm_device() {
  local iface="$1" master
  case "$iface" in
    bnep*)
      master="$(genmon_IP -o link show dev "$iface" 2>/dev/null \
        | awk '{for (i=1;i<=NF;i++) if ($i=="master") {print $(i+1); exit}}')"
      [[ -n "$master" ]] && iface="$master"
      ;;
  esac
  printf '%s' "$iface"
}

genmon_iface_display_name() {
  local iface="$1" nm_dev name

  nm_dev="$(genmon_nm_device "$iface")"

  if command -v nmcli >/dev/null 2>&1; then
    case "$iface" in
      wlan*|wlp*)
        name="$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null \
          | awk -F: '$1=="yes" && $2!="" && $2!="--" {print $2; exit}')"
        [[ -z "$name" ]] && name="$(iw dev "$iface" link 2>/dev/null \
          | awk '/SSID:/{print $2; exit}')"
        [[ -n "$name" ]] && { printf '%s' "$name"; return; }
        ;;
      hci*|bnep*|pan*)
        name="$(nmcli -t -f GENERAL.CONNECTION device show "$nm_dev" 2>/dev/null \
          | awk -F: '/^GENERAL.CONNECTION:/{print $2; exit}')"
        [[ -n "$name" && "$name" != "--" ]] && { printf '%s' "$name"; return; }
        ;;
      eth*|enp*|eno*|ens*|usb*)
        name="$(nmcli -t -f GENERAL.CONNECTION device show "$nm_dev" 2>/dev/null \
          | awk -F: '/^GENERAL.CONNECTION:/{print $2; exit}')"
        [[ -n "$name" && "$name" != "--" ]] && { printf '%s' "$name"; return; }
        ;;
    esac
  fi

  printf '%s' "$iface"
}

# bnep slave is redundant when parent hci NAP is already listed.
genmon_hide_from_panel_summary() {
  local iface="$1"
  [[ "$iface" != bnep* ]] && return 1
  local other master nm_master
  master="$(genmon_nm_device "$iface")"
  for other in "${GENMON_IFACES[@]}"; do
    [[ "$other" == "$iface" ]] && continue
    [[ "$other" == "$master" ]] && return 0
    nm_master="$(genmon_nm_device "$other")"
    [[ "$nm_master" == "$master" ]] && return 0
  done
  return 1
}

genmon_discover_ifaces() {
  genmon_load_settings
  GENMON_IFACES=()

  local -A seen=()
  local name

  while read -r name _; do
    genmon_should_skip_iface "$name" && continue
    genmon_iface_skipped "$name" && continue
    genmon_matches_iface_pattern "$name" || continue
    seen["$name"]=1
    GENMON_IFACES+=("$name")
  done < <(genmon_IP -o link show | awk -F': ' '{print $2}')

  for name in "${GENMON_EXTRA_IFACES[@]}"; do
    [[ -n "${seen[$name]:-}" ]] && continue
    genmon_should_skip_iface "$name" && continue
    genmon_iface_skipped "$name" && continue
    genmon_IP link show dev "$name" &>/dev/null || continue
    seen["$name"]=1
    GENMON_IFACES+=("$name")
  done

  if ((${#GENMON_IFACES[@]} > 1)); then
    local IFS=$'\n'
    GENMON_IFACES=($(printf '%s\n' "${GENMON_IFACES[@]}" | sort -V))
  fi

  export GENMON_IFACES
}