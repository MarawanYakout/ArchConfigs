#!/bin/bash

# Create the menu options
chosen=$(echo -e "Performance\nBalanced\nPower-Saver" | rofi -dmenu -i -p "Power Profile")

# Execute the matching command and write the label to a file for i3status
case "$chosen" in
    "Performance") 
        powerprofilesctl set performance
        echo "Perf" > /tmp/power_profile.txt
        ;;
    "Balanced") 
        powerprofilesctl set balanced
        echo "Bal" > /tmp/power_profile.txt
        ;;
    "Power-Saver") 
        powerprofilesctl set power-saver
        echo "Save" > /tmp/power_profile.txt
        ;;
esac

# Force i3status to refresh immediately so you don't have to wait for the next tick
killall -USR1 i3status
