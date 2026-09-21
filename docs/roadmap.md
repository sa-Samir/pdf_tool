# PDF Toolbox — Development Plan

Companion to `requirements.md` (v2.1) and `feasibility.md` · 2026-09-18

---

## 1. How to read this

**Effort** is in dev-days and totals **140** for v1.0, matching the feasibility model. Days are working days for one experienced Flutter developer at ~6 productive hours, including tests and edge cases, excluding visual design.

**Two staffing scenarios** are costed in §8. Solo is ~28 weeks; two developers is ~16 weeks, not 14, because the foundation is mostly serial.

**Phases end at gates, not at dates.** Each gate has exit criteria you can objectively fail. A phase that misses its criteria does not advance by declaring itself done — that is the entire mechanism by which this plan resists the usual outcome, which is discovering in month five that page rendering leaks memory.

## 2. Three principles the sequencing is built on

**Risk first, features last.** The two things that could invalidate the stack — engine quality and binary size — are measured in week one, before a line of UI exists. The one thing that could invalidate the business — nobody can find the app — is answered in parallel by someone else, and it is a real go/no-go.

**Walking skeleton before breadth.** Phase 1 ends with *one* tool (rotate) working end to end through the entire pipeline: pick a file → copy to sandbox → run in an isolate → show progress → cancel → preview → atomic save → share → appear in recents. Every architectural decision is proven against a real operation before eight more tools are poured into it. Tools built after a proven skeleton cost 3–7 days each; tools built while the architecture is still moving cost double and get rewritten.

**Build the shared components once, early, properly.** The page grid is used by the viewer, five page-management tools, split preview, PDF→Images selection, and later by watermark and annotation page ranges. The job runner is used by everything. These two get funded properly in Phases 1–2 instead of being grown accidentally out of whichever tool needed them first.

## 3. Phases at a glance

| Phase | Name | Days | Solo weeks | Gate |
|---|---|---|---|---|
| 0 | Spike and decision | 5 | 1 | **G0 — go / no-go / change stack** |
| 1 | Foundation and walking skeleton | 32 | 6.5 | G1 — skeleton survives the corpus |
| 2 | Viewer and library | 16 | 3 | G2 — shared components hold |
| 3 | The eight tools | 28 | 5.5 | G3 — feature-complete alpha |
| 4 | Settings, money, instrumentation | 27 | 5.5 | G4 — a stranger can buy and restore |
| 5 | Hardening, localization, accessibility | 21 | 4 | G5 — release candidate meets §13 |
| 6 | Compliance, beta, launch | 11 | 2.5 | **G6 — shipped** |
| | **v1.0 total** | **140** | **28** | |

---

## 4. Phase 0 — Spike and decision (5 days)

**Goal:** find out whether this plan is built on sand, while it costs a week instead of a quarter.

| Work | Days |
|---|---|
| Assemble the first regression corpus (~30 files: scanned, text-heavy, mixed, CJK, Arabic, encrypted RC4/AES, forms, linearized, malformed, 0-byte, 200 MB, 1,000-page) | 1 |
| Benchmark the engine on it: compress ratios and time, merge, render, encrypt/decrypt — on a real mid-tier Android device, not a simulator | 2 |
| Measure binary size with the `keep:` capability sets actually needed, both platforms | 1 |
| Repo, CI skeleton, branch and release conventions | 1 |

**Exit criteria (G0):**

- Compress achieves ≥50% on the scanned samples at Balanced, and correctly reports the no-op case on text-heavy samples.
- Merge, render, encrypt and decrypt succeed on every non-malformed corpus file; malformed files fail cleanly rather than crashing.
- Android download size projects under 35 MB and iOS under 70 MB with the needed capabilities.
- §20 open question 2 (acquisition budget / organic wedge) has an answer.

**If the engine fails:** re-run the same benchmark against `syncfusion_flutter_pdf` (pure Dart, drops into an isolate with no native build work) before changing anything else. The facade in Phase 1 exists precisely so this stays a contained decision.

**Do not** start UI work, design systems or tool screens in this phase. The output of Phase 0 is a decision and a benchmark table committed to the repo, nothing else.

---

## 5. Phase 1 — Foundation and walking skeleton (32 days)

**Goal:** one tool working end to end through architecture that everything else will reuse.

| Work | Days | Notes |
|---|---|---|
| Project setup, flavors, DI, routing, theming, design system, logging | 7 | Design system means tokens, typography, spacing and the 6–8 shared widgets — not a component library. |
| `PdfEngine` facade (§17) | 4 | Every engine call in the app goes through this. No feature code imports the PDF package directly, ever. |
| Job runner: isolates, queue, progress, cancellation, temp lifecycle, atomic temp→verify→move commit | 8 | The §5.2 invariants live here and are enforced in one place, not per tool. |
| Import layer: document picker, photo picker, share-target and Open-with intents, sandbox copy, HEIC transcode, cloud-placeholder states | 8 | |
| Export: save, share sheet, open-with, rename, move, print | 5 | |

**Exit criteria (G1):** rotate a page in a PDF picked from Files/Drive, watch determinate progress, cancel it mid-run and see nothing left behind, run it again, save atomically, share it, and find it in a list — on both platforms, against every corpus file. Killing the app mid-operation leaves the original intact and no orphaned temp files. An integration test covers exactly this path and runs in CI.

**Why rotate:** it is the cheapest operation that still exercises the whole pipeline. It is not the most valuable tool, and that is the point — the skeleton is about the pipeline, not the feature.

---

## 6. Phase 2 — Viewer and library (16 days)

**Goal:** the two shared surfaces everything else sits on.

| Work | Days |
|---|---|
| Viewer: continuous scroll, zoom, page jump, text search, password prompt, rotation handling | 8 |
| Page grid / thumbnail component: lazy render, bounded cache, multi-select, drag-reorder with edge auto-scroll | — (in the 8 above) |
| Recents, folders, favorites: DB schema, migrations, unavailable-file pruning, retention and clear-history | 8 |

**Exit criteria (G2):** a 500-page document opens without loading all pages and scrolls the grid without jank; the thumbnail cache is bounded and demonstrably evicts; peak RSS stays under 400 MB on the 4 GB reference device; DB migrations run forward from an empty install and from a seeded v1 schema.

This is the phase where memory discipline is either established or lost. §13's 400 MB ceiling is a Phase 2 exit criterion rather than a Phase 5 discovery.

---

## 7. Phase 3 — The eight tools (28 days)

With the skeleton and shared components in place, each tool is a thin feature: an engine call, a configuration screen, a result screen, edge cases, tests.

| Tool | Days | Sequencing note |
|---|---|---|
| Page management — reorder, rotate, delete, duplicate, extract, one undo stack, one save | 5 | Do first: five tools on the Phase 2 grid, and it proves the multi-edit-then-save model. |
| Merge | 3 | |
| Split — four modes, range parser, output preview | 4 | |
| Images → PDF | 5 | Different pipeline (image memory discipline, EXIF, HEIC). |
| PDF → Images | 4 | |
| Compress | 6 | Last, because its UX depends on the Phase 0 benchmark data to set honest expectations. |
| First-run, onboarding, empty states (§3.0) | 1 | |

**Exit criteria (G3) — feature-complete alpha:** every tool runs every corpus file to a correct result or a correctly-classified §12 error; no tool can produce a file that fails to reopen; integration tests cover all eight; the app is dogfoodable and the team uses it for real documents for a week.

**Do not** add tools outside this list. Scanner, signature, annotation and watermark are v1.1+ (§16) and each one added here costs two to five weeks and delays every signal you are building the app to collect.

---

## 8. Phase 4 — Settings, money and instrumentation (27 days)

**Goal:** the app can earn, and you can see what it is doing.

| Work | Days |
|---|---|
| Settings, app lock (biometric + app-switcher snapshot), notifications | 6 |
| IAP: StoreKit 2 / Play Billing via RevenueCat, paywall, single `isPremium` gate, entitlement cache, 14-day offline grace, restore without an account | 8 |
| Free-tier trial accounting — 3 lifetime uses per premium tool, not consumed by failures or no-ops (§3.7, §12) | 3 |
| Ads: placements, frequency caps, UMP consent, ATT, the "never before first success" rule | 5 |
| Analytics (usage + funnel), crash reporting with scrubbed payloads, remote config with per-tool kill switches | 5 |

**Exit criteria (G4):** someone outside the team, on a fresh device, buys a subscription, force-quits, reinstalls, restores it, and goes offline for a day with premium still working. A tool can be disabled remotely without an app release. No analytics event, log line or crash report contains a file name or path — verified by the §8.2 automated scan, not by inspection.

The kill switch is the cheapest insurance in the plan. Build it here, not after the first bad release.

---

## 9. Phase 5 — Hardening, localization, accessibility (21 days)

| Work | Days |
|---|---|
| Complete the corpus to ~100 files; integration tests across every tool in CI | 5 |
| Device-matrix QA; performance and memory tuning to every §13 number | 8 |
| Localization infrastructure and seven languages, RTL layout correctness | 5 |
| Accessibility pass: semantics, contrast, dynamic type, VoiceOver/TalkBack on viewer and grid | 3 |

**Exit criteria (G5):** every §13 number met on both reference devices — not on a flagship. Crash-free sessions ≥99.5% across a week of internal use. Every string externalised, no clipping at the largest dynamic type in any language, Arabic layout correct. Full task completion for a screen-reader user on merge and compress.

**Start the Play closed test on day 1 of this phase** — see §11. Its 14-day clock should run against a hardening build, in parallel, not after.

---

## 10. Phase 6 — Compliance, beta, launch (11 days)

| Work | Days |
|---|---|
| Privacy manifest, Play Data Safety, privacy policy and ToS, store listings, screenshots, ASO copy | 6 |
| TestFlight/closed beta round, fix pass, staged rollout | 5 |

**Exit criteria (G6):** staged Play rollout at 5% and iOS phased release under way, crash-free ≥99.5% at 5%, no P1 in the first 48 hours, rollback path documented and rehearsed.

Rollout discipline: Play at 5 → 20 → 50 → 100% with at least 24 hours and a crash-rate check between steps. Budget one App Store rejection round; it is the normal case, not a failure.

---

## 11. The parallel non-engineering track

These have lead times measured in weeks and no engineering dependency, so they start in Phase 0 and are the most common cause of a finished app that cannot ship.

| Item | Start | Lead time | Note |
|---|---|---|---|
| **Google Play account decision** | Phase 0, day 1 | — | **Decisive.** A *personal* account created after 13 Nov 2023 must run a closed test with **12 testers opted in for 14 continuous days**, then apply for production access (~7 days review), and Google now also checks the testers actually used the app. **Organization accounts are exempt.** A personal account adds roughly 3–4 weeks to launch unless the test runs in parallel. |
| Play closed test recruitment and run | **Phase 5, day 1** | 14 days + ~7 review | Recruit the 12 during Phase 4. Running this against a Phase 5 hardening build costs zero calendar time; running it after Phase 6 costs a month. |
| Apple Developer Program | Phase 0 | days, or 1–2 weeks for an organization (D-U-N-S) | Organization enrolment needs a D-U-N-S number. Start immediately if not already enrolled. |
| App name and brand decision (§20 Q6) | Phase 0 | — | "PDF Toolbox" is generic and hard to rank for. Blocks icon, listing, screenshots and every piece of creative. |
| ASO and keyword research | Phase 0 | 1 week | Feeds the G0 distribution answer. |
| Privacy policy and ToS, publicly hosted | Phase 4 | — | Needed before store submission and linked in-app. |
| Pricing decision per market (§20 Q1) | Phase 4 | — | Needed before the beta paywall. |
| Store creative: icon, screenshots, preview video | Phase 5 | 1–2 weeks | Typically outsourced; brief it in Phase 4. |

---

## 12. Staffing

**Solo — 28 weeks (~6.5 months).** Phases run in the order above.

**Two developers — ~16 weeks (~3.5–4 months),** not 14: Phases 0–1 are largely serial, since the second developer cannot build tools on a job runner that does not exist yet.

| Phase | Dev A (architecture) | Dev B |
|---|---|---|
| 0 | Benchmark, binary size | Corpus, CI, repo conventions |
| 1 | Engine facade, job runner, import layer | Design system, theming, export/share, settings shell |
| 2 | Viewer and page grid | Recents, folders, DB and migrations |
| 3 | Page management, compress, images→PDF | Merge, split, PDF→images, first-run |
| 4 | IAP, entitlements, trial accounting | Ads, consent, analytics, crash, remote config |
| 5 | Performance and memory tuning | Localization, accessibility, corpus and integration tests |
| 6 | Release engineering, rollout | Compliance, listings, beta management |

A part-time designer is worth having from Phase 1 (design system) and Phase 5 (store creative). A third developer does not meaningfully compress this; the critical path is Phases 1–2 and it does not divide well.

---

## 13. After launch

**Do not start v1.1 on launch day.** Hold 2–3 weeks for the post-launch fix cycle — first-week reviews and crash reports will name things no internal QA found.

| Phase | Scope | Days | Solo weeks |
|---|---|---|---|
| Post-launch stabilisation | Crash fixes, review triage, first ASO iteration | 10 | 2 |
| v1.1 | Document scanner (15) + Signature (10) | 25 | 5 |
| v1.2 | Annotation editor (25) + Watermark (6) | 31 | 6 |
| v1.3 | Protect (5) + Unlock (3) + OCR (8) | 16 | 3 |

**The 90-day gate (§19), run before v1.2 is committed.** If operations per active user is below 1.5 **and** D7 retention is below 10%, stop adding tools. That combination means people use the app once and leave, and a fourteenth tool does not fix a habit problem. The response is repositioning or a different wedge, not more surface area.

Sequencing rationale for v1.1 before v1.2: the scanner is the strongest retention hook in this category — it creates documents rather than processing existing ones, which is the difference between monthly use and daily use. The annotation editor is the single most expensive item in the whole roadmap (25 days) and should be funded only once the 90-day metrics justify it.

---

## 14. Leading indicators that this plan is slipping

Check these at each gate; they surface trouble earlier than a burndown.

- **A gate passes without its criteria being run.** The most common failure. If G2's memory ceiling was never measured on the 4 GB device, G2 did not pass.
- **A tool in Phase 3 takes more than 1.5× its estimate.** That is rarely about the tool — it means the Phase 1 foundation is missing something, and the next six tools will pay it too. Stop and fix the foundation.
- **Engine calls appearing outside the facade.** Mechanically checkable in CI; catch it the first time.
- **The corpus not growing.** Every bug found in the wild should arrive as a corpus file in the same commit as its fix. A static corpus means regressions are shipping.
- **Compress still reporting misleading ratios at G3.** This is the rating risk in §3.7; it must be settled in Phase 3, not discovered in beta.
- **Phase 5 starting before the Play closed test.** Costs a month of calendar time for nothing.
