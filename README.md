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
| Settings window: where new models are downloaded | Built; not yet checked by eye |
| Pause and resume a download | Working; tested live (resumes from the partial files) |
| Delete a model (files and setup folder), with a confirmation window | Working; tested live on a throwaway install |
| Download time left, measured over the last few minutes rather than Colibri's whole-run average | Working; tested with real readings |
| Health check: `coli doctor --json` decoding, surfaced as a Metal-capability indicator (bolt icon) in the Configure window and the models list, read per model from the `accelerator.gpu` check | Built, with unit-tested interpretation of pass/warn/fail; not yet checked by eye against a live Metal-capable engine |
| `kolibrie` helper: `list`, `start`, `stop`, `catalogue`, `install`, `pause`, `resume`, `delete`, `install-colibri`, `check-updates` | Working |
| Set up Colibri when it is missing: checks Python and libomp, installs them with Homebrew if present, downloads the release archive, verifies its checksum | Core tested, including a real download and checksum check; the offer window at launch is built but not yet seen on a Mac without Colibri |
| Update checks at launch for Colibri and Kolibrie, with an Updates window; Colibri updates restart running models; Kolibrie replaces itself and reopens | Checks tested against GitHub; Colibri update uses the tested installer; the app swap is tested on a stand-in app, not yet on a packaged release |
| Harness launcher: Claude Code, Codex, OpenCode, Pi, Hermes Agent, Copilot CLI (pure env vars or CLI flags); Mistral Vibe, DeepSeek Harness (isolated per-launch config); OpenClaw (isolated config, schema unverified) | Built, with unit-tested config generation for each harness; not yet checked by eye in a real Terminal window, and only Claude Code, Codex, OpenCode, Pi and Hermes Agent are installed on the dev Mac to confirm against |
| Configuration UI: RAM/context/cap/VRAM, sampling (temp/top-p/top-k/policy/think/effort), server flags (model id, API key, CORS, allowed hosts, queue, KV slots), a Metal toggle, and an Advanced table for any other Colibri environment variable by name, applied via `coli setup --reconfigure` | Built, with unit-tested flag generation and round-trip parsing of an existing setup.json; the window itself not yet checked by eye |
| Metal engine option (surfaced in the configuration UI above; still Colibri's own default on this Mac) | Planned |
| Run at login via `SMAppService`, with a per-model "start automatically at login" toggle so Kolibrie can open with no model loaded, or with one already starting | Built; `SMAppService` registration needs a properly bundled, signed app to test for real, so this is unverified until Phase 6 packaging |

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

## Releases

Kolibrie looks for updates on its GitHub releases page. A release needs `Kolibrie-<version>.zip` (containing `Kolibrie.app`) and a `SHA256SUMS.txt` that lists it. The check is quiet until a release exists.
