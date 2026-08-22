import WebKit

/**
Loads a content-blocking rule list so pages stop showing cookie banners and ads on the desktop.

Asked for upstream (Plash#37). This maintains no rules of its own. Blocklists go stale within weeks and keeping one working is a full-time job. It takes a URL to a list somebody else keeps and hands it to WebKit, which has done the actual blocking since macOS 10.13.

The compiled list is cached by WebKit under a name derived from the source, so it is compiled once and reused across launches. A fetch that fails leaves the previous compiled list in place rather than dropping protection.
*/
enum ContentRules {
	private static let identifier = "user-rules"

	/**
	The list currently compiled and ready to attach to new web views.
	*/
	@MainActor private(set) static var compiled: WKContentRuleList?

	/**
	Load whatever the user pointed at, compile it, and keep it for future web views.
	*/
	@MainActor
	static func refresh() async {
		guard
			let source = Defaults[.contentRulesURL]?.trimmed.nilIfEmpty,
			let url = URL(string: source)
		else {
			compiled = nil
			return
		}

		let store = WKContentRuleListStore.default()

		// Use whatever was compiled last time first, so a slow or failed fetch never leaves pages unprotected.
		if let cached = try? await store?.contentRuleList(forIdentifier: identifier) {
			compiled = cached
		}

		guard
			let (data, response) = try? await URLSession.shared.data(from: url),
			(response as? HTTPURLResponse)?.statusCode == 200,
			let json = String(data: data, encoding: .utf8)
		else {
			return
		}

		guard let list = try? await store?.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) else {
			// A list that will not compile is the author's problem, not something to keep retrying.
			return
		}

		compiled = list
	}
}

extension WKWebViewConfiguration {
	/**
	Attach the compiled rule list, if there is one.
	*/
	@MainActor
	func applyContentRules() {
		guard let list = ContentRules.compiled else {
			return
		}

		userContentController.add(list)
	}
}
