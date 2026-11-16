# swiftColibri

A native macOS menu bar app, written entirely in Swift, for installing, configuring and running [Colibri](https://github.com/JustVugg/colibri) and pointing coding harnesses at its models.

> Working name, to be confirmed before the first release.

## Status

Phase 1 of the plan: the core and a first menu bar app. It finds existing Colibri installs, shows each model's state, and starts and stops them.

| Area | State |
| --- | --- |
| Discover installs, read `setup.json`, read `coli status --json` | Working, tested against real Colibri 2.1.0 output |
| Start and stop a model | Working; tested on a live install |
| Menu bar app: model rows, download progress, logs window, copy URLs | Built; not yet checked by eye |
| `swiftcolibri` helper: `list`, `start <id>`, `stop <id>` | Working |
| Install Colibri and models, harness launcher, configuration UI, updates, run at login | Planned |

## Building

You need macOS 15 or later on Apple Silicon and Xcode. The Command Line Tools alone are not enough, because SwiftUI's macros ship only with Xcode.

```sh
export DEVELOPER_DIR=/Applications/Development/Xcode.app/Contents/Developer
swift build
swift test
swift run SwiftColibriApp          # the menu bar app
swift run swiftcolibri list        # the helper
```

The app expects an existing Colibri install: one folder per model named `colibri` or `colibri-*` in `~/Library/Application Support`, and Colibri's `coli` launcher at `~/Development/colibri/c/coli` or at the path in `SWIFTCOLIBRI_COLI`. Python 3.10 or newer is needed (Homebrew's works).

## Layout

| Path | What it is |
| --- | --- |
| `Sources/ColibriKit` | Models for `setup.json` and `coli status --json`, discovery, the `coli` wrapper, the state logic |
| `Sources/ColibriAPI` | Client for a running server's `/health` and `/v1/models` |
| `Sources/SwiftColibriApp` | The SwiftUI menu bar app |
| `Sources/swiftcolibri` | The command-line helper |
| `Tests/` | Swift Testing suites, with fixtures captured from a real install |

## Requirements

macOS 15 or later on Apple Silicon.

## Licence

Apache-2.0, the same licence as Colibri. See `LICENSE` and `NOTICE`. Model weights keep their own licences.
