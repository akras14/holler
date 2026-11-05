# Holler

A minimal push-to-talk dictation app for macOS. Hold Right Option, talk, let go, and
the text is pasted wherever your cursor is. It started as a lean replacement for
FluidVoice, keeping just the part that gets used.

Speech recognition is [Parakeet TDT v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)
(English) running on the Neural Engine through [FluidAudio](https://github.com/FluidInference/FluidAudio).
Nothing leaves your Mac.

## Using it

- **Hold Right Option** to record. A small pill at the bottom of the screen shows your
  voice level. **Let go** and the transcript is pasted into the app you're in.
- **Taps and shortcuts are ignored.** A press shorter than 0.3 s, or Right Option used as
  part of a shortcut (⌥-letter for special characters, ⌘⌥…), records nothing.
- **Your clipboard is put back** after the paste, and the dictated text is marked
  transient so clipboard managers skip it.
- **The menu bar icon** shows the last ten transcripts (click one to copy it again),
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
