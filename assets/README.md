# assets

Images the repository itself uses. Nothing here ships inside the app — the app's own icons live in
`Nifro/Assets.xcassets`.

| File | Where it is used | How it gets there |
| --- | --- | --- |
| `icon.png` | Nothing references it. Kept as the full-size original, for anywhere 256px is too small | Exported from `Nifro/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png` |
| `icon-256.png` | The heading of both READMEs | Downscaled from `icon.png` |
| `nifro-icon-256.png` | The heading of both READMEs | Rendered from the checked-in `Nifro/Nifro.icon` source |
| `menu-bar-icon-legacy-2026-08-30.svg` | Nothing references it. Kept as Nifro's original menu bar acorn icon | Restored from the revision immediately before the menu bar icon was first redrawn for Nifro |

There is no social preview here any more. Several uploads through Settings → General were accepted
by the page and stored a broken reference: the repository's `og:image` points at
`repository-images.githubusercontent.com/…` and that URL answers 404, so every link preview came out
blank. Formats were not the problem — it was tried at 2560×1280 16-bit and at 1280×640 8-bit RGB,
GitHub's own recommended shape, and both ended the same way. There is no API for this setting, so
there is nothing here to fix or automate; a blank card and no card look about the same, and no card
costs nothing to maintain. Worth another try if GitHub's uploader starts working.
