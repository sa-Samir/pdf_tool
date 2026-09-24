# PDF Toolbox — Product Requirements (v2)

Status: draft for approval · Revision v2.1 · Last updated 2026-09-18

---

## 0. Changes from v1 (review summary)

| # | Change | Why |
|---|---|---|
| 1 | **Added a PDF viewer** as a first-class surface (§3.2) | v1 had 15 tools and no way to look at a document. Every tool needs page preview; the viewer is the most-used screen in this category. |
| 2 | **MVP re-cut**: scanner, annotations and signature moved out of v1.0 into v1.1/v1.2 (§16) | v1's MVP is a ~170 dev-day build. The re-cut v1.0 is ~125 days and ships a coherent product. Scanner and the annotation canvas share almost no code with the rest. |
| 3 | **Tools grouped into 5 categories** instead of 15 flat cards (§3.1) | 15 undifferentiated cards is past the limit of scannability, and groups make the paywall legible. |
| 4 | **Every requirement given numeric acceptance criteria** (§13, per-feature) | v1 said "fast" and "handle large documents gracefully". Those cannot be tested or accepted. |
| 5 | **Compression claims made honest** (§3.7) | v1 implied a fixed ~66% saving. Real savings range 0–90% depending on content. Text-only PDFs barely shrink. Requirement now covers the no-op case and forbids silent quality destruction. |
| 6 | **Free tier redesigned**: no daily counters, no watermark on user output (§9) | Local daily counters reset on reinstall and wall the user at the worst moment. Branding the user's own output is the most-complained-about pattern in this category and contradicts our positioning. |
| 7 | **Privacy claim scoped to document content, with the supporting compliance work listed** (§8) | "Privacy-focused" + ad SDK + analytics is defensible only if the claim is about document bytes. Added ATT, UMP consent, Apple privacy manifest, Play Data Safety. |
| 8 | **Offline claim: one documented exception** (§7) | Android's ML Kit document scanner downloads its module on first use. v1 promised all core features work offline; that promise cannot include the scanner on Android as specified. |
| 9 | **Added non-functional requirements**: localization, accessibility, crash reporting, remote kill-switch, app-size budget, tablet layout, data-integrity invariants, background-suspension behaviour (§13, §17, §18) | Absent from v1 and expensive to retrofit. |
| 10 | **Error handling turned into a taxonomy with recovery actions** (§12) | v1 gave two sample strings. Needed: a closed list of failure classes, each with message, recovery, logging and quota behaviour. |
| 11 | **"Never overwrite the original" elevated to a system invariant** (§5.2) | Stated once in passing in v1. It is the single most damaging class of bug in a file utility. |
| 12 | **Engine access via an internal facade, one keystone dependency** (§17) | All PDF work will sit behind our own interface so the underlying library can be swapped. See the feasibility report for the dependency risk this mitigates. |
| 13 | **Analytics extended to the conversion funnel** (§14) | v1 tracked operations but not paywall views, trigger tool, trial starts or abandonment — i.e. not the things that decide whether this business works. |
| 14 | **Success criteria given target numbers** (§19) | "Retention" is not a metric without a threshold. |
| 15 | **Added explicit differentiation requirements** (§1.2) | The wedge (fully local, no account, never watermarked) has to be a build requirement and a store-listing requirement, not an aspiration. |
| 16 | Removed duplication between the tool list and §3.10/§3.11 (Add Text, Add Signature) | "Add Text" appeared both as a tool and as an annotation type. |

### 0.1 Changes in this revision (v2.1)

Gaps found when auditing v2 against its own change log, plus the items the review flagged but did not specify.

| # | Change | Why |
|---|---|---|
| 17 | **Scan and OCR added to the tool list; list rebuilt as a table with group, phase and tier** (§3.1) | The home screen omitted the scanner entirely while §3.10 specified it. The list is now a build checklist: every tool states when it ships and whether it is free. |
| 18 | **Acceptance criteria added to the nine features that lacked them** (§3.5, §3.8–§3.15) | v2's change log claimed every requirement was testable. Four had criteria; eleven did not. Now all do. |
| 19 | **First-run and empty states specified** (§3.0) | §19 targets a median time-to-first-operation under 60s, with nothing in the spec making that happen. Permissions, consent and the paywall are now explicitly ordered *after* the first success. |
| 20 | **Notifications defined, not just "notification settings"** (§11) | v2 listed a settings toggle for an unspecified feature. Scope is now: completion notices and subscription lifecycle only — no engagement pushes. |
| 21 | **Optional biometric app lock** (§8.2, §11) | A privacy-positioned document app that cannot lock its own library is leaving the claim half-built; also covers the app-switcher snapshot. |
| 22 | **Assumptions, open questions and explicit non-goals** (§20) | Six decisions are currently unmade, one of which (is there a UA budget?) should gate the build itself. Non-goals are written down so they are not re-litigated mid-build. |
| 23 | **Replacing a document made reversible instead of confirmed** (§5.2.1b–1c) | The first cut asked "new file or replace?" on every save. That taxes the most deliberate user — someone who opened their own document on purpose — every single time, and the prompt had to warn that the old version was "gone for good", which was only true because nothing kept it. Keeping the previous version removes both problems: the common case loses a step, and the destructive case stops being destructive. |
| 24 | **Save to device built, and the reason for it written down** (§6.1) | §6 always listed "a user-chosen location via the system picker" and it was never built, leaving the share sheet as the only way out of the sandbox. That matters more than a missing menu item: app-private storage is deleted on uninstall, so the library silently doubled as a place to lose work. |
| 25 | **Print built on the platform print systems, not a package** (§6.2) | The last of §6's actions. `printing` would have added a dependency whose layout callback takes the whole document as bytes — the same §13 breach as `file_picker.saveFile()`. Android's PrintDocumentAdapter and iOS's UIPrintInteractionController both take a descriptor or a URL, so neither needs the bytes. |

---

## 1. Overview

### 1.1 Product

PDF Toolbox is a mobile utility that performs everyday PDF and document tasks entirely on the user's device. No account, no upload, no watermark on the user's output.

Principles, in priority order when they conflict:

1. **The user's file is never damaged.** Originals are never modified in place; a failed operation leaves nothing behind.
2. **Documents never leave the device.** No network transfer of document bytes, ever, for any v1 feature.
3. **No account required** for anything except restoring a purchase.
4. **Fast.** Cold start to a usable home screen under 2s on a mid-tier device.
5. **Simple.** A task is reachable in at most three taps from launch.

### 1.2 Differentiation (build + listing requirement)

The competitors in this category (iLovePDF, Smallpdf, and most "PDF tools" apps) upload documents to a server to process them. Our four claims must be literally true and must appear in the App Store / Play subtitle, the first screenshot, and the paywall:

- Processes on your device — nothing is uploaded.
- No sign-up.
- No watermark on your files.
- Works in airplane mode.

Any future feature that breaks one of these claims requires an explicit per-operation opt-in and a decision to revise this section.

## 2. Platforms

- iOS 15+ (iOS 13 is the floor for VisionKit scanning; 15 is the floor for our UI and StoreKit 2)
- Android 8.0 / API 26+ (API 21 is the library floor; 26 avoids a long tail of storage and camera bugs)
- Flutter, single codebase. Phone-first, but layouts must be responsive from the first commit (§18.4).

## 3. Features

### 3.0 First run and empty states

§19 targets a median time-to-first-successful-operation under 60 seconds from install. That is a design requirement here, not an outcome to hope for.

- **Nothing stands between launch and the first successful operation**: no sign-up, no onboarding gate, no permission prompt, no paywall. Camera and photo permissions are requested at the moment of use. ATT and ads consent (§8.2) are requested *after* the first operation completes, never at launch.
- Onboarding is at most 3 screens, skippable from the first, and says the four things in §1.2. Shown once; the flag survives app update.
- The home screen is interactive immediately — no blocking splash beyond the platform launch screen.
- Empty states are specified for Recents, Favorites, folders, tool search and file search. Each names the action that fills it and offers that action as a button; none is a bare empty list.
- At most one first-run tooltip, on one element. No coach-mark tours.

Acceptance: from a cold install a user can complete a merge without meeting a sign-up, a permission dialog or a paywall; median time-to-first-successful-operation measured under 60s in beta.

### 3.1 Home screen

Tools are grouped. Grouping is also how the paywall is explained. This table is the build checklist — every tool states its group, its release and its tier.

| Tool | Group | Ships | Tier |
|---|---|---|---|
| View & read | shared surface (§3.2) | v1.0 | Free |
| Merge | Organize | v1.0 | Free up to 3 files · Premium unlimited |
| Split | Organize | v1.0 | Free |
| Extract pages | Organize | v1.0 | Free |
| Delete pages | Organize | v1.0 | Free |
| Rotate pages | Organize | v1.0 | Free |
| Reorder pages | Organize | v1.0 | Free |
| Duplicate pages | Organize | v1.0 | Free |
| Images → PDF | Convert | v1.0 | Free up to 10 images · Premium unlimited |
| PDF → Images | Convert | v1.0 | Free to 150 DPI / JPG · Premium 300 DPI / PNG |
| Compress | Optimize | v1.0 | Premium · 3 free uses |
| Scan document | Capture | v1.1 | Free up to 3 pages · Premium unlimited |
| Signature | Edit & Sign | v1.1 | Premium · 3 free uses |
| Annotate | Edit & Sign | v1.2 | Premium · 3 free uses |
| Add text | Edit & Sign | v1.2 | Premium · 3 free uses |
| Watermark | Edit & Sign | v1.2 | Premium · 3 free uses |
| Protect | Secure | v1.3 | Premium · 3 free uses |
| Unlock | Secure | v1.3 | Premium · 3 free uses |
| OCR → searchable PDF | Convert | v1.3 | Premium · 3 free uses |

Notes:

- **Add text** is a home-screen card that opens the annotation tool with the text tool already selected. It is one of the highest-volume search intents in this category and deserves its own entry point; it is not a separate implementation (§3.11).
- **Unshipped tools are not displayed.** No "coming soon" cards, no disabled tiles, no upgrade teasers for things that do not exist yet.
- Free tools must never be presented in a way that implies they are premium; the tier is shown on the card only where a limit applies.

Plus: a search field over tools (users arrive knowing the verb, not the category), Recent files, Favorites, Settings.

The home screen must render and be interactive before any file-system or database work completes. Recents load in asynchronously.

Acceptance: home screen is interactive within the §13 cold-start target while recents are still loading; tool search matches the verbs users actually type ("combine", "join", "shrink", "convert", "sign", "password"), not only each tool's own name.

### 3.2 PDF viewer (NEW)

The shared surface behind every tool.

- Continuous scroll, pinch zoom, double-tap zoom
- Page indicator and jump-to-page
- Thumbnail strip / page grid
- Text search with hit highlighting and next/previous
- Open in landscape and after rotation without losing position
- Password prompt for encrypted documents, with a clear "wrong password" state

Acceptance: a 50-page, 5 MB text PDF opens to first rendered page in under 1.5s on the reference mid-tier device; scrolling holds 60 fps at 1× zoom; a 500-page document opens without loading all pages.

### 3.3 File import

Sources: device storage, the system document picker (Files app on iOS / SAF on Android, which covers iCloud Drive, Google Drive, Dropbox and any document provider the user has installed), the system photo picker, and share-sheet / "Open with" intents from other apps.

Formats in: PDF, JPG/JPEG, PNG, HEIC/HEIF, WebP.

Requirements:

- **No broad storage permission.** The app must never request `MANAGE_EXTERNAL_STORAGE` or broad media permissions; the document picker and photo picker require no runtime permission and are the only import paths. Camera permission is requested only when the scanner is first used.
- **Imported files are copied into the app sandbox** before any work begins, and the copy is what we operate on. On iOS, picked URLs are temporary and cannot be relied on later; on Android, content URIs need persisted permission we will not request. This copy is also what makes §4 Recents work.
- **Cloud placeholders**: a file selected from iCloud Drive or Drive may not be downloaded locally yet. The app must show a download state and a clear message if the file is unavailable offline.
- **HEIC** must be transcoded to JPEG via platform decoders on import (Dart cannot decode HEIC).
- Reject with a clear message: files over the size cap (§13), non-PDF content with a `.pdf` extension, and PDFs we cannot parse.

Acceptance: a 100 MB PDF copies into the sandbox in under 5s; an undownloaded iCloud Drive file shows a download state rather than an error; a HEIC photo imports and transcodes with no user action; a mislabelled `.pdf` is rejected with the §12 message rather than crashing.

### 3.4 Merge

Multi-select, preview each file, reorder by drag, remove, merge, save, share.

- Must preserve bookmarks and page dimensions of the inputs; pages are not re-scaled to a common size.
- Handles mixed page sizes and orientations.
- Encrypted inputs prompt for a password per file.

Acceptance: 10 files / 200 pages total merged in under 8s; output opens in Preview, Adobe Acrobat and Chrome.

### 3.5 Split

Modes: every page (N single-page files) · one range · multiple ranges · every N pages · split at size.

- Range input accepts `1-5, 8, 11-13` and validates against the page count with inline errors.
- Output naming: `{original}_1-5.pdf`, collision-safe.
- Preview of what will be produced (count and names) before committing.

Acceptance: a 300-page PDF splits into 300 single-page files in under 20s; the range parser rejects `0`, `5-2`, out-of-bounds and overlapping ranges with an inline message naming the specific problem; every output opens with exactly the expected page count.

### 3.6 Page management

One shared page-grid component serving reorder, rotate, delete, duplicate and extract, with multi-select and a single undo stack. The user performs several edits and saves once — not one tool invocation per edit.

- Drag to reorder, with auto-scroll at the edges
- Select all / range select
- Rotate selection 90° CW/CCW, 180°
- Delete selection (blocked when it would empty the document)
- Duplicate selection, inserted after the source page
- Extract selection to a new document
- Undo/redo, and a discard-changes confirmation on back-out

Acceptance: grid scrolls smoothly over 500 pages with thumbnails rendered lazily and a bounded thumbnail cache.

### 3.7 Compress

Presets: **Light** (high quality) · **Balanced** · **Strong** (smallest).

What compression does: downsample and re-encode embedded raster images (roughly 150 ppi balanced, 72 ppi strong), recompress content streams, drop unused objects and duplicate resources. Text and vector content stay text and vector.

Honesty requirements — these are the ones that protect the store rating:

- **Report a range, never a promise, before the user starts.** The estimate is derived from actual content inspection (how much of the file is raster images), not a fixed ratio.
- **The no-op case must be handled.** A text- or vector-heavy PDF may shrink by 0–5%, or not at all. If the result is not at least 5% smaller, show *"Already optimized — we couldn't make this meaningfully smaller"*, offer to discard the result, and **do not consume a free-tier use or a credit.**
- **Never silently rasterize.** A mode that converts pages to images destroys text selection, search and accessibility. If offered at all, it must be a separate, explicitly labelled option with a warning, never inside a preset.
- Result screen shows before/after with the real numbers and a side-by-side page preview at 100% zoom so the user can judge the quality loss:

```text
Original    18.4 MB
Compressed   6.2 MB
Saved          66%          [Preview]  [Discard]  [Save]
```

Acceptance: a 20 MB, 30-page scanned PDF compresses in under 30s and achieves ≥50% reduction at Balanced. A 2 MB text-only PDF reports the no-op case rather than a misleading 1% saving.

### 3.8 Images → PDF

Multi-select, reorder, per-image crop and rotate, page size (A4, A5, Letter, Legal, original image size), orientation (portrait / landscape / auto per image), margin, fit mode (fit / fill), quality.

- 50 images must not load 50 full-resolution bitmaps into memory at once.
- EXIF orientation must be honoured.

Acceptance: 50 × 12 MP JPEGs convert in under 45s with peak RSS under 400 MB; output page count equals input image count; EXIF-rotated inputs appear upright.

### 3.9 PDF → Images

All pages or a selection · JPG or PNG · resolution by DPI (72 / 150 / 300 / custom) with the resulting pixel dimensions and estimated total size shown before export · export to photo library or as a ZIP / multiple files.

- Warn before exporting more than 100 images.
- Cancellable mid-export, with partial results either kept deliberately or cleaned up — chosen explicitly, not by accident.

Acceptance: 50 pages export at 150 DPI in under 30s; the size estimate shown before export is within ±25% of the actual total; cancelling at any point leaves no orphaned files.

### 3.10 Document scanner (v1.1)

Automatic edge detection, perspective correction, manual crop handles, enhancement (Original / Color / Grayscale / Black & white), multi-page capture, reorder and retake before export, PDF or image output.

Implementation note and constraint: this uses the platform scanners — VisionKit on iOS, ML Kit Document Scanner on Android. The Android component **requires Google Play services and downloads its module on first use**, so the first scan on a fresh Android install needs a network connection, and the feature is unavailable on non-GMS devices. Required behaviour: detect availability up front, hide or disable the tool with an explanation rather than failing at capture time, and state the exception in §7 and in the store listing if scanning is promoted as offline.

Acceptance: edge detection locks onto an A4 sheet on a contrasting surface within 2s in normal indoor light; a 10-page scan exports to PDF in under 10s; the availability check completes within 300ms of home-screen load so the tool never appears and then disappears.

### 3.11 Annotation (v1.2)

Freehand draw (pressure-insensitive, stroke width and colour), highlight, underline, strikethrough, text box, shapes (rect / ellipse / line / arrow), checkmark and cross stamps, eraser, undo/redo, per-object select-move-resize-delete.

- Annotations are written as real PDF annotation objects where possible, so other readers can see and edit them; a "flatten on export" option is offered for compatibility.
- Editing state survives app backgrounding.

Acceptance: freehand strokes track the finger with no perceptible lag at 1× and 3× zoom; 200 annotation objects on one page render without dropped frames; annotations survive save → close → reopen and are visible in Apple Preview and Adobe Acrobat; undo restores the exact prior state for every operation type.

### 3.12 Signature (v1.1)

Draw (smoothed stroke), clear and redraw, transparent-background capture, save multiple named signatures locally, place / move / resize / rotate on any page, apply to multiple pages.

- Stored signatures live in the app sandbox, excluded from OS backups by default, with an option to require biometric unlock before use.
- Signature is a stamp, not a cryptographic signature. The UI must not imply legal e-signature certification. Certificate-based signing is out of scope.

Acceptance: a saved signature applies to a 50-page document in under 5s; placed position and scale on export match the on-screen preview within 1pt; stored signatures survive an app update.

### 3.13 Watermark (v1.2)

Text or image watermark · position (9-point grid + tiled) · size · opacity · rotation · font · colour · behind or in front of content · all pages or a page range · live preview.

Acceptance: a watermark applies to 200 pages in under 15s; the live preview matches the export within 1pt; text watermarks render correctly in CJK and Arabic.

### 3.14 Protect (v1.3)

Set a user (open) password and optionally an owner password with permission flags: print, copy content, modify, annotate. AES-256.

- Password strength indicator and mandatory confirm field.
- An unmissable warning that a lost password cannot be recovered by us or anyone else, with an explicit acknowledgement before saving.
- Passwords are never persisted, never logged, never sent to analytics or crash reports, and are held in memory only for the duration of the operation.

Acceptance: the protected output refuses to open without the password in Apple Preview, Adobe Acrobat and Chrome; permission flags are honoured by Acrobat; the irreversibility warning requires an explicit acknowledgement and cannot be dismissed by tapping through.

### 3.15 Unlock (v1.3)

Remove protection from a document **when the user supplies the correct password.** No password is guessed, brute-forced, bypassed or recovered. Wrong-password attempts are rate-limited only by the user's patience; we do not store attempts. This limitation is stated in the tool's own UI so the intent is unambiguous to users and to store reviewers.

Acceptance: a correct password unlocks RC4-40, RC4-128, AES-128 and AES-256 documents from the §15 corpus; a wrong password returns the §12 message in under 1s with no partial output written.

## 4. Recent files

A local history of processed documents: name, type, size, page count, timestamp, last operation, source tool. Open, rename, share, favorite, delete, "redo this operation on a new file".

- Backed by the sandbox copies from §3.3. Entries whose file no longer exists are shown as unavailable and pruned on next launch.
- Configurable retention (default: keep last 50 / 30 days), and a one-tap "clear history" in Settings that also deletes the underlying copies.
- History is local only and is not backed up to iCloud/Drive unless the user enables it.

## 5. File management

### 5.1 Folders

Create, rename, move, delete, favorite, share. Sort by name / date / size. Search by name.

### 5.2 Data integrity invariants (non-negotiable)

1. Output is written to a temp path, verified as a parseable PDF with the expected page count, then atomically moved into place. **A file outside the app is never written to at all**: picked files are copied into the sandbox (§3.3) and the copy is what tools operate on.
1b. A document the app owns is **replaced in place, without being asked**, when a tool changes that same document: the page editor and Compress, on a document opened from the library. Editing your own document is what the screen already said it would do, so there is nothing to confirm. Two conditions gate it, both necessary:
    - the app must own the document — never an imported copy, where a write would overwrite our copy and leave the user's own file untouched;
    - the tool must be changing that document rather than deriving a new one. Extract, Split, Merge and the converters always save alongside: writing the result over the original would destroy exactly what the user asked to pull out of it.
1c. **A replace is always reversible.** Before the swap, the previous version is copied into a revisions directory; the result screen then offers to put it back, restoring four things — the content, the library entry's description, its page count, and any free run the operation spent. Copied rather than moved: a move would leave the document absent from its own path for the duration of the swap, and a crash inside that window would leave a library entry pointing at nothing. Revisions are bounded (7 days, 20 most recent) and swept at launch, never during an operation. An undo is one-shot: it consumes the revision.
2. A failed or cancelled operation leaves no partial output and no orphaned temp files.
3. Before starting, check free space for at least 2.5× the input size and fail fast with a clear message if unavailable.
4. Temp files are cleaned on operation completion, on app launch (sweeping anything left by a crash), and on a size ceiling.
5. Saving never silently overwrites: name collisions auto-suffix. The in-place replace of §5.2.1b is not an exception — it is announced on the result screen and reversible per §5.2.1c.
6. The app never deletes a user's original file. Deletion is always an explicit user action on a file the app owns. Exporting is never such an action: saving to the device copies out and leaves the library untouched (§6.1).

## 6. Sharing and export

Save (to app folder or a user-chosen location via the system picker) · native share sheet · open in another app · rename · move · print. Registered as a share target and an "Open with" handler for PDFs and images.

### 6.1 Save to device (built)

Everything the app produces lives in **app-private storage**, which the platform deletes when the app is uninstalled. The share sheet could always rescue a file, but nobody reads "share" as "keep this" — so getting a copy out is a first-class action, not a corner of a menu.

1. **Always a copy, never a move.** The library keeps its own file, so a document that has been saved out is still there to work on. Nothing in the app removes a file as a side effect of exporting it (§5.2.6).
2. **Two entry points, because one is none.** The result screen after any operation, and the Files list — per document via its menu, or several at once by long-pressing to start a selection.
3. **Streamed, never materialised.** `file_picker`'s `saveFile()` requires the whole file as `bytes`; at the 200 MB input ceiling, that plus the copy a platform channel makes crossing into Kotlin or Swift would breach the 400 MB RSS cap in §13 on exactly the documents most worth rescuing. Both platforms therefore use a small native channel that takes a path: `ACTION_CREATE_DOCUMENT` / `ACTION_OPEN_DOCUMENT_TREE` with `ContentResolver` streams on Android, `UIDocumentPickerViewController(forExporting:asCopy:)` on iOS.
4. **No storage permission, ever.** The user's choice of destination in the system picker *is* the grant. `MANAGE_EXTERNAL_STORAGE` and broad media permissions are never requested (§8).
5. **Honest reporting.** A partial save ("Saved 2 of 3 files") is never rounded up to success, a destination the platform does not name is omitted rather than invented, and cancelling the picker is reported as nothing at all, because it is a choice rather than an event.

Acceptance: a document saved out is byte-identical to the one in the library and both still exist; a 200 MB document exports without exceeding the §13 memory cap; cancelling leaves no message and no file; selecting N documents produces exactly N files in one chosen folder.

### 6.2 Print (built)

Reachable from the viewer's app bar and from a document's menu in Files.

1. **The file is the job.** Neither platform re-renders or re-encodes the PDF: Android streams it into the descriptor the print framework supplies, iOS hands `UIPrintInteractionController` a file URL. Nothing is held in memory, for the same reason as §6.1.3 — the `printing` package's layout callback wants the whole document as bytes.
2. **The real page count is passed on** wherever it is already known (the viewer has it, the library stores it), so the print preview shows a number rather than "unknown".
3. **Page ranges belong to the spooler.** The Android adapter always writes the whole document and reports `ALL_PAGES`, which is the truth about what it wrote; selecting a subset is then the print framework's job, not a second export path of ours.
4. **No outcome is claimed.** Handing off to the system print UI produces no message, because that UI is still open and the user may yet print, save as PDF, or back out. Only "cannot print" and "printing unavailable" are reported.

Acceptance: printing a 200 MB document does not exceed the §13 memory cap; the preview shows the document's real page count; handing off shows no message; a device with no print services says so rather than failing silently.

## 7. Offline

Every v1.0 feature works fully offline with no network permission needed at runtime.

Documented exceptions, which must be surfaced in the UI rather than discovered by the user:

1. **Android document scanner (v1.1)** — first use downloads the ML Kit module (§3.10).
2. **Purchase and restore** — store transactions need connectivity. Entitlements are cached locally and honoured offline for a grace period (default 14 days) so a paying user is never locked out on a plane.
3. **Ads** (free tier) — served when online; their absence must never block a tool.

## 8. Privacy

### 8.1 The claim

"Your documents never leave your device." Scoped deliberately to **document content**: file bytes, file names, page text, images and passwords. The app does collect anonymous usage analytics and, on the free tier, serves ads that involve device-level identifiers — this is disclosed plainly rather than hidden behind a broad "privacy-first" claim.

### 8.2 Requirements

- No document bytes, file names, paths, page text or passwords in any network request, analytics event, log line or crash report. Enforced by a lint/test that scans event payloads for path-like strings.
- Temp files cleaned per §5.2.
- Ads and analytics gated behind consent: **Google UMP / IAB TCF consent flow** in EEA/UK, **App Tracking Transparency** prompt on iOS before any tracking identifier is used. Denial must leave the app fully functional (non-personalised ads).
- **Apple privacy manifest** (`PrivacyInfo.xcprivacy`) declaring data types and required-reason APIs, plus the manifests of all third-party SDKs.
- **Play Data Safety** declaration kept in sync with what the app actually sends.
- Privacy policy and ToS hosted publicly, versioned, reachable from Settings and from the store listings, written in plain language with a specific section on document handling.
- Crash reporting scrubs file names and user-entered text before upload.
- Optional biometric app lock over the document library and the app-switcher snapshot (§11).
- Child-safety: age rating set so the app is not directed to children; no personalised ads for users who signal otherwise.

## 9. Monetization

Freemium with a hard-gated premium tier. **No daily counters and no watermark on user output** — see §0 item 6.

**Free, unlimited**
Viewer · Merge (up to 3 files) · Split · Rotate / Delete / Reorder / Extract / Duplicate · Images → PDF (up to 10 images) · PDF → Images at up to 150 DPI · Recents and folders

**Premium**
Unlimited merge and image count · Compress · Batch / queued operations · 300 DPI and PNG export · Document scanner beyond 3 pages per document · Annotations and Add text · Signature · Watermark · Protect and Unlock · OCR · No ads

**Trial mechanics**
Each premium tool may be used **3 times total** (lifetime, not daily) so the user experiences the value on their own documents before the wall. A failed or no-op operation does not consume a use (§3.7). Plus a standard 3-day or 7-day free trial on the yearly plan, to be A/B tested.

**Plans**: monthly · yearly (positioned as the default, with the saving shown) · lifetime. Pricing to be set per market after testing; the paywall must support remote price/copy changes without an app release.

**Requirements**
- StoreKit 2 / Play Billing 6+ via a subscription layer (RevenueCat or equivalent) with server-side receipt validation.
- Entitlement cached locally and honoured offline (§7).
- Restore purchases works with no account, on a new device, in two taps.
- Paywall states price, period, renewal terms and cancellation path adjacent to the purchase button, as both stores require.
- Subscription management deep-links to the store's own management screen.
- A single `isPremium` gate in code, never a per-feature ad-hoc check.

## 10. Ads

Free tier only. Placements: home screen banner and an interstitial after a **completed** operation, frequency-capped (max 1 per 3 minutes, never two in a row).

Ads must never: overlay a document or any control, appear during processing, appear before the user has completed their first successful operation, appear on the error or the save/share screen, or sit adjacent to a destructive control. No rewarded-video gate on core tools in v1.

## 11. Settings

Theme (system / light / dark) · default quality · default page size · default export format · default save location · scan defaults · history retention and clear history · signature management · app lock · language · subscription management and restore · notifications · privacy policy · terms · open-source licences · about and version · contact support (pre-filled with device and app version, no document data).

Two of those need defining rather than just listing:

**App lock** — optional Face ID / Touch ID / biometric or device-passcode gate on opening the app, off by default, with a configurable grace period (immediately / 1 min / 5 min). It must also blank the app-switcher snapshot, otherwise the lock protects nothing. No custom PIN system of our own.

**Notifications** — the app sends exactly two kinds: (a) completion of a long operation that finished while the app was backgrounded, and (b) subscription lifecycle notices the stores expect (trial ending, renewal failure). **No marketing, engagement, streak or re-activation pushes in v1.** Permission is requested before the first long operation, never at launch.

## 12. Error handling

A closed taxonomy. Every failure maps to exactly one class, and every class defines the message, the recovery action, whether it is logged, and whether it consumes a free-tier use.

| Class | User message (short) | Recovery offered | Logged | Consumes use |
|---|---|---|---|---|
| Unsupported / corrupt file | "We can't open this PDF. It may be damaged." | Pick another file | Yes (type only) | No |
| Password required | "This PDF is password-protected." | Enter password | No | No |
| Wrong password | "That password didn't work." | Retry | No | No |
| Permission denied by owner password | "This PDF's owner has blocked changes." | Explain, offer Unlock tool | Yes | No |
| Out of storage | "Not enough space. Free about {N} MB and try again." | Retry, open storage settings | Yes | No |
| Out of memory / too large | "This document is too large to process on this device." | Suggest splitting first | Yes (size bucket) | No |
| Cancelled by user | — (silent) | — | No | No |
| No result / already optimized | "Already optimized — we couldn't make this smaller." | Discard | Yes | No |
| Camera/photo permission denied | "Allow camera access to scan documents." | Deep-link to settings | No | No |
| Scanner unavailable (no GMS) | "Scanning isn't available on this device." | — | Yes | No |
| Store / network failure on purchase | "Couldn't reach the store. Try again." | Retry, restore | Yes | No |
| Unknown | "Something went wrong. Nothing was changed to your file." | Retry, contact support | Yes + crash report | No |

Rules: every message names what happened and what to do next; no error codes as the primary text; **every error path ends with the original file untouched**, and the message says so where relevant.

## 13. Performance and limits (acceptance criteria)

Reference devices: **mid-tier Android** (Snapdragon 6-series class, 4 GB RAM, Android 13) and **iPhone SE 3**. Numbers are the acceptance bar on those devices, not on flagships.

| Metric | Target |
|---|---|
| Cold start to interactive home | < 2.0s |
| Open 50-page / 5 MB PDF to first page | < 1.5s |
| Merge 10 files / 200 pages | < 8s |
| Compress 20 MB / 30 pages, Balanced | < 30s |
| Render page thumbnail | < 120ms |
| Peak RSS during any operation | < 400 MB |
| Frame rendering | no jank frames while scrolling the viewer or page grid |
| Max supported input file | 200 MB (rejected above, with a clear message) |
| Max pages | 2,000 (warn above 500) |
| Crash-free sessions | ≥ 99.5% |
| Android download size | ≤ 35 MB per ABI |
| iOS download size | ≤ 70 MB |

Requirements:

- All PDF work runs off the platform thread (isolate / worker), never on the UI thread.
- Determinate progress where the engine reports it (page X of Y), indeterminate only where it genuinely cannot.
- Cancellation for every operation expected to exceed 2s, with the cancel taking effect in under 1s.
- **Background suspension**: iOS suspends the app shortly after backgrounding. A long operation must either complete within the grace window, or fail cleanly with the original intact and a resumable state — never leave a half-written file or a stuck progress bar.
- Bounded caches (thumbnails, rendered pages) with eviction, sized from device memory.
- Large documents are streamed, not fully materialised in memory.

## 14. Analytics

Anonymous, no document content (§8.2). Events:

**Usage** — tool_opened · file_imported (source, format, size bucket, page bucket) · operation_started · operation_completed (duration bucket, input/output size buckets) · operation_failed (error class) · operation_cancelled (at what progress) · file_shared · file_saved
**Funnel** — paywall_shown (trigger tool, trial uses remaining) · paywall_dismissed · trial_started · purchase_started · purchase_completed (plan) · purchase_failed (reason class) · restore_attempted · subscription_cancelled
**Health** — app_open · time_to_first_successful_operation · session_length · abandoned_at_file_pick · d1 / d7 / d30 return
**Never** — file names, paths, page text, passwords, folder names, share targets.

Every event must be answerable against a question we actually have ("which tool drives purchases?", "where do first-time users drop?"). Events that answer nothing get deleted.

## 15. Instrumentation for quality

- Crash and non-fatal error reporting with scrubbed payloads (§8.2).
- Remote config / feature flags with a **per-tool kill switch**, so a tool that corrupts files on one OS version can be disabled without an app release. This is the cheapest insurance in the whole plan.
- A regression corpus of test PDFs committed to the repo: linearized, PDF 1.4 through 2.0, encrypted (RC4 and AES), CJK and Arabic text, huge scanned, malformed/truncated, forms, 0-byte, mislabelled JPEG, 1,000-page. Every release runs every tool against the corpus.

## 16. Release plan

**v1.0 — the operations engine** (~140 dev-days; see feasibility report)
First-run and empty states · Viewer · import · Merge · Split · page management (reorder / rotate / delete / duplicate / extract) · Images → PDF · PDF → Images · Compress · save / share / export · Recents · folders · Settings · paywall, IAP, ads, analytics, crash reporting · app lock · notifications · localization infrastructure · accessibility pass

**v1.1 — capture and sign** (~25 days) — Document scanner · Signature
**v1.2 — markup** (~30 days) — Annotations · Watermark
**v1.3 — security and text** (~15 days) — Protect · Unlock · OCR (on-device, ML Kit / Vision)
**Later** — batch/queued operations · page numbers, headers, crop · form filling · compare · cloud folder sync (opt-in, still no account) · iPad multi-column and drag-and-drop · desktop · PDF ↔ Office (needs a server — would break §1.2 and requires a separate decision)

Rationale for the re-cut: everything in v1.0 is the same shape — pick a file, run one engine call, preview, save — and shares the page grid, the job runner and the export sheet. The scanner is a camera pipeline and the annotation canvas is a gesture/rendering system; each is effectively its own small app, and neither is needed for the core value proposition to be testable in the market.

## 17. Architecture requirements

- **One PDF engine behind our own facade.** All PDF operations go through an internal `PdfEngine` interface (`merge`, `split`, `rotate`, `compress`, `render`, `encrypt`, …). No UI or feature code imports the third-party PDF library directly. This keeps a single-library dependency swappable — see the feasibility report's dependency risk.
- Feature-first module structure; each tool is a self-contained feature depending on shared `core` (engine facade, job runner, file store, design system).
- One job runner owning all long operations: queue, progress, cancellation, isolate lifecycle, temp-file ownership, atomic commit.
- Local persistence for recents, folders, favorites, signatures and settings in a single embedded DB with migrations from v1.
- Dependency versions pinned exactly; upgrades are deliberate, reviewed changes.

## 18. Other non-functional requirements

1. **Localization** — externalised strings from the first commit, `Intl`-based plurals and number/date formats, RTL-correct layouts. Launch languages: English, Spanish, Portuguese (BR), German, French, Indonesian, Arabic. This category's install base is heavily non-English; retrofitting is far more expensive than doing it from day one.
2. **Accessibility** — semantic labels on every control, 4.5:1 contrast, dynamic type support without clipping, full VoiceOver/TalkBack traversal on the viewer and page grid, minimum 44/48 dp touch targets.
3. **Theming** — light and dark, following system by default; the viewer background must be correct in both.
4. **Responsive layout** — phone, large phone and tablet breakpoints. No stretched phone UI on iPad; two-pane on ≥ 700 dp. Cheap now, expensive later.
5. **Testing** — unit tests on the engine facade and range/selection logic; widget tests on each tool flow; integration tests running each tool end-to-end against the §15 corpus; golden tests on the viewer and page grid. CI runs analyze, tests and both platform builds on every change.
6. **Release process** — semantic versioning, staged rollout on Play (5 → 20 → 50 → 100%), phased release on iOS, a documented rollback path, and no release without a green corpus run.
7. **Legal** — EU trader status for App Store distribution, GDPR/CCPA posture, subscription terms disclosure in-app, third-party licence attributions screen.

## 19. Success criteria

The question v1.0 answers: **do people come back to us instead of googling "merge pdf online"?**

| Metric | Target at 90 days |
|---|---|
| Operation success rate | ≥ 98% |
| Operations per active user per month | ≥ 3 (repeat use is the whole thesis) |
| D1 / D7 / D30 retention | ≥ 35% / ≥ 18% / ≥ 10% |
| Free → paid conversion | 1.5–3% of installs |
| Paywall view → purchase | ≥ 4% |
| Time to first successful operation (median) | < 60s from install |
| Crash-free sessions | ≥ 99.5% |
| Store rating | ≥ 4.3 |
| Uninstall rate at 7 days | ≤ 40% |

Kill criteria, defined now so they are not rationalised away later: if after 90 days of v1.0 with meaningful install volume, operations per active user is below 1.5 **and** D7 retention is below 10%, the product is a one-time-use tool rather than a habit, and the plan should change rather than continue adding tools.

## 20. Assumptions, open questions and non-goals

### 20.1 Assumptions

- One or two experienced Flutter developers, no dedicated backend engineer, and no server to operate or pay for.
- The chosen PDF engine benchmarks acceptably in the week-one spike; if not, the choice is revisited behind the §17 facade before feature work starts.
- Pricing, launch markets and any acquisition budget are decided before v1.0 code freeze, not after launch.
- No enterprise, MDM, SSO or team requirements exist for v1.x.

### 20.2 Open questions

Each needs an owner and a decision date. Question 2 should be answered before any code is written.

| # | Question | Blocks | Needed by |
|---|---|---|---|
| 1 | Price points per market, and the monthly / yearly / lifetime ratio | Paywall copy, §19 conversion targets | v1.0 beta |
| 2 | Is there an acquisition budget? If not, what is the organic wedge? | Whether v1.0 is worth building at all | **Before build starts** |
| 3 | Ads on the free tier at launch, or added in v1.1? | §10, first-week rating risk | v1.0 beta |
| 4 | Launch languages beyond the seven in §18.1 | Localization budget, string freeze | String freeze |
| 5 | Do we ship a rasterizing "maximum" compression mode at all? | §3.7 | v1.0 |
| 6 | Is "PDF Toolbox" the shipping name? It is generic and hard to rank for. | ASO, icon, every piece of creative | Store setup |

### 20.3 Explicit non-goals for v1.x

Written down so they are not re-litigated mid-build: cloud sync or any account system · PDF ↔ Word / Excel / PowerPoint conversion (requires a server, breaks §1.2) · certificate-based digital signatures · collaborative review or commenting · AI or LLM document features · desktop and web builds · e-signature request workflows · PDF form *creation* (form *filling* is a later candidate).
