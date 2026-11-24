# HoldKey

<p align="right"><sub><a href="README.zh-CN.md">中文文档</a></sub></p>

**One hotkey holds a key for N seconds — four presets, each with its own hotkey, that let go the instant you switch away.**

<sub>macOS 14+ · Apple silicon (arm64) · local-only, no network or telemetry</sub>

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

HoldKey is for games and streamed sessions (e.g. GeForce NOW) where you need a movement key held for a while — climbing, walking forward, mounting. Holding it by hand is tedious, and a naive macro can leave the key stuck. HoldKey lets go on a timer and the moment you leave the app.

| Preset | Hotkey | Holds | Time |
| --- | --- | --- | --- |
| 1 · Forward | `⌥⌘H` | W | 30 s |
| 2 · Left | `⌥⌘J` | A | 30 s |
| 3 · Back | `⌥⌘K` | S | 30 s |
| 4 · Jump | `⌥⌘L` | Space | 30 s |

No default hotkey uses Ctrl (walk/run in Genshin), and all four can be recorded in the panel. While a hold is running the menu bar shows `Preset name · Ns`; at rest it shows a keyboard icon.

## Install

Requirements: macOS 14+, Apple silicon only (`arm64-apple-macosx14.0`), Xcode Command Line Tools to build (no full Xcode), and Accessibility permission.

### Prebuilt binary

Download `HoldKey.app.zip` from the [latest release](https://github.com/zyphraxns/holdkey/releases/latest), unzip, and move `HoldKey.app` into Applications. On first launch, right-click → **Open** (locally signed, not notarized).

### From source

```bash
git clone https://github.com/zyphraxns/holdkey.git
cd holdkey
./scripts/setup-signing.sh   # once: local self-signed cert
./scripts/build.sh           # -> dist/HoldKey.app
open dist/HoldKey.app
```

There is no SwiftPM package: `build.sh` compiles `Sources/HoldKey/*.swift` directly with `swiftc`, so Command Line Tools are enough.

<details>
<summary>Why the signing script matters</summary>

TCC remembers *code identity*, not just "which app". An ad-hoc signature (`codesign -s -`) changes on every rebuild, so Accessibility authorization silently stops working after each build. `setup-signing.sh` creates a local certificate whose designated requirement stays stable across rebuilds. Both scripts are local-only: nothing is uploaded and no Apple developer account is needed.

</details>

## Quick start

1. Launch HoldKey, grant Accessibility permission, and wait for the green dot in the panel.
2. Click the menu-bar keyboard icon, pick preset 1–4, and adjust name, key, or duration if you like.
3. Focus your game and press that preset's hotkey (or click **Start holding…**).
4. Press the same hotkey again, or switch to another app, to stop.

Full instructions (Chinese): [使用说明.md](使用说明.md).

## Configuration

Presets are stored in local preferences: `hold.presets.v1` (four presets as JSON) and `hold.selectedPreset`. The panel lets you rename a preset, pick the key, set the duration, and record a hotkey. A recorded hotkey must include Option, Command, or Shift, and must not include Control.

## Safety and scope

HoldKey injects **global** keyboard events (CGEvent): while a hold is active it occupies the keyboard and the machine is not freely usable. It only holds a key — it does not read the screen, click, or make decisions. There is a 30-minute cap; keys are released on quit, sleep, logout, and shutdown, and stale keys are cleaned up on the next launch.

<details>
<summary>Terms-of-service note</summary>

Use it at your own risk and make sure your use complies with the terms of the game and any streaming platform. Some publishers treat third-party input tools as a violation.

</details>

## Logs

One line per activation goes to `~/Library/Logs/HoldKey.log` (falling back to a temp dir). `systemKeyState=up` confirms the system sees the key as released; `WARNING` means a release was retried.

<details>
<summary>Example log lines</summary>

```
[2026-11-23T18:26:49Z] [pid 337] fire key=W vk=13 secs=2.0 focus=Safari
[2026-11-23T18:26:51Z] [pid 337] hold done vk=13 fired=53 cancelled=false held=0 systemKeyState=up
```

</details>

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for build instructions and contribution guidelines.

## License

MIT — see [LICENSE](LICENSE).
