# Shared interface discovery for genmon network scripts.
# Auto-detects interfaces on every run; config is optional (TTL, skip, force-include).

genmon_IP() { command ip "$@"; }

genmon_should_skip_iface() {
  case "$1" in
    lo|docker0|podman0|tailscale0|br-*|veth*|virbr*|vethernet*|hci*)
      return 0
      ;;
  esac
  return 1
}

genmon_matches_iface_pattern() {
  case "$1" in
    eth*|enp*|eno*|ens*|wlan*|wlp*|wlx*|usb*|tun*|tap*|pan*|ppp*|wwan*)
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
  local mode
  mode="$(iw dev "$1" info 2>/dev/null | awk '/type /{print $2; exit}')"
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
}
