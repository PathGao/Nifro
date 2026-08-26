import Foundation

/**
Knowing there is a new version.

Nothing in the app knew a release existed. That matters most for the people it is hardest to reach:
Nifro is an accessory app with no Dock icon, so somebody who installed the disk image has no reason
to ever open it and no surface where a new version could be mentioned. Homebrew users are already
covered by the cask's `livecheck`, but only when they think to run `brew upgrade`.

Deliberately quiet, following Sparkle's guidance for background apps: no dialog, no notification, no
focus taken. The result is written down and the menu reads it, so the only time anything is said is
when the user has already opened the menu to look at something.
*/
enum UpdateCheck {
	/**
	One day, which is Sparkle's default and the interval macOS apps have settled on.
	*/
	static let interval: TimeInterval = 24 * 60 * 60

	// `URL(string:)` rather than the app's non-failable `URL(_:)` helper, which lives in a file this
	// target does not compile — the pure half has to build without the app around it.
	private static let latestReleaseURL = URL(string: "https://api.github.com/repos/PathGao/Nifro/releases/latest")

	private struct Release: Decodable {
		let tagName: String

		enum CodingKeys: String, CodingKey {
			case tagName = "tag_name"
		}
	}

	/**
	The version of the newest release, or `nil` if that could not be established.

	Failure is silent on purpose. A wallpaper app that cannot reach GitHub has nothing to tell the
	user that they would act on, and the next check is a day away.
	*/
	static func latestReleaseVersion() async -> String? {
		guard let latestReleaseURL else {
			return nil
		}

		var request = URLRequest(url: latestReleaseURL)
		request.timeoutInterval = 10
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

		guard
			let (data, response) = try? await URLSession.shared.data(for: request),
			(response as? HTTPURLResponse)?.statusCode == 200,
			let release = try? JSONDecoder().decode(Release.self, from: data)
		else {
			return nil
		}

		// Tags are `v0.1.3`; versions are `0.1.3`.
		return release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
	}

	/**
	Whether `candidate` is a later version than `current`.

	Compared as numbers per component rather than as text, because text says 0.1.10 is older than
	0.1.9 — and a project that has shipped ten patches is exactly the one that stops being told about
	them. A missing component counts as zero, so 0.2 is newer than 0.1.9 and the same as 0.2.0.

	Anything unparseable is not newer. The answer drives a menu item that sends people to a download
	page, and being wrong in that direction is worse than saying nothing.
	*/
	static func isNewer(_ candidate: String, than current: String) -> Bool {
		func components(_ version: String) -> [Int]? {
			let parts = version.split(separator: ".", omittingEmptySubsequences: false)

			guard !parts.isEmpty else {
				return nil
			}

			return try? parts.map {
				guard let number = Int($0), number >= 0 else {
					throw CocoaError(.formatting)
				}

				return number
			}
		}

		guard
			let candidate = components(candidate),
			let current = components(current)
		else {
			return false
		}

		for index in 0..<max(candidate.count, current.count) {
			let left = index < candidate.count ? candidate[index] : 0
			let right = index < current.count ? current[index] : 0

			if left != right {
				return left > right
			}
		}

		return false
	}
}
