# TextUI architecture

[Open the interactive English diagram](https://r3d42-git.github.io/R3DsTextUI/).

The page is a standalone Archify architecture viewer with light/dark themes,
search, pan/zoom, source references and export controls. It documents the native
editor, controller, preview, persistence and local integration boundaries.

## Source evidence

Source snapshot: `73adb159cf5579e12d25bb16bd4c21d1ea8dd4b3`.
All ten component references were verified against that commit and origin.
The JSON source is `architecture.json`; the published artifact is `../index.html`.
The arrows describe selected outbound operations, not every callback or return.
“Database” is Archify's storage category; TextUI uses files and JSON, not a database server.
Preview rendering includes Markdown and DokuWiki conversion plus HTML pass-through.
The confirmed-link path is coordinated by AppDelegate. The clipboard path uses
PreviewCodeCopy in an isolated WebKit content world.

Draft checkpointing is delayed by 350 ms; dependent UI refresh is delayed by
650 ms. Explicit Save checks the original byte baseline before an atomic write.
Optional autosave is disabled by default. Session recovery is local and does not
replace an external backup. These details are implementation evidence, not new
runtime acceptance tests.

## Verification

- Archify showcase: 9/9 checks, zero errors and zero warnings.
- Browser evidence: passed at 1440×900, 1600×1000, 1920×1080 and 2048×1320.
- Light/dark captures: both endpoint sizes; no horizontal or vertical overflow.
- Perceptual review: passed after inspection of the 1440×900 light and
  2048×1320 dark screenshots; clear routes, readable labels and balanced layout.
- Geometry correction rounds: 1 (two downward relationship labels).
- Viewer interaction and export workflows were not separately exercised.

`delivery.json` records exact specification and artifact SHA-256 digests.
`../index.visual-check.json` contains automated browser evidence; local machine
paths in the public receipts have been replaced with portable descriptions.
The automated receipt intentionally keeps `visualReview: pending`; the separate
perceptual review above does not overwrite the automated result.

## Regeneration

With Archify installed, run from the repository root (replace `$ARCHIFY` with
its installation directory):

```sh
node "$ARCHIFY/bin/archify.mjs" validate architecture docs/diagrams/architecture.json --quality showcase --repo-root . --json
node "$ARCHIFY/bin/archify.mjs" deliver architecture docs/diagrams/architecture.json docs/index.html --quality showcase --repo-root . --json
node "$ARCHIFY/bin/archify.mjs" visual-check docs/index.html --json
```

Update the pinned commit and evidence when changing the documented architecture.
Review new screenshots and remove local machine paths from public receipts.
GitHub Pages serves `/docs` from `main`; `.nojekyll` keeps the viewer unchanged.
