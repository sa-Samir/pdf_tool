# PDF Toolbox

On-device PDF tools for iOS and Android. Nothing is uploaded: every operation
runs locally, there is no account, and the app works in airplane mode.

## Documentation

| Document | What it covers |
|---|---|
| [docs/requirements.md](docs/requirements.md) | Product requirements (v2.1). Features, tiers, privacy, error taxonomy, performance targets. |
| [docs/feasibility.md](docs/feasibility.md) | Per-feature technical feasibility, library and licensing decisions, effort model, risk register. |
| [docs/roadmap.md](docs/roadmap.md) | Phased development plan with gates, staffing scenarios and the non-engineering track. |

## Current state

Phase 1 foundation and the first two tools (roadmap.md 5, 7).

**Working**

- Native launch screens on both platforms, adaptive to light and dark.
- Home screen: grouped tool catalog, verb-aware search, recents, empty states,
  responsive phone/tablet layouts, light and dark themes.
- `PdfEngine` facade over the Rust engine, with engine errors mapped onto the
  requirements.md 12 failure taxonomy. One file imports the PDF package.
- Job runner: step progress, cancellation, failure mapping.
- Document store: workspaces, verify-then-commit, collision-safe naming,
  crash sweep at launch.
- Import through the system document picker, copied into the sandbox.
- **Merge** and **Split** end to end, including share/export.
- **Page grid**: one screen behind Rotate, Reorder, Delete, Duplicate and
  Extract. Multi-select, drag to reorder with edge auto-scroll, one undo stack
  across every kind of edit, and a single save (requirements.md 3.6).
- Lazily rendered page thumbnails with a bounded LRU cache.
- **Library**: a local SQLite record of everything the app produces, wired into
  every save. Recents on the home screen, a Files screen with search, sort and
  favourites, rename/share/delete, retention, and clear-history in Settings.

**Not yet**

Compress, Images to PDF and PDF to Images are still placeholder screens.
Folders are not built yet, and there is no full-page viewer (the grid covers
page-level work; opening a file hands it to the platform).

## Architecture

All PDF work goes through `PdfEngine` (`lib/core/engine/`). No feature or UI
code imports the PDF package directly, so the engine stays swappable
(requirements.md 17).

Long operations run through `JobController`, which owns progress, cancellation
and error mapping. Output is always written to a workspace, verified, then
atomically moved into the library, so a failure leaves the original untouched
and nothing half-written behind (requirements.md 5.2).

## Running

```
flutter pub get
flutter run
```

Requires Flutter 3.38+. Minimum platforms are Android API 26 and iOS 15
(requirements.md 2).

## Checks

```
flutter analyze
flutter test
```

`test/integration/` exercises the real Rust engine rather than a fake.

## Build prerequisites

`pdf_manipulator` ships the engine's Rust sources and its build hook compiles
them with cargo, so **a Rust toolchain of 1.92 or newer is required** to build
the app (verified against 5.0.0 on an iOS simulator build; an older toolchain
fails the build with a clear version error). Install or update with:

```
rustup update
```

No `sudo` is needed — rustup installs into your home directory. The first
build is slow because the engine compiles from source; later builds reuse
cargo's cache. CI must cache `~/.cargo` and the hook's build directory, and
must have Rust available at all.
