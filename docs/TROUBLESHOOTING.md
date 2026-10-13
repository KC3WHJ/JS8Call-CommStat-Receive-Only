# Troubleshooting

Logs: `~/.local/share/websdr-js8/js8call.log`, `commstat.log`, and `fldigi/fldigi.log`.
Run `./preflight.sh` any time for a read-only health check of the machine.

## The installer stops with FAIL items

Each FAIL line ends with a hint. Common ones:

| FAIL | Meaning / fix |
|---|---|
| Package manager busy | Another apt/dpkg process holds the lock. Linux Mint's background refresh does this for a minute or two after boot; wait and run again. |
| package: js8call not available | Enable the `universe` component (Ubuntu) or check your Mint sources, then `sudo apt update`. |
| package: python3-pyqt5.qtwebengine not available, on an end-of-life Ubuntu (e.g. 22.10, which EmComm Tools R7 uses) | The release's packages have moved to `old-releases.ubuntu.com`. Point apt there: `sudo sed -i -E 's#http://(us\.archive\|security)\.ubuntu\.com#http://old-releases.ubuntu.com#' /etc/apt/sources.list && sudo apt update` (back up `sources.list` first). |
| Audio server | `pactl` can't reach PulseAudio/PipeWire - run from a terminal inside your logged-in desktop, not plain ssh. |
| Desktop session | No `DISPLAY`/`WAYLAND_DISPLAY`: JS8Call and CommStat are desktop apps. |
| TCP port in use | Something else is listening on JS8Call's API port. Set another `TCP_PORT` in `~/.config/websdr-js8/config`. |
| Running as root | Run as your normal user; the installer uses sudo itself where needed. |

Nothing is installed or changed when a FAIL stops the installer.

## JS8Call shows nothing / no audio

- Is the WebSDR page actually **playing**? Many sites need a click on a play/"start audio" button.
- Was the stream routed? Run `websdr-js8-start` again after the audio is playing (safe to repeat).
- With the stream routed you will **not** hear it from your speakers; that's expected.
- Check the SDR is in **USB** mode and tuned to the JS8 dial frequency (see USAGE.md).
- Check your clock: `timedatectl` should say "System clock synchronized: yes".
- Weak or crowded band? Try 40 m or 20 m at a busy time of day.

## The browser goes silent after I finish

Run `websdr-js8-stop`. It removes the virtual devices so the browser's audio returns to your
speakers. (If a page is still silent afterwards, reload it.)

## CommStat can't connect / its connector says Disabled

CommStat connects to JS8Call once at startup and disables the connector after repeated
failures. Make sure JS8Call is running, then in CommStat open **JS8 Connectors**, select
`WebSDR` and click **Reconnect**. `websdr-js8-start` always starts JS8Call first.

## CommStat's map is blank

Its map is drawn by helper processes that must survive the launcher's terminal closing;
`websdr-js8-start` starts CommStat fully detached so they do. If you launched CommStat some
other way and the map is blank, quit it and use `websdr-js8-start`. The map also needs
internet access for its tiles.

## "receive-only guard: ..." and it won't start

The JS8Call profile no longer looks receive-only (rig control, a CAT port or a PTT port is
set - possibly changed from inside JS8Call). The message says which. Fix it in
`~/.config/JS8Call - WebSDR.ini`, or remove that file and re-run `./install.sh` for a fresh
profile.

## The JS8Call window title says "de KN4CRD"

That is normal for every JS8Call: KN4CRD is the JS8Call author's callsign, built into the
window-title format (`... de KN4CRD (v2.x)`). It isn't your callsign and can't be changed.
Your own callsign is shown in the main display (under the frequency) and is what JS8Call's
API and CommStat use.

## An old install left a silent audio device behind

`websdr-js8-stop` removes every copy of its two virtual devices. To check:
`pactl list short modules | grep websdr`.

## Updating

- **CommStat** updates itself when its server pushes an update. Don't `git pull` in its folder.
- **JS8Call** updates through apt like any package.
- **This project:** `git pull` here, then `./install.sh` again (it keeps your existing configuration).

## FLDIGI shows nothing / a flat waterfall

- Same first checks as for JS8Call: is the WebSDR page **playing**, was the stream routed
  (run `websdr-fldigi-start` again), and is the SDR in **USB**?
- The two stations have separate audio devices. A tab routed into JS8Call doesn't reach
  FLDIGI; play a second tab for FLDIGI and pick that one.
- Check FLDIGI is on PulseAudio: *Configure > Sound Card > Audio devices*. The launcher sets
  this at every start; if it was changed while FLDIGI was running, restart the station.

## FLMSG or FLAMP doesn't open, or says it can't reach FLDIGI

They are started by FLDIGI (*Configure > Misc > Autostart*), through `websdr-flmsg` and
`websdr-flamp`, and connect to this station's FLDIGI on port 7363 (not the usual 7362). Stop
and start the station to re-apply that. A FLMSG or FLAMP you open some other way connects to
a normal FLDIGI instead.

## FLDIGI's settings changes don't stick

Rig control, PTT, spotting, ports and audio settings are re-applied at every start, by
design. Other changes (modem settings, colors, macros) are kept, provided FLDIGI is closed
with `websdr-fldigi-stop` or its own File > Exit.
