import Foundation

/**
A named list of websites, and which display may offer it.

The inversion this type exists for. A website carries the display it belongs to, so the screen shows
whatever names it. Which displays get a wallpaper at all no longer follows from those fields —
`rebuildScenes` builds one scene per attached display — but *what* a display may show still does:
`eligible(for:)` filters the whole list by `effectiveDisplay`, so a display no website names has a
scene with nothing in it. Here the screen picks a list instead, and the list is a thing the user can
name, reorder and duplicate.

Nothing reads this yet, and it is filled ahead of its readers on purpose. What fills it runs once
against a list the user built by hand, and there is no undoing a migration that ran wrong. Landing the
model and the migration on their own is what makes it possible to look at what was written before
anything depends on it.
*/
struct Playlist: Hashable, Codable, Identifiable, Sendable, Defaults.Serializable {
	// `let`, for the reason `Website.id` gives at more length: an id is what other things file
	// themselves under, so changing one orphans whatever did.
	let id: UUID

	var name: String

	/**
	The websites in this playlist, as bodies rather than as ids into one shared list.

	The case that decides it: duplicate a playlist, bind each copy to a different display, and give the
	same site a different crop on each screen. A crop is `Website.zoom`, and it is stored on the
	website — as are `css`, `javaScript`, `invertColors2`, `usePrintStyles`, `audio` and
	`reloadInterval`. Under a list of ids, every copy shares all seven, so the one thing duplication is
	for is the one thing it could not do.

	It follows that duplicating a playlist is a deep copy: new `Website` values with new ids. That also
	settles what renaming or editing a copy needs, which is nothing — the copy's members are separate
	objects from the moment they exist, so there is no pair of things to keep in step.
	*/
	var websites: [Website]

	/**
	Which display may offer this playlist in its picker. `nil` is every display, and is the default.

	A binding filters a picker and does nothing else. It is not applied, not preferred and never
	consulted while a wallpaper is up, so two playlists bound to one display do not conflict — both
	are offered there and the user picks one. That is also what makes an unplugged display answer
	itself rather than needing a rule: a picker exists only for a display that is attached, so a
	playlist bound to a display that is gone is offered nowhere, and there is nothing to fall back to
	and no new default to choose.

	`private(set)` because of `isDefault` below. The only write is through this type's own initializer,
	which is what stops the refusal being gone around by a caller who has not read the argument for it.
	*/
	private(set) var boundDisplay: DisplayBinding?

	/**
	Whether this is the one playlist that cannot be bound to a display.

	Every playlist being bound to some display is a state ordinary use reaches — bind them one at a
	time until none are left over — and it leaves any display that got none with an empty picker:
	nothing to select, nothing on the screen, and no way back out from the panel. Keeping one playlist
	that every picker offers is the cheapest guard against that, and it buys the guard with no runtime
	check anywhere: a binding handed to the initializer for this playlist is dropped, and the
	management page draws the display option disabled.

	A stored flag rather than "the first one in the list", because the list is reordered by dragging and
	that ordering is ordering, not precedence.
	*/
	let isDefault: Bool

	init(
		id: UUID = UUID(),
		name: String,
		websites: [Website],
		boundDisplay: DisplayBinding? = nil,
		isDefault: Bool = false
	) {
		self.id = id
		self.name = name
		self.websites = websites
		self.isDefault = isDefault
		self.boundDisplay = isDefault ? nil : boundDisplay
	}
}

/**
The display a playlist is bound to, and the name that display had at the time.

The name is a snapshot rather than something resolved on each read, which is the whole reason this is
a type and not a `Display`. `Display.localizedName` resolves through `NSScreen.screens` and answers
`<Unknown name>` for a display that is not attached — and a binding is most worth seeing exactly when
its display is missing, because that is when the user is looking for the thing they cannot find.
Resolved live, the management page would show them a row called `<Unknown name>` and offer to unbind
it.
*/
struct DisplayBinding: Hashable, Codable, Sendable {
	let id: UUID
	let nameWhenBound: String
}

extension Playlist {
	/**
	What the one playlist every display falls back to is called.

	A computed property and not a stored `let`, so it follows a language change in the same launch
	rather than answering with whatever the language was the first time anything asked. Written once
	here because two places name it — the migration that makes it and the add that has to find or
	remake it — and a list called "Default" in one and something else in the other is two default
	playlists.
	*/
	static var defaultName: String { String(localized: "Default") }

	/**
	Bind this playlist to a display, or to none.

	The refusal that `isDefault` argues for, stated a second time because there are two ways in. The
	initializer drops a binding handed to the default playlist, and that covers the migration and the
	copy; this covers the management page, where the user picks a display from a menu. `boundDisplay`
	is `private(set)` so that these two are the only ways in, and the menu item is disabled as well —
	a control the user cannot reach is the honest version, and this is what makes reaching it anyway
	harmless.
	*/
	mutating func bind(to display: DisplayBinding?) {
		guard !isDefault else {
			return
		}

		boundDisplay = display
	}

	/**
	A copy of this playlist, with its own websites.

	`withFreshIDs` is the whole of what makes it a copy rather than a second name for the same thing;
	the argument for it is over that function. The other three differences are decisions rather than
	mechanism:

	- **It starts on no display.** Duplicating a bound playlist would otherwise put a second entry with
	the same name in that display's picker, which nobody asked for, and the case duplication is for is
	"copy the default twice, then bind each" — where the binding is the step the user is about to take
	themselves.
	- **It is not the default.** There is exactly one playlist every display falls back to, and copying
	it would make the fallback ambiguous the moment the two lists differ.
	- **It is named rather than numbered.** Finder's word, because this is Finder's gesture.
	*/
	func duplicated() -> Self {
		Self(
			name: String(localized: "\(name) copy"),
			websites: withFreshIDs(websites, id: \.id)
		)
	}
}
