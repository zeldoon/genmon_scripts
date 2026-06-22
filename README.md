# genmon_scripts
Some genmon scripts for xfce4 that I find useful on kali

## Recommended: unified script

`genmon-network-status.sh` replaces the three older scripts with one panel widget that shows:

- **WAN IP** (cached, click to copy)
- **LAN IP** (primary active interface)
- **Per-interface status**: `↑` up, `↓` down, `◎` monitor mode
- **Tooltip** with full interface list, IPv4, and wireless mode
- **VPN icon** when a `tun`/`tap` interface is active

### Install

```bash
cp genmon-network-status.sh ~/.local/bin/
chmod +x ~/.local/bin/genmon-network-status.sh
mkdir -p ~/.config/genmon
```

Point your xfce4-genmon plugin at `~/.local/bin/genmon-network-status.sh` and set update period to ~3000ms.

### Optional config

`~/.config/genmon/network-devices.conf`:

```
# WAN_TTL=60
eth0
wlan0
wlan1
pan1
```

Leave the file empty (or comment all interfaces) to auto-detect network devices.

## Legacy scripts

These still work but are superseded by `genmon-network-status.sh`:

- `genmon-show-down.sh` — interfaces that are down
- `genmon-show-up.sh` — interfaces that are up + local IPs
- `genmon-vpn-show-ip.sh` — WAN IP + VPN on/off icon

## Notes

Genmon works best with compact panel output and richer detail in the tooltip. The unified script follows that pattern and caches WAN lookups so it does not curl on every 1s poll.
