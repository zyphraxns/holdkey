# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/lang/zh-CN/).

## [Unreleased]

## [0.1.0] - 2026-11-23

### Added

- Four configurable presets (name / key / duration / hotkey), persisted in local preferences.
- One global hotkey per preset, recordable in the panel. Defaults are `⌥⌘H/J/K/L` with no Ctrl modifier.
- Live menu-bar countdown showing `Preset name · Ns` while running; keyboard icon at rest.
- Automatic stop and key release when focus leaves the target app or the panel becomes key.
- Stale-key cleanup on launch and manual "release all keys" button.
- Local self-signed certificate setup so Accessibility authorization survives rebuilds.

### Fixed

- Carbon hotkey dispatch: replaced four event handlers that matched only on signature with a single handler that dispatches on hotkey ID, so each hotkey triggers its own preset.
- Generation tokens on key releases prevent an old hold from releasing a newer hold of the same key.
- Removed the contradictory "switch back within one second" hint.
