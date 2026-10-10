# Nifro Design

[简体中文](DESIGN.zh-Hans.md)

This document records the names, behaviour and visual rules that have been decided for Nifro's interface. Each entry cites the pull request, document or source file where it was decided. Questions that are still open stay out until they are decided. A pull request that changes the interface updates this file.

## 1. Glossary

| ID | Concept | English | 简体中文 | Do not use | Why |
|---|---|---|---|---|---|
| G1 | An ordered list of websites that a display selects | Playlist | 播放列表 | “Playlist” for the mechanism that moves a display between websites; that is rotation | The word named two things; the list is what a user calls a playlist (#62, #64) |
| G2 | A saved entry with its address and settings | Website | 网站 | — | Saved websites are kept distinct from the page currently shown (#123). The list keeps “网站” as its collective name even though it can hold local HTML files (G15, 2026-10-10 user decision) |
| G3 | What a display is showing now | Page | 网页 | “No Website” / 无网站 for a display with nothing selected | Same distinction; the empty state reads “No page selected” / 未选择网页 (#123) |
| G4 | Choosing which part of a page fills the wallpaper | Crop | 裁切 | Choose Region | Help text names the panel's Crop button (#40, #123) |
| G5 | Using the wallpaper page with the pointer and keyboard | Browsing Mode | 浏览模式 | browsing mode | Capitalised as a name (#123) |
| G6 | How a display moves between websites | Rotate in order; Rotate randomly; Keep this page displayed | 按顺序轮播；随机轮播；固定显示此页面 | Rotating in order; Rotating in shuffled order; Staying on this website / 固定在这个网站 | #123 |
| G7 | Switching a state | Turn … on or off | 打开或关闭… | Toggle … / 切换… | #123; Shortcuts follow it too (2026-10-10, decided by agent at the user's request) |
| G8 | Relaunching the app to apply a change | Restart | 重新启动 | Reopen / 重新打开 | #123 |
| G9 | Proposing a site for the gallery | Suggest a site… | 推荐网站… | Submit a Site… / 提交站点… | #123 |
| G12 | A website, in any wording that says “site” | Site | 网站 | 站点 | 2026-10-10 user decision |
| G13 | The curated list of wallpaper-ready sites | Site Gallery | 网站库 | 推荐站点 | 2026-10-10 user decision; 推荐 is kept for Suggest a site… (G9) |
| G14 | Loading a page again | Reload | 刷新 | 重新加载 | 2026-10-10 user decision |
| G10 | The display that holds the menu bar | Main Display | 主显示器 | — | The label and the behaviour mean the menu-bar display, never the screen with keyboard focus (#17) |
| G11 | The app | Nifro | Nifro | Plash as the app's own name, icon or artwork; the credit in About is the one mention | Nifro is an independent fork ([CONTRIBUTING](../.github/CONTRIBUTING.md)) |
| G15 | A local HTML file added to the list | Local Website… | 本地网页 | 本地网站 | 2026-10-10 user decision: 网页 can be a plain HTML file, 网站 has a live service behind it |

## 2. Product decisions

- **B1 Displays and playlists.** Each display selects a playlist and keeps its own current website, rotation mode, interval, on/off state and Browsing Mode. A duplicated playlist gets new website IDs, so crop, sign-in and page storage stay separate. See [Playlist design](PLAYLIST-REFACTOR.md) and the roadmap's Done section.
- **B2 Panel and Websites window.** The menu-bar panel has one column per display and controls displays; the Websites window edits website records. Website editing and shortcut configuration stay out of the panel (#21, roadmap `X12`–`X14`).
- **B3 One commit point in the panel.** Choosing a website is the only commit, and it writes the playlist and the website together. Choosing a playlist in the chooser changes only what the website chooser offers (#99).
- **B4 Random rotation.** A display rotating randomly deals a shuffled order: every website is shown before any is shown again, and each new order starts with the website already on screen (#99).
- **B5 Crop.** A region is stored as page position and magnification, not as fixed pixels, so it adapts to displays of other shapes (roadmap Done).
- **B6 Settings panes.** General holds the app's own affairs: launch, language, version and author. Behavior holds what the desktop shows. Shortcuts holds the keyboard shortcuts. Advanced holds the settings that can leave the app in a state its owner did not intend, and Restore All Settings last (#34, #69).
- **B7 Help text.** Each setting's explanation is one sentence that says what the user needs in order to keep or change the default. Restore All Settings is the exception: its labelled Reset and Kept lines guard an irreversible action (#40). The explanation opens from an ⓘ button beside the setting's name, and the tooltip remains ([`SettingHelp`](../Sources/Nifro/Screens/SettingHelp.swift)).
- **B8 Destructive actions.** They ask first and name the cost. Clear All Website Data says every website will be signed out and that websites and their settings are kept (#30). Deleting a website asks because the app has no Undo for it, and the confirming button names the action (#37). Restore All Settings makes Cancel the default button ([`RestoreDefaults`](../Sources/Nifro/App/RestoreDefaults.swift)).
- **B9 Languages.** English and Simplified Chinese. Untranslated text stays in English (README; the language setting's help text).

## 3. Visual design

- **A1 System and custom surfaces.** Settings, Websites, Add Website and Site Gallery use stock controls in grouped forms, which follow the accent colour, Increase Contrast, Reduce Transparency and VoiceOver (#73).
- **A2 Panel controls.** Stock bordered controls at the large control size. A control with a lit state is a toggle and lights in the user's accent colour; the app icon's orange is no longer a lit state. `accessoryBar` is not used, because it draws no bezel at rest over an arbitrary page (#73, #121).
- **A3 Panel surface.** The panel sits on the regular material and always draws its controls in the active appearance, including while Browsing Mode holds the keyboard (#73).
- **A4 Column metrics.** A column is 260 pt wide. The card behind it has a 12 pt radius and the picture inside it 8 pt; they are nested, so the radii differ on purpose. Controls in a row are 4 pt apart. Choosers size to their label up to a ceiling: three quarters of the column for the playlist chooser, seven eighths for the website chooser ([`PanelMetrics`](../Sources/Nifro/Screens/PanelControls.swift)).
- **A5 Column hover.** A quaternary fill and a 2 pt accent border, in both light and dark appearance (#29).
- **A6 Colour.** Captions and the panel's failure line use the secondary style, not red or the accent ([`DisplayPanel`](../Sources/Nifro/Screens/DisplayPanel.swift)). The confirming button of a destructive dialog is marked destructive (#30, [`RestoreDefaults`](../Sources/Nifro/App/RestoreDefaults.swift)).
- **A7 Crop overlay.** Black and white are contrast decisions against an arbitrary page; theme colours are the wrong answer there (#29, #73).
- **A8 Menu bar.** The colour band has no palette; its colour is sampled from the wallpaper. The icon is drawn dim when no wallpaper is showing and pulses while a page loads ([`AppState`](../Sources/Nifro/App/AppState.swift), #73).
- **A9 Symbols.** SF Symbols throughout ([`PanelControls`](../Sources/Nifro/Screens/PanelControls.swift)).
