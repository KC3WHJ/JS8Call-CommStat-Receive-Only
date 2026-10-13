# Using it

## JS8Call + CommStat: a session, start to finish

1. **Start the station.** Run `websdr-js8-start` in a terminal, or use *Start WebSDR
   JS8Call + CommStat* from your applications menu or Desktop. It creates two
   virtual audio devices, starts JS8Call, waits for its API port, then starts
   CommStat.
2. **Play a web SDR.** In your browser, open a WebSDR (e.g. from websdr.org) or a
   KiwiSDR, start its audio, and tune it to a JS8 frequency in **USB** mode.
3. **Route the audio.** Back in the launcher window press Enter and choose the
   browser stream from the menu (it looks like *Firefox - the page title*). From
   now on that tab plays into JS8Call instead of your speakers - you won't hear it;
   that's expected.
4. **Watch it decode.** JS8Call shows decoded traffic; CommStat, which connected
   to JS8Call automatically, shows heard stations and any STATREPs on its map and
   lists.
5. **Stop.** `websdr-js8-stop` (or the *Stop* shortcut). It closes both apps and
   removes the virtual audio devices, so the browser plays through your speakers again.

You can close the launcher's terminal window at any time; JS8Call and CommStat keep
running until you stop them.

## Tuning the web SDR

JS8 is a weak-signal mode sent as audio tones, so the SDR must be in **USB** with a
passband wide enough to carry roughly 500-2500 Hz of audio (a normal USB passband,
about 300-2700 Hz or wider, is fine). Set the SDR's dial to the JS8 dial frequency;
signals then appear at their audio offsets in JS8Call's waterfall.

JS8Call's standard dial frequencies (all USB):

| Band | MHz | | Band | MHz |
|---|---|---|---|---|
| 160 m | 1.842 | | 17 m | 18.104 |
| 80 m | 3.578 | | 15 m | 21.078 |
| 40 m | 7.078 | | 12 m | 24.922 |
| 30 m | 10.130 | | 10 m | 28.078 |
| 20 m | 14.078 | | 6 m | 50.318 |

Activity varies with the band and time of day; 40 m and 20 m are good places to start.
JS8Call has no radio to tune, so the frequency it displays is only informational:
set its band to match what you tuned the SDR to.

**Audio level:** adjust the volume on the WebSDR/KiwiSDR page (or the browser tab),
not in the launcher. The level meter beside JS8Call's waterfall should sit roughly in
the middle of its range - not pinned at the top, and not near zero.

## CommStat

CommStat's connector is created for you (named `WebSDR`, auto-connect on, RF Ack off).
The first time, you may want to:

- Use CommStat's **Manage Groups** dialog to add the groups/nets you follow, so their
  messages are shown.
- Optionally add a **QRZ** login (QRZ Settings) for callsign look-ups.

(These dialogs are in CommStat's menus; the exact menu layout can change between CommStat versions.)

CommStat connects to JS8Call **once, at startup**, so JS8Call has to be running first -
`websdr-js8-start` takes care of that order. If you restart JS8Call on its own, open
CommStat's *JS8 Connectors* dialog, select the `WebSDR` row and click **Reconnect**.

## Options

| Command | Effect |
|---|---|
| `websdr-js8-start --no-route` | Start the apps but skip the audio-routing step (you'll route it yourself). |
| `websdr-js8-start --no-commstat` | JS8Call only. |
| `websdr-js8-start` again | Safe at any time: everything already running is reused (handy to re-route audio after changing sites). |

## Changing settings

Settings live in `~/.config/websdr-js8/config` (plain `KEY=VALUE` lines): the JS8Call
profile name, the virtual-device names, the JS8Call API ports, the FLDIGI station's
folders, devices and ports (`FLDIGI_DIR`, `NBEMS_DIR`, `FL_SINK`, `FL_TXVOID`,
`FL_XMLRPC_PORT`, `FL_ARQ_PORT`, `FL_KISS_IO_PORT`, `FL_KISS_OUT_PORT`), and your callsign
and grid. Environment variables named `WEBSDR_JS8_<KEY>` override them (for example
`WEBSDR_JS8_TCP_PORT=2500 websdr-js8-start`). Callsign, grid and state are also stored
inside JS8Call's and CommStat's own settings; change them there.

## FLDIGI + FLMSG + FLAMP: a session, start to finish

1. **Start the station.** Run `websdr-fldigi-start`, or use *Start WebSDR FLDIGI +
   FLMSG/FLAMP* from your applications menu or Desktop. The first time, it creates the
   station's own settings: a copy of `~/.fldigi` (so your macros, frequency list and
   modem settings carry over) in `~/.fldigi-websdr`, and FLMSG/FLAMP settings in
   `~/.nbems-websdr`. If you've never run FLDIGI, it starts from fresh settings with
   the callsign and grid you gave the installer.
2. Every start then switches off rig control, PTT and spotting, creates two virtual
   audio devices, and starts FLDIGI, which opens FLMSG and FLAMP.
3. **Play and tune a web SDR** in **USB** mode, to the dial frequency you'd use on a
   radio. Signals appear at their audio offsets in FLDIGI's waterfall (for example an
   AmRRON net on 7.110 MHz dial with Contestia at 900 Hz).
4. **Route the audio**: press Enter in the launcher window and pick the browser stream.
5. **Watch it decode.** Click a signal in the waterfall, or let RSID switch the mode
   for you. Received FLMSG forms open in FLMSG; FLAMP collects received files in
   `~/.nbems-websdr/FLAMP/rx`.
6. **Stop.** `websdr-fldigi-stop` closes FLAMP, FLMSG and FLDIGI (asking FLDIGI to
   close itself, so it saves its settings) and removes its virtual audio devices.

Both stations can run at the same time: they use different audio devices and ports.
Play each in its own browser tab (one per frequency) and pick the right tab in each
launcher. The FLDIGI station can also run beside a normal, radio-connected FLDIGI.

| Command | Effect |
|---|---|
| `websdr-fldigi-start --no-route` | Start FLDIGI, FLMSG and FLAMP but skip the audio-routing step. |
| `websdr-fldigi-start` again | Safe at any time: re-routes the audio and reuses everything already running. |
