# genmon_scripts

xfce4-genmon panel scripts for Kali / Raspberry Pi setups. The main widget replaces three older scripts with one compact network monitor you can click to control.

## What it's for

Live network situational awareness on the XFCE panel: public IP, every local IP, and every important interface at a glance — without opening a terminal. Built for field rigs (Pi + phone tether, WiFi, Ethernet, Bluetooth PAN, VPN, monitor mode) where you want status and control in one place.

## What it shows

**Panel (always visible, one line):**

```
74.77.xxx.xxx · 192.168.1.205 · 10.42.0.1 · eth0  hci0  wlan0 · VPN
```

| Part | Meaning |
|------|---------|
| `74.77.xxx.xxx` | WAN / public IP (cached, white) |
| `192.168.1.205` | LAN IP on WiFi (white) |
| `10.42.0.1` | LAN IP on Bluetooth PAN (white) |
| `eth0` | Interface name, **red** = down |
| `hci0` | Interface name, **green** = up |
| `wlan0` | Interface name, **green** = up |
| `VPN` | **green** = active, **red** = off |

Interface names are color-coded: **green** = UP, **red** = DOWN, **orange** = MON (monitor mode). IPs stay uncolored. Every UP interface with an IPv4 address is listed on the panel (not just one “primary” LAN).

**Hover tooltip:** WAN, all LAN lines (with connection labels like SSID or BT profile name), per-interface status/IP/mode, VPN on/off, and click hint.

**Click panel text:** action menu to set any device **UP**, **DOWN**, or **MON** (monitor mode on wireless).

## Features

- **Single panel widget** — replaces `genmon-show-up.sh`, `genmon-show-down.sh`, and `genmon-vpn-show-ip.sh`
- **Auto-detect interfaces** — new USB WiFi, Bluetooth PAN (`hci*`/`bnep*`/`pan*`), VPN (`tun*`/`tap*`), cellular (`wwan*`) appear automatically
- **All LAN IPs on panel** — WiFi, Ethernet, BT PAN, VPN tunnel addresses shown together
- **Color-coded interface names** — no arrow glyphs on the panel line
- **VPN indicator** — colored `VPN` label at the end of the panel
- **WAN IP caching** — configurable TTL; no curl on every poll
- **Rich hover tooltip** — details without cluttering the panel
- **Click-to-control** — set interface state UP / DOWN / MON from a whiptail menu
- **Optional config** — skip noisy interfaces or force-include odd device names
- **Shared library** — `genmon-network-common.sh` keeps status + action menus in sync

## Install

```bash
git clone https://github.com/zeldoon/genmon_scripts.git
cd genmon_scripts
chmod +x genmon-network-*.sh
cp genmon-network-*.sh ~/.local/bin/
mkdir -p ~/.config/genmon
cp network-devices.conf.example ~/.config/genmon/network-devices.conf   # optional
```

In XFCE: add **Generic Monitor** to the panel, set command to:

```
~/.local/bin/genmon-network-status.sh
```

Set update period to **3000** ms (3 seconds). Adjust `GENMON_PLUGIN_ID` in `genmon-network-action.sh` if your genmon plugin name differs (default `genmon-13`; find yours under Panel → Properties → Items, hover the plugin).

**Dependencies:** `ip`, `iw`, `curl`, `whiptail` or `dialog`, `sudo` (passwordless sudo recommended for panel clicks), optional `nmcli`, `airmon-ng`, `notify-send`, `qterminal`.

## Files

| File | Role |
|------|------|
| `genmon-network-status.sh` | Panel output (text + tooltip + click handler) |
| `genmon-network-action.sh` | UP / DOWN / MON menu |
| `genmon-network-common.sh` | Shared discovery + status helpers |
| `network-devices.conf.example` | Optional overrides (skip / include / WAN TTL) |

Legacy scripts (`genmon-show-*.sh`, `genmon-vpn-show-ip.sh`) still work but are superseded by the unified widget.

## Optional config

Interfaces are **auto-detected** each refresh. Edit `~/.config/genmon/network-devices.conf` only when you need overrides:

```ini
# WAN cache seconds (default 60)
WAN_TTL=90

# Hide interfaces (prefix with -)
-pan1

# Force-include devices auto-detect might miss (prefix with +)
+cdc-wdm0
+rmnet0
```

### Phone tether (Bluetooth PAN)

Bluetooth NAP usually shows as `hci0` (and optionally `bnep0`). Connection names (e.g. `rpi5`) appear in the tooltip via NetworkManager. Hide stale PAN profiles if needed:

```ini
-pan1
```

### USB / cellular modem

Add the interface name once; it will be tracked whenever it exists:

```ini
+wwan0
```

If the modem uses an unusual name, add a pattern in `genmon-network-common.sh` inside `genmon_matches_iface_pattern()`:

```bash
cdc*|rmnet*|wwan*
```

## Customization examples

### Change interface colors

Edit `genmon_iface_name_markup()` in `genmon-network-common.sh`:

```bash
genmon_iface_name_markup() {
  local iface="$1" status="$2"
  case "$status" in
    UP)   printf "<span foreground='#2ecc71'>%s</span>" "$iface" ;;
    DOWN) printf "<span foreground='#e74c3c'>%s</span>" "$iface" ;;
    MON)  printf "<span foreground='#f39c12'>%s</span>" "$iface" ;;
    *)    printf '%s' "$iface" ;;
  esac
}
```

### Change panel separators

In `genmon-network-status.sh`, swap ` · ` for ` | ` in the `panel_txt` assembly.

### Shorter WAN cache for roaming setups

In `~/.config/genmon/network-devices.conf`:

```ini
WAN_TTL=30
```

### Match your genmon plugin ID

If click-actions do not refresh the panel, set the plugin name in `genmon-network-action.sh`:

```bash
GENMON_PLUGIN_ID="${GENMON_PLUGIN_ID:-genmon-13}"
```

Find the ID under XFCE Panel properties (hover the genmon item).

## Quick test

```bash
~/.local/bin/genmon-network-status.sh
~/.local/bin/genmon-network-action.sh --menu
```

## License

See [LICENSE](LICENSE).
