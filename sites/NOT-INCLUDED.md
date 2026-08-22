# Platforms deliberately left out

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
