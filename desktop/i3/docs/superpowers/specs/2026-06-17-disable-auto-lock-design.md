# Design Spec: Disable Automatic Screen Locking in i3

## Problem
The user wants to prevent the screen from locking automatically (either due to idle time or system suspend). They want locking to be a purely manual action.

## Current State
- `xss-lock` is configured in `~/.config/i3/config` (line 32) to lock the screen on suspend and when the X screen saver triggers.
- `xset s 3600 5` is configured (line 222) to trigger the screen saver after 1 hour of idle time.
- A manual shortcut exists: `$mod+Shift+x` runs `~/.local/bin/safelock.sh`.

## Proposed Changes
1. **Disable xss-lock**: Comment out the line starting `xss-lock` to stop automatic locking on suspend and idle signals.
2. **Disable X Screen Saver**: Replace or modify the `xset s` line to `xset s off` to ensure the screen saver never triggers.
3. **Disable DPMS (Optional but recommended)**: Add `xset -dpms` to prevent the screen from turning off due to power management, if that's also desired (often associated with "auto-locking" in user's minds).

## Approaches Considered
- **Approach 1 (Selected)**: Comment out `xss-lock` and set `xset s off`. This is the most direct way to achieve "manual only" locking.
- **Approach 2**: Keep `xss-lock` but only for suspend. (Rejected by user, they want "manual only" even for suspend).

## Verification Plan
1. Apply changes to `~/.config/i3/config`.
2. Instruct user to reload i3 (`$mod+Shift+r`).
3. Verify `xss-lock` is no longer running (if possible via shell) or explain how to test.
