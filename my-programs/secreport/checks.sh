#!/usr/bin/env bash
# checks.sh - read-only security checks, printed as a tagged text report.
#
#   [ALERT] possible compromise - look now
#   [WARN]  worth a look (risky setting, or something new since last scan)
#   [INFO]  context
#   [OK]    check passed
#
# Usage: checks.sh STATE_DIR
#   STATE_DIR keeps the previous scan, so new services/ports/keys/etc. are flagged.
# Runs as your normal user; nothing here changes the system.

export LC_ALL=C
STATE_DIR=${1:-$HOME/.local/share/secreport/state}
mkdir -p "$STATE_DIR"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/state"          # "category|item" lines, compared with last scan
: > "$STATE"

ok()       { printf '[OK]    %s\n' "$*"; }
info()     { printf '[INFO]  %s\n' "$*"; }
warn()     { printf '[WARN]  %s\n' "$*"; }
alert()    { printf '[ALERT] %s\n' "$*"; }
section()  { printf '\n==== %s ====\n' "$*"; }
indent()   { sed 's/^/        /'; }
wrap()     { paste -sd' ' | fold -s -w 96 | indent; }
remember() { printf '%s|%s\n' "$1" "$2" >> "$STATE"; }

is_lan() {
    case $1 in
        10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|127.*|169.254.*|fe80:*|fd*|::1) return 0 ;;
    esac
    return 1
}

# ---------------------------------------------------------------------------
section "System"
info "host $(cat /proc/sys/kernel/hostname), kernel $(uname -r), $(uptime -p)"

# ---------------------------------------------------------------------------
section "Listening ports"
ss -tulpnH | indent
declare -A EXPOSED            # "tcp/22" -> process, for the firewall check
exposed=0
read -r eph_lo eph_hi < /proc/sys/net/ipv4/ip_local_port_range
while read -r proto _ _ _ local _ proc; do
    addr=${local%:*}; port=${local##*:}
    name=$(grep -o '(("[^"]*"' <<<"$proc" | head -1 | tr -d '("')
    if [ -z "$name" ]; then
        uid=$(grep -o 'uid:[0-9]*' <<<"$proc" | cut -d: -f2)
        if [ "${uid:-0}" = "$(id -u)" ]; then name="hidden-app(sandboxed)"
        else name="process hidden, user $(getent passwd "${uid:-0}" | cut -d: -f1)"; fi
    fi
    case $addr in 127.*|'[::1]'|*%lo|'[::ffff:127.'*) continue ;; esac
    # random high UDP port = outgoing socket (browser QUIC/WebRTC), not a server
    if [ "$proto" = udp ] && [ "$port" -ge "$eph_lo" ] && [ "$port" -le "$eph_hi" ]; then
        info "udp $port: outgoing socket of $name (random port, e.g. browser QUIC/WebRTC)"
        continue
    fi
    exposed=1
    EXPOSED["$proto/$port"]=$name
    remember listen "$proto/$port $name"
    case $port in
        5353) info "$proto $port on $addr: mDNS (systemd-resolved)" ;;
        5355) info "$proto $port on $addr: LLMNR name lookup (systemd-resolved)" ;;
        *)    warn "$proto port $port open to the network on $addr ($name)" ;;
    esac
done < <(ss -tulpnHe)
[ "$exposed" = 0 ] && ok "nothing listens on the network, only on localhost"

# ---------------------------------------------------------------------------
section "Active connections"
myuid=$(id -u)
ss -tunHpe state established > "$TMP/conns"
declare -A IPS
while read -ra f; do
    ip=${f[4]%:*}; ip=${ip#[}; ip=${ip%]}; ip=${ip#::ffff:}
    IPS["$ip"]=1
done < "$TMP/conns"
# reverse DNS, in parallel, 2 s max each
for ip in "${!IPS[@]}"; do
    ( timeout 2 getent hosts "$ip" | awk '{print $2; exit}' > "$TMP/rdns_$ip" ) &
done
wait

declare -A FLAGGED
: > "$TMP/conn_lines"
while read -r line; do
    read -ra f <<<"$line"
    proto=${f[0]}; peer=${f[4]}
    ip=${peer%:*}; ip=${ip#[}; ip=${ip%]}; ip=${ip#::ffff:}; port=${peer##*:}
    name=$(grep -o '(("[^"]*"' <<<"$line" | head -1 | tr -d '("')
    uid=$(grep -o 'uid:[0-9]*' <<<"$line" | cut -d: -f2)
    user=$(getent passwd "${uid:-x}" | cut -d: -f1)
    if [ -n "$name" ]; then owner=$name
    elif [ "$uid" = "$myuid" ]; then owner="hidden-app(sandboxed)"
    else owner="user:${user:-uid$uid}"
    fi
    rdns=$(cat "$TMP/rdns_$ip" 2>/dev/null)
    printf '%-24s -> %s:%s %s\n' "$owner" "$ip" "$port" "${rdns:+($rdns)}" >> "$TMP/conn_lines"

    key="$owner $ip:$port"
    [ -n "${FLAGGED[$key]}" ] && continue
    FLAGGED[$key]=1
    if [ "$user" = tor ]; then continue; fi            # Tor relays use any port
    if is_lan "$ip"; then continue; fi
    case $port in
        80|443|53|853|22|993|995|465|587|143|5222|5223|5228|3478|19302|8443) ;;
        *) warn "$proto connection on unusual port: $owner -> $ip:$port ${rdns:+($rdns)}" ;;
    esac
done < "$TMP/conns"
total=$(wc -l < "$TMP/conns")
info "$total established connections (count, owner, remote):"
sort "$TMP/conn_lines" | uniq -c | sort -rn | indent
grep -q 'user:tor' "$TMP/conn_lines" && info "user:tor = Tor network relays (tor.service is running)"
grep -q 'hidden-app' "$TMP/conn_lines" && info "hidden-app = your own app whose sockets can't be read, e.g. firejail-sandboxed Firefox"

# ---------------------------------------------------------------------------
section "Processes"
info "top CPU (average since each process started):"
ps -eo pid,user:12,pcpu,pmem,etime,comm --sort=-pcpu | awk '$6 != "ps"' | head -12 | indent

bad=0
for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    exe=$(readlink "$d/exe" 2>/dev/null) || continue
    comm=$(cat "$d/comm" 2>/dev/null)
    case $exe in
        /memfd:*)
            alert "pid $pid ($comm) runs from memory only, no file on disk: $exe"; bad=1 ;;
        *' (deleted)')
            path=${exe% (deleted)}
            case $path in
                /tmp/*|/dev/shm/*|/var/tmp/*)
                    alert "pid $pid ($comm) runs a deleted file from a temp dir: $path"; bad=1 ;;
                *)
                    warn "pid $pid ($comm) runs a file that was replaced or deleted: $path (often just an update - restart it)"; bad=1 ;;
            esac ;;
        /tmp/.mount_*) ;;                                   # AppImage
        /tmp/*|/dev/shm/*|/var/tmp/*)
            alert "pid $pid ($comm) runs from a temp dir: $exe"; bad=1 ;;
    esac
done
[ "$bad" = 0 ] && ok "no programs running from temp dirs, memory or deleted files"

# user programs pretending to be kernel threads: [kworker] etc.
fake=$(ps -eo pid=,ppid=,stat=,args= | awk '$4 ~ /^\[/ && $1 != 2 && $2 != 2 && $3 !~ /Z/')
if [ -n "$fake" ]; then
    alert "processes disguised as kernel threads:"; echo "$fake" | indent
else
    ok "no processes disguised as kernel threads"
fi

# long-running heavy CPU users (cryptominer pattern)
heavy=$(ps -eo pid=,etimes=,pcpu=,comm= | awk '$2 > 300 && $3 > 80 {printf "pid %s (%s) averaged %s%% CPU for %d min\n", $1, $4, $3, $2/60}')
if [ -n "$heavy" ]; then
    while read -r l; do warn "$l - expected if you are compiling/rendering/running a model"; done <<<"$heavy"
else
    ok "no process has used heavy CPU for a long time"
fi

# ---------------------------------------------------------------------------
section "Rootkit basics"
if [ -s /etc/ld.so.preload ]; then
    alert "/etc/ld.so.preload is set (forces a library into every program):"; indent < /etc/ld.so.preload
else
    ok "no /etc/ld.so.preload"
fi
pre=$(grep -lsz '^LD_PRELOAD=' /proc/[0-9]*/environ 2>/dev/null | cut -d/ -f3)
if [ -n "$pre" ]; then
    for p in $pre; do warn "pid $p ($(cat /proc/$p/comm 2>/dev/null)) runs with LD_PRELOAD set"; done
else
    ok "none of your processes use LD_PRELOAD"
fi

# ---------------------------------------------------------------------------
section "Accounts"
root0=$(awk -F: '$3==0 && $1!="root" {print $1}' /etc/passwd)
if [ -n "$root0" ]; then alert "extra accounts with root power (UID 0): $root0"; else ok "only root has UID 0"; fi
while IFS=: read -r u _ id _ _ _ sh; do
    case $sh in *nologin|*false) continue ;; esac
    info "login account: $u (uid $id, $sh)"; remember account "$u $sh"
done < /etc/passwd
wheel=$(getent group wheel | cut -d: -f4)
info "admins (wheel): ${wheel:-none}"
for u in ${wheel//,/ }; do remember wheel "$u"; done

# ---------------------------------------------------------------------------
section "Logins (last 7 days)"
last -n 6 2>/dev/null | indent
journalctl SYSLOG_FACILITY=4 SYSLOG_FACILITY=10 --since "7 days ago" -q --no-pager 2>/dev/null \
    | grep -E 'authentication failure|Failed password|Invalid user|incorrect password attempt|Accepted (password|publickey|keyboard-interactive)' \
    > "$TMP/auth"
remote=$(grep -vE 'Accepted' "$TMP/auth" | grep -E 'rhost=[^ ]|from [0-9a-fA-F.:]+ port')
accepted=$(grep -E 'Accepted' "$TMP/auth")
localf=$(grep -vE 'rhost=[^ ]|from [0-9a-fA-F.:]+ port|Accepted' "$TMP/auth" | grep -c .)
if [ -n "$remote" ]; then
    alert "$(grep -c . <<<"$remote") failed logins from the network:"; tail -5 <<<"$remote" | indent
else
    ok "no failed logins from the network"
fi
if [ -n "$accepted" ]; then
    warn "SSH logins accepted (make sure these were you):"; tail -5 <<<"$accepted" | indent
fi
if [ "$localf" -gt 15 ]; then
    warn "$localf local password failures (sudo / lock screen / login) - many"
else
    info "$localf local password failures (sudo / lock screen / login typos)"
fi

# ---------------------------------------------------------------------------
section "Remote access and services"
if systemctl is-active --quiet sshd; then
    warn "SSH server is ON (password logins allowed by default) - turn off with 'SSH Toggle' when not needed"
else
    ok "SSH server is off"
fi
if [ -s "$HOME/.ssh/authorized_keys" ]; then
    while read -r type _ comment; do
        case $type in ''|'#'*) continue ;; esac
        info "authorized SSH key: $type ${comment:-no-comment}"; remember authkey "$type ${comment:-no-comment}"
    done < "$HOME/.ssh/authorized_keys"
else
    ok "no SSH authorized_keys (nobody can log in with a key)"
fi
info "tor: $(systemctl is-active tor) (boot: $(systemctl is-enabled tor 2>/dev/null))"
info "syncthing: $(systemctl --user is-active syncthing)"
failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
[ -n "$failed" ] && info "failed services (not a security issue by itself): $(echo $failed)"

# ---------------------------------------------------------------------------
# Reads firewalld's saved config files (world-readable) instead of calling
# firewall-cmd, whose zone queries pop up a polkit password prompt each time.
section "Firewall (saved firewalld config)"
xml_of() {   # xml_of zones|services NAME -> path (local override wins)
    for d in /etc/firewalld/$1 /usr/lib/firewalld/$1; do
        [ -f "$d/$2.xml" ] && { echo "$d/$2.xml"; return; }
    done
}
ports_in() { # "22/tcp" lines from <port .../> tags, any attribute order
    grep -o '<port [^>]*>' "$1" 2>/dev/null | while read -r tag; do
        p=$(sed -n 's/.* port="\([^"]*\)".*/\1/p' <<<"$tag")
        pr=$(sed -n 's/.*protocol="\([^"]*\)".*/\1/p' <<<"$tag")
        echo "$p/$pr"
    done
}
if systemctl is-active --quiet firewalld; then
    ok "firewalld is running"
    defzone=$(sed -n 's/^DefaultZone=//p' /etc/firewalld/firewalld.conf 2>/dev/null)
    declare -A ZONE_IFACES
    for ifc in $(ip -o link show up | awk -F': ' '{print $2}' | cut -d@ -f1); do
        [ "$ifc" = lo ] && continue
        z=$(grep -l "<interface name=\"$ifc\"/>" /etc/firewalld/zones/*.xml 2>/dev/null | head -1)
        z=$(basename "${z:-${defzone:-public}.xml}" .xml)
        ZONE_IFACES[$z]+="$ifc "
    done
    for zone in "${!ZONE_IFACES[@]}"; do
        ifaces=${ZONE_IFACES[$zone]% }
        zf=$(xml_of zones "$zone")
        if grep -q 'target="ACCEPT"' "$zf" 2>/dev/null; then
            case " $ifaces" in
                *' wl'*) warn "Wi-Fi ($ifaces) is in zone $zone which accepts everything - that network can reach every port" ;;
                *)       info "zone $zone ($ifaces) accepts all incoming traffic - only connect devices you own" ;;
            esac
            continue
        fi
        info "zone $zone: $ifaces"
        openings=""
        for svc in $(sed -n 's/.*<service name="\([^"]*\)".*/\1/p' "$zf"); do
            for pp in $(ports_in "$(xml_of services "$svc")"); do openings+=" $svc:$pp"; done
        done
        for pp in $(ports_in "$zf"); do openings+=" port:$pp"; done
        for o in $openings; do
            svc=${o%%:*}; pp=${o#*:}; port=${pp%/*}; proto=${pp#*/}
            remember fw "$zone $svc $pp"
            if [ -n "${EXPOSED[$proto/$port]}" ]; then
                warn "zone $zone ($ifaces) lets the network reach $svc ($pp) and it IS running (${EXPOSED[$proto/$port]})"
            else
                info "zone $zone allows $svc ($pp) - nothing listening there now"
            fi
        done
    done
else
    alert "firewalld is NOT running - no firewall"
fi

# ---------------------------------------------------------------------------
section "Startup items (things that run automatically)"
# enabled = symlinked into /etc/systemd/system (much faster than systemctl list-unit-files)
units=$(find /etc/systemd/system -type l ! -lname /dev/null -printf '%f\n' 2>/dev/null | sort -u)
info "enabled system services:"; echo "$units" | wrap
for u in $units; do remember unit "$u"; done
uunits=$(find /etc/systemd/user "$HOME/.config/systemd/user" -type l ! -lname /dev/null -printf '%f\n' 2>/dev/null | sort -u)
info "enabled user services:"; echo "$uunits" | wrap
for u in $uunits; do remember userunit "$u"; done
for f in "$HOME"/.config/systemd/user/*.service "$HOME"/.config/systemd/user/*.timer; do
    [ -f "$f" ] && remember userfile "$(basename "$f") $(grep -m1 '^ExecStart=' "$f" | cut -d= -f2-)"
done
timers=$( { systemctl list-timers --all --no-legend; systemctl --user list-timers --all --no-legend; } 2>/dev/null | awk '{print $(NF-1)}')
info "timers:"; echo "$timers" | wrap
for t in $timers; do remember timer "$t"; done
for f in /etc/xdg/autostart/*.desktop "$HOME"/.config/autostart/*.desktop; do
    [ -f "$f" ] || continue
    remember autostart "$f $(grep -m1 '^Exec=' "$f" | cut -d= -f2-)"
done
info "autostart entries: $(ls /etc/xdg/autostart "$HOME"/.config/autostart 2>/dev/null | grep -c '\.desktop$')"
if [ -f "$HOME/.config/i3/config" ]; then
    grep -E '^[[:space:]]*exec(_always)?[[:space:]]' "$HOME/.config/i3/config" | sed 's/^[[:space:]]*//' > "$TMP/i3exec"
    info "i3 autostart commands: $(grep -c . "$TMP/i3exec")"
    while read -r l; do remember i3exec "$l"; done < "$TMP/i3exec"
fi
cron=$(for p in /etc/crontab /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /var/spool/cron /var/spool/atd; do
           [ -e "$p" ] && find "$p" -type f 2>/dev/null; done)
if [ -n "$cron" ]; then
    info "cron/at jobs:"; echo "$cron" | indent
    for c in $cron; do remember cron "$c"; done
else
    ok "no cron or at jobs"
fi
for f in .bashrc .bash_profile .profile .zshrc .zshenv .zprofile .zlogin .xinitrc .xprofile; do
    [ -f "$HOME/$f" ] || continue
    remember rcfile "~/$f $(sha256sum "$HOME/$f" | cut -c1-12)"
    [ -n "$(find "$HOME/$f" -mtime -7)" ] && info "~/$f changed in the last 7 days ($(date -r "$HOME/$f" '+%F %R'))"
done

# ---------------------------------------------------------------------------
section "Privileges"
rules=$(timeout 5 sudo -n -l 2>/dev/null | grep 'NOPASSWD')
if [ -n "$rules" ]; then
    info "passwordless sudo rules:"; echo "$rules" | indent
    while read -r r; do remember sudo "$(echo $r)"; done <<<"$rules"
    for cmd in $(echo "$rules" | sed 's/.*NOPASSWD://' | tr ',' '\n' | awk '{print $1}'); do
        [ "$cmd" = ALL ] && { warn "passwordless sudo for ALL commands"; continue; }
        if [ -w "$cmd" ] || [ -w "$(dirname "$cmd")" ]; then
            alert "passwordless sudo runs $cmd, which you can edit - anything you run could become root"
        fi
    done
else
    ok "no passwordless sudo rules"
fi
# home is only searched 4 levels deep (a full search takes minutes)
{ find /usr /opt /etc /var /tmp /dev/shm -xdev \( -path /usr/share -o -path /usr/include -o -path /usr/src \) -prune -o -perm -4000 -type f -print
  find /home -xdev -maxdepth 4 -perm -4000 -type f; } 2>/dev/null | sort -u > "$TMP/suid"
while read -r f; do
    remember suid "$f"
    case $f in /home/*) alert "setuid-root program inside home: $f" ;; esac
done < "$TMP/suid"
unowned=$(xargs -r -d '\n' pacman -Qqo -- < "$TMP/suid" 2>&1 >/dev/null | sed -n 's/^error: No package owns //p')
info "$(grep -c . "$TMP/suid") setuid-root programs; not from a package:"
if [ -n "$unowned" ]; then echo "$unowned" | indent; else echo "(none)" | indent; fi

# ---------------------------------------------------------------------------
section "Packages"
foreign=$(pacman -Qm 2>/dev/null)
info "packages not from the Arch repos (AUR/manual):"; echo "${foreign:-(none)}" | indent
while read -r p _; do [ -n "$p" ] && remember foreign "$p"; done <<<"$foreign"
since=$(date -d '7 days ago' +%Y-%m-%d)
recent=$(awk -v s="[$since" '$1 >= s && /\[ALPM\] installed/ {print $4, $5}' /var/log/pacman.log 2>/dev/null)
info "installed in the last 7 days: $(grep -c . <<<"$recent")"
[ -n "$recent" ] && echo "$recent" | wrap

# ---------------------------------------------------------------------------
section "Changes since last scan"
sort -u "$STATE" -o "$STATE"
prev="$STATE_DIR/last-state"
label() {
    case $1 in
        listen) echo "network port" ;;     unit) echo "system service" ;;
        userunit) echo "user service" ;;   userfile) echo "user service file" ;;
        timer) echo "timer" ;;             autostart) echo "autostart entry" ;;
        i3exec) echo "i3 autostart" ;;     cron) echo "cron job" ;;
        rcfile) echo "shell startup file" ;; sudo) echo "passwordless sudo rule" ;;
        suid) echo "setuid program" ;;     foreign) echo "non-repo package" ;;
        account) echo "login account" ;;   wheel) echo "admin (wheel) member" ;;
        authkey) echo "SSH authorized key" ;; fw) echo "firewall opening" ;;
        *) echo "$1" ;;
    esac
}
if [ -f "$prev" ]; then
    new=$(comm -13 "$prev" "$STATE"); gone=$(comm -23 "$prev" "$STATE")
    if [ -z "$new" ] && [ -z "$gone" ]; then
        ok "nothing changed since last scan ($(date -r "$prev" '+%F %R'))"
    fi
    [ -n "$new" ]  && while IFS='|' read -r c item; do warn "NEW since last scan - $(label "$c"): $item"; done <<<"$new"
    [ -n "$gone" ] && while IFS='|' read -r c item; do info "gone since last scan - $(label "$c"): $item"; done <<<"$gone"
else
    info "first scan - saved a baseline; next scans will flag anything new"
fi
cp "$STATE" "$prev"

section "Not checked (needs root)"
info "full file integrity: run  sudo pacman -Qkk 2>&1 | grep -v ' 0 altered'"
info "root-only process sockets, /etc/sudoers.d contents, deep rootkit scan (rkhunter)"
exit 0
