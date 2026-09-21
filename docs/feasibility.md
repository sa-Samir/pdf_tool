# PDF Toolbox — Feasibility Assessment

Assessed 2026-09-17 against `docs/requirements.md` (v2) · Flutter 3.38.5 / Dart 3.10.4

---

## Verdict

**Technically feasible with high confidence.** 15 of 15 tools can be implemented fully on-device with MIT-licensed libraries and platform APIs. There is no feature in the spec that requires a server, which means the privacy positioning in §1.2 is a real, defensible product claim and infrastructure cost is €0.

**Two engineering items carry genuine risk**, neither fatal:
1. Compression outcomes vary from 0% to 90% depending on document content — a product/expectations problem more than a technical one (mitigated in requirements §3.7).
2. The Android document scanner is not truly offline on first use (requirements §3.10, §7).

**One keystone dependency** concentrates most of the technical risk in a single package (see Risk 1).

**The binding constraint is not engineering — it is distribution.** This is one of the most saturated categories on both stores. Effort to build v1.0 is ~140 dev-days (~6.5 months solo, ~3.5 months with two developers). The original MVP scope is ~180 days (~8.5 months solo). Recommendation at the end.

---

## 1. Per-feature technical feasibility

Confidence: **High** = library API exists and is documented for this exact operation · **Medium** = achievable, non-trivial work or variable outcome · **Conditional** = works with a stated limitation.

| # | Feature | How | Confidence | Notes |
|---|---|---|---|---|
| 1 | PDF viewer, zoom, search | `pdfrx` (MIT, PDFium) | High | Mature, actively developed, 6 platforms. Also gives text search and links. |
| 2 | Page thumbnails / grid | `pdfrx` render at thumbnail size | High | Must bound the cache; see Risk 5. |
| 3 | Merge | `pdf_manipulator` merge | High | Preserves bookmarks per docs; verify page-size handling on the corpus. |
| 4 | Split (pages / ranges / size / bookmarks) | `pdf_manipulator` split | High | Supports split by page count, size and bookmarks. |
| 5 | Reorder / delete / duplicate / extract | `pdf_manipulator` page ops | High | Also expressible via `pdfrx_engine` page-list reassignment as a fallback. |
| 6 | Rotate | `pdf_manipulator` rotate | High | |
| 7 | Images → PDF | `pdf_manipulator` `imagesToPdf`, or `pdf` (Apache-2.0) | High | Two independent options; HEIC needs platform transcode first. |
| 8 | PDF → Images | `pdf_manipulator` `render()` or `pdfrx` | High | PNG out of the box; JPEG re-encode via `image`. |
| 9 | **Compress** | `pdf_manipulator` `compress()` — image downsampling to 150/72 ppi, JPEG re-encode, stream deflate, unused-object removal | **Medium** | The mechanism is right (this is what desktop tools do). The *outcome* is content-dependent: scanned PDFs shrink a lot, text/vector PDFs barely at all. Needs the honesty UX in requirements §3.7 and a benchmark corpus to set expectations. |
| 10 | Document scanner | VisionKit (iOS) + ML Kit Document Scanner (Android), via `cunning_document_scanner` or direct platform channels | **Conditional** | Android module is downloaded on first use → needs network once; unavailable on non-GMS devices. iOS 13+. Native UI means less styling control but far better detection than anything we would build. |
| 11 | Annotations | `pdf_manipulator` annotation handling + custom gesture canvas | Medium | The PDF-writing half is solved; the *editor* is the expensive part (~25 days), not the file format. |
| 12 | Signature | Draw canvas → PNG with alpha → `addImageStamp` | High | Stamp, not certificate signing (requirements §3.12). |
| 13 | Watermark | `pdf_manipulator` `addStamp` / `addImageStamp` (opacity, rotation, font size) | High | |
| 14 | Protect | `pdf_manipulator` `encrypt()`, AES-256, user/owner passwords + permission flags | High | |
| 15 | Unlock | `pdf_manipulator` `PdfEncryption.remove()` with the user-supplied password | High | No bypass or recovery, by design and by capability. |
| 16 | OCR (v1.3) | ML Kit Text Recognition / Apple Vision, on-device | High | Both are on-device; no server needed. |
| 17 | Import from iCloud / Drive / providers | System document picker (SAF / `UIDocumentPicker`) | High | Covered by one picker; no per-provider SDKs, no OAuth, no broad storage permission. |
| 18 | HEIC input | Platform decode via `heif_converter` / `flutter_image_compress` | High | Dart cannot decode HEIC; must transcode on import. |
| 19 | Share / open-with / print | `share_plus`, platform intents, `printing` | High | |
| 20 | IAP, entitlements, offline grace | StoreKit 2 / Play Billing via RevenueCat or `in_app_purchase` | High | Restore-without-account works via store receipts. |
| 21 | Ads + consent | `google_mobile_ads` + UMP + ATT | High | |

**No feature in the spec requires a backend.** The only server-side component worth having is receipt validation, which RevenueCat provides as a managed service.

## 2. Library and licensing decision

The important recent change: **`pdf_manipulator` 5.0.0** (MIT, verified publisher, 160/160 pub points, Rust core compiled to native + WASM, off-main-thread with cancellable tasks) covers merge, split, page ops, rotate, compress, watermark/stamps, AES-256 encrypt/decrypt with permissions, render, text extraction, redaction and PDF/A validation in one MIT-licensed package.

Why that matters commercially: the obvious alternative, `syncfusion_flutter_pdf`, is excellent and pure Dart but **is not open source**. Its Community License requires under $1M USD annual gross revenue, 5 or fewer developers, 10 or fewer employees and no more than $3M in outside capital. A commercial app that succeeds eventually fails those tests, and the paid licence is a per-developer annual cost. Building the core of a monetised product on it means either accepting that future cost or a painful migration later.

**Recommended stack**

| Concern | Package | Licence |
|---|---|---|
| PDF operations | `pdf_manipulator` | MIT |
| Viewing, thumbnails, text search | `pdfrx` | MIT |
| PDF generation (images→PDF, printing) | `pdf` + `printing` | Apache-2.0 |
| Scanner | `cunning_document_scanner` / platform channels | verify at integration |
| Image work, HEIC | `image`, `flutter_image_compress`, `heif_converter` | permissive |
| IAP | `purchases_flutter` (RevenueCat) or `in_app_purchase` | MIT / BSD |
| Ads | `google_mobile_ads` | Apache-2.0 (SDK proprietary) |

Keep `syncfusion_flutter_pdf` documented as a break-glass fallback for any single operation that the Rust engine handles badly — it is pure Dart, so it drops into an isolate with no native build changes.

## 3. Effort model

Assumes one experienced Flutter developer, ~6 productive hours/day, estimates **including** tests, edge cases and QA, **excluding** visual design and store creative. Rounded to whole days.

### v1.0 — the operations engine

| Area | Work | Days |
|---|---|---|
| Foundation | Project setup, CI, flavors, DI, routing, design system, theming, logging | 8 |
| | Job runner: isolates, queue, progress, cancellation, temp lifecycle, atomic commit | 8 |
| | Import layer: document picker, photo picker, share-target, sandbox copy, HEIC transcode, cloud-placeholder handling | 8 |
| | Engine facade over `pdf_manipulator` + fallback seams | 4 |
| | Viewer + page-grid/thumbnail component | 8 |
| | Export: save, share, open-with, rename, move, print | 5 |
| | Recents + folders + favorites (DB, migrations) | 8 |
| | Settings, app lock, notifications | 6 |
| | First-run, onboarding, empty states | 3 |
| Tools | Merge | 3 |
| | Split (4 modes, range parser, previews) | 4 |
| | Page management (reorder / rotate / delete / duplicate / extract on the shared grid, undo stack) | 7 |
| | Images → PDF (crop, rotate, page size, memory discipline) | 5 |
| | PDF → Images (DPI, selection, ZIP, cancellation) | 4 |
| | Compress (presets, content inspection, honest reporting, no-op path, benchmark corpus) | 6 |
| Money | IAP + paywall + entitlement cache + offline grace + restore | 8 |
| | Ads + UMP/ATT consent + placement rules | 5 |
| | Analytics + crash reporting + remote config kill switches | 5 |
| Quality & launch | Test corpus assembly + integration tests across all tools | 6 |
| | Device-matrix QA, performance and memory tuning to §13 targets | 8 |
| | Localization infrastructure + 7 languages | 5 |
| | Accessibility pass | 3 |
| | Privacy manifest, Data Safety, policy/ToS, store listings, screenshots, ASO | 6 |
| | Beta round, fix pass, release | 6 |
| **Total** | | **~139** |

Realistic range: **125–155 dev-days.**

- Solo: **~6.5 months** (28 weeks at 5 days)
- Two developers: **~3.5 months** (parallelism is good here — tools are independent once the foundation lands, but the foundation itself is ~2 person-months of mostly serial work)

### Subsequent phases

| Phase | Scope | Days |
|---|---|---|
| v1.1 | Scanner (15) + Signature (10) | 25 |
| v1.2 | Annotation editor (25) + Watermark (6) | 31 |
| v1.3 | Protect (5) + Unlock (3) + OCR (8) | 16 |

### The original MVP, as specified in v1

Original MVP = v1.0 + scanner + signature + basic annotations ≈ **180 dev-days ≈ 8.5 months solo** (~5 months with two developers). That is the single most important number in this assessment: the v1 document describes an 8-month first release, and the sections most likely to be read as "small" (annotations, scanner) account for 50 of those days.

### Cash cost

| Item | Cost |
|---|---|
| Apple Developer Program | $99/yr |
| Google Play registration | $25 one-time |
| Backend / infrastructure | **$0** (nothing is uploaded) |
| RevenueCat | free under ~$2.5k monthly tracked revenue, then ~1% |
| Crash reporting / analytics | free tiers sufficient at launch |
| Design, ASO tooling, localization review | optional, $0–2k |
| **User acquisition** | **the real budget line — see Risk 9** |

## 4. Risk register

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| 1 | **Keystone dependency.** `pdf_manipulator` carries almost every operation. It is MIT with a perfect pub score, but it has moderate adoption (~3k weekly downloads) and has shipped 5 major versions in 3 years — two of them in the last two months. Breaking API churn is likely. | High | Facade every call behind our own `PdfEngine` (requirements §17); pin exact versions; upgrade deliberately with the corpus as the gate; keep `syncfusion_flutter_pdf` and `pdfrx_engine` as documented fallbacks; MIT licence means we can fork if maintenance stops. |
| 2 | **App size.** The Rust engine is ~21 MB native at full capability, ~5 MB core-only. | Medium | Use the package's `keep:` tree-shaking to include only the capabilities in scope; Android App Bundle splits per ABI; measure download size in week 2, not week 20; budget in requirements §13. |
| 2b | **Build prerequisite: Rust.** The package vendors ~58 MB of engine sources and its build hook compiles them with cargo, so every developer machine and CI runner needs a Rust toolchain at or above the version the engine pins (1.92 for 5.0.0). Confirmed by an iOS simulator build failing on Rust 1.83. First builds are slow. | Medium | Pin the toolchain in the repo (`rust-toolchain.toml`), document it in the README, cache `~/.cargo` and the hook build directory in CI, and treat an engine upgrade as a possible toolchain upgrade. |
| 3 | **Compression expectations.** Users compare against desktop tools and expect big wins on every file. Text PDFs will disappoint. | Medium-High (rating risk) | Content-based estimate before running; explicit "already optimized" outcome; never consume a free use on a no-op; side-by-side quality preview; never rasterize silently. |
| 4 | **Android scanner is not offline on first use** and absent on non-GMS devices, contradicting the offline claim as originally written. | Medium | Capability check up front; disable with explanation; document the exception in-app and in the listing; do not headline scanning as offline on Android. |
| 5 | **Memory / OOM on large scanned PDFs**, especially 3–4 GB Android devices. | Medium | Stream rather than materialise; cap render concurrency; bounded thumbnail cache sized from device memory; hard input cap at 200 MB with a clear message; test explicitly on a 4 GB device, not a flagship. |
| 6 | **iOS background suspension** killing a long compress mid-write. | Medium | Atomic temp→verify→move; checkpointing; clean failure with the original intact; never leave a stuck progress bar. |
| 7 | **iOS/Android file-access model.** Picked URLs are temporary; cloud files may be undownloaded placeholders. Naive "recent files" implementations break here. | Medium | Copy into the sandbox on import (requirements §3.3); treat the sandbox copy as the unit of work and of history. |
| 8 | **Store review.** IAP compliance, subscription disclosure, privacy manifests, Data Safety accuracy, and "Unlock PDF" drawing scrutiny. | Low-Medium | Manifests and disclosures built in from the start; unlock UI states plainly that the user must supply the password; expect one rejection round and budget for it. |
| 9 | **Distribution.** CamScanner alone has 500M+ downloads; iLovePDF, Adobe Scan, Smallpdf and dozens of near-identical "PDF Tools" apps compete for the same keywords. Organic discovery for "merge pdf" is effectively closed. Utility-category conversion runs ~1–3%. | **High — this is the real constraint** | Validate before building: keyword volume and difficulty research, a landing-page or small paid test against the specific wedge (fully offline, no account, no watermark on your file), and a decision on UA budget. Consider a narrower entry wedge (e.g. "the PDF app that never uploads your documents" aimed at legal/medical/finance users) rather than competing head-on as tool #47. |
| 10 | Free-tier bypass by reinstall (lifetime trial counters are local). | Low | Accept it — the alternative is an account, which costs more in conversion than the leakage costs in revenue. Keep counters local and cheap. |

## 5. What is not feasible as originally described

| Item | Issue |
|---|---|
| "All core features work without an internet connection" | True for every v1.0 tool; **not** true for the Android scanner's first use, nor for purchase/restore. Requires the documented exceptions now in requirements §7. |
| "Compressed: 6.2 MB · Saved 66%" as the illustrated outcome | Cannot be promised. Content-dependent; needs the honesty UX. |
| "Watermark: available with branding" on the free tier | Feasible, but self-defeating: it brands the user's own output, which is the pattern this category is most criticised for and directly contradicts the "no watermark on your files" wedge in §1.2. Removed. |
| Daily usage limits without an account | Enforceable only locally and resettable by reinstall; also walls users at their moment of need. Replaced with a 3-use lifetime trial per premium tool. |
| PDF ↔ Word/Excel conversion (listed as "later") | Not achievable on-device at acceptable quality. Would require a server and would break §1.2. Needs an explicit product decision, not a backlog item. |
| Certificate-based digital signatures | Out of scope; the signature feature is a visual stamp and the UI must not imply otherwise. |

## 6. Recommendation

1. **Build it — the engineering is sound.** Every tool is achievable on-device with permissive licences and no backend. That is unusual in this category and is the product's actual advantage.
2. **Ship the re-cut v1.0 (~140 days), not the original MVP (~180 days).** Scanner, signature and annotations are three separate sub-products; holding the launch for them delays market feedback by ten weeks for value the core thesis does not need to be tested.
3. **Spend the first week on the two risk items, before any UI work**: benchmark `pdf_manipulator`'s compress and merge against a realistic corpus (scanned, text-heavy, mixed, CJK, encrypted, 200 MB), and measure the resulting binary size with the `keep:` set you actually need. Those two measurements can change the stack choice, and they cost days now versus months later.
4. **Validate distribution in parallel with that first week.** The build is 6 months; finding out afterwards that nobody can find the app is the expensive failure mode here, not a library limitation.
5. **Put the engine behind a facade on day one.** It is a few hours of work and it is the difference between a dependency change being a one-file edit and a rewrite.
