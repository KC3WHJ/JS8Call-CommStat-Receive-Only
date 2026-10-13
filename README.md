# WebSDR-Digital-Receive-Only

**Receive-only digital-mode stations, fed by any web SDR or KiwiSDR.**
No radio, no antenna, no transmitting: play a WebSDR in your browser, and this
sets up the decoders to listen to it:

- **JS8Call + CommStat** - [JS8Call](http://js8call.com/) decodes JS8 traffic and
  [CommStat](https://github.com/mgochoa57/CommStat) shows what it hears (map, STATREPs).
- **FLDIGI + FLMSG + FLAMP** - [FLDIGI](http://www.w1hkj.com/) decodes PSK, MFSK,
  Contestia, Olivia, RTTY and more; FLMSG opens received forms and FLAMP
  reassembles received files (NBEMS traffic, e.g. AmRRON nets).

It is a small installer and a set of launchers - not a copy of any of these
programs. It installs them from your distribution (keeping any you already have),
pulls CommStat from its own GitHub repository, and configures everything for
listening only.

```
 web SDR / KiwiSDR  ->  browser tab  ->  virtual audio device  ->  JS8Call  ->  CommStat
                                          (receive only)          (no rig)     (map, STATREPs)

 web SDR / KiwiSDR  ->  browser tab  ->  virtual audio device  ->  FLDIGI  ->  FLMSG / FLAMP
                                          (receive only)          (no rig)    (forms, files)
```

The two stations are independent: run either, or both at once (two browser tabs on
two frequencies).

*This project was called **JS8Call-CommStat-Receive-Only** before the FLDIGI station
was added. GitHub redirects the old address, and existing installs keep working.*

## What you get

- A **prerequisite check** that runs before anything is installed, and refuses
  to touch your system if a hard requirement isn't met (`./preflight.sh`).
- One installer (`./install.sh`) and launchers for each station:
  `websdr-js8-start` / `websdr-js8-stop` and `websdr-fldigi-start` / `websdr-fldigi-stop`
  (also in your applications menu and on the Desktop).
- **Separate settings for everything**: a JS8Call profile, a CommStat copy, and
  FLDIGI/FLMSG/FLAMP settings folders of their own, so a normal radio setup you
  may already have is never disturbed.
- A guided step that routes the browser tab playing the WebSDR into the decoder.
- **The programs detach from the terminal**, so closing the launcher's window
  doesn't kill them.

## Receive-only, by design

Nothing here can key a radio, because there isn't one to key. On top of that:

| Safeguard | What it does |
|---|---|
| No rig control | The JS8Call profile has `Rig=None` and no CAT or PTT port. FLDIGI's settings have Hamlib, RigCAT and flrig control and **every PTT method** (CAT, serial RTS/DTR, GPIO, parallel port, CM108, right-channel tone) switched off. |
| Start-up guard | `websdr-js8-start` re-checks the JS8Call profile every time and **refuses to start** if rig control, a CAT port, a PTT port, or PSKReporter/APRS spotting has since been configured (or if the spotting setting is missing - it must be explicitly off). `websdr-fldigi-start` re-applies FLDIGI's receive-only settings on every start - undoing anything changed later in FLDIGI's Configure dialogs - then checks the result and refuses to start if it isn't receive-only. |
| Transmit audio discarded | Each decoder's audio *output* is a virtual device that goes nowhere, so an accidental "transmit" makes no sound and reaches nothing. |
| No automatic transmissions | CommStat's connector is created with **RF Ack off**, so a received STATREP never triggers an over-the-air reply. FLDIGI's transmit RSID and pre-tone are off, and FLAMP's automatic and timed repeats are off. |
| No false spotting | JS8Call's **PSKReporter and APRS spotting**, and FLDIGI's **PSKReporter, DX-cluster, eQSL and LoTW** uploads, are all off. Stations heard through a remote receiver must never be reported as if heard at *your* location. |

The programs still show their normal transmit buttons and menus; with no radio
behind them they do nothing on the air.

## Requirements

- **Linux with apt** and a graphical desktop session. Tested on **Linux Mint 22**
  (Ubuntu 24.04 base) and **EmComm Tools Community R7** (Ubuntu 22.10 base). Other
  Debian/Ubuntu derivatives should work but are untested.
- PipeWire or PulseAudio (the default on current Ubuntu/Mint).
- A web browser, an internet connection, and an account that can use `sudo`.
- About 1.5 GiB of free disk space (CommStat uses Qt WebEngine).
- An accurate system clock - JS8 decodes on tight time slots.

## Quick start

```bash
git clone https://github.com/KC3WHJ/WebSDR-Digital-Receive-Only.git
cd WebSDR-Digital-Receive-Only

./install.sh --check     # prerequisite check only - changes nothing
./install.sh             # check again, ask a few questions, then install
websdr-js8-start         # JS8Call + CommStat (or "Start WebSDR JS8Call + CommStat" in your menu)
websdr-fldigi-start      # FLDIGI + FLMSG + FLAMP (or "Start WebSDR FLDIGI + FLMSG/FLAMP")
```

Don't want the FLDIGI station? `./install.sh --no-fldigi`.

You'll be asked for a callsign (or any short ID if you're only listening, such as
`N0CALL`), your grid square, and optionally your US state. Then, for either station:

1. Open a web SDR or KiwiSDR in your browser and start its audio.
2. Tune it in **USB** mode - to a JS8 frequency for JS8Call (for example 7.078 MHz),
   or to the dial frequency you'd use on a radio for FLDIGI.
3. Press Enter in the launcher window and pick the browser stream from the menu.
4. The decoder starts working; CommStat connects to JS8Call automatically, and
   FLDIGI opens FLMSG and FLAMP for you.
5. When you're done: `websdr-js8-stop` / `websdr-fldigi-stop`.

Details and tuning tips: [docs/USAGE.md](docs/USAGE.md).

## The prerequisite check

`install.sh` runs `preflight.sh` first. It is **read-only** (no changes, no sudo)
and marks each item OK, WARN or FAIL. Any FAIL stops the installer before it has
changed anything. It checks:

Operating system and CPU architecture - not running as root - sudo rights - free
disk space and memory - Python 3.8+ and git - internet access to GitHub and to
every configured apt server - that apt isn't locked by another process - that
`js8call` and Qt WebEngine are actually available from your apt sources (and
FLDIGI, FLMSG and FLAMP, as warnings, since that station is optional) - a
reachable audio server - a graphical session and a web browser - the system
clock being synchronized - that your chosen settings and ports are valid and
free - and any existing install (which is kept, never overwritten).

Run `./preflight.sh --help` for its options.

## What gets installed, and where

| Item | Location |
|---|---|
| Packages | `js8call`, `fldigi`, `flmsg`, `flamp`, `git`, `dialog`, `pulseaudio-utils`, `python3`, `curl`, plus whatever CommStat's own installer needs. Programs you already have (e.g. EmComm Tools' own builds) are kept, not replaced. |
| CommStat | `~/.local/share/websdr-js8/CommStat` (cloned from GitHub) |
| JS8Call profile | `~/.config/JS8Call - WebSDR.ini` |
| FLDIGI settings | `~/.fldigi-websdr` (created at first start - a copy of `~/.fldigi` if you have one, so macros and the frequency list carry over) |
| FLMSG / FLAMP settings and received messages | `~/.nbems-websdr` (FLAMP in its `FLAMP/` subfolder) |
| Settings | `~/.config/websdr-js8/config` |
| Launchers | `~/.local/bin/websdr-js8-start`, `websdr-js8-stop`, `websdr-js8-watch-sink`, `websdr-fldigi-start`, `websdr-fldigi-stop`, `websdr-flmsg`, `websdr-flamp`, and menu/Desktop shortcuts |
| Logs | `~/.local/share/websdr-js8/js8call.log`, `commstat.log`, `routing-watcher.log`, and `fldigi/` for the FLDIGI station |

Re-running the installer is safe: it keeps an existing JS8Call profile, an
existing CommStat database, any connector already present, and existing FLDIGI
settings.

## Uninstall

```bash
./uninstall.sh              # removes launchers and settings; asks before deleting data
./uninstall.sh --purge      # removes the JS8Call profile, CommStat folder and FLDIGI/FLMSG/FLAMP folders too
```

Installed packages are left alone; remove them with `apt` if you want. Your normal
`~/.fldigi` and `~/.nbems` are never touched.

## Things worth knowing

- **CommStat talks to its own server.** It sends a periodic heartbeat with your
  callsign and grid, receives the nationwide STATREP feed, and downloads map
  tiles - so it needs internet. What it shows from the radio side is what the
  WebSDR heard, not your local RF environment.
- **CommStat updates itself** in place from its server. Don't run `git pull`
  inside its folder; the installer already handles this.
- **Someone else's receiver has its own rules.** Public KiwiSDRs often limit
  session length and users; follow the operator's terms.
- **A second, unrelated audio stream (e.g. another browser tab) won't go silent.** PipeWire/PulseAudio
  remembers which sink an app's audio goes to *per application*, not per tab - so without this, once
  the WebSDR's stream is routed in, any *other* new stream from the same browser could get silently
  swept in too. `websdr-js8-watch-sink` runs for the length of the session (for either station) and
  moves anything else that lands on the WebSDR sink back to your normal output automatically.
- **The FLDIGI station uses its own ports** (XML-RPC 7363, ARQ 7323, KISS 7344/7345)
  so it can run beside a normal FLDIGI (7362/7322), and FLMSG and FLAMP talk only to
  it. FLDIGI accepts XML-RPC connections from your local network, whatever address
  is configured; that's FLDIGI's own behavior.
- **RSID does the mode switching.** FLDIGI's receive RSID stays on, so it follows a
  net that changes modes (e.g. Contestia for the net, MFSK-32 for FLMSG/FLAMP traffic).
- **JS8Call's title bar always says "de KN4CRD".** That is the JS8Call author's callsign,
  built into the title of every JS8Call window (its format string is literally
  `%1 de KN4CRD (v%2)`). It is not your callsign and not a setting; yours is shown in the
  main display and used by the API and CommStat.

## Testing

`tests/run-tests.sh` runs 110 checks with no sudo, GUI or internet: prerequisite
failures, the installer, idempotency, launcher start/stop for both stations, audio
routing and the stray-stream watcher, terminal-close survival, duplicate audio
devices, the receive-only guards, FLDIGI's settings copy (rig control, PTT and
spotting switched off; the normal `~/.fldigi` untouched; a fresh setup when there is
none), and uninstall. It uses stand-ins for the GUIs (but CommStat's real database
template and connector code) and its own profile name, ports and audio devices, so
it can run beside a live install. Separate end-to-end checks ran the **real JS8Call
binary** with the generated profile (it started without a wizard, answered its API,
and kept the settings) and the **real FLDIGI 4.2, FLMSG 4.0 and FLAMP 2.2** (set up like an AmRRON net -
7.110 MHz, Contestia 4/250 at 900 Hz - FLDIGI decoded a recorded AmRRON training
transmission played into its virtual device in full, followed it to MFSK-32 and back
by RSID, and never left receive).

Not covered by the test suite: the `apt install` step and CommStat's own
`linuxinstall.sh` on a clean machine (they need sudo and a fresh system). If you
try it on a fresh VM or a distribution not listed above, please report what you find.

## Part of a bigger station

This is the receive-only piece of a full ham radio + SDR station build for Linux Mint:
**[mint-sauce-for-ham](https://github.com/KC3WHJ/mint-sauce-for-ham)** - ADS-B tracking,
multi-radio selection, Winlink, VARA, WSJT-X, JS8Call, Fldigi/Flmsg and more. If you have a
radio and want the whole station, start there; this repository is for anyone who only wants
receive-only digital-mode listening stations.

## Credits and licenses

This project only installs and configures other people's software; it does not
include or redistribute it.

- **JS8Call** - Jordan Sherer (KN4CRD) and contributors, GPL-3.0.
- **CommStat** - Manuel Ochoa (N0DDK), GPL-3.0, <https://github.com/mgochoa57/CommStat>.
- **FLDIGI, FLMSG, FLAMP** - Dave Freese (W1HKJ), Robert Stiles (KK5VD) and contributors, GPL-3.0, <http://www.w1hkj.com/>.

The scripts in this repository are released under the MIT License (see `LICENSE`).
