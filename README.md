# tepevësen

[![build](https://github.com/luksgodoy/Tepev-sen/actions/workflows/build.yml/badge.svg)](https://github.com/luksgodoy/Tepev-sen/actions/workflows/build.yml)

A field recorder for iPhone, built as a version of the [teenage engineering
TP–7](https://teenage.engineering/products/tp-7) — the same design, the same
capabilities, the same proposal, carried over to the only recorder people
actually have in their pocket.

Native SwiftUI. iOS 17+. iPhone only, portrait only, because the machine is
held in one hand.

> An independent tribute. Not affiliated with, endorsed by, or produced in
> partnership with teenage engineering.

---

## The proposal

The TP–7's argument is that a recorder should be a *machine*, not an app: one
key that always starts a take, one reel that is always the tape, one display
that never lies about what it is doing, and a body you can operate without
looking at it. Everything else — files, transcripts, sharing — happens
afterwards, somewhere else.

tepevësen keeps that argument intact. The face of the app is the machine. The
two screens behind it (tapes, text) are drawers you open and close, and the
app never asks you to visit one before you can record.

## Parity with the hardware

| TP–7 | tepevësen |
|---|---|
| Motorised brushless reel, high resolution | `TapeReel` + `ReelMotor` — a `CADisplayLink`-driven angle geared to the transport at 0.5 rev/s per 1× |
| Reel for scrubbing and scratching | `ScratchVoice` — an interpolating read head over a 22.05 kHz mono copy of the tape, driven by signed angular velocity, so reverse works |
| Finger on the reel stops capture | Touch-down while recording enters `recordHold`: still armed, no longer writing |
| Reel as visual feedback | Three windows at 120° and a rim index mark, so rotation is legible; ring around the well shows position |
| 24-bit / 96 kHz | Session asks for 96 kHz, `AVAudioFile` writes 24-bit linear PCM at whatever rate the phone actually delivers — and the machine displays the rate it *got* |
| 128 GB internal storage | Device storage, with free space and remaining tape time in `system` mode |
| Memo key: one press, starts a new recording | `MemoButton`, plus `StartMemoIntent` on the Action button, Lock Screen, Control Center and Siri |
| Mode key | Walks five display pages: `tape · level · speed · input · system` |
| Side rocker: press up to run forward, down to rewind | `ShuttleRocker`, winding up 2× → 4× → 8× while held |
| Tape speed | 0.25×–4×, pitch following speed by default (`AVAudioUnitVarispeed`), pitch-lock optional (`AVAudioUnitTimePitch`) |
| 64 × 32 monochrome display | A real 2048-dot bilevel panel — glyphs are rasterised through Core Graphics with antialiasing off and thresholded, so any script renders |
| 3× two-way 3.5 mm jacks + 1× 1/4" out | `JackStrip` bound to live `AVAudioSession` routes: internal, wired/USB-C, Bluetooth, monitor out. A socket fills only when the route genuinely exists; tapping a two-way socket patches the input |
| USB-C · MFi · Bluetooth | Route selection and monitoring through the audio session |
| Transcription in most languages, via the app | `SFSpeechRecognizer` over every locale the phone supports, forced on-device wherever available, with each word a tappable seek point |
| Brushed aluminum and black anodized bodies | Both finishes, in `setup` |
| Mechanical feel | Core Haptics: 24 detents per reel revolution, transport key clicks, a continuous motor hum under scrubbing |

## What the machine does

**Record.** Press `memo` — or `rec` — and it is already rolling. Long-press
`rec` while recording to drop a mark. Takes under a quarter second are thrown
away rather than filed.

**Play.** `play` toggles play/pause. Long-press `stop` steps to the next tape.
The rocker shuttles; the reel scrubs.

**The reel.** Put a finger on it and the tape stops. Turn it and the tape
moves, audibly, in either direction. Let go with a flick and it freewheels
until the bearings give up, then hands the tape back to the transport. While
recording, the reel is a brake on capture instead.

**Transcribe.** `text` → pick a language → transcribe. The machine states
before it starts whether the job runs entirely on-device or goes to Apple's
servers. Low-confidence words are drawn fainter rather than presented as
certain.

**Tapes.** Plain 24-bit WAV files in the app's Documents folder, visible in the
Files app, with a JSON index beside them. The index follows the files, never
the other way round — delete a WAV and its entry disappears.

## Layout

The hardware is 96 × 68 × 16 mm and lands in a palm sideways. A phone is the
same object stood upright, so the layout is stood up with it and the
relationships are preserved:

```
┌──────────────────────────────┐
│  int   1/8   bt   1/4        │  connector edge
│ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│  tepevësen        96k · 24bit│
│  ┌────────────────┐   ╭───╮  │
│  │ 64 × 32 dots   │   │mem│  │  display + memo
│  └────────────────┘   ╰───╯  │
│  ▲  ╭──────────────────╮     │
│  ║  │       reel       │     │  rocker + reel
│  ▼  ╰──────────────────╯     │
│  ╭─────╮ ╭─────╮ ╭─────╮     │
│  │ rec │ │play │ │stop │     │  transport
│  ╰─────╯ ╰─────╯ ╰─────╯     │
│  ╭────╮ ╭────╮ ╭────╮        │
│  │mode│ │tape│ │text│        │
│  ╰────╯ ╰────╯ ╰────╯        │
└──────────────────────────────┘
```

## Building

Requires Xcode 16 or later (the project uses synchronized folder groups, so
files added under `tepevesen/` are picked up without editing the project file).

```sh
open tepevesen.xcodeproj
# select a device or simulator, ⌘R
```

Set your own team under **Signing & Capabilities**; the bundle identifier is
`engineering.tepevesen.app`.

To regenerate the project from scratch instead:

```sh
brew install xcodegen && xcodegen generate
```

**Test on a device, not the Simulator.** The Simulator has no real input route,
no Core Haptics, and no 96 kHz hardware, so the reel, the meters and the format
line are all meaningless there.

## Source map

```
tepevesen/
├── Design/
│   ├── TEDesign.swift        finishes, palettes, metrics, type, silkscreen
│   ├── BrushedMetal.swift    milled chassis surfaces, edges, recesses
│   └── DotMatrix.swift       64 × 32 bitmap, CG rasteriser, the panel
├── Audio/
│   ├── AudioMachine.swift    the transport: record, play, varispeed, shuttle
│   ├── ScratchVoice.swift    scrub copy + the reel's read head
│   └── JackPanel.swift       jacks bound to live audio routes
├── Hardware/
│   ├── DeviceFace.swift      the faceplate layout
│   ├── TapeReel.swift        the reel and its gesture
│   ├── ReelMotor.swift       angle, detents, freewheel
│   ├── TransportKeys.swift   key caps, rec/play/stop
│   ├── MemoButton.swift      memo + mode
│   ├── ShuttleRocker.swift   the side rocker
│   └── JackStrip.swift       the connector edge
├── Tape/
│   ├── Tape.swift            the tape model and timecode
│   ├── TapeLibrary.swift     storage, index, capacity
│   └── Waveform.swift        peak reduction
├── Transcription/
│   └── Transcriber.swift     SFSpeechRecognizer, on-device first
├── State/
│   ├── DeviceState.swift     the machine — the only place the parts meet
│   ├── DisplayRenderer.swift what the 2048 dots say, per mode
│   ├── Haptics.swift         detents, key clicks, motor hum
│   └── MemoIntent.swift      memo as a system-wide button
└── Screens/
    ├── TapeListView.swift    the tapes drawer
    ├── TranscriptView.swift  transcribe
    ├── SettingsView.swift    setup
    └── WaveformView.swift    a tape, drawn
```

## Known limits

- Recording continues in the background (the `audio` background mode), but iOS
  will not start a recording while the app is backgrounded — which is why the
  memo intent foregrounds the app rather than capturing silently.
- Scrub audio is 22.05 kHz mono by design. Full-rate playback streams from
  disk; only the reel's read head is lo-fi, the same way dragging tape across a
  head is.
- 96 kHz is a request, not a promise. Bluetooth inputs in particular will hand
  back 16 kHz, and the machine displays that rather than the number it asked
  for.
- **Compiled, not yet run.** CI builds the app clean for the iOS Simulator on
  every push — zero errors, zero warnings — but nothing here has been launched
  on a device, so no runtime behaviour is verified. The reel physics, the
  scratch voice, the meters, haptics, route switching and transcription have
  all been reasoned about and none of them have been heard. Expect the first
  session on hardware to be a tuning session.
