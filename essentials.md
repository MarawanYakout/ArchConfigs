# Essentials

Every program I chose to install on this Arch box, with a tag showing how much I use it.
Last checked: **2026-11-11**.

## Tags

| Tag | Meaning |
|---|---|
| **(Used Often)** | used in the last month, or always running in the background |
| **(Barely Used)** | used a few times, but recently |
| **(Recently Unused)** | used before, but not in the last month |
| **(Not Used)** | no sign of use since it was installed |

How the tags were picked: shell history (atuin, since May 2026), rofi launch counts,
the last time each program file was opened, and which services start at boot.
They're a best guess. Change any tag that looks wrong.

---

## 1. Terminal navigation (moving around the terminal faster)

- **zoxide**: smart `cd` that jumps to folders you visit a lot. Your `cd` *is* zoxide (set in `.zshrc`) **(Used Often)**
- **atuin**: searchable shell history (Ctrl+R) **(Used Often)**
- **ripgrep** (`rg`): very fast text search in files. nvim, Doom Emacs and Claude Code use it behind the scenes **(Used Often)**
- **less**: scroll through long output **(Used Often)**
- **yazi**: file manager inside the terminal **(Barely Used)**
- **htop**: see running processes and CPU/RAM **(Barely Used)**
- **fzf**: fuzzy finder for files and lists **(Recently Unused)**
- **fd**: simpler, faster `find` **(Recently Unused)**
- **tmux**: split the terminal into panes and sessions **(Recently Unused)**
- **dust**: shows what's eating disk space **(Recently Unused)**
- **ncdu**: interactive disk usage browser **(Recently Unused)**
- **trash-cli**: delete to trash instead of `rm` **(Recently Unused)**
- **fastfetch**: system info splash screen **(Recently Unused)**
- **starship**: fancy shell prompt (installed but never turned on in `.zshrc`) **(Not Used)**

## 2. Shell and terminal

- **zsh**: the shell **(Used Often)**
- **alacritty**: the terminal (`Super+Enter`) **(Used Often)**
- **xterm**: backup terminal **(Barely Used)**

## 3. Editors

- **neovim**: main editor (kickstart.nvim config) **(Used Often)**
- **emacs**: Doom Emacs **(Used Often)**
- **sublime-text**: GUI editor **(Barely Used)**
- **nano**: tiny editor **(Barely Used)**
- **gvim**: classic vim, also gives `xxd` **(Recently Unused)**

## 4. Desktop (i3 setup)

- **i3-wm**: tiling window manager **(Used Often)**
- **i3status**: top/bottom status bar **(Used Often)**
- **i3lock** + **xss-lock**: lock screen (`Super+Shift+X` and on sleep) **(Used Often)**
- **rofi**: app launcher and all the menus (`Super+D`) **(Used Often)**
- **picom**: compositor (transparency, shadows) **(Used Often)**
- **dunst**: notification popups **(Used Often)**
- **feh**: sets the wallpaper **(Used Often)**
- **nemo**: file manager **(Used Often)**
- **tumbler**: thumbnails for nemo **(Used Often)**
- **maim** + **xclip**: area screenshot to clipboard (`Super+Shift+S`) **(Used Often)**
- **gpu-screen-recorder**: screen recording (Screen Recorder menu) **(Used Often)**
- **brightnessctl**: screen and keyboard brightness keys **(Used Often)**
- **xdotool**: fakes key presses and window actions **(Used Often)**
- **polkit-gnome**: password popup for admin actions **(Used Often)**
- **xdg-utils**: opens files with the right app **(Used Often)**
- **lightdm** + **lightdm-gtk-greeter**: login screen **(Used Often)**
- **xorg-server**: the X display server **(Used Often)**
- **xorg-xset**: screen blanking settings **(Used Often)**
- **noto-fonts**, **noto-fonts-cjk**, **noto-fonts-emoji**, **ttf-fira-code**, **ttf-fira-sans**: fonts **(Used Often)**
- **arandr**: screen layout GUI **(Barely Used)**
- **xorg-xdpyinfo**: screen size info (used by `winpos.sh`) **(Barely Used)**
- **flameshot**: screenshot editor (`Super+Shift+Z`) **(Recently Unused)**
- **pamixer**: volume from terminal (volume keys use `pactl` now) **(Recently Unused)**
- **lxappearance**: GTK theme picker **(Recently Unused)**
- **i3blocks**: status bar blocks (no longer in i3 config) **(Recently Unused)**
- **dmenu**: old menu (rofi replaced it) **(Recently Unused)**
- **xorg-xev**: shows key codes **(Recently Unused)**
- **polybar**: status bar **(Not Used)**
- **xorg-xinit**: `startx` (lightdm starts X instead) **(Not Used)**

## 5. Core system

- **base**, **base-devel**, **linux**, **linux-headers**, **linux-firmware**, **amd-ucode**, **sof-firmware**, **sudo**: the base of Arch **(Used Often)**
- **zram-generator**: compressed RAM swap **(Used Often)**
- **sbctl**: Secure Boot; signs the kernel by itself on every update **(Used Often)**
- **iwd**: Wi-Fi (`wifi-menu.sh` runs on it) **(Used Often)**
- **power-profiles-daemon**: Performance / Balanced / Power-Saver **(Used Often)**
- **rtkit**: real-time priority for audio **(Used Often)**
- **usbmuxd**: iPhone over USB (tethering) **(Used Often)**
- **pipewire**, **pipewire-alsa**, **pipewire-jack**, **pipewire-pulse**, **wireplumber**, **libpulse**, **gst-plugin-pipewire**: sound **(Used Often)**
- **smartmontools**: disk health watcher (smartd runs at boot) **(Used Often)**
- **dosfstools**: FAT tools (boot partition is checked at every boot) **(Used Often)**
- **efibootmgr**: edit UEFI boot entries **(Barely Used)**
- **ntfs-3g**: read/write Windows drives **(Barely Used)**
- **ntfsprogs**: NTFS repair/resize tools **(Recently Unused)**
- **gnome-disk-utility**: disk GUI **(Recently Unused)**
- **exfatprogs**: exFAT tools **(Not Used)**
- **bluez**, **bluez-utils**: Bluetooth (service is off) **(Not Used)**
- **cups**, **cups-pk-helper**, **system-config-printer**: printing (service is off) **(Not Used)**

## 6. Graphics drivers

- **nvidia-open**, **nvidia-utils**, **lib32-nvidia-utils**: NVIDIA driver **(Used Often)**
- **cuda**, **cudnn**: GPU computing (local LLM, Laslo) **(Used Often)**
- **lib32-vulkan-radeon**: AMD Vulkan for 32-bit games **(Barely Used)**
- **nvidia-container-toolkit**: GPU inside Docker **(Recently Unused)**
- **vdpauinfo**: video decode check **(Recently Unused)**
- **libva-utils**: video decode check **(Not Used)**
- **nvidia-settings**: NVIDIA settings GUI **(Not Used)**
- **xf86-video-nouveau**, **vulkan-nouveau**: open NVIDIA driver (the official one is used instead) **(Not Used)**

## 7. Security and privacy

- **apparmor**: app restrictions (on at boot) **(Used Often)**
- **firejail**: sandboxes Firefox and Chromium **(Used Often)**
- **firewalld**: firewall **(Used Often)**
- **pass**: password manager **(Used Often)**
- **mullvad-vpn**: VPN (new, installed 2026-11-09) **(Barely Used)**
- **clamav**: antivirus scanner **(Barely Used)**
- **openssh**: SSH (server via `ssh-toggle.sh`) **(Barely Used)**
- **nmap**: network scanner **(Barely Used)**
- **openbsd-netcat**: raw network connections **(Barely Used)**
- **cloudflared**: Cloudflare tunnels **(Barely Used)**
- **tor**: Tor network (off at boot) **(Recently Unused)**
- **torsocks**: run a command through Tor **(Recently Unused)**
- **torbrowser-launcher**: Tor Browser **(Recently Unused)**
- **obfs4proxy**: Tor bridge helper **(Recently Unused)**
- **arp-scan**: find devices on the local network **(Recently Unused)**
- **obfs4proxy-debug**: debug files for obfs4proxy **(Not Used)**

## 8. Network tools

- **syncthing**: file sync (via `syncthing-toggle.sh`) **(Barely Used)**
- **wget**: download files **(Recently Unused)**
- **iftop**: bandwidth per connection **(Recently Unused)**
- **nethogs**: bandwidth per program **(Recently Unused)**

## 9. Development

- **git** **(Used Often)**
- **github-cli** (`gh`) **(Used Often)**
- **bun**: JavaScript runtime and package manager (the default here) **(Used Often)**
- **make**, **cmake**, **gcc**, **gcc15**, **clang**: build tools and compilers **(Used Often)**
- **rustup**: Rust toolchain **(Used Often)**
- **ollama-cuda**: run local AI models on the GPU **(Used Often)**
- **webkit2gtk-4.1**: web engine that chartr, terax and Vargo need **(Used Often)**
- **npm**: JavaScript packages (Bun is used instead) **(Barely Used)**
- **llvm**: comes with clang **(Barely Used)**
- **waydroid** + **cage**: Android inside Linux (Expo app testing) **(Barely Used)**
- **shellcheck**: checks shell scripts for mistakes **(Barely Used)**
- **pandoc-cli**: converts documents between formats **(Barely Used)**
- **texlive-basic**, **texlive-latex**, **texlive-latexextra**, **texlive-fontsrecommended**, **texlive-fontsextra**, **texlive-mathscience**, **texlive-binextra**, **biber**: LaTeX **(Barely Used)**
- **tk**: Python GUI toolkit (tkinter) **(Barely Used)**
- **python-notify2**: Python desktop notifications **(Barely Used)**
- **python-pkg_resources**: Python helper (AUR) **(Barely Used)**
- **poppler-glib**: PDF library **(Barely Used)**
- **blas-openblas**: fast math library (numpy and friends) **(Barely Used)**
- **pnpm**: JavaScript packages **(Recently Unused)**
- **docker** + **docker-compose**: containers **(Recently Unused)**
- **jdk21-openjdk**, **jre-openjdk**: Java (Android builds) **(Recently Unused)**
- **arm-none-eabi-gcc**, **arm-none-eabi-binutils**, **arm-none-eabi-gdb**, **arm-none-eabi-newlib**: ARM microcontroller toolchain **(Recently Unused)**
- **gemini-cli**: Google's AI agent in the terminal **(Recently Unused)**
- **shfmt**: formats shell scripts **(Not Used)**
- **boost**: C++ libraries **(Not Used)**

## 10. Media and audio

- **mpv**: video player (also plays the animated wallpaper) **(Used Often)**
- **espeak-ng**: speech engine (Laslo TTS) **(Barely Used)**
- **vlc** + **vlc-plugin-ffmpeg**: video player **(Barely Used)**
- **obs-studio**: recording and streaming **(Barely Used)**
- **ardour**: audio workstation (DAW) **(Barely Used)**
- **spotify-launcher**: Spotify **(Barely Used)**
- **sox**: audio processing (lyrebird voice changer) **(Recently Unused)**
- **v4l2loopback-dkms**: OBS virtual camera **(Recently Unused)**
- **droidcam-obs-plugin**: phone as a camera in OBS **(Recently Unused)**
- **droidcam-obs-plugin-debug**: debug files **(Not Used)**

## 11. Apps

- **firefox** **(Used Often)**
- **unzip**: extract `.zip` **(Used Often)**
- **chromium** **(Barely Used)**
- **telegram-desktop** **(Barely Used)**
- **zoom** **(Barely Used)**
- **libreoffice-still**: office suite **(Barely Used)**
- **qbittorrent**: torrents **(Barely Used)**
- **steam**: games **(Barely Used)**
- **vkd3d**, **lib32-vkd3d**: DirectX 12 for games **(Barely Used)**
- **qemu-desktop**, **qemu-system-aarch64**, **qemu-system-arm**, **qemu-system-riscv**, **qemu-system-microblaze**: virtual machines **(Barely Used)**
- **libvirt**, **virt-manager**, **edk2-ovmf**: VM manager and UEFI for VMs **(Barely Used)**
- **7zip**: extract `.7z` **(Barely Used)**
- **unrar**: extract `.rar` **(Barely Used)**
- **lutris**: game launcher **(Recently Unused)**
- **wine-staging**, **wine-mono**, **wine-gecko**, **winetricks**: run Windows programs **(Recently Unused)**
- **gamemode**, **lib32-gamemode**: game performance boost **(Recently Unused)**
- **zip**: make `.zip` **(Recently Unused)**
- **wimlib**: Windows install image tools **(Recently Unused)**
- **innoextract**: unpack Windows installers **(Not Used)**

---

## 12. Installed outside pacman

AppImages in `~/aur-builds`, tools in `~/.local/bin`, `~/.cargo/bin` and `~/.bun/bin`.

### AI tools
- **claude** (Claude Code) **(Used Often)**
- **agy** (Antigravity CLI) **(Used Often)**
- **openclaude** **(Used Often)**
- **appa** / **clappa**: guard that checks AI tool calls before they run **(Used Often)**
- **llama.cpp** (`llama-server`) + Local LLM menu: runs local models **(Used Often)**
- **odysseus**: web UI (on-demand service) **(Recently Unused)**
- **bd** / **beads**: issue tracker for AI agents **(Recently Unused)**
- **terax-ai** **(Recently Unused)**
- **chartr** **(Recently Unused)**
- **rea** / **rea-agents** (from `~/playground/reverseTechnique`) **(Not Used)**

### Desktop apps
- **obsidian**: notes **(Used Often)**
- **cinny**: Matrix chat **(Used Often)**
- **kdenlive**: video editor **(Used Often)**
- **handy**: voice dictation (`Shift+X`, starts at login) **(Used Often)**
- **sioyek**: PDF reader **(Barely Used)**
- **mechvibes**: mechanical keyboard sounds **(Barely Used)**
- **edex-ui**, **matrix-ui**: sci-fi terminal dashboards **(Barely Used)**
- **JetBrains IDEs** (CLion, PyCharm, RustRover, WebStorm) **(Barely Used)**
- **blender**: 3D **(Recently Unused)**
- **inkscape**: vector drawing **(Recently Unused)**
- **zotero**: research paper library **(Recently Unused)**
- **lyrebird**: voice changer **(Recently Unused)**
- **Burp Suite**: web security testing **(Recently Unused)**
- **tesseract**: text from images (OCR) **(Recently Unused)**

### Terminal tools
- **marcopolo**: finds and downloads files from many sources **(Used Often)**
- **python** / **ipython** / **pip** **(Used Often)**
- **coursera-dl** (`coursera` command in `.zshrc`) **(Barely Used)**
- **manim**: math animations **(Barely Used)**
- **uv** / **uvx**: Python packages and tools **(Barely Used)**
- **adb** / **fastboot**: talk to Android (WayDroid) **(Barely Used)**
- **live-server**: local web server with auto reload **(Barely Used)**
- **laslo**: my text-to-speech hotkey daemon **(Barely Used)**
- **secreport**: my security report tool **(Barely Used)**
- **iamb**: Matrix chat in the terminal **(Recently Unused)**

---

## Reinstall everything from pacman on a new machine

```sh
pacman -Qeq > pkglist.txt                       # on this machine: save the list
sudo pacman -S --needed - < pkglist.txt         # on the new machine (AUR ones will fail, build those by hand)
```
