import Foundation

/**
A named list of websites, and which display may offer it.

The inversion this type exists for. A website carries the display it belongs to, so the screen shows
whatever names it — and `displaysInUse`, which decides whether a display gets a wallpaper at all, is
derived from those fields. That is why a display nothing names gets no wallpaper, and why the shipped
websites have to be pinned one per screen on first launch: not as curation, but so the second screen
is named by something. Here the screen picks a list instead, and the list is a thing the user can
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
