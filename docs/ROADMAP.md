# Nifro Roadmap

[简体中文](ROADMAP.zh-Hans.md)

Nifro makes a web page part of the desktop. This roadmap separates hypotheses needing evidence from work ready to build, records the decisions that shape the current app, and keeps rejected directions from returning as new proposals. Legacy labels such as `P`, `L1`, and `K7` remain as indexes for code comments and older design notes.

## Trying

### Lower idle-wallpaper cost (`P`)

Nifro renders until disabled, locked, or configured to pause on battery. The old power subsystem was removed because its rendering backends, occlusion checks, and still-image detection all also answered “what is rendering now”, which Browsing Mode changes too. Any replacement needs a measurement of a covered idle wallpaper, exactly one owner of rendering state, and an explicit, reversible off switch. It must beat the present baseline in its target state.

### HDR and real multi-display hardware (`K7`, `D4`, `D6`)

No code or entitlement handles HDR. A real HDR source and end-to-end hardware measurement come before a design. Also validate a display without a menu bar and a pair with different sizes and backing scales; the remaining risk is OS geometry and pixels.

### Shared rendering across displays (`V3`)

The old sync feature was removed because independent pages, clocks, and controls drifted into conflicting states. A probe showed `SCShareableContent` can capture Nifro’s own desktop-level windows without Screen Recording permission. This remains an experiment: only one-shot capture was measured; continuous `SCStream`, colour management, independent crops, follower interaction, and differing layouts remain open. See [the shelved design](shelved/MULTI-DISPLAY-SYNC.md).

## Planned

### Desktop blocks (`L1`–`L4`)

Let maps, dashboards, and small live pages occupy part of a desktop. Use free placement plus a snap grid, stored as fractions. A block is the window’s base frame; visibility may shrink within it, never redefine it. Every block needs its own web process and data store, and it is placed through the wallpaper rather than a title-bar window.

### Page state, panel, and media (`M3`, `M5`, `M6`, `W1`–`W5`, `V1`–`V5`)

Nifro remembers its own settings; sites remember their own state. URL fragments and scroll can sometimes restore position, while Floor796-like pages may not restore their internal zoom. A per-website in-session `WKWebView` cache is possible if it preserves isolation.

Complete the panel with enable, reload, immediate random selection, safe address saving, and old-menu cleanup. The panel controls a **display**; the Websites window edits a **record**. Media controls require a per-page reporter first. GIFs need a full-resolution capture path, bounded memory, and a hard stop.

### Catalogue, reliability, and release (`S1`, `K1`, `K6`, `E23`, `E25`, `U2`)

Review featured sites first. Bilibili sign-in and YouTube playback are separate problems; YouTube’s measured `Referer` solution stays held while WebKit element fullscreen can damage the Dock (`K40`). Review help text, create versioned settings migrations, run or remove inactive SwiftLint analyzer rules, enable release immutability, and defer Sparkle until its permanent signing and installer commitments are justified.

## Done

- **Playlists and independent displays:** displays select playlists; copied playlists use new IDs, isolating crop and sign-in state.
- **Per-display state:** loading failures, switched-off state, and Browsing Mode are keyed by display; the panel reads its owning scene.
- **Crop:** page position and magnification, rather than fixed pixels, adapt a chosen region across display shapes.
- **Display-first panel:** one column per display shows that display’s page, state, errors, and controls.
- **Reliability:** intended reloads reuse pages; thumbnail cleanup shares the data-store sweep; hidden panels stop snapshotting; older website data still decodes.
- **Build and release:** stable local signing preserves sandbox and bookmarks; releases are per architecture through GitHub Releases and Homebrew.

## Not Do

- **No engine or framework rewrite (`X1`–`X4`):** the problem is scheduling and AppKit window behaviour, not a missing web engine, generator, DI container, or plugin system.
- **No high-risk or static substitute (`X7`–`X11`):** camera/screen input crosses an unjustified permission boundary; static desktop images remove live interaction; Chrome windows have no public desktop-layer API; opaque pages and configurable reloads lack measured value.
- **No panel duplication (`X12`–`X14`):** the current localisation system is sufficient; website editing and shortcut configuration belong outside a display-control panel.
- **Keep reviewed mechanisms:** transparent `WKWebView` KVC, `NSStatusItem` + `NSPopover`, `ScrollableTextView`, security-scoped bookmarks, image caching, icon fetching, and the 80 ms preview loop all have concrete API or behaviour reasons to remain.
- **Platform boundary (`K40`):** element fullscreen remains disabled because it can destroy the Dock window in this accessory-app configuration, with no app-side mitigation.

