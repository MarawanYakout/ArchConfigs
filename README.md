# ArchConfigs

> **Note:** on my machine every file here is a link to the real config.

One place for all the configs on my Arch machine.

Everything here is a **link** (a shortcut), not a copy. Each link points to the real file in its normal place.
- Edit a file here and the real one changes too, because it is the same file.
- Deleting a link here only removes the shortcut. The real file stays.
- If a program moves or deletes its config, that link breaks. Find broken links with: `find ~/ArchConfigs -xtype l`

**[essentials.md](essentials.md)** lists every program I installed, grouped by type, with a tag showing how much I use it:
(Used Often), (Barely Used), (Recently Unused), (Not Used). Use it to clean up the system or to reinstall on a new machine.

---

## terminal/

| Link | Points to | What it does |
|---|---|---|
| `alacritty/` | `~/.config/alacritty` | Terminal look and keys: transparency, colors, keybindings |
| `zshrc` | `~/.zshrc` | Shell setup: history, aliases, PATH, starts atuin and zoxide (`cd` = zoxide) |
| `bashrc` | `~/.bashrc` | Bash setup (backup shell) |
| `bash_profile` | `~/.bash_profile` | Runs when bash logs in, loads bashrc |
| `profile` | `~/.profile` | Adds `~/.local/bin` to PATH at login |
| `atuin/` | `~/.config/atuin` | Shell history search settings (Ctrl+R) |
| `htop/` | `~/.config/htop` | Process viewer layout |
| `gitconfig` | `~/.gitconfig` | Git name, email and settings |
| `git-ignore` | `~/.config/git/ignore` | Files git ignores in every repo |

## editors/

| Link | Points to | What it does |
|---|---|---|
| `nvim/` | `~/.config/nvim` | Neovim config (based on kickstart.nvim, own plugins in `lua/custom`) |
| `doom-emacs/` | `~/.config/doom` | Doom Emacs config: `init.el` (modules), `config.el` (settings), `packages.el` (extra packages), `wheelhouse.el` (AI agent setup) |
| `vimrc` | `~/.vimrc` | Plain vim: system clipboard and syntax colors |
| `sublime-text/` | `~/.config/sublime-text/Packages/User` | Sublime settings and keybindings |

Doom Emacs itself lives in `~/.config/emacs`. It isn't linked because it's the installed program, not my settings.

## desktop/

| Link | Points to | What it does |
|---|---|---|
| `i3/` | `~/.config/i3` | Window manager: keybindings, startup programs, bar (`i3status.conf` lives here too) |
| `picom/` | `~/.config/picom` | Transparency, shadows, fading |
| `rofi/` | `~/.config/rofi` | App launcher look, plus the Tor and iPhone toggle scripts |
| `dunst/` | `~/.config/dunst` | Notification popup style |
| `flameshot/` | `~/.config/flameshot` | Screenshot tool settings |
| `gtk-3.0/` | `~/.config/gtk-3.0` | Theme, icons and font for GTK apps |
| `autostart/` | `~/.config/autostart` | Apps that start at login (Handy) |
| `mimeapps.list` | `~/.config/mimeapps.list` | Which app opens which file type |
| `xprofile` | `~/.xprofile` | Settings loaded when X starts (terminal, GPU video, GTK fix) |
| `fehbg` | `~/.fehbg` | Sets the current wallpaper |
| `app-launchers/` | `~/.local/share/applications` | My own menu entries in rofi (toggles, Local LLM, VMs, AppImages) |

## apps/

| Link | Points to | What it does |
|---|---|---|
| `appa/` | `~/.config/appa` | Rules for the AI tool-call guard |
| `iamb/` | `~/.config/iamb` | Terminal Matrix chat settings |
| `screen-recorder/` | `~/.config/screen-recorder` | Last used recorder options (audio, quality) |
| `handy-settings.json` | `~/.local/share/com.pais.handy/settings_store.json` | Voice dictation settings (hotkey, model) |
| `local-llm/` | `~/.config/local-llm/*` | Local LLM: active model, API providers, MCP servers, tool guidance. **The `secrets/` folder is left out on purpose.** |

## my-scripts/

My own scripts from `~/.local/bin`. Downloaded programs in that folder (claude, agy, uv, adb...) are left out.

| Script | What it does |
|---|---|
| `animated-wallpaper.sh` | Pick or stop a moving wallpaper (GIF or video) |
| `wallpaper-menu.sh` | Pick a still wallpaper from a menu with thumbnails |
| `battery-monitor.sh` | Writes the battery % for the bar (the firmware's own number is wrong) |
| `gpu-monitor.sh` / `gpu-monitor-toggle.sh` | Shows GPU usage in the bar / turns that on or off |
| `status_feeder.sh` | Old GPU usage feeder for the bar |
| `netspeed.sh` | Shows Wi-Fi up/down speed in the bar |
| `sharemon.sh` | Shows Ethernet sharing traffic in the bar |
| `iploc.sh` / `iploc-toggle.sh` | Shows public IP and location in the bar / turns that on or off |
| `torcheck.sh` | Shows Tor ON/OFF in the bar |
| `lang-monitor.sh` | Shows keyboard language in the bar |
| `powermenu.sh` | Menu: Performance / Balanced / Power-Saver |
| `cpu-boost-toggle.sh` | Turns CPU boost on/off on battery |
| `toggle-gpu.sh` | Switches the NVIDIA GPU between Linux and VM passthrough |
| `wifi-menu.sh` | Wi-Fi picker menu |
| `iphone-net-toggle` | Turns iPhone USB internet on/off |
| `ssh-toggle.sh` | Turns the SSH server on/off |
| `syncthing-toggle.sh` | Turns Syncthing on/off |
| `safelock.sh` | Switches the keyboard to English, then locks the screen |
| `winpos.sh` | Moves the floating window to a corner or the center (`Super+Ctrl+C/V/B/N/M`) |
| `screen-recorder.sh` | Screen recorder menu: record, pause, area, replay |
| `local-llm-menu.sh` | Menu to start/stop/switch the local AI model |
| `start-local-llm` | Starts the local AI server (llama-server) |
| `local-llm-models` | Lists and finds local models |
| `local-llm-api-proxy` | Makes the local AI web page answer with a cloud model instead |
| `local-llm-build-ui` | Builds the patched local AI web page |
| `local-llm-mcp-run` | Runs AI tool servers inside a sandbox |
| `odysseus-menu.sh` | Menu to start/stop the Odysseus web UI |
| `chartr-fast` | Opens chartr in a real browser (faster) |
| `clappa` | Starts Claude Code behind the appa guard |
| `laslo` | Starts Laslo (highlight text, hotkey, it reads it aloud) |
| `lyrebird` | Starts the lyrebird voice changer |
| `mechvibes` | Starts Mechvibes with a library fix |
| `tesseract.sh` | Starts the Tesseract OCR AppImage |
| `waydroid-launch` | Opens Android (WayDroid), only one copy at a time |
| `run-win10.sh` / `save-win10-snapshot.sh` | Starts the Windows 10 VM / saves its state |
| `run-hbcd.sh` | Starts the Hiren's Boot CD rescue VM |

## my-programs/

Small programs I made, kept in `~/.local/share`.

| Link | What it does |
|---|---|
| `secreport/` | Security report tool (C + shell). Reports go to `~/Documents/security-reports` |
| `iphone-net/` | iPhone USB tether switch: installer, network file, sudo rule |
| `cpu-boost/` | CPU boost on battery: installer, sudo rule, udev rule, reset service |

## services/

Background jobs that run as my user, from `~/.config/systemd/user`.
Control them with `systemctl --user start|stop|status <name>`.

| Service | What it runs |
|---|---|
| `battery-monitor.service` | `battery-monitor.sh` |
| `gpu-monitor.service` | `gpu-monitor.sh` (off until toggled) |
| `iploc.service` | `iploc.sh` |
| `netspeed.service` | `netspeed.sh` |
| `sharemon.service` | `sharemon.sh` |
| `torcheck.service` | `torcheck.sh` |
| `local-llm.service` | local AI server on port 8080 |
| `odysseus.service` | Odysseus web UI (on demand) |

## system/

System-wide files from `/etc` and `/usr/local/bin`. **Editing these needs `sudo`.**

| Link | Points to | What it does |
|---|---|---|
| `kernel-cmdline` | `/etc/kernel/cmdline` | Boot options: AppArmor, `tsc=nowatchdog` (lag fix), zswap off |
| `mkinitcpio.conf` | `/etc/mkinitcpio.conf` | What goes into the boot image |
| `mkinitcpio-linux.preset` | `/etc/mkinitcpio.d/linux.preset` | How the boot image (UKI) gets built |
| `pacman.conf` | `/etc/pacman.conf` | Package manager settings and repos |
| `mirrorlist` | `/etc/pacman.d/mirrorlist` | Download servers for packages |
| `fstab` | `/etc/fstab` | Which drives mount at boot |
| `smartd.conf` | `/etc/smartd.conf` | Disk health checks and alerts |
| `torrc` | `/etc/tor/torrc` | Tor settings |
| `zram-generator.conf` | `/etc/systemd/zram-generator.conf` | Compressed RAM swap |
| `xorg-keyboard.conf` | `/etc/X11/xorg.conf.d/00-keyboard.conf` | Keyboard layout for X |
| `modprobe-nvidia.conf` | `/etc/modprobe.d/nvidia.conf` | NVIDIA driver option (modeset) |
| `modprobe-v4l2loopback.conf` | `/etc/modprobe.d/v4l2loopback.conf` | OBS virtual camera |
| `cpu-boost-reset.service` | `/etc/systemd/system/` | Turns CPU boost off at every boot |
| `udev-90-cpu-boost.rules` | `/etc/udev/rules.d/` | Re-applies the CPU boost setting when the charger is plugged in or pulled out |
| `usr-local-bin-cpu-boost` | `/usr/local/bin/cpu-boost` | Does the CPU boost switching |
| `usr-local-bin-iphone-net` | `/usr/local/bin/iphone-net` | Does the iPhone tether switching |
| `usr-local-bin-disk-health-details.sh` | `/usr/local/bin/` | Shows detailed disk health |
| `usr-local-bin-smartd-notify.sh` | `/usr/local/bin/` | Sends a notification when a disk has problems |

---

## Personal Note

- **Backups:** a link isn't a backup. To make a real copy that follows the links: `cp -rL ~/ArchConfigs ~/ArchConfigs-backup`.
  That copy *does* include real file contents, so check it for private stuff before sharing it.
- **Adding a new config:** `ln -s ~/.config/<program> ~/ArchConfigs/<folder>/<name>`, then add a line to this file.
