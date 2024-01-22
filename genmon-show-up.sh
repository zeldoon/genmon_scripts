#! /bin/bash

iconUP=<insert location of icon you want to use ex. /usr/share/icons/foo.png>
iconPHONEup=<insert location of icon you want to use ex. /usr/share/icons/foo.png>


sortDEVICES() {
    getUPDEVS=$(ip -brief addr | grep -i -E "up|usb" | awk 'BEGIN {OFS="  "} {ORS="  "} {sub(/\/.*/,""); print toupper($1),$3}')

    printf "<img>${iconUP}</img>"
    printf "<txt>${getUPDEVS}</txt>"
    printf "<tool>DEVICE UP</tool>"
}

hazPHONE() {
phone=$(ip -brief addr | grep -E 'usb' | awk 'BEGIN {ORS="  "} {print toupper($1),$3}')

if [[ "$phone" == USB* ]] ; then
    printf "<img>${iconPHONEup}</img>"
    printf "<txt>${phone}</txt>"
    printf "<tool>PHONE TETHER ON</tool>"
fi
}

sortDEVICES
hazPHONE