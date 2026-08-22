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
	The region of the page being shown, if the current website is cropped.
	*/
	var cropRect: CGRect? {
		didSet {
			setFrame()
		}
	}

	/**
	Whether the website wants clicks while the wallpaper is just a wallpaper.

	Separate from `isInteractive`, which is Browsing Mode: that brings the window forward and takes focus, this only stops the window from letting clicks fall through to the desktop.
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

		disableSnapshotRestoration()
		setFrame()

		NSScreen.publisher
			.sink { [weak self] in
				self?.setFrame()
			}
			.store(in: &cancellables)

		Defaults.publisher(.extendBelowMenuBar)
			.sink { [weak self] _ in
				self?.setFrame()
			}
			.store(in: &cancellables)
	}

	private func setFrame() {
		// Ensure the screen still exists.
		guard let screen = targetDisplay?.screen ?? .main else {
			return
		}

		// A cropped website gets a window the size of its crop. Anything larger would keep covering the desktop it was supposed to give back.
		if let cropRect {
			setFrame(cropRect.screenFrame(inScreen: screen.frame), display: true)
			return
		}

		var frame = screen.frameWithoutStatusBar
		frame.size.height += 1 // Probably not needed, but just to ensure it covers all the way up to the menu bar on older Macs (I can only test on M1 Mac)

		if Defaults[.extendBelowMenuBar] {
			frame = screen.frame
		}

		setFrame(frame, display: true)
	}
}
