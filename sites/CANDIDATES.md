# Candidate sites

[简体中文](CANDIDATES.zh-Hans.md)

A pool of pages that look like they would work as wallpapers, kept as links because that is all
anyone has established about them yet.

The YAML files next to this one are a different kind of thing. **A YAML entry is a claim that
somebody made the page work**: which reload interval it needs, which rectangle of it is worth
showing, which three lines of CSS hide its navigation, whether it should keep rendering or be
photographed on a schedule. That is the work, and it is the part worth not doing twice. A link
cannot carry it and CI cannot check it.

So an entry graduates:

```
here          a URL and a sentence
  ↓           somebody works out its settings and checks they hold
<name>.yml    the settings, schema-checked, offered in the app gallery
  ↓           picked as one of the few worth shipping
featured      installed on first launch, then an ordinary website the user can edit or delete
```

Adding a link here is welcome and cheap. Graduating one is worth more.

---

Updated 2026-08-23. This file keeps only pages worth looking at as a wallpaper, or worth stepping into occasionally with the hold-to-interact key. Every link was checked with an HTTPS/redirect probe; pages whose anti-bot rules blocked the probe were opened in an isolated browser to confirm they still load. Dead links, certificate errors, challenge pages and refused requests have been dropped.

The bar comes from the entries this list started with — `Windy`, `World Monitor`, `Floor796`, `A Genealogy of Technology and Power since 1500`, `anime.js`: a page either makes a real system visible, or offers a space to wander around in, or keeps its motion restrained and alive.

## The state of the world

- [Windy](https://www.windy.com/?35.689,139.690,5) — Wind, cloud, waves, rain and flights layered over one globe. Collapse the sidebar and what is left is a world map that never stops changing.
- [Earth Nullschool](https://earth.nullschool.net/) — A dark globe of wind, ocean currents and temperature. Dense up close, still quiet from across the room.
- [Zoom Earth](https://zoom.earth/) — Satellite cloud imagery, radar and storm tracks, for a desktop that shows what the planet looks like from space right now.
- [Ventusky](https://www.ventusky.com/) — A weather map built around colour and switchable meteorological layers; the one to use if `Windy` does not look right.
- [World Monitor](https://worldmonitor.app/) — Conflict, disaster, markets, shipping, flights and news on one wall of world state.
- [LightningMaps.org](https://www.lightningmaps.org/) — A live lightning detection network, closer to the planet's own sensor feed than to a forecast.
- [Submarine Cable Map](https://www.submarinecablemap.com/) — Undersea cables, which show the internet as landing points, routes and geopolitical infrastructure.
- [The Internet Map](https://internet-map.net/) — Websites drawn as a star field by traffic and by what links to what, so the network becomes terrain you can look at directly.
- [FlightRadar24](https://www.flightradar24.com/) — Aircraft in the air, which is also a picture of where people are going.
- [MarineTraffic](https://www.marinetraffic.com/) — Ship tracks turn the ocean from blank blue into a logistics network at work.
- [Google Trends TV](https://trends.google.com/tv/?rows=4&cols=4) — A grid of trend feeds, for showing what people are paying attention to at this moment.

## Live cameras and windows onto somewhere real

> Only landmark and nature streams that their operators publish deliberately. Open the individual camera first and give Nifro that URL; the aggregator front pages carry navigation and ads.

- [WindowSwap](https://www.window-swap.com/) — Someone else's window, picked at random. Nothing asks anything of you, so the desktop just opens onto another place.
- [EarthCam](https://www.earthcam.com/) — A network of public streams from city landmarks, streets and construction sites.
- [SkylineWebcams](https://www.skylinewebcams.com/en.html) — High-definition public cameras on squares, coastlines, ski slopes and heritage sites.
- [Explore.org Live Cams](https://www.explore.org/livecams) — Nature streams of bears, eagles, walruses, reefs and reserves.
- [Cornell Lab Bird Cams](https://www.allaboutbirds.org/cams/) — Long-running public streams of nests, migration and chicks being raised.
- [Africam — Elephant Pan](https://africam.com/lodge/elephant-pan/) — A waterhole in the Khwai private reserve in Botswana; the page embeds a YouTube live stream, so it goes straight into Nifro.

## Long-form scenery and sound

> A long video is a different kind of virtual window: frame it as a landscape, then decide separately whether it should be heard. Check the page first, since YouTube playback and availability can change by region.

- [Norway Nature 4K](https://www.youtube.com/watch?v=vLHD66WehlE) — Fjords, islands and a slow aerial coast; a quiet Nordic window for a large display.
- [Antarctica 4K](https://www.youtube.com/watch?v=F09tnNH2SvY) — Ice, sea and mountain scale, with a much colder and sparer visual field.
- [Lofi Girl — beats to relax/study to](https://www.youtube.com/watch?v=jfKfPfyJRdk) — The familiar 24/7 lo-fi room; turn on Nifro's per-site audio only when the desktop should also be a listening space.

## Digital spaces

- [Floor796](https://floor796.com/) — A pixel building under permanent construction, less a picture than a city you can walk into whenever you feel like it.
- [Zoomquilt](https://zoomquilt.org/) — A collaborative painting that zooms forward forever. Every move lands in another dream, and there is no UI in the way.
- [Slow Roads](https://slowroads.io/) — Generated road, terrain and weather; left alone it is a slow driving film.
- [Akirodic — Jellyfish](https://akirodic.com/p/jellyfish/) — A small aquarium with something alive in it, suited to a dark desktop.
- [After Dark CSS](https://www.bryanbraun.com/after-dark-css/) — The old Mac screensavers rebuilt in CSS: cheap to run, and a record of what screens used to do.

## Graphics and animation

- [Pavel DoGreat — WebGL Fluid Simulation](https://paveldogreat.github.io/WebGL-Fluid-Simulation/) — Left alone it is colour in motion; hold the Nifro key when you want to stir it.
- [Mr.doob Lab — Clouds](https://mrdoob.com/lab/javascript/webgl/clouds/) — An early WebGL cloud field, quiet and content to sit behind the windows in front of it.
- [Flat Surface Shader](https://matthew.wagerfield.com/flat-surface-shader/) — A low-poly surface lit by the pointer, restrained in both colour and movement.
- [Patatap](https://patatap.com/) — Keys trigger sounds and shapes; untouched, the screen stays plain, which makes it a page for occasional interaction.

## Maps, infrastructure and time

- [Starlink Map](https://www.starlink.com/map) — Low-orbit satellites and their coverage.
- [Satellite Map](https://satellitemap.space/) — Where satellites in low orbit are right now.
- [OpenSky Network](https://opensky-network.org/network/explorer) — A live view built on open air-traffic data.
- [ADS-B Exchange Globe](https://globe.adsbexchange.com/) — Denser global flight tracks.
- [Global Fishing Watch](https://globalfishingwatch.org/map/) — Fishing vessel activity and ocean governance.
- [NASA Worldview](https://worldview.earthdata.nasa.gov/) — Stackable layers of satellite observation of the Earth.
- [NASA Eyes](https://eyes.nasa.gov/) — Planets, missions and spacecraft trajectories.
- [USGS Earthquake Map](https://earthquake.usgs.gov/earthquakes/map/) — Earthquakes worldwide, as they are recorded.
- [VolcanoDiscovery](https://www.volcanodiscovery.com/earthquakes/today.html) — A map of earthquake and volcanic activity.
- [SpaceWeatherLive](https://www.spaceweatherlive.com/en/auroral-activity/auroral-oval.html) — The auroral oval and space weather.
- [NOAA Aurora Forecast](https://www.swpc.noaa.gov/products/aurora-30-minute-forecast) — The 30-minute aurora forecast map.
- [NASA FIRMS](https://firms.modaps.eosdis.nasa.gov/map/) — Global heat sources and wildfire observations.
- [Global Forest Watch](https://www.globalforestwatch.org/map/) — The Earth seen by how its forests are changing.
- [LiveUAMap](https://liveuamap.com/) — Geopolitical events placed on a map.
- [Earth Clock](https://earthclock.cwandt.com/) — A minimal view of Earth time and daylight.
- [GeaCron](https://geacron.com/home-en/) — Historical borders redrawn as the year moves.
- [Old Maps Online](https://www.oldmapsonline.org/en/) — Historical maps laid over today's.
- [MapCrunch](https://www.mapcrunch.com/) — Dropped into a random Street View location.
- [Radio Garden](https://radio.garden/) — The world's radio stations spread over a globe you can spin.
- [AirPano](https://www.airpano.com/) — High-quality 360° tours of places.

## Environments, places and wandering

- [Webcam Taxi](https://www.webcamtaxi.com/) — A directory of city and nature cameras around the world.
- [EarthTV](https://www.earthtv.com/) — Public live views of cities.
- [Monterey Bay Aquarium Live Cams](https://www.montereybayaquarium.org/animals/live-cams) — Jellyfish, sea otters and the bay itself.
- [Aquarium of the Pacific Webcams](https://www.aquariumofpacific.org/exhibits/webcams) — A live window into the tanks.
- [Drive & Listen](https://driveandlisten.com/) — Drive through a city with its local radio playing.
- [360Cities](https://www.360cities.net/) — Panoramas from everywhere, uploaded by the people who shot them.
- [Google Arts & Culture](https://artsandculture.google.com/) — A way into art, culture and machine-learning experiments.
- [The Useless Web](https://theuselessweb.com/) — Dropped into a random strange page.
- [Pixel Thoughts](https://www.pixelthoughts.co/) — Put a thought into a slowly expanding universe.
- [This Person Does Not Exist](https://thispersondoesnotexist.com/) — A generated face, worth a short look rather than a whole day.

## Net art and strange pages

- [Jackson Pollock](https://www.jacksonpollock.org/) — Digital drip painting you throw paint at yourself.
- [Pointer Pointer](https://pointerpointer.com/) — Wherever the cursor is, a photo of someone pointing at it.
- [OMFGDOGS](https://www.omfgdogs.com/) — Early-web glee, undiluted.
- [Cat Bounce](https://cat-bounce.com/) — Bouncing cats, at desktop scale.
- [RRRGGGBBB](https://www.rrrgggbbb.com/) — A minimal toy driven by RGB and the pointer.
- [ZomboCom](https://zombo.com/) — The early web's you-can-do-anything speech, looping forever.
- [Click Click Click](https://clickclickclick.click/) — Every click gets noticed by the page.
- [Superbad](https://www.superbad.com/) — A maze-like relic of early Flash and web art.
- [JODI](https://wwwwwwwww.jodi.org/) — Classic net.art, deliberately making the browser look like a machine coming apart.
- [Falling Falling](https://www.fallingfalling.com/) — A gradient between two kinds of endless falling.
- [The Deep Sea](https://neal.fun/deep-sea/) — Descending far enough to rebuild your sense of scale.
- [Internet Artifacts](https://neal.fun/internet-artifacts/) — A display case of internet forms that no longer exist.
- [The Size of Space](https://neal.fun/size-of-space/) — From a human body out to the universe.
- [Neal.fun](https://neal.fun/) — A set of interactive pieces worth leaving up and stepping into.
- [A Soft Murmur](https://asoftmurmur.com/) — Rain, wind, fire and cafe noise, mixed to taste.
- [Noisli](https://www.noisli.com/) — Ambient sound over plain blocks of colour.
- [Nyan Cat](https://www.nyan.cat/) — The web totem that never stops flying.
- [The Museum of Modern Art Collection](https://www.moma.org/collection/) — Contemporary art entered one work at a time.

## Web experiments you can step into

- [anime.js](https://animejs.com/) — The reference point for web motion design and timeline control.
- [Three.js Examples](https://threejs.org/examples/) — A large live specimen collection of 3D in the browser.
- [p5.js Editor](https://editor.p5js.org/) — Light creative coding with the sketch running as you type.
- [OpenProcessing](https://openprocessing.org/discover/) — A feed of p5.js and Processing work.
- [ShaderToy](https://www.shadertoy.com/) — A universe of shaders that run where they sit.
- [Cables](https://cables.gl/) — Node-based WebGL and the pieces built with it.
- [CodePen](https://codepen.io/) — A live showcase of small front-end experiments.
- [Dwitter](https://www.dwitter.net/top/month) — JavaScript animations in 140 characters.
- [Chrome Experiments](https://experiments.withgoogle.com/collection/chrome) — Google's collection of browser-native experiments.
- [Chrome Music Lab](https://musiclab.chromeexperiments.com/) — Sound, rhythm and visualisation to play with.
- [Quick, Draw!](https://quickdraw.withgoogle.com/) — Draw something and a model guesses it back at once.
- [Teachable Machine](https://teachablemachine.withgoogle.com/) — Train a small model with the webcam.
- [Sampulator](https://sampulator.com/) — A keyboard sampler and sound collage.
- [Incredibox](https://www.incredibox.com/) — Vocal rhythms arranged on screen.
- [Line Rider](https://www.linerider.com/) — Draw a line and let the physics perform it.
- [Loopy](https://ncase.me/loopy/) — Draw a feedback system out of arrows and nodes.
- [The Evolution of Trust](https://ncase.me/trust/) — Cooperation and betrayal, worked out as a game.
- [The Wisdom and/or Madness of Crowds](https://ncase.me/crowds/) — Crowds, contagion and tipping points.
- [Parable of the Polygons](https://ncase.me/polygons/) — How individual preferences turn into segregation.
- [How to Simulate the Universe](https://ncase.me/simulating/) — What a simulation has to do with the thing it simulates.
- [World's Biggest Pac-Man](https://worldsbiggestpacman.com/) — A maze map that players keep joining onto.
- [A Dark Room](https://adarkroom.doublespeakgames.com/) — A bare text interface that grows into a world.
- [Universal Paperclips](https://www.decisionproblem.com/paperclips/) — A minimal parable of automation, optimisation and growth getting away from itself.
- [Cookie Clicker](https://orteil.dashnet.org/cookieclicker/) — Another growth machine, worth checking back on now and then.

## Technology, power and the memory of the web

- [Calculating Empires](https://calculatingempires.net/) — *A Genealogy of Technology and Power since 1500*: a long timeline of technology, capital, colonialism and infrastructure, drawn as art.
- [Wayback Machine](https://archive.org/web/) — Put a site back into an older version of itself and look at it.
- [OldWeb.Today](https://oldweb.today/) — Old pages through the browsers of their time.
- [The History of the Web](https://thehistoryoftheweb.com/) — A timeline of web technology and web culture.
- [Web Design Museum](https://www.webdesignmuseum.org/) — An archive of interface history and of how web pages looked.
- [Internet Archive](https://archive.org/) — The public memory of books, audio, film, software and web pages.
- [Public Domain Review](https://publicdomainreview.org/) — Old images, maps and odd texts, carefully curated.
- [Low-tech Magazine](https://solar.lowtechmagazine.com/) — A magazine about energy, maintenance and low technology whose own server is part of the work.
- [Software Library](https://archive.org/details/softwarelibrary) — Old software and games that run in the page.
- [DiscMaster](https://discmaster.textfiles.com/) — Search old CD-ROMs for forgotten digital publications.
- [Rhizome](https://rhizome.org/) — Digital art, software preservation and network culture.
- [Are.na](https://www.are.na/) — Research cards and how one person's material connects up.
- [Neocities Browse](https://neocities.org/browse) — The personal-homepage ecosystem, still growing.
- [Histography](https://histography.io/) — A zoomable timeline of historical events.
- [The Pudding](https://pudding.cool/) — Essays where the data, the interaction and the story are one thing.
- [Information Is Beautiful](https://informationisbeautiful.net/) — A library of data graphics and visual storytelling.
- [Institute of Network Cultures](https://networkcultures.org/) — Research on network culture, platforms and digital publishing.
- [The HTML Review](https://thehtml.review/) — An annual journal that treats the web page as a literary and interactive medium.
- [Wiby](https://wiby.me/) — A search engine that prefers old, personal pages.
- [The Old Net](https://theoldnet.com/) — The old web through today's browser.
- [Computer History Museum](https://www.computerhistory.org/) — A way into the history of computing and the internet.

## Using these

1. Open a page in a browser and check how it looks first, then paste that URL into Nifro.
2. For live streams, use the individual camera page rather than a search page, a login prompt or an ad-heavy index.
3. Animation and live maps use the GPU; if the machine runs hot, drops frames or keeps its fans up, switch to `WindowSwap`, `After Dark CSS`, `Mr.doob Clouds` or a single camera stream.
