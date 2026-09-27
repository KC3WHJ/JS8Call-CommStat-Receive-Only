#!/usr/bin/env bash
# Remove JS8Call-CommStat-Receive-Only.
#
#   ./uninstall.sh            remove the launchers, shortcuts and settings; ASK before
#                             deleting the JS8Call profile and the CommStat folder
#   ./uninstall.sh --purge    remove those too, without asking
#   ./uninstall.sh --keep-data  never remove them
#   -y, --yes                 answer yes to the confirmation
#
# It does NOT uninstall packages (js8call, Qt libraries, ...) - other software
# may use them. To remove those: sudo apt remove js8call
set -eu

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"
load_config

PURGE=0; KEEP=0; YES=0
for a in "$@"; do
    case "$a" in
        --purge) PURGE=1 ;; --keep-data) KEEP=1 ;; -y|--yes) YES=1 ;;
        -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $a" ;;
    esac
done

BIN_DIR="${WEBSDR_JS8_BIN_DIR:-$HOME/.local/bin}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DESK="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"

confirm() {  # "question"  -> 0 for yes
    [ "$YES" = 1 ] && return 0
    [ -t 0 ] || return 1
    read -r -p "$1 [y/N] " ans; case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

step "Stopping anything that is running"
if [ -x "$BIN_DIR/websdr-js8-stop" ]; then "$BIN_DIR/websdr-js8-stop" || true
else info "Launchers not found - skipping."; fi

step "Removing launchers, shortcuts and settings"
rm -fv "$BIN_DIR/websdr-js8-start" "$BIN_DIR/websdr-js8-stop" "$BIN_DIR/websdr-js8-watch-sink" \
       "$DATA_HOME/applications/websdr-js8-start.desktop" "$DATA_HOME/applications/websdr-js8-stop.desktop" \
       "$DESK/websdr-js8-start.desktop" "$DESK/websdr-js8-stop.desktop"
rm -rf "$DATA_DIR/app" "$DATA_DIR/js8call.log" "$DATA_DIR/commstat.log" "$DATA_DIR/routing-watcher.log"
rm -rf "$CONFIG_DIR"
info "Removed the app files and $CONFIG_DIR"

if [ "$KEEP" = 1 ]; then
    info; info "Kept your JS8Call profile and CommStat folder (--keep-data)."
else
    step "Data"
    if [ -f "$JS8_INI" ] && { [ "$PURGE" = 1 ] || confirm "Delete the JS8Call profile '$PROFILE' (settings and received-message history)?"; }; then
        rm -fv "$JS8_INI"; rm -rf "$DATA_HOME/JS8Call - $PROFILE"; info "Deleted the JS8Call profile."
    fi
    if [ -d "$COMMSTAT_DIR" ] && { [ "$PURGE" = 1 ] || confirm "Delete the CommStat folder $COMMSTAT_DIR (its database and settings)?"; }; then
        rm -rf "$COMMSTAT_DIR"; info "Deleted $COMMSTAT_DIR."
    fi
    [ -d "$DATA_DIR" ] && rmdir "$DATA_DIR" 2>/dev/null || true
fi

echo
info "Done. Installed packages (js8call, Qt libraries) were left alone - remove them with apt if you want."
