import WebKit

/**
Asks the page how busy it has been, so a website that never moves can stop being rendered like one
that does.

Most pages people put on a wallpaper are documents, maps or dashboards. They load, they settle, and
then they are a picture until something reloads them. Rendering those with a live browser costs a
WebContent process all day to redraw a frame that was already correct. The snapshot backend exists
for exactly that, but it was a switch somebody had to find and flip per website, so almost nobody
would.

The page reports on itself: how many animation frames it asked for, whether any CSS animation is
running, whether media is playing, and how many DOM mutations happened. Those four cover the ways a
page can change, and each is a counter rather than a measurement of pixels.
*/
enum ActivityWatcher {
	/**
	How long each reported window covers.
	*/
	static let windowSeconds = 10.0

	static let script = """
		(() => {
			let frames = 0;
			let mutations = 0;

			const requestFrame = window.requestAnimationFrame.bind(window);

			window.requestAnimationFrame = callback => {
				frames++;
				return requestFrame(callback);
			};

			new MutationObserver(records => {
				mutations += records.length;
			}).observe(document, {
				childList: true,
				subtree: true,
				characterData: true,
				attributes: true
			});

			const isPlayingMedia = () => {
				for (const element of document.querySelectorAll('audio, video')) {
					if (!element.paused && !element.ended && element.readyState > 2) {
						return true;
					}
				}

				return false;
			};

			const runningAnimations = () => {
				// Not every engine ships getAnimations. Reporting zero is the safe direction here
				// only because the frame counter and the mutation counter still see most movement.
				if (!document.getAnimations) {
					return 0;
				}

				return document.getAnimations().filter(animation => animation.playState === 'running').length;
			};

			setInterval(() => {
				window.webkit.messageHandlers.\(messageName).postMessage({
					animationFrames: frames,
					runningAnimations: runningAnimations(),
					isPlayingMedia: isPlayingMedia(),
					mutations,
					seconds: \(Int(windowSeconds))
				});

				frames = 0;
				mutations = 0;
			}, \(Int(windowSeconds * 1000)));
		})();
		"""

	static let messageName = "nifroActivity"

	static func sample(from body: Any) -> ActivitySample? {
		guard
			let payload = body as? [String: Any],
			let animationFrames = payload["animationFrames"] as? Int,
			let runningAnimations = payload["runningAnimations"] as? Int,
			let isPlayingMedia = payload["isPlayingMedia"] as? Bool,
			let mutations = payload["mutations"] as? Int,
			let seconds = payload["seconds"] as? Double ?? (payload["seconds"] as? Int).map(Double.init)
		else {
			return nil
		}

		return ActivitySample(
			animationFrames: animationFrames,
			runningAnimations: runningAnimations,
			isPlayingMedia: isPlayingMedia,
			mutations: mutations,
			seconds: seconds
		)
	}
}

/**
Forwards the page's reports to the scene without keeping it alive.

`WKUserContentController` retains its message handlers, and the controller is owned by the web view
which is owned by the scene. Handing it the scene directly would close that circle and leak every
scene the app ever built.
*/
final class ActivityMessageProxy: NSObject, WKScriptMessageHandler {
	private weak var scene: WallpaperScene?

	init(scene: WallpaperScene) {
		self.scene = scene
	}

	func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
		guard let sample = ActivityWatcher.sample(from: message.body) else {
			return
		}

		MainActor.assumeIsolated {
			scene?.record(sample)
		}
	}
}
