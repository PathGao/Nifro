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
	What a check found.

	Three answers rather than an optional version, because "nothing newer" and "could not ask" are
	different things to tell somebody who pressed a button, and inferring them apart afterwards gets it
	wrong: a failed fetch with an older version already on record looks exactly like being up to date.
	*/
	enum Result: Equatable {
		case unreachable
		case upToDate
		case newer(String)
	}

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
		// Empty means "not a version I can read", which is why the caller refuses to act on it. There is
		// no real version with no components, so the sentinel cannot collide with an answer.
		func components(_ version: String) -> [Int] {
			let parts = version.split(separator: ".", omittingEmptySubsequences: false)
			let numbers = parts.compactMap { Int($0) }

			guard
				numbers.count == parts.count,
				numbers.allSatisfy({ $0 >= 0 })
			else {
				return []
			}

			return numbers
		}

		let candidate = components(candidate)
		let current = components(current)

		guard
			!candidate.isEmpty,
			!current.isEmpty
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
