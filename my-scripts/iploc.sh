#!/bin/bash
while true; do
    RESULT=$(curl -s --max-time 5 "https://ipapi.co/json/")
    if [ $? -eq 0 ] && [ -n "$RESULT" ]; then
        IP=$(echo "$RESULT" | grep -oP '"ip":\s*"\K[^"]+')
        CITY=$(echo "$RESULT" | grep -oP '"city":\s*"\K[^"]+')
        COUNTRY=$(echo "$RESULT" | grep -oP '"country_name":\s*"\K[^"]+')
        echo "$IP ($CITY, $COUNTRY)" > /tmp/iploc.txt
    else
        echo "Offline" > /tmp/iploc.txt
    fi
    sleep 180
done
