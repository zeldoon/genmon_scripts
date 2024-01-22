#! /bin/bash

iconDOWN=<insert location of icon you want to use ex. /usr/share/icons/foo.png>

checkDOWN() {
    getDOWNdevs=$(ip -brief addr | grep -E 'DOWN' | awk 'BEGIN {ORS="  "} {print toupper($1)}')

        printf "<img>${iconDOWN}</img>"
        printf "<txt>${getDOWNdevs}</txt>"
        printf "<tool>DEVICE DOWN</tool>"
}

checkDOWN