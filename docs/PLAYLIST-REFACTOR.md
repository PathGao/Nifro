# Playlist design

Implemented in the current baseline (0.9.1). This describes the stored model and
runtime behavior, not a pending refactor.

## Ownership and display state

A `Playlist` owns its `Website` values. Each display selects a playlist and keeps
its own website cursor. Rotation mode, interval, power and browsing state also
belong to the display.

```text
Playlist → Website values (settings and independent IDs)
Display  → selected Playlist.ID + current Website.ID
```

`WebsitesController.playlist(for:in:)` falls back to the default playlist when a
selection is missing or refers to a deleted playlist. An empty library can still
have no playlist to show.

The stored cursor records what was requested. `WallpaperScene.website` resolves
that request against available, scheduled websites. `loadedWebsiteID` records
what the web view has actually loaded. These can differ during a page change.

## Binding and duplication

A playlist's `boundDisplay` filters the picker. It does not move content or force
a runtime selection. The saved display name remains readable while unplugged.
The default playlist refuses a binding so every display can select it.

Duplication creates a new playlist and new website IDs, starts unbound, and clears
the default flag. Settings are copied, but login sessions, page storage and saved
positions are independent because they are keyed by website ID.

## Startup and rotation

Attached displays own wallpaper scenes. On first installation, featured websites
are added to the default playlist and assigned to displays in order, main display
first. This sets the cursor without binding a website to a display.

`RotationBehaviour` resolves eligible websites from the selected playlist and its
schedule. Per-display cursors and shuffled orders keep navigation independent.
Unplugging a display leaves its stored selection available for reconnection.

## Storage boundary

`Defaults.playlists` is the source of website storage. The earlier flat-list
conversion and display-pinning migration have been removed from this baseline.
The historical migration proposal is not an implemented upgrade guarantee.

See `Sources/Nifro/Sites/Playlist.swift`, `WebsitesController.swift`, and
`RotationBehaviour.swift` for the implementation. `Tests/PlaylistRulesTests.swift`
checks that copied members receive fresh identities.
