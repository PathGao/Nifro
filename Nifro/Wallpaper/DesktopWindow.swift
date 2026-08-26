import Cocoa

final class DesktopWindow: NSWindow {
	override var canBecomeMain: Bool { isInteractive }
	override var canBecomeKey: Bool { isInteractive }
	override var acceptsFirstResponder: Bool { isInteractive }

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
			guard !isInteractive else {
				return
			}

			ignoresMouseEvents = !allowsPassiveInteraction
		}
	}

	var isInteractive = false {
		didSet {
			if isInteractive {
				level = Defaults[.bringBrowsingModeToFront] ? .floating : (.desktopIcon + 1) // The `+ 1` fixes a weird issue where the window is sometimes not interactive. (macOS 11.2.1)
				makeKeyAndOrderFront(self)
				ignoresMouseEvents = false
			} else {
				level = .desktop
				orderBack(self)

				// Even though the window is on `.desktop` level, the user would be able to interact if they hide desktop icons.
				ignoresMouseEvents = !allowsPassiveInteraction
			}
		}
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
			.fullScreenNone // This ensures that if Nifro is launched while an app is fullscreen (fullscreen is a separate space), it will not show behind that app and instead show in the primary space.
		]

		// Read here rather than left to the settings subscription, which only ever reaches the scenes
		// that exist when it fires. That is every scene at launch and no scene built afterwards, so a
		// display plugged in later got a wallpaper that stayed on one Space with the setting on.
		collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: Defaults[.showOnAllSpaces])

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
