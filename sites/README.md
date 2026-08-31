# Site registry

A curated list of websites that work well as a desktop wallpaper.

Each `*.yml` file in this directory describes one website: where it lives, what it looks like, and
the settings Nifro should use for it. The app reads this registry to build its built-in gallery, so
adding a good site here is a one-click win for everyone who installs Nifro.

**This is the lowest-effort way to contribute to Nifro.** You do not need Swift, Xcode, or a Mac
build. You need a text editor and a website you like looking at.

The seed entries are the maintainer's own shortlist: pages that have been run as a wallpaper long
enough to know how they behave.

## Fields

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `name` | string | yes | Display name in the gallery. |
| `url` | string | yes | What Nifro loads. Include query parameters that are part of the setup (kiosk mode, transparent background, colours). |
| `description` | string | yes | One sentence describing what the user ends up staring at. |
| `tags` | string[] | yes | One or more of: `3d`, `ambient`, `art`, `calendar`, `clock`, `dashboard`, `data`, `gaming`, `live`, `map`, `music`, `nature`, `news`, `personal`, `photo`, `screensaver`, `space`, `weather`. [`schema.json`](schema.json) is the list that is enforced; this table follows it. |
| `backend` | `snapshot` \| `live` | yes | Recorded, not acted on. See below. |
| `backendNote` | string | no | Why you chose that backend, when it is not obvious. Write one for every `live` entry. |
| `reloadInterval` | integer | no | Seconds between reloads. Omit if the page refreshes itself. |
| `zoom` | `{centerX, centerY, scale}` | no | Fill the wallpaper with one part of the page. `centerX`/`centerY` are fractions of the page from its top-left; `scale` is how many times that part is enlarged. Given this way rather than as a rectangle so the entry works on any screen shape. |
| `css` | string | no | Custom CSS injected into the page. Usually hides chrome or makes the background transparent. |
| `js` | string | no | Custom JavaScript injected after load. |
| `audio` | `muted` \| `unmuted` | no | The sound setting the site **starts** with. Only a starting value: once added, the website belongs to the user and the Sound item in the menu owns this. Omit for muted, which is what a wallpaper wants unless it is a stream. |
| `requiresLogin` | boolean | no | `true` if the site shows nothing useful unless the user is signed in. |
| `screenshot` | string | no | Preview image. Leave it out — we will add images later. |
| `featured` | integer | no | Where the entry sits in the list the app ships with, counting from 1. Omit it and the entry does not ship. A number rather than `true` because the order is the decision: rank 1 is the wallpaper somebody sees before they have chosen anything, and on a second display they see rank 2. Ranks must be unique — `Tools/validate-sites.py` rejects a duplicate. Keep the list very short: every featured entry is one a new user has to delete if they do not want it. Eight entries carry it today; adding a ninth needs a reason, and a rank. |
| `source` | string | yes | Where the entry came from, plus anything a reader needs to adapt it: which part of the URL to swap, why a flag is there, what goes stale. |

### `backend`: what the page needs

**Nothing reads this field today.** The two rendering backends were built and then taken out, so that
the interaction could be got right first, and nothing in the app currently branches on `backend`. It
stays in the schema and stays required because it records something true about the page that only
somebody who has watched it can tell you, and re-deriving it later for every entry would be worse than
carrying it. It will be read again when the backends come back. See `docs/ROADMAP.md`.

So answer it for the page, not for what the app does with it:

- **`snapshot`** — the page changes slowly, and a still frame taken every so often would lose nothing.
  Clocks, weather, calendars, dashboards, charts, photo feeds: all snapshot.
- **`live`** — the page has to keep rendering, because animation or interaction *is* the content.
  Screensavers, WebGL scenes, simulations, auto-advancing presentations.

**Default to `snapshot`.** Only reach for `live` when a still frame would destroy the point of the
site, and say why in `backendNote`. A clock that ticks in seconds is not a reason — drop the seconds
and reload every 60s instead.

### What the page is laid out at

The page gets the size of the wallpaper — the screen without the menu bar strip — so `100vw`,
`100vh` and `@media (min-aspect-ratio: …)` all refer to that area. Write for the ratio rather than
for one screen: an entry framed on a 16:10 laptop is going to be opened on a 16:9 monitor.

`zoom` does not change any of this. It is the web view's own magnification, and the page is
deliberately never told about it — if the layout changed when the region was framed, the part that
was framed would stop being the part that shows.

Two classes are on `<html>` for CSS to target: `is-nifro-app` always, and `nifro-is-browsing-mode`
while Browsing Mode is on.

### `zoom` vs. `css`

Prefer `css` when the site gives you a selector to hide (`header { display: none }`). Reach for
`zoom` when it does not — when the clutter is baked into a canvas, an iframe, or an embed you cannot
select. `zoom` exists so you do not have to paste a transform script into every entry.

## A complete entry

`sites/infinitown.yml`:

```yaml
name: Infinitown
url: https://demos.littleworkshop.fr/infinitown
description: An endlessly scrolling low-poly town with cars and trees, seen from above.
tags: [art, ambient, 3d, screensaver]
backend: live
backendNote: A continuously animating 3D scene.
css: |
  #about-button {
    display: none;
  }
source: The maintainer's own shortlist. The CSS above hides the about button.
```

It carries no `reloadInterval`, because the page never stops moving and has nothing to fetch again.
An entry that shows a reading — a forecast, a calendar, a chart — needs one.

## Contributing an entry

1. **Try it first.** Put the URL in Nifro, live with it for a bit, and work out the settings — the
   query parameters, the CSS that hides the nav bar, the reload interval that is often enough
   without being wasteful. An entry nobody has actually used is worse than no entry.
2. **Write the file.** One site per file, named in kebab-case after `name`
   (`Random Street View` → `random-street-view.yml`). Copy the example above and edit it. Fill in `source`
   honestly, and credit whoever's CSS you borrowed.
3. **Open a pull request.** CI validates every file against [`schema.json`](schema.json). To check
   locally before pushing, run the same script CI runs — see [`../Tools/README.md`](../Tools/README.md)
   for the dependencies:

   ```sh
   python3 Tools/validate-sites.py
   ```

### What gets merged

- The site is publicly reachable and still works. Dead links and abandoned demos get rejected.
- It looks good behind icons and windows, at wallpaper size, for more than ten seconds.
- `backend` is honest. If you marked it `live`, `backendNote` says why.
- No login walls without `requiresLogin: true`, and nothing that needs an API key pasted into the URL.
- No ads, no trackers you would not want running for eight hours a day, no autoplaying audio.

## Generated files

`index.json` and `../Nifro/Sites/SiteCatalog.generated.swift` are produced from the YAML
files here by `Tools/generate-site-catalog.py`. Do not edit them by hand.

The app reads `index.json` straight from this branch, so an entry merged here shows
up in the in-app gallery without waiting for a release. The Swift file is the copy
compiled into the app, used when there is no network.

```sh
python3 Tools/generate-site-catalog.py
```

CI fails if the YAML and the generated files disagree.

## Platforms we left out

`NOT-INCLUDED.md` records the live platforms that were considered and rejected, with the reason
for each. Popularity is not the filter; working in a plain web view without an account is.

## Candidates

`CANDIDATES.md` is a pool of pages that look promising but that nobody has worked out the settings
for yet. Moving one from there to a YAML file here is the contribution that carries weight.
