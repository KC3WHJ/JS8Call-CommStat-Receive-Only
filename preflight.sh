#!/usr/bin/env bash
# Prerequisite check for JS8Call-CommStat-Receive-Only.
#
# Read-only: it installs nothing, changes nothing, and never asks for sudo.
# install.sh runs this first and refuses to touch your system if anything is
# marked FAIL. You can also run it by itself as a dry run:
#
#     ./preflight.sh              # full check
#     ./preflight.sh --quiet      # only show warnings and failures
#     ./preflight.sh --no-network # skip the internet checks (offline test)
#     ./preflight.sh --no-gui-check
#
# Exit status: 0 = ready to install (warnings allowed), 1 = at least one FAIL.

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"
load_config

PF_QUIET=0; PF_NETWORK=1; PF_GUI=1
N_OK=0; N_WARN=0; N_FAIL=0

# result LEVEL "Label" "detail" ["how to fix"]
result() {
    local level="$1" label="$2" detail="$3" hint="${4:-}" tag
    case "$level" in
        OK)   tag="${C_GRN}[ OK ]${C_OFF}"; N_OK=$((N_OK+1)) ;;
        WARN) tag="${C_YEL}[WARN]${C_OFF}"; N_WARN=$((N_WARN+1)) ;;
        FAIL) tag="${C_RED}[FAIL]${C_OFF}"; N_FAIL=$((N_FAIL+1)) ;;
    esac
    if [ "$level" = OK ] && [ "$PF_QUIET" = 1 ]; then return 0; fi
    printf '  %s %-22s %s\n' "$tag" "$label" "$detail"
    [ -n "$hint" ] && printf '         %s%s%s\n' "$C_DIM" "-> $hint" "$C_OFF"
    return 0
}

# Is a package installable from the configured apt sources? Prints the candidate
# version, or nothing. Sets PKG_LISTS_EMPTY=1 if apt has no package lists at all
# (a fresh system that hasn't run `apt update` yet - so "not found" means nothing).
apt_candidate() {
    local c
    c="$(apt-cache policy "$1" 2>/dev/null | sed -n 's/^  Candidate: //p')"
    [ "$c" = "(none)" ] && c=""
    printf '%s' "$c"
}
apt_lists_empty() { [ "$(find /var/lib/apt/lists -maxdepth 1 -type f -name '*Packages*' 2>/dev/null | wc -l)" -lt 3 ]; }

tcp_reachable() {  # host port
    timeout 8 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}

# ------------------------------------------------------------------ checks
check_os() {
    local id="" like="" ver="" pretty="" codename=""
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id="${ID:-}"; like="${ID_LIKE:-}"; ver="${VERSION_ID:-}"; pretty="${PRETTY_NAME:-$id}"; codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    fi
    if [ "$(uname -s)" != Linux ]; then
        result FAIL "Operating system" "$(uname -s) is not Linux" "This project only supports Linux."
    elif ! have apt-get; then
        result FAIL "Operating system" "$pretty - no apt-get found" "Only Debian/Ubuntu-family systems (apt) are supported."
    else
        local major="${ver%%.*}"
        case "$id" in
            ubuntu)    if [ "${major:-0}" -ge 24 ] 2>/dev/null; then result OK "Operating system" "$pretty (tested)"
                       else result WARN "Operating system" "$pretty" "Tested on Ubuntu 24.04+; older releases may lack a js8call package."; fi ;;
            linuxmint) if [ "${major:-0}" -ge 22 ] 2>/dev/null; then result OK "Operating system" "$pretty, Ubuntu ${codename:-?} base (tested)"
                       else result WARN "Operating system" "$pretty" "Tested on Linux Mint 22+."; fi ;;
            *)         result WARN "Operating system" "$pretty (apt-based, untested)" "Should work on Debian/Ubuntu derivatives, but only Ubuntu 24.04 and Linux Mint 22 have been tested." ;;
        esac
    fi
}

check_arch() {
    local arch; arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    case "$arch" in
        amd64|arm64) result OK "CPU architecture" "$arch" ;;
        *)           result WARN "CPU architecture" "$arch" "Only amd64 and arm64 have been considered; package availability may differ." ;;
    esac
}

check_user() {
    if [ "$(id -u)" -eq 0 ]; then
        result FAIL "Running as" "root" "Run as your normal desktop user. The installer uses sudo itself only for apt."
        return
    fi
    result OK "Running as" "$(id -un) (not root)"
    if ! have sudo; then
        result FAIL "sudo" "not installed" "Install sudo, or ask an administrator to install the packages listed in the README."
    elif id -nG | tr ' ' '\n' | grep -qxE 'sudo|admin|wheel'; then
        result OK "sudo" "available; $(id -un) is an administrator (you'll be asked for your password once)"
    else
        result FAIL "sudo" "$(id -un) is not in the sudo/admin group" "Installing packages needs administrator rights."
    fi
}

check_resources() {
    local kb free_root free_home mem_kb
    free_root="$(df -Pk / 2>/dev/null | awk 'NR==2{print int($4/1024)}')"
    free_home="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2{print int($4/1024)}')"
    if [ "${free_root:-0}" -lt 1536 ] || [ "${free_home:-0}" -lt 512 ]; then
        result FAIL "Disk space" "${free_root:-?} MiB free on /, ${free_home:-?} MiB in \$HOME" "Need about 1.5 GiB free for the Qt WebEngine packages CommStat uses."
    else
        result OK "Disk space" "${free_root} MiB free on /, ${free_home} MiB in \$HOME"
    fi
    mem_kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)"
    if [ "${mem_kb:-0}" -lt 1800000 ]; then
        result WARN "Memory" "$(( ${mem_kb:-0} / 1024 )) MiB" "CommStat's embedded web engine is memory-hungry; 2 GiB or more is comfortable."
    else
        result OK "Memory" "$(( mem_kb / 1024 )) MiB"
    fi
    kb=0
}

check_tools() {
    if have python3 && python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
        result OK "Python" "$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])')"
    else
        result FAIL "Python" "python3 3.8 or newer not found" "sudo apt install python3"
    fi
    if have git; then result OK "git" "$(git --version | awk '{print $3}')"
    else result WARN "git" "not installed" "The installer will install it."; fi
}

check_network() {
    if [ "$PF_NETWORK" = 0 ]; then result WARN "Internet" "skipped (--no-network)" "The installer downloads packages and clones CommStat from GitHub."; return; fi
    if tcp_reachable github.com 443; then result OK "GitHub" "github.com:443 reachable (CommStat is cloned from here)"
    else result FAIL "GitHub" "cannot reach github.com:443" "Check your internet connection, proxy, or firewall."; fi
    # Test every apt source host, not just the first one listed.
    local hosts host up=0 down="" n=0
    hosts="$(grep -rhoE 'https?://[A-Za-z0-9.-]+' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | sed 's#https\?://##' | sort -u | head -8)"
    if [ -z "$hosts" ]; then
        result WARN "apt sources" "could not determine your apt servers" ""
    else
        for host in $hosts; do
            n=$((n+1))
            if tcp_reachable "$host" 443 || tcp_reachable "$host" 80; then up=$((up+1)); else down="$down $host"; fi
        done
        if [ "$up" -eq 0 ]; then result FAIL "apt sources" "none of $n configured servers is reachable" "Package downloads will fail. Check your connection or proxy."
        elif [ -n "$down" ]; then result WARN "apt sources" "$up of $n reachable; unreachable:$down" "apt update may print errors for those, but the install can still work."
        else result OK "apt sources" "all $n configured servers reachable"; fi
    fi
}

check_apt() {
    # Only processes that actually take the apt/dpkg lock count. (Tray applets such as
    # mintUpdate and an idle packagekitd are always running and don't hold it.)
    local busy
    busy="$(pgrep -x 'apt|apt-get|apt.systemd.dai|dpkg|aptitude|unattended-upgr|mint-refresh-ca' 2>/dev/null | wc -l)"
    if [ "$busy" -gt 0 ]; then
        result FAIL "Package manager" "busy: another apt/dpkg process is running" "Wait for it to finish (Linux Mint's background refresh can hold apt for a minute or two after boot), then run again."
    else
        result OK "Package manager" "not locked by another process"
    fi

    local pkg cand
    for pkg in js8call python3-pyqt5.qtwebengine; do
        cand="$(apt_candidate "$pkg")"
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            result OK "package: $pkg" "already installed"
        elif [ -n "$cand" ]; then
            result OK "package: $pkg" "available ($cand)"
        elif apt_lists_empty; then
            result WARN "package: $pkg" "can't tell - apt has no package lists yet" "Run 'sudo apt update' first, then check again."
        else
            result FAIL "package: $pkg" "not available from your apt sources" "Enable the 'universe' component (Ubuntu) / check your Mint sources, then 'sudo apt update'."
        fi
    done
}

check_audio() {
    if have pactl; then
        local server
        if server="$(pactl info 2>/dev/null | sed -n 's/^Server Name: //p')" && [ -n "$server" ]; then
            result OK "Audio server" "$server"
        else
            result FAIL "Audio server" "pactl can't reach PulseAudio/PipeWire" "Run this inside your logged-in desktop session (not over plain ssh), and make sure pipewire-pulse or pulseaudio is running."
        fi
    else
        if pgrep -x 'pipewire-pulse|pulseaudio' >/dev/null 2>&1; then
            result WARN "Audio server" "running, but 'pactl' isn't installed" "The installer will install pulseaudio-utils."
        else
            result WARN "Audio server" "'pactl' isn't installed and no audio server was found" "The installer will install pulseaudio-utils; you still need a running PipeWire or PulseAudio session."
        fi
    fi
}

check_desktop() {
    if [ "$PF_GUI" = 0 ]; then result WARN "Desktop session" "skipped (--no-gui-check)" ""; return; fi
    if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        result OK "Desktop session" "${XDG_SESSION_TYPE:-graphical} session (DISPLAY=${DISPLAY:-none})"
    else
        result FAIL "Desktop session" "no graphical session found (DISPLAY/WAYLAND_DISPLAY unset)" "JS8Call and CommStat are desktop apps. Run this from a terminal inside your desktop, not over plain ssh."
    fi
    local b
    for b in firefox firefox-esr chromium chromium-browser google-chrome brave-browser epiphany falkon; do
        if have "$b"; then result OK "Web browser" "$b (plays the WebSDR audio)"; return; fi
    done
    if have flatpak && flatpak list --app 2>/dev/null | grep -qiE 'firefox|chromium|chrome|brave'; then
        result OK "Web browser" "found (flatpak)"; return
    fi
    result WARN "Web browser" "none found" "You need a browser to play the WebSDR/KiwiSDR page (install Firefox or Chromium)."
}

check_clock() {
    if have timedatectl; then
        local sync; sync="$(timedatectl show -p NTPSynchronized --value 2>/dev/null)"
        case "$sync" in
            yes) result OK "Clock" "synchronized (JS8 decoding needs time accurate to about a second)" ;;
            no)  result WARN "Clock" "not synchronized" "JS8 decodes on tight time slots. Turn on automatic time ('sudo timedatectl set-ntp true')." ;;
            *)   result WARN "Clock" "could not determine sync status" "" ;;
        esac
    else
        result WARN "Clock" "timedatectl not available" "Make sure your system clock is accurate; JS8 needs it within about a second."
    fi
}

check_settings() {
    local bad=0
    valid_name "$PROFILE" || { result FAIL "Setting: PROFILE" "'$PROFILE' - use letters, digits and underscores only" "Edit $CONFIG_DIR/config."; bad=1; }
    valid_name "$SINK"    || { result FAIL "Setting: SINK" "'$SINK' - use letters, digits and underscores only" ""; bad=1; }
    valid_name "$TXVOID"  || { result FAIL "Setting: TXVOID" "'$TXVOID' - use letters, digits and underscores only" ""; bad=1; }
    valid_port "$TCP_PORT" || { result FAIL "Setting: TCP_PORT" "'$TCP_PORT' is not a port between 1024 and 65535" ""; bad=1; }
    valid_port "$UDP_PORT" || { result FAIL "Setting: UDP_PORT" "'$UDP_PORT' is not a port between 1024 and 65535" ""; bad=1; }
    [ "$SINK" = "$TXVOID" ] && { result FAIL "Setting: SINK/TXVOID" "the receive and discard sinks must be different" ""; bad=1; }
    [ "$bad" = 0 ] && result OK "Settings" "profile '$PROFILE', ports $TCP_PORT/$UDP_PORT, sinks $SINK / $TXVOID"
}

check_existing() {
    local ours=0
    pgrep -f "(^|/)js8call -r $PROFILE( |\$)" >/dev/null 2>&1 && ours=1
    if [ "$ours" = 1 ]; then
        result WARN "JS8Call profile" "'$PROFILE' is running right now" "Close it before installing; JS8Call rewrites its settings when it exits."
    fi
    if port_in_use "$TCP_PORT"; then
        if [ "$ours" = 1 ]; then result OK "TCP port $TCP_PORT" "in use by this install's own JS8Call"
        else result FAIL "TCP port $TCP_PORT" "already in use by something else" "Choose another port: set TCP_PORT in $CONFIG_DIR/config (or WEBSDR_JS8_TCP_PORT)."; fi
    else
        result OK "TCP port $TCP_PORT" "free"
    fi
    [ -f "$JS8_INI" ] && result OK "JS8Call profile" "$JS8_INI exists - it will be kept, not overwritten"
    [ -d "$COMMSTAT_DIR/.git" ] && result OK "CommStat" "existing install at $COMMSTAT_DIR - it will be reused, not overwritten"
    return 0
}

# --------------------------------------------------------------------- main
run_preflight() {
    N_OK=0; N_WARN=0; N_FAIL=0
    printf '%sJS8Call-CommStat-Receive-Only %s - prerequisite check%s\n' "$C_BLD" "$WEBSDR_JS8_VERSION" "$C_OFF"
    printf '%sRead-only: nothing is installed or changed.%s\n\n' "$C_DIM" "$C_OFF"
    check_os; check_arch; check_user; check_resources; check_tools
    check_network; check_apt; check_audio; check_desktop; check_clock
    check_settings; check_existing
    printf '\n  %d passed, %d warning(s), %d failure(s)\n' "$N_OK" "$N_WARN" "$N_FAIL"
    if [ "$N_FAIL" -gt 0 ]; then
        printf '\n%sNot ready: fix the items marked FAIL above, then run ./preflight.sh again.%s\n' "$C_RED" "$C_OFF"
        return 1
    fi
    [ "$N_WARN" -gt 0 ] && printf '\nReady to install. Warnings won'"'"'t stop the install, but are worth a look.\n' \
                        || printf '\nAll clear - ready to install.\n'
    return 0
}

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    while [ $# -gt 0 ]; do
        case "$1" in
            --quiet)        PF_QUIET=1 ;;
            --no-network)   PF_NETWORK=0 ;;
            --no-gui-check) PF_GUI=0 ;;
            -h|--help)      usage; exit 0 ;;
            *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        esac
        shift
    done
    run_preflight
fi
