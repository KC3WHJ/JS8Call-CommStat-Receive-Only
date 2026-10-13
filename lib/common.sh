# shellcheck shell=bash
# Shared helpers for install.sh, preflight.sh, uninstall.sh and the launchers.
# Source this file; it does nothing on its own.

WEBSDR_JS8_VERSION="0.2.0"

if [ -t 1 ]; then
    C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_DIM=$'\e[2m'; C_BLD=$'\e[1m'; C_OFF=$'\e[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_DIM=""; C_BLD=""; C_OFF=""
fi

info() { printf '%s\n' "$*"; }
step() { printf '\n%s==> %s%s\n' "$C_BLD" "$*" "$C_OFF"; }
warn() { printf '%sWARNING:%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()  { printf '%sERROR:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

# ---------------------------------------------------------------- settings
# Defaults, then ~/.config/websdr-js8/config, then WEBSDR_JS8_* environment
# variables (used by the test suite, and handy for a second, separate profile).
# The config file is parsed as plain KEY=VALUE lines against a whitelist - it
# is never sourced, so it can't run code.
_CONFIG_KEYS="PROFILE SINK TXVOID TCP_PORT UDP_PORT COMMSTAT_DIR CALLSIGN GRID STATE FLDIGI_DIR NBEMS_DIR FL_SINK FL_TXVOID FL_XMLRPC_PORT FL_ARQ_PORT FL_KISS_IO_PORT FL_KISS_OUT_PORT"

load_config() {
    CONFIG_DIR="${WEBSDR_JS8_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/websdr-js8}"
    DATA_DIR="${WEBSDR_JS8_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/websdr-js8}"
    JS8_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"     # where JS8Call keeps its .ini files

    PROFILE="WebSDR"          # JS8Call profile name: js8call -r <PROFILE>
    SINK="websdr_sink"        # virtual sink the WebSDR's audio is routed into
    TXVOID="websdr_txvoid"    # virtual sink JS8Call's *transmit* audio is sent to (discarded)
    TCP_PORT=2443             # JS8Call's TCP API port that CommStat connects to
    UDP_PORT=2238             # JS8Call's UDP API port (unused, but kept off the defaults)
    COMMSTAT_DIR="$DATA_DIR/CommStat"
    CALLSIGN=""; GRID=""; STATE=""
    # FLDIGI + FLMSG + FLAMP station: its own settings folders, audio devices and ports, so it
    # never touches a normal (radio) FLDIGI setup and can run beside it and the JS8Call station.
    FLDIGI_DIR="$HOME/.fldigi-websdr"     # fldigi --config-dir
    NBEMS_DIR="$HOME/.nbems-websdr"       # FLMSG folder (FLAMP uses its FLAMP/ subfolder)
    FL_SINK="websdr_fldigi"               # WebSDR audio in
    FL_TXVOID="websdr_fldigi_txvoid"      # FLDIGI transmit audio, discarded
    FL_XMLRPC_PORT=7363                   # FLDIGI's XML-RPC port (FLMSG, FLAMP); a normal FLDIGI uses 7362
    FL_ARQ_PORT=7323                      # FLDIGI's ARQ port (FLAMP); normally 7322
    FL_KISS_IO_PORT=7344; FL_KISS_OUT_PORT=7345
    FL_IPC_KEY=9877                       # FLDIGI's shared-memory key; normally 9876

    local k v line
    if [ -f "$CONFIG_DIR/config" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in ''|'#'*) continue ;; esac
            k="${line%%=*}"; v="${line#*=}"
            v="${v%\"}"; v="${v#\"}"
            case " $_CONFIG_KEYS " in *" $k "*) printf -v "$k" '%s' "$v" ;; esac
        done < "$CONFIG_DIR/config"
    fi
    # environment overrides win
    PROFILE="${WEBSDR_JS8_PROFILE:-$PROFILE}"
    SINK="${WEBSDR_JS8_SINK:-$SINK}"
    TXVOID="${WEBSDR_JS8_TXVOID:-$TXVOID}"
    TCP_PORT="${WEBSDR_JS8_TCP_PORT:-$TCP_PORT}"
    UDP_PORT="${WEBSDR_JS8_UDP_PORT:-$UDP_PORT}"
    COMMSTAT_DIR="${WEBSDR_JS8_COMMSTAT_DIR:-$COMMSTAT_DIR}"
    FLDIGI_DIR="${WEBSDR_JS8_FLDIGI_DIR:-$FLDIGI_DIR}"
    NBEMS_DIR="${WEBSDR_JS8_NBEMS_DIR:-$NBEMS_DIR}"
    FL_SINK="${WEBSDR_JS8_FL_SINK:-$FL_SINK}"
    FL_TXVOID="${WEBSDR_JS8_FL_TXVOID:-$FL_TXVOID}"
    FL_XMLRPC_PORT="${WEBSDR_JS8_FL_XMLRPC_PORT:-$FL_XMLRPC_PORT}"
    FL_ARQ_PORT="${WEBSDR_JS8_FL_ARQ_PORT:-$FL_ARQ_PORT}"
    FL_KISS_IO_PORT="${WEBSDR_JS8_FL_KISS_IO_PORT:-$FL_KISS_IO_PORT}"
    FL_KISS_OUT_PORT="${WEBSDR_JS8_FL_KISS_OUT_PORT:-$FL_KISS_OUT_PORT}"
    FL_IPC_KEY="${WEBSDR_JS8_FL_IPC_KEY:-$FL_IPC_KEY}"

    JS8_INI="$JS8_CONFIG_HOME/JS8Call - $PROFILE.ini"
}

# Writes the current settings back out (used by the installer).
write_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/config" <<EOF
# WebSDR-Digital-Receive-Only settings. Plain KEY=VALUE lines; edit and re-run the
# installer (or just restart) to apply. Environment variables named
# WEBSDR_JS8_<KEY> override these.
PROFILE=$PROFILE
SINK=$SINK
TXVOID=$TXVOID
TCP_PORT=$TCP_PORT
UDP_PORT=$UDP_PORT
COMMSTAT_DIR=$COMMSTAT_DIR
CALLSIGN=$CALLSIGN
GRID=$GRID
STATE=$STATE
FLDIGI_DIR=$FLDIGI_DIR
NBEMS_DIR=$NBEMS_DIR
FL_SINK=$FL_SINK
FL_TXVOID=$FL_TXVOID
FL_XMLRPC_PORT=$FL_XMLRPC_PORT
FL_ARQ_PORT=$FL_ARQ_PORT
FL_KISS_IO_PORT=$FL_KISS_IO_PORT
FL_KISS_OUT_PORT=$FL_KISS_OUT_PORT
EOF
}

# -------------------------------------------------------------- validation
# Deliberately loose: a licensed call (W1AW, W1AW/P), or any short tactical /
# placeholder ID (N0CALL) for someone who is only listening. It only has to be
# safe to put in a config file; CommStat and JS8Call do their own interpretation.
valid_callsign() { [[ "$1" =~ ^[A-Za-z0-9/]{3,12}$ ]]; }
valid_grid()     { [[ "$1" =~ ^[A-Ra-r]{2}[0-9]{2}([A-Xa-x]{2})?$ ]]; }
valid_state()    { [[ -z "$1" || "$1" =~ ^[A-Za-z]{2}$ ]]; }
valid_port()     { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1024 ] && [ "$1" -le 65535 ]; }
valid_name()     { [[ "$1" =~ ^[A-Za-z0-9_]+$ ]]; }          # profile / sink names: no spaces or shell-special characters

# ----------------------------------------------------------- small helpers
have() { command -v "$1" >/dev/null 2>&1; }

# True if something is listening on the given local TCP port.
port_in_use() { ss -tln 2>/dev/null | awk -v p=":$1" '$4 ~ p"$" {f=1} END{exit !f}'; }

# Is a PulseAudio/PipeWire null-sink module with exactly this sink name loaded?
# (Checks the module list, which updates the instant load-module returns,
# rather than the sink list - so two quick starts can never create a duplicate.)
sink_module_loaded() { pactl list short modules 2>/dev/null | grep -Eq "sink_name=$1([[:space:]]|$)"; }

# Create a null sink if it isn't already there.
ensure_null_sink() {  # name description
    if sink_module_loaded "$1"; then return 0; fi
    pactl load-module module-null-sink "sink_name=$1" "sink_properties=device.description=$2" >/dev/null
}

# Unload EVERY module for a sink name, one call each (a duplicate would put two
# ids in a single unload-module call, which fails and strands the sink).
remove_null_sink() {  # name
    local id
    for id in $(pactl list short modules 2>/dev/null | awk -v s="sink_name=$1" '$0 ~ s"([[:space:]]|$)" {print $1}'); do
        pactl unload-module "$id" 2>/dev/null || true
    done
}

# Read one key from a JS8Call .ini file (first match wins; prints nothing if absent).
ini_get() {  # file key
    [ -f "$1" ] || return 0
    sed -n "s/^$2=//p" "$1" | head -1
}

# ------------------------------------------------------------ audio routing
# Ask which browser stream is the WebSDR, move it into a virtual sink, then start the
# stray-stream watcher. Shared by websdr-js8-start and websdr-fldigi-start.
#   route_browser_stream SINK APP_NAME TUNING_HINT START_CMD STOP_CMD WATCHER WATCH_LOG
# Returns 0 when a stream is routed (or already was), 1 otherwise.
route_browser_stream() {
    local sink="$1" app="$2" hint="$3" start_cmd="$4" stop_cmd="$5" watcher="$6" watch_log="$7"
    local streams choice="" idx label default_sink

    step "Route your WebSDR's audio into $app"
    if pactl -f json list sink-inputs 2>/dev/null | python3 -c '
import json, subprocess, sys
name = sys.argv[1]
sinks = {s["name"]: s["index"] for s in json.loads(subprocess.run(["pactl", "-f", "json", "list", "sinks"], capture_output=True, text=True).stdout)}
want = sinks.get(name)
sys.exit(0 if want is not None and any(i.get("sink") == want for i in json.load(sys.stdin)) else 1)' "$sink"; then
        info "A stream is already routed into $sink - nothing more to do."
        info; info "When you're finished: $stop_cmd"; return 0
    fi

    cat <<EOT
1. In your browser, open a web SDR or KiwiSDR and start its audio playing.
   $hint
2. Come back here and press Enter.
EOT
    read -r -p "" _

    streams="$(pactl -f json list sink-inputs 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
for i in data:
    p = i.get("properties", {})
    label = p.get("application.name", "unknown app")
    media = p.get("media.name", "")
    if media:
        label += " - " + media
    print("%s\t%s" % (i["index"], label.replace("\t", " ")))')"
    if [ -z "$streams" ]; then
        echo "No audio is playing yet. Start the WebSDR's audio, then run $start_cmd again"
        echo "(it's safe to re-run; everything already started is reused)."
        return 1
    fi

    if have dialog; then
        local args=()
        while IFS=$'\t' read -r idx label; do args+=("$idx" "$label"); done <<<"$streams"
        choice="$(dialog --clear --menu "Which audio stream is the WebSDR?" 15 76 8 "${args[@]}" 3>&1 1>&2 2>&3)" || true
        clear
    else
        echo "Which audio stream is the WebSDR?"
        local ids=() labels=() lbl
        while IFS=$'\t' read -r idx label; do ids+=("$idx"); labels+=("$label"); done <<<"$streams"
        select lbl in "${labels[@]}"; do
            [ -n "${lbl:-}" ] && { choice="${ids[$((REPLY-1))]}"; break; }
        done
    fi
    [ -n "$choice" ] || { echo "Nothing selected - nothing routed. Run $start_cmd again to retry."; return 1; }

    pactl move-sink-input "$choice" "$sink" || die "couldn't move the stream into $sink."
    info "Routed stream $choice into $sink. $app should start decoding shortly."

    # PipeWire/PulseAudio quirk: once one stream from an app is moved into the sink, it remembers
    # that choice PER APPLICATION, not per tab - so a second, unrelated stream from the same app
    # (another browser tab) can get silently swept in too and go silent. This watcher undoes that
    # for the rest of the session; the matching stop command stops it.
    if [ -x "$watcher" ]; then
        default_sink="$(pactl get-default-sink)"
        setsid -f "$watcher" "$sink" "$choice" "$default_sink" "$watch_log" >/dev/null 2>&1 </dev/null
        info "Watching for any OTHER app audio that lands on $sink by mistake (log: $watch_log)."
    fi
    info; info "When you're finished: $stop_cmd"
    return 0
}
