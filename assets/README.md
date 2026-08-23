# assets

Images the repository itself uses. Nothing here ships inside the app — the app's own icons live in
`Nifro/Assets.xcassets`.

| File | Where it is used | How it gets there |
| --- | --- | --- |
| `icon.png` | The heading of both READMEs | Exported from `Nifro/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png` |
| `icon-256.png` | Spare, for anywhere 1024px is too much | Downscaled from `icon.png` |
| `social-preview.png` | The card GitHub shows when a link to this repository is pasted anywhere | **Uploaded by hand.** Settings → General → Social preview. GitHub has no API for it |

The social preview is 1280×640, which is what GitHub crops to. A repository with none falls back to
the owner's avatar and the repository name, which is the same card every project of theirs gets.
