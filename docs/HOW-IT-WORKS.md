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
bin/websdr-js8-start        launcher
bin/websdr-js8-stop         stopper
share/JS8Call-profile.ini.template
share/seed_commstat.py      CommStat first-run configuration
tests/run-tests.sh          74 checks; tests/stubs/js8call is the JS8Call stand-in
```
