import Cocoa

extension AppState {
	/**
	Run whatever a `nifro:` URL is asking for.

	Read through `URLComponents` rather than off the `URL`, because the query has to be split and
	because the three spellings of a command land in different places — see `urlCommand(from:)`.
	*/
	func handleURLCommand(_ url: URL) {
		guard
			url.scheme == Bundle.main.urlScheme,
			let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
		else {
			return
		}

		let command = urlCommand(from: urlComponents)
		let parameters = urlComponents.queryDictionary

		func showMessage(_ message: String) {
			SSApp.forceActivate()
			NSAlert.showModal(title: message)
		}

		switch command {
		case "add":
			guard
				let urlString = parameters["url"]?.trimmed,
				let url = URL(string: urlString, encodingInvalidCharacters: false),
				url.isValid
			else {
				showMessage(String(localized: "Invalid URL for the “add” command."))
				return
			}

			WebsitesController.shared.add(url, title: parameters["title"]?.trimmed.nilIfEmpty)
		default:
			// Every other command is one of the actions, named by `Action.urlCommand`. "add" stays here
			// because it is the only one that reads a parameter.
			guard let action = Action.forURLCommand(command) else {
				showMessage("The command “\(command)” is not supported.")
				return
			}

			action.run()
		}
	}
}
