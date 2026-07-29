# Building tepevësen on a Mac

Start to finish. The project already compiles clean — CI builds it on every
push with zero errors and zero warnings — so everything below is about getting
it onto *your* phone, which is the part CI cannot do for you.

Budget about ten minutes the first time, most of it Xcode downloading
simulators.

---

## 0. What you need

| | |
|---|---|
| **Mac** | Apple silicon or Intel, macOS 14 Sonoma or later |
| **Xcode** | **16.0 or later** — required, not a preference (see below) |
| **iPhone** | iOS 17.0 or later. Strongly recommended over the Simulator |
| **Apple ID** | A free one works. No paid developer account needed |
| **Cable** | Or Wi-Fi pairing, once the phone has been plugged in once |

Xcode 16 is a hard requirement because `tepevesen.xcodeproj` uses *synchronized
folder groups* — the project references the `tepevesen/` folder rather than
listing every file, so new source files are picked up automatically. Xcode 15
does not understand that format and will refuse to open the project. If you are
stuck on 15, see [§9](#9-if-you-cannot-use-xcode-16).

Get Xcode from the Mac App Store, or from
[developer.apple.com/download](https://developer.apple.com/download/all/) if
you want a specific version.

---

## 1. Get the code

```sh
git clone https://github.com/luksgodoy/Tepev-sen.git
cd Tepev-sen
git checkout claude/tepevesen-iphone-app-og3t7e
```

Sanity-check your toolchain before opening anything:

```sh
make doctor
```

You want `Xcode 16.x` or higher. If you see 15.x, run
`sudo xcode-select -s /Applications/Xcode.app` and try again — you may have
more than one Xcode installed and the wrong one selected.

---

## 2. Prove it compiles, before you touch signing

This step needs no Apple ID and no device. It builds for the simulator with
code signing switched off, which isolates "does the code compile" from "is my
account set up" — two problems that are miserable to debug at the same time.

```sh
make build
```

Expect `** BUILD SUCCEEDED **` after 40–60 seconds. If this fails, it is a
real problem with the code or your toolchain, and nothing further in this guide
will help. If it succeeds, every remaining failure is a signing or device
problem.

---

## 3. Open the project

```sh
make open
# or: open tepevesen.xcodeproj
```

Open `tepevesen.xcodeproj` — **not** a workspace, there isn't one. There are no
Swift package dependencies to resolve, so nothing should churn on first open.

---

## 4. Set your signing team

This is the one thing you must change. Two edits:

1. Select the blue **tepevesen** project icon at the top of the file navigator.
2. Select the **tepevesen** target (under TARGETS, not PROJECT).
3. Open the **Signing & Capabilities** tab.
4. Tick **Automatically manage signing**.
5. From the **Team** dropdown, pick your name. If the list is empty:
   *Xcode → Settings → Accounts → **+** → Apple ID*, sign in, then come back.
6. Change the **Bundle Identifier** from `engineering.tepevesen.app` to
   something of your own, e.g. `com.yourname.tepevesen`.

Step 6 matters more than it looks. Bundle identifiers are globally unique
across Apple's provisioning system, and `engineering.tepevesen.app` is mine —
if you leave it, you may get *"Failed to register bundle identifier."* Change
it once and forget it.

Xcode should now show a green checkmark and a provisioning profile name. If it
shows a red error, jump to the [troubleshooting table](#10-troubleshooting).

<details>
<summary>Doing it from the command line instead</summary>

Find your team ID with:

```sh
security find-identity -v -p codesigning
```

The ten-character string in parentheses is your team ID. Then:

```sh
xcodebuild build \
  -project tepevesen.xcodeproj \
  -scheme tepevesen \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM=YOURTEAMID \
  PRODUCT_BUNDLE_IDENTIFIER=com.yourname.tepevesen
```

This does not modify the project file, so it will not show up in `git status`.
</details>

---

## 5. Choose where to run it

In the scheme selector at the top of the Xcode window, next to the ▶ button:

**On your iPhone (do this).** Plug it in. Unlock it. Tap **Trust** on the
"Trust This Computer?" prompt. Your phone's name appears in the destination
list — pick it.

**In the Simulator (only for a first look).** Pick any iPhone 16 or 15. Be
clear about what this cannot tell you:

| | Simulator | Device |
|---|---|---|
| Layout, display, waveforms | ✅ | ✅ |
| Recording | ⚠️ via your Mac's mic, 48 kHz | ✅ |
| 96 kHz / 24-bit | ❌ | ✅ |
| Haptics — reel detents, key clicks, motor hum | ❌ silent | ✅ |
| Jack strip / route switching | ❌ shows internal only | ✅ |
| Bluetooth, USB-C audio | ❌ | ✅ |
| Transcription | ⚠️ often network-only | ✅ |

The reel is the whole product and it is *half of itself* without haptics.
Judge it on a phone.

---

## 6. Build and run

Press **⌘R**, or the ▶ button.

First run on a device, in order:

1. **"Could not launch — the developer is not trusted."** Expected on the first
   install with a free account. On the phone: *Settings → General → VPN &
   Device Management → your Apple ID → **Trust***. Then press ⌘R again.
2. **Microphone permission.** Tap Allow. Denying it leaves the machine with
   nothing to record; the display will show `no mic access`.
3. **Speech recognition permission.** Only asked the first time you press
   `transcribe`, not at launch.

That's it — the machine is running.

---

## 7. What to try first

A short checklist that exercises everything that could plausibly be wrong.
Work down it in order.

1. **Press `memo`.** The reel should start turning immediately and the display
   should count up. This is the single most important interaction in the
   product.
2. **Put a finger on the reel while it records.** Capture should stop and the
   record dot should dim to half. Lift off — capture resumes. Nothing should
   be lost.
3. **Press `stop`.** The take gets filed and the display flashes its length.
4. **Press `play`.** The reel turns at 1×, the position ring fills.
5. **Grab the reel and turn it.** You should hear the recording scrub, forwards
   and backwards, and feel a detent every 15°. Backwards is the part to check
   hardest — it is the thing a normal audio player cannot do.
6. **Flick the reel and let go.** It should freewheel, still audible, and coast
   to a stop over about a second.
7. **Hold the rocker.** Top runs forward, bottom rewinds; hold past one second
   and past 2.5 seconds to feel it step 2× → 4× → 8×.
8. **Press `mode` five times.** `tape → level → speed → input → system` and
   back around. Watch `level` while you talk — the meters should move and
   invert on clipping.
9. **Plug in headphones.** The `1/8` socket on the jack strip should fill.
   Connect AirPods — `bt` should fill.
10. **Press `text`, pick a language, transcribe.** Then tap any word to seek
    to it.

Anything on that list that misbehaves is worth reporting — none of it has ever
been run.

---

## 8. Getting the tapes off the phone

Recordings are plain 24-bit WAV files, not hidden in a container:

- **On the phone:** Files app → On My iPhone → tepevësen → `tapes/`
- **On the Mac:** plug the phone in → Finder → your phone → **Files** tab →
  tepevësen
- **In the app:** long-press any tape in the `tapes` list → **share wav**

There is an `index.json` beside them holding names, marks and transcripts. It
follows the files, never the reverse — delete a WAV and its entry disappears on
next launch.

---

## 9. If you cannot use Xcode 16

Regenerate the project from `project.yml`, which produces a conventional
project file with every source listed:

```sh
brew install xcodegen
make project        # runs: xcodegen generate
```

This overwrites `tepevesen.xcodeproj`. The trade-off is that you must re-run it
whenever a source file is added or removed. The deployment target is iOS 17, so
you still need an Xcode new enough to ship that (15.0+).

---

## 10. Troubleshooting

| What you see | What it means | Fix |
|---|---|---|
| *"The project is damaged and cannot be opened"* | Xcode 15 or older | Upgrade, or use [§9](#9-if-you-cannot-use-xcode-16) |
| *"Signing for tepevesen requires a development team"* | No team selected | [§4](#4-set-your-signing-team) |
| *"Failed to register bundle identifier"* | Someone owns that ID | Change the bundle ID — [§4](#4-set-your-signing-team) step 6 |
| *"Unable to install… device is locked"* | Phone locked | Unlock it, ⌘R again |
| *"Untrusted Developer"* on launch | First install, free account | Trust it — [§6](#6-build-and-run) step 1 |
| App quits after 7 days | Free accounts expire profiles | Re-run from Xcode. A paid account lasts a year |
| Builds, but the reel does nothing | No tape loaded | Press `memo`, record a few seconds, `stop` |
| Reel turns silently when scrubbed | Scrub copy still building | Wait a moment after recording — it is built off the main thread |
| No haptics at all | Simulator, or Haptics off | Run on a device; check `setup → feel` |
| Display shows `no mic access` | Mic permission denied | Settings → tepevësen → Microphone |
| `input` mode shows 48k, not 96k | The phone declined 96 kHz | Expected. Bluetooth mics drop to 16 kHz. The machine reports what it got, deliberately |

---

## 11. Project layout

```
Tepev-sen/
├── tepevesen.xcodeproj/       the project — open this
├── Config/Info.plist          permissions, background audio, file sharing
├── tepevesen/                 all source (synchronized folder — just add files)
│   ├── Design/  Audio/  Hardware/  Tape/  Transcription/  State/  Screens/
│   └── Assets.xcassets/
├── Tools/make_icon.py         redraws the app icon, stdlib only
├── project.yml                XcodeGen manifest (fallback)
├── Makefile                   make build / open / icon / doctor
└── .github/workflows/build.yml  the CI build
```

To change the app's name on the home screen, edit `CFBundleDisplayName` in
`Config/Info.plist`. To redraw the icon, edit `Tools/make_icon.py` and run
`make icon`.
