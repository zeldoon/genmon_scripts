# genmon_scripts

xfce4-genmon panel scripts for Kali / Raspberry Pi setups. The main widget replaces three older scripts with one compact network monitor you can click to control.

## What it's for

Live network situational awareness on the XFCE panel: public IP, local IP, and every important interface at a glance — without opening a terminal. Built for field rigs (Pi + phone tether, WiFi, Ethernet, VPN, monitor mode) where you want status and control in one place.

## What it shows

**Panel (always visible, one line):**

```
74.77.226.88 · 192.168.1.66 · pan1↑  wlan0↑  eth0↓
```

| Part | Meaning |
|------|---------|
| `74.77.226.88` | WAN / public IP (cached) |
| `192.168.1.66` | Primary LAN IP |
| `pan1↑` | Interface name + state glyph |
| `wlan0↑` | `↑` up · `↓` down · `◎` monitor |

**Hover tooltip:** full breakdown per interface (status, IPv4, wireless mode), VPN on/off, and click hint.

**Click panel text:** action menu to set any device **UP**, **DOWN**, or **MON** (monitor mode on wireless).

## Features

- **Single panel widget** — replaces `genmon-show-up.sh`, `genmon-show-down.sh`, and `genmon-vpn-show-ip.sh`
- **Auto-detect interfaces** — new USB WiFi, phone PAN (`pan*`), VPN (`tun*`/`tap*`), cellular (`wwan*`) appear automatically
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
-hci0

# Force-include devices auto-detect might miss (prefix with +)
+cdc-wdm0
+rmnet0
```

### Phone tether (Bluetooth PAN)

Most phones expose `pan0` or `pan1` when BT tethering is active — already matched by `pan*` and shows up automatically. If your phone uses a different name:

```ini
+pan2
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

### Change state glyphs

Edit `genmon_iface_glyph()` in `genmon-network-common.sh`:

```bash
genmon_iface_glyph() {
  case "$1" in
    UP)   printf '▲' ;;
    DOWN) printf '▼' ;;
    MON)  printf '◉' ;;
    *)    printf '?' ;;
  esac
}
```

### Change panel separators

In `genmon-network-status.sh`, find the `panel_txt=` lines and swap ` · ` for ` | ` or drop interface summary:

```bash
# WAN + LAN only (hide per-interface glyphs on the panel line)
panel_txt="${wan} · ${lan_ip}"
# remove or comment out: [[ -n "$iface_summary" ]] && panel_txt=...
```

### Prefer phone tether IP as LAN

`pick_lan()` chooses the displayed LAN IP. Put PAN/tun before WiFi by adding at the top of the priority loops:

```bash
for iface in "$@"; do
  case "$iface" in
    pan*) priority+=("$iface") ;;
  esac
done
```

### Colored tooltip (Pango markup)

Genmon supports Pango in `<tool>` text. Example in `genmon-network-status.sh`:

```bash
tooltip_lines+=("  <span foreground='#2ecc71'>wlan0  UP</span>  192.168.1.66  managed")
```

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
