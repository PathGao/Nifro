import Cocoa

final class DesktopWindow: NSWindow {
	override var canBecomeMain: Bool { isRaised }
	override var canBecomeKey: Bool { isRaised }
	override var acceptsFirstResponder: Bool { isRaised }

	private var cancellables = Set<AnyCancellable>()

	var targetDisplay: Display? {
		didSet {
			setFrame()
		}
	}

	/**
	The patch of desktop the window is shrunk to, giving the rest back.

	Always `nil` today. The visibility policy that used to set it came out with the rest of the power
	machinery, and what is left is the half that has no owner: the property, the branch in `setFrame`
	and `CGRect.screenFrame(inScreen:)`. Kept rather than deleted because putting a page on part of the
	desktop is the L series, and this is the shape it needs — but nothing writes it, so anything
	reasoning about where the wallpaper window is may assume it covers the whole page area.
	*/
	var reducedRegion: CGRect? {
		didSet {
			setFrame()
		}
	}

	/**
	Whether the website wants clicks while the wallpaper is just a wallpaper.

	Separate from `isInteractive`, which is Browsing Mode. That brings the window forward and takes focus. This only stops clicks from falling through to the desktop.
	*/
	var allowsPassiveInteraction = false {
		didSet {
			guard !isRaised else {
				return
			}

			ignoresMouseEvents = !allowsPassiveInteraction
		}
	}

	var isInteractive = false {
		didSet {
			applyRaisedState()
		}
	}

	/**
	Whether a region is being framed over this wallpaper.

	Framing needs exactly what Browsing Mode needs — the window in front, taking clicks, and able to
	become key so the overlay can be typed at. It is a second, temporary reason for the same thing,
	and it has to be its own property because `isInteractive` is not the framing mode's to hold:
	`rebuildScenes` writes `isInteractive = isBrowsingMode(on:)` on every window, and it runs on any
	edit to the website list — including the one the panel's Crop button makes on the way in, one
	runloop turn later. Held as Browsing Mode, framing was switched back off by the very act that
	started it, leaving a click-through desktop window that cannot be key and an overlay whose Return
	and Escape went nowhere.

	Kept here rather than beside each writer because all of them write this one window.
	*/
	var isFramingRegion = false {
		didSet {
			applyRaisedState()
		}
	}

	/**
	Whether the window is in front and taking input, for either reason.
	*/
	private var isRaised: Bool { isInteractive || isFramingRegion }

	private func applyRaisedState() {
		guard isRaised else {
			level = .desktop
			orderBack(self)

			// Even though the window is on `.desktop` level, the user would be able to interact if they hide desktop icons.
			ignoresMouseEvents = !allowsPassiveInteraction
			return
		}

		// Framing is always in front, whatever Browsing Mode is set to: the page being framed is the
		// thing the user is aiming at, and a page behind another window cannot be aimed at.
		level = isFramingRegion || Defaults[.bringBrowsingModeToFront] ? .floating : (.desktopIcon + 1) // The `+ 1` fixes a weird issue where the window is sometimes not interactive. (macOS 11.2.1)
		makeKeyAndOrderFront(self)
		ignoresMouseEvents = false
	}

	convenience init(display: Display?) {
		self.init(
			contentRect: .zero,
			styleMask: [
				.borderless
			],
			backing: .buffered,
			defer: false
		)

		self.targetDisplay = display

		self.isOpaque = false
		self.backgroundColor = .clear
		self.level = .desktop
		self.isRestorable = false
		self.canHide = false
		self.displaysWhenScreenProfileChanges = true
		self.collectionBehavior = [
			.stationary,
			.ignoresCycle,
			// A wallpaper that is only on the Mission Control desktop that happened to be in front when
			// Nifro started is a wallpaper that disappears when you switch desktop, which nobody wants
			// from a wallpaper. This used to be a setting, off by default.
			.canJoinAllSpaces,
			// So that launching Nifro while an app is fullscreen — a Space of its own — does not put the
			// wallpaper behind that app. It lands on the ordinary desktop instead.
			.fullScreenNone
		]

		disableSnapshotRestoration()
		setFrame()

		NSScreen.publisher
			.sink { [weak self] in
				self?.setFrame()
			}
			.store(in: &cancellables)
	}

	private func setFrame() {
		// Ensure the screen still exists.
		guard let screen = targetDisplay?.screen ?? Display.mainScreen else {
			return
		}

		// The window shrinks to whatever is still visible so the rest of the desktop is given back.
		if let reducedRegion {
			setFrame(reducedRegion.screenFrame(inScreen: screen.pageFrame), display: true)
			return
		}

		var frame = screen.pageFrame
		frame.size.height += 1 // Probably not needed, but just to ensure it covers all the way up to the menu bar on older Macs (I can only test on M1 Mac)

		setFrame(frame, display: true)
	}
}
