# PDF Toolbox — Architecture and Developer Guide

For a developer who has never seen this codebase and needs to change it.
Read §1–§5 before touching anything; the rest is reference.

Companion documents: [requirements.md](requirements.md) is the product spec and
the source of the `§n` references scattered through the code; [feasibility.md](feasibility.md)
holds the risk register; [roadmap.md](roadmap.md) the phase plan; [benchmarks.md](benchmarks.md)
the measured compression numbers that shaped the Compress feature.

---

## 1. What this is

A Flutter app for Android and iOS that manipulates PDFs **entirely on the
device**. No account, no upload, no network permission at runtime.

That constraint is not a feature, it is the product. It explains why there is a
Rust engine compiled into the app rather than a server call, why the file
library is a local SQLite database, and why several things that would be
trivial server-side (OCR, heavy compression) are hard here.

**Shipped in v1.0:** Viewer · Merge · Split · Rotate / Delete / Reorder /
Extract / Duplicate pages · Compress · Images → PDF · PDF → Images · Document
scanner · Library with folders · Save to device · Print.

**Deliberately not shipped yet:** annotations, signature, watermark,
protect/unlock, OCR. They are in the catalog but filtered out of the UI — see
`kShippedThrough` in [`lib/core/models/pdf_tool.dart`](../lib/core/models/pdf_tool.dart).

Roughly 10,700 lines of Dart in `lib/`, 6,600 in `test/`, 368 tests.

---

## 2. Before you can build

### Rust is required, and this is the most common setup failure

`pdf_manipulator` vendors the Rust sources of its PDF engine (`pdf_oxide`) and
compiles them through a Dart **native assets build hook** at build time. You
need a Rust toolchain of **1.92 or newer**:

```bash
rustup update
```

No `sudo` — rustup installs into your home directory. An older toolchain fails
the build with a version error that does *not* obviously point at Rust, so
check this first when a fresh clone will not build.

### Everything else

| | |
|---|---|
| Flutter | 3.38+ |
| Dart | 3.10.4 (`sdk: ^3.10.4`) |
| Android | minSdk 26, applicationId `com.samir.pdf_toolbox` |
| iOS | deployment target 15.0 |
| Disk | **several GB free.** The Rust target directories run ~1 GB *per platform*. Building on a nearly-full disk fails in confusing, non-obvious ways — see §12. |

---

## 3. First run

```bash
flutter pub get
flutter run
```

Checks:

```bash
flutter analyze        # must be clean; CI treats warnings as failures
flutter test           # 368 tests
```

The first `flutter test` after a clean checkout compiles the Rust engine for
the **host** machine (the integration tests exercise the real engine, not a
fake). That takes minutes once, then is cached.

Release build for a device:

```bash
flutter build apk --release --target-platform android-arm64
```

**Always verify the engine actually got bundled** — see §11, this has silently
failed before:

```bash
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep libpdf_oxide
```

---

## 4. Layout and the dependency rule

```
lib/
  main.dart            runApp only; no pre-runApp work, so the first frame is fast
  app/                 App widget, theme mode, launch-time maintenance
  core/                everything that is not a screen
    engine/            the PDF facade and its one real implementation
    files/             document store, import, export, print, save targets
    library/           the SQLite record of what the app produced
    entitlements/      the free tier and its master switch
    jobs/              progress, cancellation, error mapping
    pages/             page-edit session model, thumbnail cache
    images/            image normalisation, gallery saving, page layout
    catalog/ models/   the tool list and its types
    services/          AppServices: the object graph
    theme/ util/
  features/            one directory per screen or tool
```

**The rule:** `features/` imports `core/`. `core/` never imports `features/`.
Nothing imports `main.dart`. If you find yourself wanting `core` to reach into
a feature, the thing you want probably belongs in `core` already.

Within `features/`, a tool is conventionally two files:

- `x_page.dart` — the widget. Pumps state, shows progress, navigates.
- `x_operation.dart` — **plain Dart**, no widgets. Does the actual work.

That split is not stylistic. See rule R2 below.

---

## 5. Six rules that explain most of the code

If something in this codebase looks over-engineered, it is probably one of
these. Each was paid for.

### R1 — Exactly one file imports the PDF package

[`lib/core/engine/pdf_manipulator_engine.dart`](../lib/core/engine/pdf_manipulator_engine.dart)
is the only file in the project that may `import 'package:pdf_manipulator/...'`.
Everything else goes through the `PdfEngine` interface.

Why: the engine is a young dependency in a young ecosystem. Keeping one seam
means swapping it is a day, not a rewrite. It also makes every test able to run
without Rust.

**When adding engine capability:** add the method to the `PdfEngine` interface,
implement it in `PdfManipulatorEngine`, add it to the fakes in `test/fakes.dart`,
and add a case to `test/integration/real_engine_test.dart` proving the real
engine does what you think. Do not skip the last one — see §12.

### R2 — File I/O never happens inside a widget test's reach

`testWidgets` runs its body inside a **fake-async zone**. Real file I/O never
completes there. It does not fail — it *hangs*, which is far worse to debug.

So: anything that touches the filesystem lives in a plain Dart function
(`*_operation.dart`, `undo_replace.dart`, `save_to_device.dart`), tested with
plain `test()`. Widget tests use `MemoryFakeEngine`, which performs no I/O at
all.

Where a widget genuinely must trigger I/O, the action is injected so tests can
substitute it — see `ResultPage.undoAction`.

### R3 — temp → verify → move

Every write follows the same path, enforced by `DocumentStore`:

```
workspace (temp dir)  →  _verify()  →  atomic rename into place
                            │
                            └─ reopen the file, check the page count;
                               on failure delete it and throw
```

A result the engine cannot reopen never reaches the user's library. A failed or
cancelled operation leaves the original untouched and nothing half-written. See
requirements.md §5.2.

`replace()` extends this: it **copies** the previous bytes into `revisions/`
before the swap, so a replace is reversible and a crash mid-swap cannot leave a
library row pointing at nothing.

### R4 — Platform capability = interface + real + fake

Anything that touches the platform gets three pieces:

| Interface | Real | Fake |
|---|---|---|
| `PdfEngine` | `PdfManipulatorEngine` | `FakePdfEngine`, `MemoryFakeEngine` |
| `FileImporter` | `SystemFileImporter` | `FakeFileImporter` |
| `DeviceExporter` | `PlatformDeviceExporter` | `FakeDeviceExporter` |
| `DocumentPrinter` | `PlatformDocumentPrinter` | `FakeDocumentPrinter` |
| `DocumentScanner` | `PlatformDocumentScanner` | `FakeDocumentScanner` |
| `GallerySaver` | `PlatformGallerySaver` | `FakeGallerySaver` |
| `ImageNormalizer` | `PlatformImageNormalizer` | `FakeImageNormalizer` |
| `LibraryRepository` | `SqfliteLibraryRepository` | `FakeLibraryRepository` |
| `Entitlements` | `SqfliteEntitlements` | `FakeEntitlements` |

All are assembled in `AppServices` and handed down through
`AppServicesScope` (a plain `InheritedWidget`).

**A fake that diverges from its real counterpart is worse than no fake.** This
has bitten the project: `FakeLibraryRepository.rename` once skipped the `.pdf`
suffix and left `relativePath` stale, so tests asserted names the real app never
showed. If you change a real implementation's contract, change the fake in the
same commit.

### R5 — One source of truth for any number the UI states

If a card says "Up to 3 files", the enforcement reads the same constant. They
live together in [`ToolLimits`](../lib/core/entitlements/tool_limits.dart).

Why: they drifted once. The free tier was advertised on every card and enforced
nowhere — `consumesUse` had zero callers — and it shipped, because the test
asserted a hardcoded string that could not fail.

### R6 — Say nothing rather than claim something you cannot see

Recurring across the UI:

- Cancelling a picker shows **no message**. Backing out is a choice, not an event.
- Handing a document to the system print UI shows **no message**. That UI is
  still open; the user may yet print, save as PDF, or back out. "Sent to the
  printer" would assert something the app cannot observe.
- A partial save reads "Saved 2 of 3 files", never rounded up.
- A destination the platform will not name is omitted, not invented.

The wording logic is factored into pure functions (`describeDeviceSave`,
`describePrint`) precisely so it can be tested.

---

## 6. Core subsystems

### AppServices — the object graph

[`lib/core/services/app_services.dart`](../lib/core/services/app_services.dart)

A factory constructor resolves every dependency once, with test-injectable
parameters. Two details matter:

- The engine is built **once** and shared (`resolvedEngine`), because it owns
  native resources. An earlier version built it twice.
- The database is opened **lazily and memoised**:
  ```dart
  Future<Database>? database;
  Future<Database> sharedDatabase() => database ??= _openDatabase();
  ```
  A test that injects both `library` and `entitlements` must not touch the
  filesystem at all. Opening it eagerly caused `MissingPluginException` across
  the whole suite.

### PdfEngine — the facade

[`lib/core/engine/pdf_engine.dart`](../lib/core/engine/pdf_engine.dart)

```dart
Future<PdfDocumentInfo> inspect(File, {String? password});
Future<void>            merge({inputs, output, onStep, cancel, password});
Future<void>            extractPages({input, output, pageIndices, ...});
Future<Uint8List>       renderPage({input, pageIndex, maxSize, ...});
Future<void>            applyPageEdits({input, output, pages, ...});
Future<CompressionOutlook> inspectForCompression(File, {...});
Future<CompressionResult>  compress({input, output, level, ...});
Future<List<PageGeometry>> pageGeometry(File, {...});
Future<void>            imagesToPdf({images, output, ...});
Future<Uint8List>       renderPageAt({input, pageIndex, pixelWidth, pixelHeight, ...});
Future<List<TextHit>>   search({input, query, ...});
Future<void>            dispose();
```

`applyPageEdits` is the interesting one: it takes the whole edit session — any
mix of reorder, rotate, delete, duplicate — and saves once. Internally it is
one pass when there are no duplicated pages and two when there are, because the
underlying engine's `selectPages` rejects duplicate indices. That was
established by probing the engine, not by reading its docs.

### PdfFailure — the error taxonomy

[`lib/core/engine/pdf_failure.dart`](../lib/core/engine/pdf_failure.dart)

```dart
enum FailureKind {
  corruptFile, passwordRequired, wrongPassword, permissionDenied,
  outOfStorage, tooLarge, pageOutOfRange, unsupported,
  cancelled, noResult, io, unknown,
}
```

Every kind carries a user-facing message. Two properties matter:

- `consumesUse` — **false for every kind.** A failure never costs a free run.
- `isLoggable` — false for anything password-related, so a password can never
  reach a log or a crash report.

### DocumentStore — where files live

[`lib/core/files/document_store.dart`](../lib/core/files/document_store.dart)

Directories under the app's documents root:

| | |
|---|---|
| `documents/` | the library. What the app produced. |
| `imports/` | sandbox copies of files the user picked. |
| `exports/` | rendered images (not PDFs, so not the library). |
| `revisions/` | previous versions of replaced documents. Bounded: 7 days, 20 entries. |
| *(temp)* `workspaces/` | one scratch dir per operation, swept at launch. |

Key methods:

- `openWorkspace()` → a scratch directory; `dispose()` it in a `finally`.
- `commit(temp, desiredName:, expectedPages:)` → verify, then move into
  `documents/` with a unique name.
- `replace(temp, target:, expectedPages:)` → verify, copy the old bytes to
  `revisions/`, then swap. Returns a `Replacement` carrying both paths.
- `restore(replacement)` → undo. **Deliberately not verified**: `_verify` guards
  *our output*; a revision is content that was already in the library, and
  refusing to restore it would strand the user.
- `sweepWorkspaces()`, `pruneRevisions()` → launch-time maintenance, called from
  `app.dart` in a post-frame callback so they never delay the first frame.
- `sanitizeFileName()` → strips separators and control characters, keeps the
  result inside the 255-byte filesystem limit.

### Library — the SQLite record

[`lib/core/library/`](../lib/core/library/)

`LibraryDocument` stores a **relative** path, never absolute: iOS gives the app
container a new UUID on reinstall, so an absolute path stored today can be dead
tomorrow.

Schema is at **version 3**, migrated one step at a time:

```
1  documents
2  + folders, documents.folder_id
3  + tool_usage (free-tier counts)
```

Folders are logical — `folder_id` on a row. Files do not move on disk when you
move a document into a folder. Deleting a folder does **not** delete its
documents (requirements.md §5.2: the app never deletes a user's file as a side
effect of something else).

Tests swap sqflite's global `databaseFactory` for the FFI one, so the same
`open()` call works on a device and in a plain Dart test.

### Entitlements — the free tier, currently off

[`lib/core/entitlements/`](../lib/core/entitlements/)

```dart
// tool_limits.dart
static bool enforced = false;   // ← the master switch
```

With it off: every tool is unlimited, no card advertises a cap, and
`recordUse`/`refundUse` are no-ops — so turning it back on starts every counter
from zero rather than charging for testing.

One predicate gates everything:

```dart
extension EntitlementGate on Entitlements {
  bool get isUnrestricted => !ToolLimits.enforced || isPremium;
}
```

The flag is **not `const`** on purpose: a const would make the enforced branches
unreachable from tests. `enforceFreeTier()` in `test/fakes.dart` flips it for
the tests that cover the wall, so both states run on every suite.

To re-enable the tier: set `enforced = true`. Nothing else.

### Jobs — progress, cancellation, error mapping

[`lib/core/jobs/`](../lib/core/jobs/)

```dart
final job = JobController<SaveOutcome>();
job.run((handle) => savePageEdits(services: ..., handle: handle, ...));
```

`JobStatus` is `idle | running | success | failure | cancelled`. The controller
maps thrown errors into `PdfFailure`, so a screen never has to catch raw
exceptions. `JobHandle` gives the operation `cancel` (a `CancelToken`) and
`report(completed:, total:, label:)`.

Operations call `handle.cancel.throwIfCancelled()` at checkpoints. Cancellation
is reported as `cancelled`, not `failure` — it is not an error and costs nothing.

### Document scanner

[`lib/core/scan/document_scanner.dart`](../lib/core/scan/document_scanner.dart),
[`lib/features/scan/scan_flow.dart`](../lib/features/scan/scan_flow.dart)

The only tool whose **existence** is a runtime question. `isAvailable()` is
asked as the home screen loads; the card starts hidden and appears, never the
reverse, because on Android the scanner ships with Google Play services and is
genuinely absent without them (requirements.md §3.10).

Captured pages become `PickedImage`s and flow into the Images → PDF screen, so
there is one review-and-save pipeline rather than two. `ImageSource` carries
the differences: title, wording, and how the library records the result.

`scan()` takes **no output directory** on purpose. The platform writes into its
own cache (wiped at the start of every capture) and returns paths plus byte
sizes. Choosing a directory in Dart means file I/O between the tap and the
camera, which never completes in a widget test's fake-async zone — that was
built the wrong way round first and a widget test caught it.

### Native channels

Three MethodChannels, all taking or returning **paths**, never bytes:

| Channel | Android | iOS |
|---|---|---|
| `com.samir.pdf_toolbox/device_export` | `ACTION_CREATE_DOCUMENT` (one file) / `ACTION_OPEN_DOCUMENT_TREE` (several) + `ContentResolver` streams | `UIDocumentPickerViewController(forExporting:asCopy:)` |
| `com.samir.pdf_toolbox/print` | `PrintManager` + a `PrintDocumentAdapter` writing into the framework's `ParcelFileDescriptor` | `UIPrintInteractionController` with `printingItem` = file URL |
| `com.samir.pdf_toolbox/scan` | ML Kit `GmsDocumentScanning` via Play services | VisionKit `VNDocumentCameraViewController` |

Android: [`MainActivity.kt`](../android/app/src/main/kotlin/com/samir/pdf_toolbox/MainActivity.kt).
iOS: [`DeviceExportHandler.swift`](../ios/Runner/DeviceExportHandler.swift) (holds
both handlers), registered in [`AppDelegate.swift`](../ios/Runner/AppDelegate.swift).

**Why not packages.** `file_picker`'s `saveFile()` and the `printing` package
both require the whole document as `Uint8List`. Requirements §13 caps input at
200 MB and peak RSS at 400 MB and states that large documents are streamed — a
200 MB list plus the copy a platform channel makes crossing into Kotlin/Swift
breaches that on exactly the documents most worth exporting.

**Adding a Swift file** needs four `project.pbxproj` entries (build file, file
reference, group child, sources phase); this project has no synchronized
groups. Validate with `plutil -lint ios/Runner.xcodeproj/project.pbxproj`.

---

## 7. Anatomy of a feature — Compress end to end

1. **`compress_page.dart`** picks a file via `services.importer`, which copies it
   into `imports/` and hands back an `ImportedDocument`. The page wraps it in an
   `EditableSource`.
2. It calls `engine.inspectForCompression` for the pre-flight and shows an
   honest outlook. **It never promises a percentage** — benchmarking showed a
   mixed document saved 76.1% where the model predicted ~38%, so the model was
   removed rather than shipped wrong.
3. **`compress_operation.dart`** (`compressDocument`) runs the engine into a
   workspace and returns a `CompressionOutcome` that is *not yet committed* —
   requirements §3.7 requires showing the real before/after first.
4. The user keeps or discards. `outcome.keep(services, target:)`:
   - target comes from `defaultTargetFor(source)` — replace if the app owns the
     document, new file otherwise.
   - replace → `store.replace()`, `library.refreshAfterReplace()`, and build a
     `ReplacedVersion` undo token.
   - new file → `store.commit()`, `library.record()`.
   - spend a free run **only if the result actually shrank** (`!result.isNoOp`).
5. `ResultPage` shows the outcome and, when something was replaced, an **Undo**
   card that restores bytes, library description, page count and any spent run.

The same shape applies to every tool: page = state and navigation, operation =
plain Dart doing the work and returning a value the page can render.

---

## 8. Adding a new tool

1. **Catalog** — add a `PdfTool` to [`tool_catalog.dart`](../lib/core/catalog/tool_catalog.dart)
   with `id`, `group`, `release`, `tier`, aliases (search matches verbs people
   type: "shrink" finds Compress). Set `release` to a version at or before
   `kShippedThrough` or it will not appear.
2. **Engine** — if it needs new capability, extend `PdfEngine` (R1), implement,
   fake, and add a real-engine integration test.
3. **Operation** — `lib/features/<tool>/<tool>_operation.dart`, plain Dart,
   taking `AppServices` and a `JobHandle`, using a workspace and `commit`/`replace`.
4. **Page** — `lib/features/<tool>/<tool>_page.dart`, driving a `JobController`.
5. **Route** — wire it in `home_page.dart`'s tool tap handler.
6. **Tests** — operation tests with real temp files; widget tests with
   `MemoryFakeEngine`.
7. **Does it derive or edit?** If it produces a *new* document from an existing
   one (like Extract), add its id to `PdfTool.derivesNewDocument` so it never
   replaces its source.

---

## 9. Testing

```bash
flutter test                                   # everything
flutter test test/features/compress_test.dart  # one file
flutter test --tags integration                # real Rust engine only
```

**Three tiers:**

- `test/core/` — pure logic. Page-range parsing, the edit session model, the
  thumbnail cache's LRU, the document store's invariants.
- `test/features/` — operations (real temp files, plain `test()`) and widgets
  (`MemoryFakeEngine`, no I/O).
- `test/integration/real_engine_test.dart` — the real Rust engine. Tagged
  `integration`. Without it nothing proves the facade speaks the engine's
  actual language, which has been wrong three times.

**Writing a widget test that involves the tool grid:** slivers do not build
off-screen children, so finders miss lower groups at the default 800×600
viewport. Enlarge it:

```dart
tester.view.physicalSize = const Size(1200, 3000);
tester.view.devicePixelRatio = 2;
addTearDown(tester.view.resetPhysicalSize);
```

**Make sure your test can fail.** Before trusting a regression test, break the
code and watch it go red. Two defects in this project's history came from
assertions that were true either way — a hardcoded `'3 free uses'` string, and a
fake that could not diverge from what was asserted. If a test passes before and
after your fix, it is not testing your fix.

---

## 10. UI conventions

- `ResultPage` is the shared terminal screen for every tool: summary, file
  tiles, optional undo card, Save to device / Done / Share.
- `JobProgressView` shows determinate progress where the engine reports it and
  indeterminate only where it genuinely cannot.
- Errors render from `PdfFailure.message`; screens do not write their own copy
  for engine failures.
- Theme lives in `core/theme/`; use `Insets`, `Corners` and `AppColors.accentFor`
  rather than raw numbers.
- **The repo is not `dart format`-clean** (62 of 83 files would change). Do not
  run it across the project — it will bury your diff. Match surrounding style.

---

## 11. Build and release

```bash
flutter build apk --release --target-platform android-arm64
```

**Verify the engine is in the APK. Every time.**

```bash
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep libpdf_oxide
```

A correct arm64 release APK is **~32.8 MB** and contains
`lib/arm64-v8a/libpdf_oxide.so` at ~14.6 MB. An **18.1 MB** APK is the engine
missing: the app installs, launches, and fails on every PDF operation. Exit
code 0 and "✓ Built" do not tell you this. Budget is ≤35 MB per ABI (§13).

App size is kept down by `keep: auto` in `pubspec.yaml`, which scans the source
for the engine capabilities actually called and trims the rest (22 MB → 13 MB
host engine). Guessing wrong is loud: the engine raises a typed error naming
the missing capability.

**iOS has not been built since the native channels were added.** Save-to-device,
print and the `AppDelegate` wiring are all unverified there.

---

## 12. Traps

Things that have cost real time here.

**Deleting `build/` on a tight disk poisons the native-assets cache.**
`build/native_assets/` disappears, but `.dart_tool/` still reports everything
up to date, so the link step trims the engine to nothing
(`"assets_from_linking": []`), `install_code_assets` stages zero files, and both
cache themselves as done. Every later build then skips straight past and
produces a byte-identical engine-less APK. **Fix:** clear all three layers
*before one build* — `rm -rf build .dart_tool/flutter_build .dart_tool/hooks_runner/<pkg>`
— keeping `.dart_tool/hooks_runner/shared/` so the Rust does not recompile.
Invalidating them one at a time just moves the stale layer down.

**Diagnose the hook by reading its own output**, not by guessing:
`.dart_tool/hooks_runner/<pkg>/<hash>/{stdout.txt,output.json}` states exactly
what the build and link steps decided.

**`timeout` does not exist on macOS.** A command wrapped in it exits 127 and
produces no output, which reads as "no matches" and invites a wrong conclusion.

**Exit codes lie in pipelines.** `adb install ... | tail -2` reports `tail`'s
status, so a failed install looks like success. Check the output text.

**Gradle caches are large and version-specific.** `~/.gradle/caches/<version>/`
for versions this project does not use (it pins 8.14) can be several GB and are
regenerable.

**`setState(() => _x = _load())`** returns a Future and assigns it — use a block
body. This has appeared twice.

**A `TextEditingController` created by the caller of a dialog** gets disposed
during teardown while the dialog is still animating out. Dialogs own their
controllers here (`_RenameDialog`, `_NameDialog`).

**A `try`/`finally` around a workspace must `await` what it returns.**
`return store.replace(...)` inside a `try` lets the `finally` dispose the
workspace while the operation is still reading it. It fails roughly one run in
four, which reads as a flaky suite rather than a bug.

**Android's `ACTION_OPEN_DOCUMENT_TREE`** cannot grant the Download folder, the
internal-storage root, or `Android/data` (Android 11+). The picker resumes where
it was last used, so without `EXTRA_INITIAL_URI` it routinely opens on a folder
whose confirm button is greyed out.

---

## 13. File map

| Path | What it is |
|---|---|
| `lib/core/services/app_services.dart` | the object graph; start here |
| `lib/core/engine/pdf_engine.dart` | the facade every feature uses |
| `lib/core/engine/pdf_manipulator_engine.dart` | the only PDF-package importer |
| `lib/core/files/document_store.dart` | workspaces, commit, replace, revisions |
| `lib/core/library/sqflite_library_repository.dart` | schema, migrations, queries |
| `lib/core/entitlements/tool_limits.dart` | the free-tier switch and its numbers |
| `lib/core/jobs/job_controller.dart` | progress, cancellation, error mapping |
| `lib/core/catalog/tool_catalog.dart` | the tool list and search aliases |
| `lib/features/shared/result_page.dart` | the terminal screen for every tool |
| `lib/features/scan/scan_flow.dart` | scanner capture, page cap, wording |
| `test/fakes.dart` | every fake, plus `enforceFreeTier()` |
| `test/integration/real_engine_test.dart` | the only tests using real Rust |
| `android/app/src/main/kotlin/.../MainActivity.kt` | export + print channels |
| `ios/Runner/DeviceExportHandler.swift` | export + print handlers |

---

## 14. Known gaps

- **iOS is uncompiled** since the native channels landed — save-to-device, print and now the scanner. Biggest untested surface.
- **The scanner has not run on a device.** ML Kit's module download on first use, and the capture itself, are unverified.
- **App size is at 33.5 MB** against a 35 MB budget per ABI (§13). ML Kit added ~0.7 MB; headroom is now thin.
- **Per-image crop** (§3.8) deferred; rotation is built.
- **"Open in another app"** and share-target / "Open with" registration (§6) unbuilt.
- **Phase 4 onward** — IAP and paywall, ads and consent, analytics, crash
  reporting — not started. The entitlements seam is where purchasing plugs in.
- **No localization, no accessibility audit** yet (Phase 5).
- **iOS release size** never measured against the 70 MB budget.
