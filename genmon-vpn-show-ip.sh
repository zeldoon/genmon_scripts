#! /bin/bash

iconUNLOCK=<insert location of icon you want to use ex. /usr/share/icons/foo.png>
iconVPN=<insert location of icon you want to use ex. /usr/share/icons/foo.png>

checkVPN() {
hazVPN=$(ip -brief addr | grep -i -E 'tun' | awk 'BEGIN {OFS="::"} {print toupper($1)}' )
WAN=$(curl -s http://whatismyip.akamai.com/ )

    if [[ "$hazVPN" == TUN* ]]; then
        printf "<img>${iconVPN}</img>"
        printf "<txt>WAN  ${WAN}</txt>"
        printf "<tool>VPN IS ACTIVE</tool>"
    elif [[ "$hazVPN" != TUN* ]]; then
        printf "<img>${iconUNLOCK}</img>"
        printf "<txt>WAN  ${WAN}</txt>"
        printf "<tool>VPN OFF!!!</tool>"
    fi
}

checkVPN