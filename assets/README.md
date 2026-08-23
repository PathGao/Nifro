# assets

Images the repository itself uses. Nothing here ships inside the app — the app's own icons live in
`Nifro/Assets.xcassets`.

| File | Where it is used | How it gets there |
| --- | --- | --- |
| `icon.png` | The heading of both READMEs | Exported from `Nifro/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png` |
| `icon-256.png` | Spare, for anywhere 1024px is too much | Downscaled from `icon.png` |

There is no social preview here any more. Several uploads through Settings → General were accepted
by the page and stored a broken reference: the repository's `og:image` points at
`repository-images.githubusercontent.com/…` and that URL answers 404, so every link preview came out
blank. Formats were not the problem — it was tried at 2560×1280 16-bit and at 1280×640 8-bit RGB,
GitHub's own recommended shape, and both ended the same way. There is no API for this setting, so
there is nothing here to fix or automate; a blank card and no card look about the same, and no card
costs nothing to maintain. Worth another try if GitHub's uploader starts working.
