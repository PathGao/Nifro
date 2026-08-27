import Combine
import WebKit

/**
Loads a content-blocking rule list so pages stop showing cookie banners and ads on the desktop.

This maintains no rules of its own. Blocklists go stale within weeks and keeping one working is a full-time job. It takes a URL to a list somebody else keeps and hands it to WebKit, which has done the actual blocking since macOS 10.13.

The compiled list is cached by WebKit under a name derived from the source, so it is compiled once and reused across launches. A fetch that fails leaves the previous compiled list in place rather than dropping protection.
*/
enum ContentRules {
	private static let identifier = "user-rules"

	/**
	What the last refresh made of the address.

	`compiled` was the only thing a refresh wrote down, and it is `nil` for three different reasons —
	nothing was pasted, the address did not answer, or what came back was not a rule list. Those are
	three different things for the person who pasted it to do, and the setting could tell none of them
	apart.
	*/
	enum Status: Equatable {
		/// Nothing pasted, so there is nothing to report.
		case unset

		/// Fetching and compiling.
		case loading

		/// A list compiled from the address is attached to every page.
		case blocking

		/// The address could not be fetched, or did not answer with a file.
		case unreachable

		/// It arrived, and WebKit would not compile it.
		case rejected
	}

	/**
	The outcome of the last refresh, for the setting to draw.

	A subject rather than a stored property because the two ends never meet: the refresh is kicked off
	from `setUpEvents`, and the pane that reports it is usually not open — so there is nobody holding
	it to ask, and nothing to ask at the moment the answer arrives.
	*/
	@MainActor static let status = CurrentValueSubject<Status, Never>(.unset)

	/**
	The list currently compiled and ready to attach to new web views.
	*/
	@MainActor private(set) static var compiled: WKContentRuleList?

	/**
	Load whatever the user pointed at, compile it, and keep it for the web views that ask for it.

	Nothing waits on this. It is a network fetch and a compile, and the first wallpaper of the session
	used to sit behind both — see `setUpEvents`. Whoever kicks it off is responsible for handing the
	result to the pages already up, which is what `applyContentRules` is for.
	*/
	@MainActor
	static func refresh() async {
		guard let source = Defaults[.contentRulesURL]?.trimmed.nilIfEmpty else {
			compiled = nil
			status.send(.unset)
			return
		}

		status.send(.loading)
		status.send(await load(from: source))
	}

	/**
	The fetch and the compile, returning what it made of the address.

	Split off `refresh` for the return type. Every way out of a load now has to name an outcome, so a
	failure exit added later cannot be a silent one — which is what the three bare `return`s here used
	to be, and the whole reason the setting had nothing to say.
	*/
	@MainActor
	private static func load(from source: String) async -> Status {
		guard let url = URL(string: source) else {
			compiled = nil
			return .unreachable
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
			return .unreachable
		}

		guard let list = try? await store?.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) else {
			// A list that will not compile is the author's problem, not something to keep retrying.
			return .rejected
		}

		compiled = list
		return .blocking
	}
}

extension WKWebViewConfiguration {
	/**
	Attach the compiled rule list, if there is one.

	Called when a web view is built, and again on the live web views once a refresh has landed —
	because the refresh no longer finishes before the first page of the session starts loading.

	It takes the old list off first, so this is "the rules are now these" rather than "add these
	rules". Left additive, clearing the setting would leave every page already on screen running the
	last list it was given for the rest of the session, and a page that loads in place rather than
	into a fresh web view would accumulate a copy per refresh.
	*/
	@MainActor
	func applyContentRules() {
		userContentController.removeAllContentRuleLists()

		guard let list = ContentRules.compiled else {
			return
		}

		userContentController.add(list)
	}
}
