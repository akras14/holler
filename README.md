# Holler

A minimal dictation app for macOS. Tap Right Option, talk, tap it again, and the
text is pasted wherever your cursor is. It started as a lean replacement for
FluidVoice, keeping just the part that gets used.

Speech recognition is [Parakeet TDT v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)
(English) running on the Neural Engine through [FluidAudio](https://github.com/FluidInference/FluidAudio).
Nothing leaves your Mac.

## Using it

- **Tap Right Option** to start recording. A small pill at the bottom of the screen shows
  your voice level. **Tap it again** and the transcript is pasted into the app you're in.
- **Esc cancels** a recording without pasting anything. Other keys don't stop it.
- **Shortcuts are ignored.** Right Option used as part of a shortcut (⌥-letter for special
  characters, ⌘⌥…) records nothing, and neither does an accidental double tap.
- **Your clipboard is put back** after the paste, and the dictated text is marked
  transient so clipboard managers skip it.
- **Transcribe File to Clipboard…** in the menu takes a recording or video (MP3, M4A, WAV,
  MP4, MOV, anything macOS plays) and copies its transcript to the clipboard. When it's done,
  a window says so, shows how it starts, and offers to save it as a text file. Long files
  are fine: a lecture is read in chunks, and you can keep dictating meanwhile.
- **The menu bar icon** shows the last five transcripts (click one to copy it again, or clear them),
  lets you pick a microphone, and has Launch at Login.

The first launch asks for two permissions: **Microphone**, and **Accessibility**, which
macOS requires both for watching the Right Option key in other apps and for pasting.

## What's left out

Deliberately: AI rewriting, command and write modes, other languages and models,
custom hotkeys, sounds, onboarding, analytics and update checks. If one of these
turns out to matter, add just that.

## Build

You need an Apple Silicon Mac with macOS 14 or later and the Xcode Command Line Tools.
Full Xcode isn't required.

```sh
./build.sh            # builds build/Holler.app
./build.sh --install  # also copies it to /Applications
```

The model (about 450 MB) is downloaded on first launch into
`~/Library/Application Support/Holler/Models`. If FluidVoice has already downloaded
Parakeet v2, Holler uses its copy instead.

Run the tests with:

```sh
swift run HollerChecks
```

They're a small executable instead of an XCTest target because XCTest doesn't run with
the Command Line Tools alone. They transcribe speech made with `say` through the real
model, cut into microphone-sized buffers, and drive the paste, menu and pill offscreen.
They can't press keys in other apps or use the microphone, so try those by hand.

To look at the recording pill without dictating:

```sh
swift run HollerChecks --snapshot-indicator pill.png
```

`swift scripts/make-icon.swift` redraws the app icon.

### Signing

macOS ties the Accessibility and Microphone grants to the app's signature. Without a
certificate, `build.sh` signs ad-hoc, and that signature changes with every build: the
grants still show ON in System Settings after a rebuild, but are silently refused.

A self-signed certificate keeps the signature the same from build to build. Create one
once:

1. Open Keychain Access, then **Keychain Access > Certificate Assistant > Create a Certificate...**
2. Name it **ak-dev**, set Identity Type to **Self Signed Root** and Certificate Type to
   **Code Signing**, and click Create.

`build.sh` finds it by name and prints `Signed with "ak-dev"`. The first time, macOS may
ask whether codesign can use the key: choose Always Allow. To use a certificate you
already have, pass its name: `LOCAL_SIGN_NAME="My Cert" ./build.sh`.

The same certificate works for [Lightdown](https://github.com/akras14/lightdown). It only
matters on your own Mac; it doesn't make builds trusted anywhere else.

## Project layout

| Path | What it does |
|------|--------------|
| `Sources/HollerKit/App.swift` | App startup: menu bar icon, permissions, wiring the pieces together |
| `Sources/HollerKit/DictationKey.swift` | Right Option taps and Esc to start, finish or cancel, ignoring shortcuts |
| `Sources/HollerKit/KeyMonitor.swift` | Key events from every app, passed to the dictation key |
| `Sources/HollerKit/Recorder.swift` | Microphone capture, converted to 16 kHz mono, and the input level |
| `Sources/HollerKit/Microphones.swift` | The list of input devices |
| `Sources/HollerKit/Transcriber.swift` | Finding, downloading and running the Parakeet model |
| `Sources/HollerKit/Dictation.swift` | Key to microphone to transcript to paste |
| `Sources/HollerKit/Paster.swift` | Pasting into the frontmost app and putting the clipboard back |
| `Sources/HollerKit/History.swift` | The last five transcripts |
| `Sources/HollerKit/Indicator.swift` | The floating pill shown while recording and transcribing |
| `Sources/HollerKit/StatusMenu.swift` | The menu bar menu |
| `Sources/Holler/main.swift` | Starts the app (the code lives in `HollerKit`) |
| `Checks/` | Test suite |
| `scripts/make-icon.swift` | Draws `Resources/AppIcon.icns` |

## Third-party code

Fetched by Swift Package Manager when you build:

- [FluidAudio](https://github.com/FluidInference/FluidAudio) 0.18.2: Apache 2.0

Downloaded on first launch, unless FluidVoice already has a copy:

- [Parakeet TDT 0.6B v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) by NVIDIA, in
  [FluidInference's Core ML conversion](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml): CC BY 4.0

## License

Holler is licensed under the [Apache License 2.0](LICENSE). Third-party notices are in [NOTICE](NOTICE).
