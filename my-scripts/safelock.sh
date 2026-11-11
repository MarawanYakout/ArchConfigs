#!/bin/bash

# 1. Force keyboard layout to US English before locking
setxkbmap us

# 2. Trigger i3lock in the foreground (-n) so xss-lock can track it
i3lock -n -i ~/Pictures/background/1380347.png

# 3. Restore your dual layout and Alt+Shift toggle after unlocking
setxkbmap -layout us,ara -option grp:alt_shift_toggle
