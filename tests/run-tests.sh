#!/usr/bin/env bash
# Test suite for JS8Call-CommStat-Receive-Only.
#
#   tests/run-tests.sh
#
# Needs no sudo, no GUI and no internet. Everything runs in a throwaway HOME with
# its own JS8Call profile name, audio-device names and ports, so it can run next to a
# live installation without touching it. JS8Call is replaced by a small stand-in
# (tests/stubs/js8call) and CommStat's GUI by stand-in scripts; CommStat's real
# database template and connector code ARE used (copied from $COMMSTAT_SRC,
# ~/CommStat, or a GitHub clone), so the seeding is tested for real.
#
# It does need a running PulseAudio/PipeWire (it creates and removes two virtual
# audio devices).
set -u

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
REAL_HOME="$HOME"
T="$(mktemp -d)"
PASS=0; FAILED=0
if [ -t 1 ]; then G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; O=$'\e[0m'; else G=""; R=""; Y=""; O=""; fi

ok()   { PASS=$((PASS+1)); printf '  %sok%s    %s\n' "$G" "$O" "$1"; }
bad()  { FAILED=$((FAILED+1)); printf '  %sFAIL%s  %s\n' "$R" "$O" "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/          /' | head -12; }
skip() { printf '  %sskip%s  %s\n' "$Y" "$O" "$1"; }
t()    { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }   # t "description" command args...
section() { printf '\n%s\n' "$1"; }

free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'; }

# --------------------------------------------------------------- isolation
export HOME="$T/home"; mkdir -p "$HOME"
unset XDG_CONFIG_HOME XDG_DATA_HOME WEBSDR_JS8_APP_DIR
TCP="$(free_port)"; UDP="$(free_port)"
export WEBSDR_JS8_PROFILE=RxTest WEBSDR_JS8_SINK=rxtest_sink WEBSDR_JS8_TXVOID=rxtest_txvoid
export WEBSDR_JS8_TCP_PORT="$TCP" WEBSDR_JS8_UDP_PORT="$UDP"
export PATH="$ROOT/tests/stubs:$PATH"
CS="$HOME/.local/share/websdr-js8/CommStat"
INI="$HOME/.config/JS8Call - RxTest.ini"
START="$HOME/.local/bin/websdr-js8-start"; STOP="$HOME/.local/bin/websdr-js8-stop"

count_procs() { pgrep -fc "$1" 2>/dev/null || true; }
modules_for() { pactl list short modules 2>/dev/null | grep -Ec "sink_name=$1([[:space:]]|\$)" || true; }
js8_pid()     { pgrep -f "/js8call -r RxTest( |\$)" | head -1; }
cs_pid()      { pgrep -f "python3 $CS/little_gucci.py" | head -1; }

cleanup() {
    local p
    for p in $(pgrep -f "/js8call -r RxTest( |\$)") $(pgrep -f "python3 $CS/little_gucci.py") \
             $(pgrep -f "websdr-js8-watch-sink rxtest_sink") $(pgrep -f "paplay.*$T/tone.wav"); do
        kill "$p" 2>/dev/null
    done
    for s in rxtest_sink rxtest_txvoid; do
        for id in $(pactl list short modules 2>/dev/null | awk -v s="sink_name=$s" '$0 ~ s {print $1}'); do pactl unload-module "$id" 2>/dev/null; done
    done
    rm -rf "$T"
}
trap cleanup EXIT

# ------------------------------------------------------------------- lint
section "Syntax"
for f in install.sh uninstall.sh preflight.sh lib/common.sh bin/websdr-js8-start bin/websdr-js8-stop bin/websdr-js8-watch-sink tests/run-tests.sh; do
    t "bash -n $f" bash -n "$ROOT/$f"
done
# (parse only - py_compile would write .pyc files into the repo)
t "python syntax share/seed_commstat.py" python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$ROOT/share/seed_commstat.py"
t "python syntax tests/stubs/js8call" python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$ROOT/tests/stubs/js8call"

# --------------------------------------------------------------- helpers
section "Validation helpers and settings"
# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"
t "callsign W1AW accepted"        valid_callsign W1AW
t "callsign W1AW/P accepted"        valid_callsign W1AW/P
t "callsign N0CALL accepted"        valid_callsign N0CALL
t "callsign 'ab' rejected"          bash -c '. "$0"; ! valid_callsign ab' "$ROOT/lib/common.sh"
t "callsign with a space rejected"  bash -c '. "$0"; ! valid_callsign "bad call"' "$ROOT/lib/common.sh"
t "callsign with ';' rejected"      bash -c '. "$0"; ! valid_callsign "x;rm"' "$ROOT/lib/common.sh"
t "grid FN31pr accepted"            valid_grid FN31pr
t "grid fn31 accepted"              valid_grid fn31
t "grid ZZ99 rejected"              bash -c '. "$0"; ! valid_grid ZZ99' "$ROOT/lib/common.sh"
t "grid FN2 rejected"               bash -c '. "$0"; ! valid_grid FN2' "$ROOT/lib/common.sh"
t "state empty accepted"            valid_state ""
t "state PA accepted"               valid_state PA
t "state PAA rejected"              bash -c '. "$0"; ! valid_state PAA' "$ROOT/lib/common.sh"
t "port 2443 accepted"              valid_port 2443
t "port 80 rejected"                bash -c '. "$0"; ! valid_port 80' "$ROOT/lib/common.sh"

mkdir -p "$T/cfg"
printf '%s\n' '# comment' 'PROFILE=FromFile' 'EVIL=$(touch /tmp/pwned)' 'CALLSIGN="Q1XYZ"' 'TCP_PORT=2999' > "$T/cfg/config"
out="$(env -u WEBSDR_JS8_PROFILE -u WEBSDR_JS8_TCP_PORT WEBSDR_JS8_CONFIG_DIR="$T/cfg" bash -c '. "$0"; load_config; echo "$PROFILE|$CALLSIGN|$TCP_PORT"' "$ROOT/lib/common.sh")"
[ "$out" = "FromFile|Q1XYZ|2999" ] && ok "config file is parsed (quotes handled, unknown keys ignored, never executed)" || bad "config parsing" "$out"
[ ! -e /tmp/pwned ] && ok "config file cannot run code" || { bad "config file executed code!"; rm -f /tmp/pwned; }
out="$(WEBSDR_JS8_CONFIG_DIR="$T/cfg" WEBSDR_JS8_PROFILE=EnvWins bash -c '. "$0"; load_config; echo "$PROFILE"' "$ROOT/lib/common.sh")"
[ "$out" = "EnvWins" ] && ok "environment overrides the config file" || bad "env override" "$out"

# ------------------------------------------------------------- preflight
section "Prerequisite check (preflight.sh)"
PF=("$ROOT/preflight.sh" --no-network --no-gui-check)
out="$("${PF[@]}" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "passes on this machine (exit 0)" || bad "preflight should pass here (exit $rc)" "$out"
echo "$out" | grep -q "Operating system" && ok "reports the operating system" || bad "no OS line"
t "read-only: --quiet mode runs" "${PF[@]}" --quiet

mkdir -p "$T/fakebin"
printf '#!/bin/sh\n[ "$1" = "-u" ] && { echo 0; exit 0; }\nexec /usr/bin/id "$@"\n' > "$T/fakebin/id"; chmod +x "$T/fakebin/id"
out="$(PATH="$T/fakebin:$PATH" "${PF[@]}" 2>&1)"; rc=$?
{ [ "$rc" = 1 ] && echo "$out" | grep -q "root"; } && ok "FAILS when run as root (exit 1)" || bad "root should fail" "rc=$rc"

python3 -c "
import socket,sys,time
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(('127.0.0.1', $TCP)); s.listen(1); time.sleep(30)" &
BLOCK_PID=$!
sleep 0.7
out="$("${PF[@]}" 2>&1)"; rc=$?
kill "$BLOCK_PID" 2>/dev/null; wait "$BLOCK_PID" 2>/dev/null
{ [ "$rc" = 1 ] && echo "$out" | grep -q "already in use"; } && ok "FAILS when the JS8Call API port is taken by something else" || bad "port conflict should fail" "rc=$rc"

out="$(WEBSDR_JS8_TCP_PORT=80 "${PF[@]}" 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok "FAILS on an invalid port setting" || bad "invalid port should fail" "rc=$rc"
out="$(WEBSDR_JS8_PROFILE='bad name' "${PF[@]}" 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok "FAILS on a profile name with a space" || bad "bad profile name should fail" "rc=$rc"

out="$(PATH="$T/fakebin:$PATH" "$ROOT/install.sh" --yes --skip-apt --no-network --no-gui-check --callsign N0CALL --grid FN31 2>&1)"; rc=$?
# (pactl itself creates ~/.config/pulse in a fresh HOME, so check this project's own files, not the whole dir)
{ [ "$rc" = 1 ] && [ ! -e "$HOME/.config/websdr-js8" ] && [ ! -e "$HOME/.local" ] && [ ! -e "$INI" ]; } \
    && ok "install.sh stops at a failed prerequisite and changes NOTHING" || bad "install must not touch anything when preflight fails" "rc=$rc; $(find "$HOME" -type f | head -5)"

# -------------------------------------------------- CommStat source (stand-in GUI)
section "Installer (stand-in CommStat, real database template and connector code)"
SRC=""
for c in "${COMMSTAT_SRC:-}" "$REAL_HOME/CommStat"; do [ -n "$c" ] && [ -f "$c/traffic.db3.template" ] && [ -f "$c/connector_manager.py" ] && { SRC="$c"; break; }; done
if [ -z "$SRC" ] && (cd "$T" && git clone -q --depth 1 https://github.com/mgochoa57/CommStat.git "$T/cs-net" 2>/dev/null); then SRC="$T/cs-net"; fi
if [ -z "$SRC" ]; then
    skip "no CommStat source available (set COMMSTAT_SRC=/path/to/CommStat) - installer and launcher tests skipped"
else
    UP="$T/commstat-upstream"; mkdir -p "$UP"
    cp "$SRC"/*.py "$SRC/traffic.db3.template" "$UP/"
    # GUI replaced by stand-ins; everything else (connector_manager.py, the DB template) is real.
    cat > "$UP/commstat.py" <<'STUB_LAUNCHER_END'
import os, subprocess, sys
subprocess.call([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "little_gucci.py")])
STUB_LAUNCHER_END
    cat > "$UP/little_gucci.py" <<'STUB_MAIN_END'
import time
while True:
    time.sleep(1)
STUB_MAIN_END
    ( cd "$UP" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -q -m stub ) >/dev/null 2>&1
    export WEBSDR_JS8_COMMSTAT_URL="$UP"

    IN=("$ROOT/install.sh" --yes --skip-apt --skip-commstat-deps --no-desktop-icons --no-network --no-gui-check --callsign n0call --grid fn31 --state pa)
    out="$("${IN[@]}" 2>&1)"; rc=$?
    [ "$rc" = 0 ] && ok "installs non-interactively (exit 0)" || bad "install failed (exit $rc)" "$(echo "$out" | tail -15)"
    t "launchers installed and executable"        test -x "$START" -a -x "$STOP"
    t "app support files installed"               test -f "$HOME/.local/share/websdr-js8/app/lib/common.sh"
    t "settings file written"                     grep -q '^PROFILE=RxTest' "$HOME/.config/websdr-js8/config"
    t "CommStat cloned"                           test -f "$CS/commstat.py"
    t "JS8Call profile written"                   test -f "$INI"
    t "profile: Rig=None (no rig control)"        grep -qx 'Rig=None' "$INI"
    t "profile: no CAT / PTT ports"               bash -c '! grep -E "^(CATSerialPort|CATNetworkPort|PTTport)=." "$0"' "$INI"
    t "profile: PSKReporter spotting is OFF"      grep -qx 'PSKReporter=false' "$INI"
    t "profile: APRS spotting is OFF"             grep -qx 'SpotToAPRS=false' "$INI"
    t "profile: audio in = the receive sink"      grep -qx 'SoundInName=rxtest_sink.monitor' "$INI"
    t "profile: audio OUT = the discard sink"     grep -qx 'SoundOutName=rxtest_txvoid' "$INI"
    t "profile: API port from settings"           grep -qx "TCPServerPort=$TCP" "$INI"
    t "profile: callsign upper-cased"             grep -qx 'MyCall=N0CALL' "$INI"
    db="$CS/traffic.db3"
    out="$(python3 -c "
import sqlite3
c=sqlite3.connect('file:$db?mode=ro',uri=True)
print(c.execute('select callsign,gridsquare,state from controls').fetchone(), c.execute('select rig_name,tcp_port,auto_connect,rf_ack from js8_connectors').fetchall())")"
    [ "$out" = "('N0CALL', 'FN31', 'PA') [('WebSDR', $TCP, 1, 0)]" ] && ok "CommStat DB: user set, ONE connector, auto-connect on, RF Ack OFF" || bad "CommStat DB contents" "$out"

    echo "# my own edit" >> "$INI"
    out="$("${IN[@]}" 2>&1)"; rc=$?
    { [ "$rc" = 0 ] && grep -q '# my own edit' "$INI"; } && ok "re-running keeps an existing profile (never overwrites your edits)" || bad "re-run clobbered the profile" "$out"
    n="$(python3 -c "import sqlite3; print(sqlite3.connect('file:$db?mode=ro',uri=True).execute('select count(*) from js8_connectors').fetchone()[0])")"
    [ "$n" = 1 ] && ok "re-running does not duplicate the connector" || bad "connector count after re-run: $n"
    sed -i '/# my own edit/d' "$INI"

    out="$(HOME="$T/home2" "$ROOT/install.sh" --yes --skip-apt --skip-commstat-deps --no-network --no-gui-check --callsign N0CALL --grid ZZ99 </dev/null 2>&1)"; rc=$?
    { [ "$rc" != 0 ] && [ ! -e "$T/home2/.config/JS8Call - RxTest.ini" ]; } && ok "rejects an invalid grid square before installing anything" || bad "invalid grid accepted" "rc=$rc"

    # ---------------------------------------------------------- start / stop
    section "Launchers (websdr-js8-start / websdr-js8-stop)"
    out="$("$START" --no-route 2>&1)"; rc=$?
    [ "$rc" = 0 ] && ok "start exits 0" || bad "start failed (exit $rc)" "$out"
    [ "$(modules_for rxtest_sink)" = 1 ]   && ok "receive sink created (exactly one)"  || bad "receive sink count: $(modules_for rxtest_sink)"
    [ "$(modules_for rxtest_txvoid)" = 1 ] && ok "discard sink created (exactly one)" || bad "discard sink count: $(modules_for rxtest_txvoid)"
    [ -n "$(js8_pid)" ] && ok "JS8Call (profile RxTest) is running" || bad "JS8Call not running" "$out"
    ss -tln | grep -q ":$TCP " && ok "JS8Call's API port $TCP is open" || bad "API port not open"
    [ -n "$(cs_pid)" ] && ok "CommStat is running" || bad "CommStat not running" "$out"

    "$START" --no-route >/dev/null 2>&1
    { [ "$(modules_for rxtest_sink)" = 1 ] && [ "$(count_procs "/js8call -r RxTest( |\$)")" = 1 ] && [ "$(count_procs "python3 $CS/little_gucci.py")" = 1 ]; } \
        && ok "starting twice reuses everything (no duplicate sinks or processes)" || bad "second start duplicated something"

    "$STOP" >/dev/null 2>&1
    { [ -z "$(js8_pid)" ] && [ -z "$(cs_pid)" ] && [ "$(modules_for rxtest_sink)" = 0 ] && [ "$(modules_for rxtest_txvoid)" = 0 ]; } \
        && ok "stop ends both apps and removes both virtual devices" || bad "stop left something behind" "js8=$(js8_pid) cs=$(cs_pid) sinks=$(modules_for rxtest_sink)/$(modules_for rxtest_txvoid)"
    "$STOP" >/dev/null 2>&1 && ok "stop is harmless when nothing is running" || bad "stop failed when idle"

    # -------------------------------------- audio routing + the stray-stream watcher
    section "Audio routing and the stray-audio watcher"
    # `dialog` stand-in: auto-picks $STUB_DIALOG_CHOICE instead of showing a menu (same fd-3
    # trick the real dialog uses: `dialog ... 3>&1 1>&2 2>&3` in websdr-js8-start captures
    # whatever we write to fd 3 as the chosen stream id).
    cat > "$T/fakebin/dialog" <<'DIALOG_STUB_END'
#!/bin/sh
echo "$STUB_DIALOG_CHOICE" >&3
DIALOG_STUB_END
    chmod +x "$T/fakebin/dialog"
    python3 -c "
import wave, struct, math
w = wave.open('$T/tone.wav', 'w'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000)
for i in range(8000 * 3):
    w.writeframesraw(struct.pack('<h', int(3000 * math.sin(2 * math.pi * 440 * i / 8000))))
w.close()"

    paplay "$T/tone.wav" >/dev/null 2>&1 &
    sleep 0.5
    CHOICE_ID="$(pactl list short sink-inputs | awk '{print $1; exit}')"
    out="$(PATH="$T/fakebin:$PATH" STUB_DIALOG_CHOICE="$CHOICE_ID" "$START" 2>&1)"; rc=$?
    [ "$rc" = 0 ] && ok "start (routed) exits 0" || bad "routed start failed (exit $rc)" "$out"
    { [ -n "$CHOICE_ID" ] && [ "$(pactl list short sink-inputs | awk -v i="$CHOICE_ID" '$1==i{print $2}')" = "$(pactl list short sinks | awk '$2=="rxtest_sink"{print $1}')" ]; } \
        && ok "chosen stream landed on rxtest_sink" || bad "chosen stream isn't on rxtest_sink"
    sleep 0.5
    [ -n "$(pgrep -f "websdr-js8-watch-sink rxtest_sink")" ] && ok "the audio-routing watcher is running" || bad "watcher didn't start"

    # A second, unrelated stream lands on rxtest_sink BY ITSELF (the PipeWire per-app-default
    # quirk this watcher exists to undo) - it must get moved back off rxtest_sink on its own.
    paplay --device=rxtest_sink "$T/tone.wav" >/dev/null 2>&1 &
    STRAY_PID=$!
    ok_stray=0
    for _ in $(seq 1 20); do
        # the stray stream should get moved OFF rxtest_sink, leaving only the original choice there
        on_sink="$(pactl list short sink-inputs | awk -v s="$(pactl list short sinks | awk '$2=="rxtest_sink"{print $1}')" '$2==s{print $1}')"
        extra="$(echo "$on_sink" | grep -vx "$CHOICE_ID" || true)"
        [ -z "$extra" ] && { ok_stray=1; break; }
        sleep 0.3
    done
    kill "$STRAY_PID" 2>/dev/null
    [ "$ok_stray" = 1 ] && ok "a stray second stream on rxtest_sink is moved back automatically" \
        || bad "stray stream was not moved off rxtest_sink" "still on sink: $extra"
    { [ "$(pactl list short sink-inputs | awk -v i="$CHOICE_ID" '$1==i{print $2}')" = "$(pactl list short sinks | awk '$2=="rxtest_sink"{print $1}')" ]; } \
        && ok "the originally-chosen stream was left alone" || bad "the chosen stream got moved too"

    "$STOP" >/dev/null 2>&1
    [ -z "$(pgrep -f "websdr-js8-watch-sink rxtest_sink")" ] && ok "stop also stops the audio-routing watcher" || bad "watcher survived stop"

    # Closing the terminal window that ran the launcher must NOT kill the apps.
    python3 - "$START" <<'PTY_HARNESS_END'
import os, pty, sys, time
pid, fd = pty.fork()
if pid == 0:
    os.execv(sys.argv[1], [sys.argv[1], "--no-route"])
deadline = time.time() + 90
while time.time() < deadline:
    try:
        done, _ = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        break
    if done:
        break
    try:
        os.read(fd, 4096)
    except OSError:
        break
    time.sleep(0.05)
os.close(fd)      # the "window" closes: the kernel hangs up the terminal
PTY_HARNESS_END
    sleep 2
    { [ -n "$(js8_pid)" ] && [ -n "$(cs_pid)" ]; } \
        && ok "closing the launcher's terminal does NOT kill JS8Call or CommStat" || bad "an app died when its terminal closed" "js8=$(js8_pid) cs=$(cs_pid)"

    # Duplicate virtual devices (e.g. two quick starts on an older version) must be fully removable.
    pactl load-module module-null-sink sink_name=rxtest_sink >/dev/null 2>&1
    n="$(modules_for rxtest_sink)"
    "$STOP" >/dev/null 2>&1
    { [ "$n" -ge 2 ] && [ "$(modules_for rxtest_sink)" = 0 ]; } && ok "stop removes a duplicated sink completely ($n copies -> 0)" || bad "duplicate sink survived stop" "before=$n after=$(modules_for rxtest_sink)"

    # Receive-only guard: a profile that could key a radio must be refused.
    cp "$INI" "$INI.good"
    sed -i 's/^Rig=None/Rig=Hamlib NET rigctl/' "$INI"
    out="$("$START" --no-route 2>&1)"; rc=$?
    { [ "$rc" != 0 ] && echo "$out" | grep -q "receive-only guard" && [ -z "$(js8_pid)" ]; } \
        && ok "GUARD: refuses to start with rig control configured (nothing launched)" || bad "guard failed for Rig" "rc=$rc; $out"
    cp "$INI.good" "$INI"
    sed -i 's|^CATSerialPort=.*|CATSerialPort=/dev/ttyUSB0|' "$INI"
    out="$("$START" --no-route 2>&1)"; rc=$?
    { [ "$rc" != 0 ] && echo "$out" | grep -q "receive-only guard" && [ -z "$(js8_pid)" ]; } \
        && ok "GUARD: refuses to start with a CAT serial port set" || bad "guard failed for CAT port" "rc=$rc"
    cp "$INI.good" "$INI"
    sed -i 's|^PTTport=.*|PTTport=/dev/ttyUSB1|' "$INI"
    out="$("$START" --no-route 2>&1)"; rc=$?
    { [ "$rc" != 0 ] && echo "$out" | grep -q "receive-only guard" && [ -z "$(js8_pid)" ]; } \
        && ok "GUARD: refuses to start with a PTT port set" || bad "guard failed for PTT port" "rc=$rc"
    cp "$INI.good" "$INI"
    sed -i 's|^PSKReporter=.*|PSKReporter=true|' "$INI"
    out="$("$START" --no-route 2>&1)"; rc=$?
    { [ "$rc" != 0 ] && echo "$out" | grep -q "PSKReporter" && [ -z "$(js8_pid)" ]; } \
        && ok "GUARD: refuses to start with PSKReporter spotting ON (nothing launched)" || bad "guard failed for PSKReporter" "rc=$rc; $out"
    cp "$INI.good" "$INI"
    sed -i 's|^SpotToAPRS=.*|SpotToAPRS=true|' "$INI"
    out="$("$START" --no-route 2>&1)"; rc=$?
    { [ "$rc" != 0 ] && echo "$out" | grep -q "APRS spotting" && [ -z "$(js8_pid)" ]; } \
        && ok "GUARD: refuses to start with APRS spotting ON (nothing launched)" || bad "guard failed for SpotToAPRS" "rc=$rc; $out"
    cp "$INI.good" "$INI"
    sed -i '/^PSKReporter=/d' "$INI"
    out="$("$START" --no-route 2>&1)"; rc=$?
    { [ "$rc" != 0 ] && [ -z "$(js8_pid)" ]; } \
        && ok "GUARD: refuses to start if the spotting setting is missing (must be explicitly off)" || bad "guard allowed a missing PSKReporter key" "rc=$rc"
    cp "$INI.good" "$INI"
    out="$("$START" --no-route 2>&1)"; rc=$?
    [ "$rc" = 0 ] && ok "guard allows the correct receive-only profile again" || bad "guard blocked a good profile" "$out"
    "$STOP" >/dev/null 2>&1

    # ------------------------------------------------------------ uninstall
    section "Uninstaller"
    out="$("$ROOT/uninstall.sh" --purge --yes 2>&1)"; rc=$?
    [ "$rc" = 0 ] && ok "uninstall exits 0" || bad "uninstall failed" "$out"
    { [ ! -e "$START" ] && [ ! -e "$STOP" ] && [ ! -e "$HOME/.config/websdr-js8" ] && [ ! -e "$INI" ] && [ ! -e "$CS" ]; } \
        && ok "removes launchers, settings, JS8Call profile and CommStat folder" || bad "uninstall left files behind" "$(find "$HOME" -type f | head)"
    "$ROOT/uninstall.sh" --purge --yes >/dev/null 2>&1 && ok "a second uninstall is harmless" || bad "second uninstall failed"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAILED"
[ "$FAILED" = 0 ]
