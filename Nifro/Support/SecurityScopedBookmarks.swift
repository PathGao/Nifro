import AppKit

// Moved out of Extensions.swift, which is where it was only because everything was. This is a
// component, not an extension.

// TODO: I plan to extract this into a Swift Package when it's been battle-tested.
/**
This always requests the permission to a directory. If you give it file URL, it will ask for permission to the parent directory.
*/
enum SecurityScopedBookmarkManager {
	private static let lock = NSLock()

	// TODO: Abstract this to a generic class to have a Dictionary like thing that is synced to UserDefaults and the subclass it here.
	private final class BookmarksUserDefaults: @unchecked Sendable {
		// TODO: This should probably be an argument to init.
		private let userDefaultsKey = Defaults.Key<[String: Data]>("__securityScopedBookmarks__", default: [:])

		private var bookmarkStore: [String: Data] {
			get { Defaults[userDefaultsKey] }
			set {
				Defaults[userDefaultsKey] = newValue
			}
		}

		subscript(url: URL) -> Data? {
			// Resolving symlinks is important for normalization. For example, sometimes a reference to the Desktop directory is pointed at a symlink in the sandbox container: `file:///Users/sindresorhus/Library/Containers/com.sindresorhus.Plash/Data/Desktop/`.
			get { bookmarkStore[url.resolvingSymlinksInPath().absoluteString] }
			set {
				var bookmarks = bookmarkStore
				bookmarks[url.resolvingSymlinksInPath().absoluteString] = newValue
				bookmarkStore = bookmarks
			}
		}
	}

	private final class NSOpenSavePanelDelegateHandler: NSObject, NSOpenSavePanelDelegate {
		let currentURL: URL

		init(url: URL) {
			// It's important to resolve symlinks so it doesn't use the sandbox URL.
			self.currentURL = url.resolvingSymlinksInPath()
			super.init()
		}

		/*
		We only allow this directory.

		You might think we could use `didChangeToDirectoryURL` and set `sender.directoryURL = currentURL` there, but that doesn't work. The directory cannot be programmatically changed after the panel is opened.
		*/
		func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
			url == currentURL
		}

		// This should in theory not be needed as we already disable the “Allow” button, but just in case.
		func panel(_ sender: Any, validate url: URL) throws {
			if url != currentURL {
				throw NSError.appError(
					String(localized: "Incorrect directory."),
					recoverySuggestion: "Select the directory “\(currentURL.tildePath)”."
				)
			}
		}
	}

	private static let bookmarks = BookmarksUserDefaults()

	/**
	Save the bookmark.
	*/
	static func saveBookmark(for url: URL) throws {
		bookmarks[url] = try url.accessSecurityScopedResource {
			try $0.bookmarkData(options: .withSecurityScope)
		}
	}

	/**
	Load the bookmark.

	Returns `nil` if there's no bookmark for the given URL or if the bookmark cannot be loaded.
	*/
	static func loadBookmark(for url: URL) -> URL? {
		guard let bookmarkData = bookmarks[url] else {
			return nil
		}

		var isBookmarkDataStale = false

		guard
			let newUrl = try? URL(
				resolvingBookmarkData: bookmarkData,
				options: .withSecurityScope,
				bookmarkDataIsStale: &isBookmarkDataStale
			)
		else {
			return nil
		}

		if isBookmarkDataStale {
			guard (try? saveBookmark(for: newUrl)) != nil else {
				return nil
			}
		}

		return newUrl
	}

	/**
	Returns `nil` if the user didn't give permission or if the bookmark couldn't be saved.
	*/
	@MainActor
	static func promptUserForPermission(
		atDirectory directoryURL: URL,
		message: String? = nil
	) -> URL? {
		lock.lock()

		defer {
			lock.unlock()
		}

		let delegate = NSOpenSavePanelDelegateHandler(url: directoryURL)

		let openPanel = with(NSOpenPanel()) {
			$0.identifier = .init("SecurityScopedBookmarkManager")
			$0.delegate = delegate
			$0.directoryURL = directoryURL
			$0.allowsMultipleSelection = false
			$0.canChooseDirectories = true
			$0.canChooseFiles = false
			$0.canCreateDirectories = false
			$0.title = String(localized: "Permission")
			$0.message = message ?? "\(SSApp.name) needs access to the “\(directoryURL.lastPathComponent)” directory. Click “Allow” to proceed."
			$0.prompt = String(localized: "Allow")
		}

		SSApp.activateIfAccessory()

		guard openPanel.runModal() == .OK else {
			return nil
		}

		guard let securityScopedURL = openPanel.url else {
			return nil
		}

		do {
			try saveBookmark(for: securityScopedURL)
		} catch {
			error.presentAsModal()
			return nil
		}

		return securityScopedURL
	}



	/**
	Accepts a file URL to a directory or file. If it's a file, it will prompt for permissions to its containing directory.

	You have to manually call the returned method when you no longer need access to the URL.
	*/
	@MainActor
	@discardableResult
	static func accessURLByPromptingIfNeeded(_ url: URL) -> (() -> Void) {
		let directoryURL = url.directoryURL

		guard let securityScopedURL = loadBookmark(for: directoryURL) ?? promptUserForPermission(atDirectory: directoryURL) else {
			return {}
		}

		_ = securityScopedURL.startAccessingSecurityScopedResource()

		return {
			securityScopedURL.stopAccessingSecurityScopedResource()
		}
	}
}
