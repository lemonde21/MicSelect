# 🎙️ MicSelect

[![Build](https://github.com/lemonde21/MicSelect/actions/workflows/build.yml/badge.svg)](https://github.com/lemonde21/MicSelect/actions/workflows/build.yml)
![iOS 15](https://img.shields.io/badge/iOS-15.x-blue)
![Rootless](https://img.shields.io/badge/jailbreak-rootless%20(Dopamine)-purple)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

**Choose which microphone your apps use — even with earphones plugged in.**

When you plug in wired earphones that have a built-in mic, iOS automatically switches every app to the earphone microphone. MicSelect lets you keep using the iPad's internal microphone instead (or force the headset mic), in Discord and any other app that records audio, while sound still plays through your earphones.

<!-- Add a screenshot of the Settings page here:
![MicSelect settings](docs/screenshot.png)
-->

## Features

- **Pick your microphone**: *Default* (iOS decides), *Built-in*, or *Headset*.
- **Works in every app** that uses the standard iOS audio system: Discord, Telegram, voice recorders, browsers, and more.
- **Applies instantly**: switch mics mid-call, no app restart needed.
- **Settings page** with a live **mic monitor**: hear the selected microphone through your earphones with a level meter, to check which one is active.
- **Microphone check**: lists the microphones iOS currently exposes.
- **Command-line control**: `micsel builtin`, `micsel headset`, `micsel default`.
- Remembers your choice across resprings and reboots.

## Compatibility

| | |
|---|---|
| iOS | 15.0 – 15.8.x |
| Jailbreak | Rootless (Dopamine) |
| Dependencies | ElleKit / Substrate, PreferenceLoader |

Developed on an iPad mini 4 (iOS 15.8.6, Dopamine).

## Installation

1. Download the latest `.deb` from the [Releases](https://github.com/lemonde21/MicSelect/releases) page.
2. Open it with Sileo, Zebra, or Filza and install.
3. Go to **Settings → MicSelect**.

## Usage

**Settings:** pick *Built-in* to keep the iPad's microphone while earphones are connected. Turn on **Listen to microphone** (earphones required) to hear the active mic and confirm it works.

**Terminal:**

```sh
micsel builtin   # internal microphone
micsel headset   # earphone microphone
micsel default   # let iOS decide
micsel           # show current mode
```

## How it works

Apps request audio routes through `AVAudioSession`. MicSelect is injected into apps and hooks `AVAudioSession` so that whenever an app activates or reconfigures its audio session, or the route changes (earphones plugged/unplugged), the selected input is applied with `setPreferredInput:`. If an app tries to choose an input itself, the user's choice takes priority.

The current mode is shared with every process through `notifyd` state, which works even inside sandboxed apps and allows live switching. SpringBoard persists the setting so it survives reboots.

## Limitations

- Works only if iOS still offers the internal microphone while earphones are connected. Use **Check connected microphones** in Settings to see whether your device does.
- Covers apps, not system daemons: regular phone/FaceTime calls, Siri and dictation use separate audio paths and aren't affected.
- Bluetooth headsets behave differently; choosing the built-in mic with Bluetooth may change the output route as well. The tweak is aimed at wired earphones.

## Building

Requires [Theos](https://theos.dev).

```sh
make package FINALPACKAGE=1
```

Building **on a rootless device** (Dopamine): `make` needs to be pointed at bash:

```sh
make SHELL="$(command -v bash)" package install
```

Every push to `main` is also built automatically by GitHub Actions; pushing a tag like `v0.3.0` publishes a release with the `.deb` attached.

### Project layout

```
Tweak.x            AVAudioSession hooks (injected into apps) + SpringBoard persistence
Shared.h           Constants shared by all parts
micselectprefs/    Settings page (PreferenceLoader bundle) with mic monitor
micselctl/         `micsel` command-line tool
```

## License

[MIT](LICENSE)
