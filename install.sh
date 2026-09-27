#!/usr/bin/env bash
# Installer for JS8Call-CommStat-Receive-Only: a receive-only JS8Call + CommStat station
# fed by a web SDR / KiwiSDR audio stream (no radio, no transmitting).
#
#   ./install.sh                  check prerequisites, then install
#   ./install.sh --check          prerequisite check only (changes nothing)
#
# Options:
#   --callsign CALL --grid GRID --state ST   skip the questions (state is optional)
#   -y, --yes                     don't stop to ask; accept warnings
#   --skip-apt                    don't install packages (you've done it already)
#   --skip-commstat-deps          don't run CommStat's own dependency installer
#   --no-desktop-icons            don't create Desktop shortcuts
#   --no-network, --no-gui-check  skip those prerequisite checks (testing only)
#   -h, --help                    this text
#
# Order of operations: (1) prerequisite check - if anything is marked FAIL the
# installer stops here and has changed nothing; (2) questions; (3) packages;
# (4) CommStat; (5) configuration; (6) launchers; (7) verification.
set -eu

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# preflight.sh only defines functions when sourced; it sources lib/common.sh itself.
# shellcheck source=preflight.sh
. "$HERE/preflight.sh"

ASSUME_YES=0; CHECK_ONLY=0; SKIP_APT=0; SKIP_CS_DEPS=0; DESKTOP_ICONS=1
OPT_CALL=""; OPT_GRID=""; OPT_STATE=""
COMMSTAT_URL="${WEBSDR_JS8_COMMSTAT_URL:-https://github.com/mgochoa57/CommStat.git}"
BIN_DIR="${WEBSDR_JS8_BIN_DIR:-$HOME/.local/bin}"
RIG_NAME="WebSDR"     # the connector's name inside CommStat
APT_PACKAGES="js8call git dialog pulseaudio-utils python3 ca-certificates curl"

while [ $# -gt 0 ]; do
    case "$1" in
        --check)              CHECK_ONLY=1 ;;
        -y|--yes)             ASSUME_YES=1 ;;
        --skip-apt)           SKIP_APT=1 ;;
        --skip-commstat-deps) SKIP_CS_DEPS=1 ;;
        --no-desktop-icons)   DESKTOP_ICONS=0 ;;
        --no-network)         PF_NETWORK=0 ;;     # skip the internet checks (offline testing)
        --no-gui-check)       PF_GUI=0 ;;         # skip the desktop-session check (headless testing)
        --callsign)           OPT_CALL="${2:?--callsign needs a value}"; shift ;;
        --grid)               OPT_GRID="${2:?--grid needs a value}"; shift ;;
        --state)              OPT_STATE="${2:?--state needs a value}"; shift ;;
        -h|--help)            sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

# ------------------------------------------------------ 1. prerequisites
if ! run_preflight; then
    echo
    echo "Nothing was installed or changed."
    exit 1
fi
[ "$CHECK_ONLY" = 1 ] && exit 0

if [ "$N_WARN" -gt 0 ] && [ "$ASSUME_YES" = 0 ]; then
    echo
    read -r -p "Continue despite the warnings above? [Y/n] " ans
    case "${ans:-Y}" in [Yy]*) ;; *) echo "Stopped. Nothing was installed or changed."; exit 1 ;; esac
fi

# -------------------------------------------------------------- 2. settings
step "Your details"
cat <<'EOF'
CommStat and JS8Call need a callsign and grid square to start. If you're only
listening you can use any short ID (for example a tactical call, or N0CALL);
use your real callsign if you have one. The grid is where YOU are, not the SDR.
EOF

ask() {  # varname "prompt" validator "error message" [default]
    local var="$1" prompt="$2" check="$3" err="$4" def="${5:-}" val=""
    val="${!var:-}"
    while :; do
        if [ -z "$val" ]; then
            if [ ! -t 0 ]; then die "$prompt is required. Pass it as a flag (see --help) when running non-interactively."; fi
            read -r -p "$prompt${def:+ [$def]}: " val
            val="${val:-$def}"
        fi
        if "$check" "$val"; then break; fi
        echo "  $err" >&2; val=""
        [ -t 0 ] || exit 1
    done
    printf -v "$var" '%s' "$val"
}

[ -n "$OPT_CALL" ]  && CALLSIGN="$OPT_CALL"
[ -n "$OPT_GRID" ]  && GRID="$OPT_GRID"
[ -n "$OPT_STATE" ] && STATE="$OPT_STATE"
ask CALLSIGN "Callsign or ID"                 valid_callsign "Use 3-12 letters/digits (a '/' is allowed), e.g. W1AW or N0CALL."
ask GRID     "Your 4- or 6-character grid"    valid_grid     "A grid square looks like FN31 or FN31pr (letters A-R, then two digits)."
if [ -z "$OPT_STATE" ] && [ -z "$STATE" ] && [ -t 0 ]; then
    read -r -p "Your US state code, e.g. PA (blank if not applicable): " STATE
fi
valid_state "$STATE" || die "State must be two letters (or empty)."
CALLSIGN="${CALLSIGN^^}"; STATE="${STATE^^}"
# Maidenhead convention: field letters upper case, subsquare letters lower case (FN31pr).
GRID="${GRID^^}"; _sub="${GRID:4}"; GRID="${GRID:0:4}${_sub,,}"
info "Using: $CALLSIGN  $GRID  ${STATE:-(no state)}"

# -------------------------------------------------------------- 3. packages
if [ "$SKIP_APT" = 1 ]; then
    step "Packages"; info "Skipped (--skip-apt)."
else
    step "Installing packages (sudo password may be requested)"
    info "Packages: $APT_PACKAGES"
    sudo apt-get update
    # shellcheck disable=SC2086
    sudo apt-get install -y $APT_PACKAGES
fi

# -------------------------------------------------------------- 4. CommStat
step "CommStat"
mkdir -p "$(dirname "$COMMSTAT_DIR")"
if [ -d "$COMMSTAT_DIR/.git" ]; then
    # CommStat updates itself in place (its server pushes program updates that rewrite its
    # files), so its checkout is normally "dirty" after first use, and a plain `git pull`
    # would abort. Pull only when clean; otherwise leave updating to the app itself.
    if [ -z "$(cd "$COMMSTAT_DIR" && git -c core.fileMode=false status --porcelain --untracked-files=no)" ]; then
        (cd "$COMMSTAT_DIR" && git -c core.fileMode=false pull --ff-only) \
            || warn "couldn't update CommStat from GitHub - keeping the installed copy."
    else
        info "CommStat has updated itself in place (its own update channel) - keeping it as it is."
    fi
elif [ -e "$COMMSTAT_DIR" ]; then
    info "$COMMSTAT_DIR exists but isn't a git checkout - using it as it is."
else
    git clone --quiet "$COMMSTAT_URL" "$COMMSTAT_DIR"
    info "Cloned CommStat to $COMMSTAT_DIR."
fi
[ -f "$COMMSTAT_DIR/commstat.py" ] || die "CommStat's files aren't at $COMMSTAT_DIR after cloning - something went wrong."

if [ "$SKIP_CS_DEPS" = 1 ]; then
    info "Skipped CommStat's own dependency installer (--skip-commstat-deps)."
elif [ -f "$COMMSTAT_DIR/linuxinstall.sh" ]; then
    info "Running CommStat's own Linux installer (installs Qt WebEngine and Python packages)..."
    (cd "$COMMSTAT_DIR" && bash linuxinstall.sh)
else
    warn "CommStat has no linuxinstall.sh here - install its dependencies by hand (see its README)."
fi

# --------------------------------------------------------- 5. configuration
step "Configuring for receive-only use"
python3 "$HERE/share/seed_commstat.py" "$COMMSTAT_DIR" "$CALLSIGN" "$GRID" "$STATE" "$RIG_NAME" "$TCP_PORT"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
if [ -f "$JS8_INI" ]; then
    info "JS8Call profile '$PROFILE' already exists - keeping it."
    if [ "$(ini_get "$JS8_INI" Rig)" != "None" ]; then
        warn "That profile is NOT receive-only (Rig is '$(ini_get "$JS8_INI" Rig)'), so websdr-js8-start will refuse to use it. Choose another PROFILE in $CONFIG_DIR/config, or remove $JS8_INI."
    fi
else
    tpl="$(cat "$HERE/share/JS8Call-profile.ini.template")"
    tpl="${tpl//@CALLSIGN@/$CALLSIGN}"; tpl="${tpl//@GRID@/$GRID}"
    tpl="${tpl//@PROFILE@/$PROFILE}";   tpl="${tpl//@DATA_HOME@/$DATA_HOME}"
    tpl="${tpl//@SINK@/$SINK}";         tpl="${tpl//@TXVOID@/$TXVOID}"
    tpl="${tpl//@TCP_PORT@/$TCP_PORT}"; tpl="${tpl//@UDP_PORT@/$UDP_PORT}"
    mkdir -p "$JS8_CONFIG_HOME"
    printf '%s\n' "$tpl" > "$JS8_INI"
    info "Wrote JS8Call profile: $JS8_INI  (no rig control, spotting off, transmit audio discarded)"
fi
write_config
info "Saved settings to $CONFIG_DIR/config"

# ------------------------------------------------------------ 6. launchers
step "Installing launchers"
mkdir -p "$BIN_DIR" "$DATA_DIR/app/lib" "$DATA_DIR/app/share"
cp "$HERE/lib/common.sh" "$DATA_DIR/app/lib/"
cp "$HERE/share/JS8Call-profile.ini.template" "$HERE/share/seed_commstat.py" "$DATA_DIR/app/share/"
install -m 0755 "$HERE/bin/websdr-js8-start" "$HERE/bin/websdr-js8-stop" "$HERE/bin/websdr-js8-watch-sink" "$BIN_DIR/"
info "Installed websdr-js8-start, websdr-js8-stop and websdr-js8-watch-sink in $BIN_DIR"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "$BIN_DIR isn't on your PATH yet - log out and back in, or run: export PATH=\"$BIN_DIR:\$PATH\"" ;; esac

APPS_DIR="$DATA_HOME/applications"
mkdir -p "$APPS_DIR"
make_desktop() {  # file name comment exec icon
    cat > "$1" <<EOF
[Desktop Entry]
Type=Application
Name=$2
Comment=$3
Exec=bash -c "$4; echo; read -r -p 'Press Enter to close this window...'"
Terminal=true
Icon=$5
Categories=HamRadio;Network;
EOF
    chmod +x "$1"
}
make_desktop "$APPS_DIR/websdr-js8-start.desktop" "Start WebSDR JS8Call + CommStat" \
    "Receive-only JS8Call and CommStat fed by a web SDR" "$BIN_DIR/websdr-js8-start" network-wireless
make_desktop "$APPS_DIR/websdr-js8-stop.desktop"  "Stop WebSDR JS8Call + CommStat" \
    "Stops the receive-only station and removes its virtual audio devices" "$BIN_DIR/websdr-js8-stop" process-stop
info "Added both to your applications menu."
if [ "$DESKTOP_ICONS" = 1 ]; then
    DESK="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
    if [ -d "$DESK" ]; then
        cp "$APPS_DIR/websdr-js8-start.desktop" "$APPS_DIR/websdr-js8-stop.desktop" "$DESK/"
        for f in "$DESK/websdr-js8-start.desktop" "$DESK/websdr-js8-stop.desktop"; do
            gio set "$f" "metadata::trusted" true 2>/dev/null || true
        done
        info "Added Desktop shortcuts."
    fi
fi

# ------------------------------------------------------------ 7. verify
step "Checking the result"
bad=0
have js8call && info "  ok  js8call: $(command -v js8call)" || { warn "js8call not found"; bad=1; }
if python3 -c 'import PyQt5.QtWebEngineWidgets, PyQt5.QtMultimedia' 2>/dev/null; then info "  ok  Qt WebEngine / Multimedia available to Python"
else warn "CommStat's Qt WebEngine Python modules aren't importable - re-run without --skip-commstat-deps."; bad=1; fi
[ -f "$JS8_INI" ]                    && info "  ok  JS8Call profile"          || { warn "JS8Call profile missing"; bad=1; }
[ -f "$COMMSTAT_DIR/traffic.db3" ]   && info "  ok  CommStat database"        || { warn "CommStat database missing"; bad=1; }
[ -x "$BIN_DIR/websdr-js8-start" ] && [ -x "$BIN_DIR/websdr-js8-watch-sink" ] \
                                     && info "  ok  launchers"                || { warn "launchers missing"; bad=1; }

echo
if [ "$bad" = 0 ]; then
    printf '%sInstalled.%s\n' "$C_GRN" "$C_OFF"
else
    printf '%sInstalled with problems - see the warnings above.%s\n' "$C_YEL" "$C_OFF"
fi
cat <<EOF

Next:
  1. Run  websdr-js8-start   (or use the "Start WebSDR JS8Call + CommStat" icon)
  2. Open a web SDR / KiwiSDR in your browser, tune it to a JS8 frequency
     in USB mode (e.g. 7.078 MHz), and play its audio.
  3. Pick that browser stream when asked. JS8Call starts decoding; CommStat
     connects to it automatically.
  4. When finished:  websdr-js8-stop

See docs/USAGE.md for details. To remove everything: ./uninstall.sh
EOF
