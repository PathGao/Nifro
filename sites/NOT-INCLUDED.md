# Sites deliberately left out

Two lists: platforms that were never added, and entries that were added, tried and taken out again.

## Platforms deliberately left out

Kept as a file rather than as silence, so the next person to ask "why is Douyin not in here"
gets an answer instead of adding it and finding out.

The filter is not popularity. It is whether the page works as a wallpaper in a plain web view:
a durable URL for one stream, viewable without an account, and a player that is the page rather
than a fallback for the app.

| Platform | Share of the Chinese live market | Why it is not here |
|---|---|---|
| Douyin | Largest | Heavy anti-automation on the web. Watching a room often demands a login or a challenge, and both land on a desktop nobody is looking at. |
| Xiaohongshu | Top ten | Live is effectively in-app. The web side has no stream page to point at. |
| TikTok Live | Largest outside China | Same as Douyin. Requires an account and the page is built to detect anything that is not the app. |
| Taobao Live | Second largest | Shopping streams are the opposite of ambient. A wallpaper that sells at you all day is not one anyone keeps. |
| Kuaishou | Third largest | The web player works, but the page needs enough CSS surgery to be worth its own contribution rather than a guess from us. |

If any of these change, the entry is a YAML file and a pull request. Reopening one of these
is welcome; reopening it with a working room URL and the CSS it needs is more welcome.

## Entries removed after they were tried

These nine shipped in the registry and were taken out again, each after being run as an actual
wallpaper. Recorded here rather than deleted quietly, so that the next person to submit one of them
gets the reason instead of rediscovering it — and so that a re-submission has something to beat.

Every one of them is welcome back with the fault fixed: a working URL, the CSS that stops it being
transparent, a stream that does not need an account. The bar is the same as for any other entry.

| Entry | Why it went |
|---|---|
| Douyu | The room URL no longer opens. Dead link. |
| Cocktails | Interactive, and about picking a drink rather than looking at one. Not a page anyone leaves up. |
| Gitstalk | The URL carried the maintainer's own username, so every user's wallpaper showed the maintainer's activity. An entry whose URL has to be edited before it means anything is not an entry. |
| Google Calendar | `requiresLogin` is not enough for it. The sign-in sheet comes up transparent over the wallpaper, and Browsing Mode cannot be reached to get through it. |
| Helvetictoc | Its CSS makes the page transparent, which on a wallpaper is a second layer over the desktop rather than a clock on a background. |
| Minimal Clock | Same fault, and here it was deliberate: `bg=transparent` was in the URL. What shows through is not what the entry assumed. |
| Polish TV Clock | Takes long enough to load that it hits the load timeout more often than not. |
| WebClock | Loads and draws nothing. |
| WebGL Fluid Simulation | Comes up almost entirely black without being stirred, and nothing stirs a wallpaper. |

Removing them takes the `clock` tag out of the gallery with them: all four clocks were in this list.
A clock that works is a wanted contribution, not an oversight.
