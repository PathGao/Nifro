# Site registry

A curated list of websites that work well as a desktop wallpaper.

Each `*.yml` file in this directory describes one website: where it lives, what it looks like, and
the settings Nifro should use for it. The app reads this registry to build its built-in gallery, so
adding a good site here is a one-click win for everyone who installs Nifro.

**This is the lowest-effort way to contribute to Nifro.** You do not need Swift, Xcode, or a Mac
build. You need a text editor and a website you like looking at.

The seed entries come from five years of people sharing their setups in
[Plash discussion #136](https://github.com/sindresorhus/Plash/discussions/136) and from the
use-cases and tips in the pre-close [Plash readme](https://github.com/sindresorhus/Plash#readme). Credit stays with them in each
entry's `source` field.

## Fields

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `name` | string | yes | Display name in the gallery. |
| `url` | string | yes | What Nifro loads. Include query parameters that are part of the setup (kiosk mode, transparent background, colours). |
| `description` | string | yes | One sentence describing what the user ends up staring at. |
| `tags` | string[] | yes | One or more of: `clock`, `weather`, `dashboard`, `art`, `data`, `calendar`, `ambient`, `photo`, `map`, `screensaver`, `news`, `personal`, `3d`. |
| `backend` | `snapshot` \| `live` | yes | See below. This is the field that matters most. |

> `backend` is recorded but not acted on at the moment. The two rendering backends were taken out
> so that the interaction could be got right first; the field stays because it is a true thing about
> the page and will be read again when they come back. See `docs/ROADMAP.md`.

| `backendNote` | string | no | Why you chose that backend, when it is not obvious. Write one for every `live` entry. |
| `reloadInterval` | integer | no | Seconds between reloads. For `snapshot` sites this is also how often the screenshot is retaken. Omit if the page refreshes itself. |
| `zoom` | `{centerX, centerY, scale}` | no | Fill the wallpaper with one part of the page. `centerX`/`centerY` are fractions of the page from its top-left; `scale` is how many times that part is enlarged. Given this way rather than as a rectangle so the entry works on any screen shape. |
| `css` | string | no | Custom CSS injected into the page. Usually hides chrome or makes the background transparent. |
| `js` | string | no | Custom JavaScript injected after load. |
| `audio` | `muted` \| `unmuted` | no | The sound setting the site **starts** with. Only a starting value: once added, the website belongs to the user and the Sound item in the menu owns this. Omit for muted, which is what a wallpaper wants unless it is a stream. |
| `requiresLogin` | boolean | no | `true` if the site shows nothing useful unless the user is signed in. |
| `screenshot` | string | no | Preview image. Leave it out — we will add images later. |
| `source` | string | yes | Where the entry came from. Credit the person, and link the upstream thread if you took their CSS or JS. |

### `backend`: the power switch

- **`snapshot`** — the page changes slowly. Nifro renders it, takes a picture, and suspends the web
  process. Between reloads the wallpaper costs about as much as a JPEG. Clocks, weather, calendars,
  dashboards, charts, photo feeds: all snapshot.
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
while Browsing Mode is on. Both also exist under their Plash names, so stylesheets written for Plash
keep working.

### `zoom` vs. `css`

Prefer `css` when the site gives you a selector to hide (`header { display: none }`). Reach for
`zoom` when it does not — when the clutter is baked into a canvas, an iframe, or an embed you cannot
select. Upstream discussed a JS approach for the same problem
([#139](https://github.com/sindresorhus/Plash/discussions/139)); `zoom` exists so you do not have to
paste a transform script into every entry.

## A complete entry

`sites/helvetictoc.yml`:

```yaml
name: Helvetictoc
url: http://www.helvetictoc.com/
description: A Helvetica word clock that spells out the time in prose.
tags: [clock]
backend: snapshot
reloadInterval: 60
css: |
  body.day, body.night {
    background-color: transparent;
    color: white
  }

  div.screen {
    margin: 4%;
    font-size: 100px !important;
    bottom: 0;
    top: auto;
  }

  #colophon { display: none }
source: >-
  tobie in upstream discussion #136; the CSS above is sindresorhus's reply in that same thread
  (transparent background, larger type, moved to the bottom, colophon hidden).
```

## Contributing an entry

1. **Try it first.** Put the URL in Nifro, live with it for a bit, and work out the settings — the
   query parameters, the CSS that hides the nav bar, the reload interval that is often enough
   without being wasteful. An entry nobody has actually used is worse than no entry.
2. **Write the file.** One site per file, named in kebab-case after `name`
   (`Polish TV Clock` → `polish-tv-clock.yml`). Copy the example above and edit it. Fill in `source`
   honestly, and credit whoever's CSS you borrowed.
3. **Open a pull request.** CI validates every file against [`schema.json`](schema.json). To check
   locally before pushing:

   ```sh
   pip install jsonschema pyyaml
   python3 -c "
   import json, glob, yaml, jsonschema
   v = jsonschema.Draft7Validator(json.load(open('sites/schema.json')))
   for f in sorted(glob.glob('sites/*.yml')):
       for e in v.iter_errors(yaml.safe_load(open(f))):
           print(f, list(e.path), e.message)
   "
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
