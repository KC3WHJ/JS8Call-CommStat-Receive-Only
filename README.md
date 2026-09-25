# JS8Call-CommStat-Receive-Only

**A receive-only JS8Call + CommStat station, fed by any web SDR or KiwiSDR.**
No radio, no antenna, no transmitting: play a WebSDR in your browser, and this
sets up [JS8Call](http://js8call.com/) to decode it and
[CommStat](https://github.com/mgochoa57/CommStat) to show what it hears.

It is a small installer and two launchers - not a copy of either program. It
installs JS8Call from your distribution and pulls CommStat from its own GitHub
repository, then configures both for listening only.

```
 web SDR / KiwiSDR  ->  browser tab  ->  virtual audio device  ->  JS8Call  ->  CommStat
                                          (receive only)          (no rig)     (map, STATREPs)
```

## What you get

- A **prerequisite check** that runs before anything is installed, and refuses
  to touch your system if a hard requirement isn't met (`./preflight.sh`).
- One installer (`./install.sh`) and two launchers: `websdr-js8-start` and
  `websdr-js8-stop` (also in your applications menu).
- A **separate JS8Call profile**, so it never disturbs a normal JS8Call setup
  you may already have.
- A guided step that routes the browser tab playing the WebSDR into JS8Call.
- **JS8Call and CommStat detach from the terminal**, so closing the launcher's
  window doesn't kill them.

## Receive-only, by design

Nothing here can key a radio, because there isn't one to key. On top of that:

| Safeguard | What it does |
|---|---|
| No rig control | The JS8Call profile has `Rig=None` and no CAT or PTT port. |
| Start-up guard | `websdr-js8-start` re-checks that profile every time and **refuses to start** if rig control, a CAT port, a PTT port, or PSKReporter/APRS spotting has since been configured (or if the spotting setting is missing - it must be explicitly off). |
| Transmit audio discarded | JS8Call's audio *output* is a virtual device that goes nowhere, so an accidental "transmit" makes no sound and reaches nothing. |
| No automatic acknowledgements | CommStat's connector is created with **RF Ack off**, so a received STATREP never triggers an over-the-air reply. |
| No false spotting | JS8Call's **PSKReporter and APRS spotting are both off**. Stations heard through a remote receiver must never be reported as if heard at *your* location. |

JS8Call and CommStat still show their normal transmit buttons and menus; with no
radio behind them they do nothing on the air.

## Requirements

- **Linux with apt** and a graphical desktop session. Tested on **Linux Mint 22**
  (Ubuntu 24.04 base). Other Debian/Ubuntu derivatives should work but are untested.
- PipeWire or PulseAudio (the default on current Ubuntu/Mint).
- A web browser, an internet connection, and an account that can use `sudo`.
- About 1.5 GiB of free disk space (CommStat uses Qt WebEngine).
- An accurate system clock - JS8 decodes on tight time slots.

## Quick start

```bash
git clone https://github.com/KC3WHJ/JS8Call-CommStat-Receive-Only.git
cd JS8Call-CommStat-Receive-Only

./install.sh --check     # prerequisite check only - changes nothing
./install.sh             # check again, ask a few questions, then install
websdr-js8-start         # or use "Start WebSDR JS8Call + CommStat" in your menu
```

You'll be asked for a callsign (or any short ID if you're only listening, such as
`N0CALL`), your grid square, and optionally your US state. Then:

1. Open a web SDR or KiwiSDR in your browser and start its audio.
2. Tune it to a JS8 frequency in **USB** mode (for example 7.078 MHz).
3. Press Enter in the launcher window and pick the browser stream from the menu.
4. JS8Call starts decoding; CommStat connects to it automatically.
5. When you're done: `websdr-js8-stop`.

Details and tuning tips: [docs/USAGE.md](docs/USAGE.md).

## The prerequisite check

`install.sh` runs `preflight.sh` first. It is **read-only** (no changes, no sudo)
and marks each item OK, WARN or FAIL. Any FAIL stops the installer before it has
changed anything. It checks:

Operating system and CPU architecture - not running as root - sudo rights - free
disk space and memory - Python 3.8+ and git - internet access to GitHub and to
every configured apt server - that apt isn't locked by another process - that
`js8call` and Qt WebEngine are actually available from your apt sources - a
reachable audio server - a graphical session and a web browser - the system
clock being synchronized - that your chosen settings and ports are valid and
free - and any existing install (which is kept, never overwritten).

Run `./preflight.sh --help` for its options.

## What gets installed, and where

| Item | Location |
|---|---|
| Packages | `js8call`, `git`, `dialog`, `pulseaudio-utils`, `python3`, `curl`, plus whatever CommStat's own installer needs |
| CommStat | `~/.local/share/websdr-js8/CommStat` (cloned from GitHub) |
| JS8Call profile | `~/.config/JS8Call - WebSDR.ini` |
| Settings | `~/.config/websdr-js8/config` |
| Launchers | `~/.local/bin/websdr-js8-start`, `websdr-js8-stop`, and menu/Desktop shortcuts |
| Logs | `~/.local/share/websdr-js8/js8call.log`, `commstat.log` |

Re-running the installer is safe: it keeps an existing JS8Call profile, an
existing CommStat database and any connector already present.

## Uninstall

```bash
./uninstall.sh              # removes launchers and settings; asks before deleting data
./uninstall.sh --purge      # removes the JS8Call profile and CommStat folder too
```

Installed packages are left alone; remove them with `apt` if you want.

## Things worth knowing

- **CommStat talks to its own server.** It sends a periodic heartbeat with your
  callsign and grid, receives the nationwide STATREP feed, and downloads map
  tiles - so it needs internet. What it shows from the radio side is what the
  WebSDR heard, not your local RF environment.
- **CommStat updates itself** in place from its server. Don't run `git pull`
  inside its folder; the installer already handles this.
- **Someone else's receiver has its own rules.** Public KiwiSDRs often limit
  session length and users; follow the operator's terms.
- **JS8Call's title bar always says "de KN4CRD".** That is the JS8Call author's callsign,
  built into the title of every JS8Call window (its format string is literally
  `%1 de KN4CRD (v%2)`). It is not your callsign and not a setting; yours is shown in the
  main display and used by the API and CommStat.

## Testing

`tests/run-tests.sh` runs 74 checks with no sudo, GUI or internet: prerequisite
failures, the installer, idempotency, launcher start/stop, terminal-close
survival, duplicate audio devices, the receive-only guard, and uninstall. It uses
stand-ins for the two GUIs (but CommStat's real database template and connector
code) and its own profile name, ports and audio devices, so it can run beside a
live install. A separate end-to-end check ran the **real JS8Call binary** with the
generated profile: it started without a wizard, answered its API, and kept the
settings.

Not covered by the test suite: the `apt install` step and CommStat's own
`linuxinstall.sh` on a clean machine (they need sudo and a fresh system). If you
try it on a fresh VM or a distribution not listed above, please report what you find.

## Credits and licenses

This project only installs and configures other people's software; it does not
include or redistribute it.

- **JS8Call** - Jordan Sherer (KN4CRD) and contributors, GPL-3.0.
- **CommStat** - Manuel Ochoa (N0DDK), GPL-3.0, <https://github.com/mgochoa57/CommStat>.

The scripts in this repository are released under the MIT License (see `LICENSE`).
