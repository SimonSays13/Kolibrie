# Kolibrie

A native macOS menu bar app, written entirely in Swift, for installing, configuring and running [Colibri](https://github.com/JustVugg/colibri) and pointing coding harnesses at its models.

> Working name, to be confirmed before the first release.

## Status

Phases 1 and 2 of the plan are under way. Kolibrie finds existing Colibri installs, shows each model's state, starts and stops them, and installs new models from Colibri's catalogue.

| Area | State |
| --- | --- |
| Discover installs, read `setup.json`, read `coli status --json` | Working, tested against real Colibri 2.1.0 output |
| Start and stop a model | Working; tested on a live install |
| Menu bar app: model rows, download progress, logs window, copy URLs | Built; not yet checked by eye |
| Models window: catalogue checked against this Mac, install with confirmation, download progress | Built; install launch tested live with a real download (then cancelled); window not yet checked by eye |
| Install a model: detached `coli setup`, free port, free-space warning, drive-connected check | Working |
| Health check: `coli doctor --json` decoding | Working in the core; not yet shown in the app |
| `kolibrie` helper: `list`, `start <id>`, `stop <id>`, `catalogue`, `install <model>` | Working |
| Installing Colibri itself, Metal engine option, harness launcher, configuration UI, updates, run at login | Planned |

## Building

You need macOS 15 or later on Apple Silicon and Xcode. The Command Line Tools alone are not enough, because SwiftUI's macros ship only with Xcode.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # adjust to where Xcode lives
swift build
swift test
swift run KolibrieApp          # the menu bar app
swift run kolibrie list        # the helper
```

The app expects an existing Colibri install: one folder per model named `colibri` or `colibri-*` in `~/Library/Application Support`, and Colibri's `coli` launcher at `~/Development/colibri/c/coli` or at the path in `KOLIBRIE_COLI`. Python 3.10 or newer is needed (Homebrew's works).

## Layout

| Path | What it is |
| --- | --- |
| `Sources/ColibriKit` | Models for `setup.json` and `coli status --json`, discovery, the `coli` wrapper, the state logic |
| `Sources/ColibriAPI` | Client for a running server's `/health` and `/v1/models` |
| `Sources/KolibrieApp` | The SwiftUI menu bar app |
| `Sources/kolibrie` | The command-line helper |
| `Tests/` | Swift Testing suites, with fixtures captured from a real install |

## Requirements

macOS 15 or later on Apple Silicon.

## Licence

Apache-2.0, the same licence as Colibri. See `LICENSE` and `NOTICE`. Model weights keep their own licences.
