# Compression benchmarks

Measured 2026-09-23 against the real engine (`pdf_manipulator` 5.0.0) on an
Apple Silicon host, via a throwaway harness. Synthetic documents: text pages
from the engine's own builder, "scans" from full-page photo-like images.

These numbers are what the Compress feature's copy and expectations are built
on. Re-run before changing presets or the wording (requirements.md 3.7).

## Results

| Document | Size | Image page share | print 300ppi/q85 | ebook 150ppi/q75 | screen 72ppi/q60 |
|---|---|---|---|---|---|
| Text, 30 pages | 0.16 MB | 0.00 | 0.0% | 0.0% | 0.0% |
| Text, 5 pages | 0.03 MB | 0.00 | 0.0% | 0.0% | 0.0% |
| Scan, 8 pages | 9.41 MB | 1.00 | 67.1% | 76.4% | 98.4% |
| Scan, 30 pages | 9.42 MB | 1.00 | 67.0% | 76.3% | 98.2% |
| Mixed, 12 pages (6 text + 6 scan) | 9.44 MB | 0.50 | 66.9% | 76.1% | 98.0% |

`lossless` (no downsampling, no lossy codec) saved 0.0% on every document,
including the scans, so it is not offered as a preset.

Time: a 9.4 MB / 30-page scan compressed in 394–501 ms, comfortably inside the
30 s bar in requirements.md 3.7.

## The finding that shaped the feature

**Savings track image *bytes*, not the share of pages carrying images.** The
mixed document has half the image pages of the pure scan and saved within
0.3 points of it, because the images are almost all of the bytes either way.

An estimate that interpolates on page-area share would have predicted ~38% for
that file against an actual 76% — exactly the kind of misleading number
requirements.md 3.7 exists to prevent. There is no cheap structured way to get
image byte share ahead of the run (`PdfImageReport` has `bytesBefore` and
`bytesAfter`, but only as a result of doing the work).

So the feature does not predict a percentage. Before the run it says only what
it can know for certain and instantly:

- no raster images at all -> say plainly that little or nothing will be saved
- raster images present -> say it is likely to shrink, and by roughly how much
  per preset, from the table above

The real numbers are then reported after the run, from the actual output.

## Text and vector content is never rasterized

The engine's compression re-encodes embedded raster images and repacks
streams. It does not convert pages to images, so text stays selectable and
searchable. Requirements.md 3.7's "never silently rasterize" holds by
construction here, not by our own restraint.
