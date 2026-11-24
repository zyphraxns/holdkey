# Contributing to HoldKey

Thanks for taking an interest in HoldKey. It is a small, single-maintainer macOS utility, so this guide is deliberately lightweight.

## Development setup

Requirements: macOS 14+ on Apple silicon, Xcode Command Line Tools (`xcode-select --install`), and no full Xcode.app.

```bash
git clone https://github.com/zyphraxns/holdkey.git
cd holdkey
./scripts/setup-signing.sh   # optional but strongly recommended
./scripts/build.sh           # release build -> dist/HoldKey.app
./scripts/build.sh debug     # debug symbols, no optimization
open dist/HoldKey.app
```

Then grant Accessibility permission in System Settings → Privacy & Security → Accessibility. The panel shows a green dot when the permission is active.

**About signing:** if `setup-signing.sh` has not been run, `build.sh` falls back to ad-hoc signing. That makes the Accessibility authorization drop on every rebuild. Create the local cert once to avoid chasing a permission checkbox that looks enabled but no longer works.

There is no SwiftPM package and no XCTest target. `scripts/build.sh` compiles `Sources/HoldKey/*.swift` directly with `swiftc` targeting `arm64-apple-macosx14.0`.

## Project layout

```
Sources/HoldKey/
  App.swift           # menu bar entry, focus observers, self-test
  HoldEngine.swift    # presets, hotkey registration, run/timer state
  HotKey.swift        # Carbon global hotkey manager (single event handler)
  Presets.swift       # preset model, defaults, key combo helpers
  KeyPresser.swift    # CGEvent key down/up with owner tokens
  MenuContent.swift   # panel UI, hotkey recording
  SettingsView.swift  # settings panel
  Permissions.swift  # Accessibility check
  Log.swift          # file logging
scripts/
  build.sh            # swiftc build + .app bundle assembly
  sign.sh             # local cert, ad-hoc fallback
  setup-signing.sh    # one-time local self-signed cert
```

## Reporting bugs

Search existing Issues first. A useful report includes:

- macOS version and hardware (Intel is currently unsupported)
- HoldKey version and how you obtained it (Release zip vs. local build)
- exact steps to reproduce, plus expected vs. actual behavior
- the relevant lines from `~/Library/Logs/HoldKey.log`

If the symptom is a stuck key, note whether `systemKeyState=up` appears in the log and whether a `WARNING` was logged.

## Proposing features

Open an Issue describing the use case first. Please keep in mind the project's constraints: it is a keyboard-holding utility, not a game bot; it does not read the screen; and every default hotkey avoids Ctrl on purpose.

## Pull requests

1. Fork and create a branch, e.g. `git checkout -b fix/menu-countdown`.
2. Keep changes focused. Verify with `./scripts/build.sh debug` and, if you change hotkey or release behavior, exercise the corresponding path in a real app window.
3. Do not regress the focus-safety behavior: switching to another app must stop the hold and release the key, and a stale owner must never release a newer hold.
4. Describe the change in the PR and link the issue it addresses.

## Style

- Swift files: 4-space indentation, descriptive names, comments only where the reason is non-obvious.
- Shell scripts: `set -euo pipefail`, 4-space indentation.
- Markdown: 2-space indentation, trailing whitespace allowed (see `.editorconfig`).

## License

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).
