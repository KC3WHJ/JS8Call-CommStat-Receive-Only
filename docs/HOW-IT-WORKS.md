# How it works

## The audio path

```
 browser tab (WebSDR / KiwiSDR audio)
        |  routed by websdr-js8-start   (pactl move-sink-input)
        v
 virtual device  "websdr_sink"        <- a PulseAudio/PipeWire "null sink": audio goes in,
        |                                nothing plays, and its monitor can be recorded
        v   ("websdr_sink.monitor" is what JS8Call is set to listen to)
      JS8Call  (its own profile: js8call -r WebSDR)
        |  TCP API on 127.0.0.1:2443  (one client allowed by JS8Call)
        v
      CommStat  (one connector, "WebSDR", to that port)

 JS8Call's *output* -> virtual device "websdr_txvoid"  (a second null sink: transmit audio is discarded)
```

Both virtual devices are created on start and removed on stop. The desktop's own audio
is never touched: only the one browser stream you pick is moved.

## Why a separate JS8Call profile

`js8call -r WebSDR` uses its own settings file (`~/.config/JS8Call - WebSDR.ini`), data
folder and API port. A normal JS8Call configured for a real radio is unaffected by
this station and vice versa, and both can run at once.

## The receive-only guard

The profile is written with no rig control. Because a profile can be edited later from
inside JS8Call (Settings > Radio), `websdr-js8-start` re-reads it on every start and
refuses to launch if `Rig` isn't `None`, if a CAT serial port, CAT network port or PTT
port is set, or if `PSKReporter` / `SpotToAPRS` isn't explicitly `false` (a remote receiver's
decodes must never be reported under your callsign and grid). It tells you exactly what to fix. This is a check on this station's own
configuration, not a claim about the programs: JS8Call and CommStat are unmodified.

## Startup order and detaching

CommStat connects to JS8Call once at startup and gives up (and disables the connector)
after repeated failures, so the launcher starts JS8Call, **waits for its API port to
open**, and only then starts CommStat.

Both programs are started with `setsid -f nohup ...`: forked into their own session
right away, so they have no terminal to hang up. Two things learned the hard way:

- A background job started with a plain `&` (even with `disown`) still receives a
  hang-up when its terminal window closes.
- `nohup` alone protects a program but **not** helper processes it starts. CommStat's
  Qt WebEngine helper processes (which draw the map) die on the hang-up, leaving CommStat
  running with a blank map. A fully separate session avoids both.

## Virtual devices: never duplicated, always fully removed

Existence is checked in the *module* list (accurate the instant a load returns) rather
than the sink list, so two quick starts can't create a duplicate. Removal unloads every
matching module one call at a time, because passing two module IDs to one
`pactl unload-module` call fails and would strand a silent device. A stranded device
matters: PipeWire remembers where a browser's audio was routed, so a browser can end up
playing into a device that goes nowhere.

## The installer

1. **Prerequisite check** (read-only). A FAIL stops here with nothing changed.
2. Your callsign, grid and state (flags or prompts; validated before anything is installed).
3. `apt` packages.
4. CommStat: cloned, then its own `linuxinstall.sh` installs Qt WebEngine and the Python
   packages. An existing CommStat is reused; it is only `git pull`ed if its checkout is clean,
   since CommStat rewrites its own files when its server pushes an update.
5. `share/seed_commstat.py` creates CommStat's database from its own shipped template,
   fills in your details **only where still blank**, and adds the single `WebSDR`
   connector through CommStat's own `ConnectorManager` (so validation and defaults are
   exactly what its dialog would produce), with auto-connect on and RF Ack off.
6. The JS8Call profile is written from `share/JS8Call-profile.ini.template` **only if it
   doesn't exist**.
7. Launchers, shortcuts and settings are installed, then the result is verified.

Every step is idempotent: re-running keeps existing profiles, databases and connectors.

## Layout

```
install.sh  uninstall.sh  preflight.sh
lib/common.sh               settings, validation, audio-device helpers (sourced by everything)
bin/websdr-js8-start        JS8Call + CommStat launcher
bin/websdr-js8-stop         its stopper
bin/websdr-js8-watch-sink   stray-audio watcher (used by both stations)
bin/websdr-fldigi-start     FLDIGI + FLMSG + FLAMP launcher
bin/websdr-fldigi-stop      its stopper
bin/websdr-flmsg            FLMSG / FLAMP with the station's own folder and ports
bin/websdr-flamp              (FLDIGI starts these)
share/JS8Call-profile.ini.template
share/seed_commstat.py      CommStat first-run configuration
tests/run-tests.sh          110 checks; tests/stubs/ holds the JS8Call, FLDIGI, FLMSG and FLAMP stand-ins
```

## The FLDIGI station

```
 browser tab (WebSDR / KiwiSDR audio)
        |  routed by websdr-fldigi-start
        v
 virtual device  "websdr_fldigi"           (FLDIGI listens to "websdr_fldigi.monitor")
        v
      FLDIGI  (fldigi --config-dir ~/.fldigi-websdr/ --flmsg-dir ~/.nbems-websdr/,
        |      XML-RPC 7363, ARQ 7323, KISS 7344/7345)
        |-- XML-RPC --> FLMSG  (flmsg --flmsg-dir ~/.nbems-websdr/)
        '-- XML-RPC + ARQ --> FLAMP  (flamp --config-dir ~/.nbems-websdr/)

 FLDIGI's *output* -> virtual device "websdr_fldigi_txvoid"  (transmit audio is discarded)
```

- **Audio**: FLDIGI is set to its PulseAudio back end and started with
  `PULSE_SOURCE=websdr_fldigi.monitor PULSE_SINK=websdr_fldigi_txvoid`, which picks its
  input and output without depending on device numbers.
- **Its own devices, not the JS8Call station's**: `websdr-js8-stop` removes its devices,
  which would cut off FLDIGI's audio if they were shared.
- **Settings are re-applied, not just checked.** FLDIGI rewrites `fldigi_def.xml` when it
  exits, so the launcher edits it only while FLDIGI is stopped: every start switches off
  rig control (Hamlib, RigCAT, flrig), every PTT method, PSKReporter/DX-cluster/eQSL/LoTW,
  transmit RSID and pre-tone; sets its own ports; and points FLDIGI's autostart at the
  `websdr-flmsg` / `websdr-flamp` wrappers. It then re-reads the file and refuses to
  start unless the result is receive-only. Settings missing from the file are added, so
  nothing is left to a default.
- **A copy, never the original**: the first start copies `~/.fldigi` and rewrites the
  copy's absolute paths into `~/.fldigi` (such as the macro file) to point at the copy.
  `~/.fldigi` and `~/.nbems` are only ever read.
- **Stopping**: FLAMP and FLMSG are closed first (FLAMP can hang if FLDIGI goes first).
  FLDIGI is asked to close over XML-RPC (`fldigi.terminate`), because a signal makes it
  exit without saving its settings; a signal is only the fallback.
- **FLAMP's option name**: its `--help` says `--confg-dir`, but the option FLAMP accepts
  is `--config-dir`, and it takes the NBEMS folder (FLAMP adds `FLAMP/` itself).
